"""Company-owned invoice artwork and payment instructions, separate from accounting records."""
import base64
from binascii import Error as Base64Error
from decimal import Decimal
from hashlib import sha256
from io import BytesIO
import re
from urllib.parse import quote, urlencode

import frappe
from PIL import Image, ImageOps, ImageStat, UnidentifiedImageError

from erp_extensions.knitting.install import field
from erp_extensions.onboarding import can_manage_team

PROFILE = 'Workspace Invoice Settings'
ACCENTS = {'#1646BD', '#195458', '#722C37', '#435A36', '#5438B1', '#9A462F', '#82500F', '#36383C'}
FIELDS = ('template_id', 'accent_color', 'logo_base64', 'bank_name', 'account_holder', 'account_number', 'ifsc', 'upi_id', 'upi_name', 'print_footer', 'signatory_name')
OPTIONAL_PROFILE_FIELDS = ('accent_color', 'print_footer', 'signatory_name')
MAX_LOGO_BYTES = 2 * 1024 * 1024


def install():
    if not frappe.db.exists('DocType', PROFILE):
        frappe.get_doc({
            'doctype': 'DocType', 'name': PROFILE, 'module': 'Custom', 'custom': 1,
            'autoname': 'field:company',
            'fields': [
                field('company', 'Link', 'Company', reqd=1, unique=1), field('revision', 'Int'),
                *(field(key, 'Long Text' if key == 'logo_base64' else 'Data') for key in FIELDS),
            ],
            'permissions': [{'role': 'System Manager', 'read': 1}],
        }).insert()
    else:
        meta = frappe.get_meta(PROFILE)
        missing = [key for key in OPTIONAL_PROFILE_FIELDS if not meta.has_field(key)]
        if missing:
            definition = frappe.get_doc('DocType', PROFILE)
            for key in missing:
                definition.append('fields', field(key))
            definition.save()


def can_manage(company):
    # The caller first verifies company scope and normal Sales Invoice access.
    return bool(can_manage_team(company) or frappe.session.user == 'Administrator' or 'System Manager' in frappe.get_roles())


def default_style(company):
    from erp_extensions.invoices import DEFAULT_STYLE
    return frappe.db.get_value(PROFILE, company, 'template_id') or DEFAULT_STYLE


def read(company, *, include_details, lock=False):
    from erp_extensions.invoices import DEFAULT_STYLE
    fields = FIELDS if include_details else ('template_id', 'accent_color')
    row = frappe.db.get_value(PROFILE, company, ['revision', *fields], as_dict=True, for_update=lock) or {}
    values = {key: row.get(key) or '' for key in FIELDS}
    values['template_id'] = values['template_id'] or DEFAULT_STYLE
    return {'company': company, 'can_manage': can_manage(company), 'revision': str(row.get('revision') or 0),
            'settings': values}


def _logo(value):
    if not value:
        return ''
    if len(value) > 4 * ((MAX_LOGO_BYTES + 2) // 3):
        frappe.throw('Choose a PNG or JPEG logo of up to 2 MB.')
    try:
        content = base64.b64decode(value, validate=True)
        if len(content) > MAX_LOGO_BYTES:
            frappe.throw('Choose a PNG or JPEG logo of up to 2 MB.')
        with Image.open(BytesIO(content), formats=('PNG', 'JPEG')) as original:
            if max(original.size) > 4096 or original.width * original.height > 8_000_000:
                frappe.throw('Choose a logo up to 4096 pixels per side and 8 megapixels in total.')
            if getattr(original, 'is_animated', False):
                frappe.throw('Choose a still PNG or JPEG logo.')
            original.load()
            corrected = ImageOps.exif_transpose(original)
            normalized = corrected.convert('RGBA' if corrected.has_transparency_data else 'RGB')
            normalized.thumbnail((768, 768), Image.Resampling.LANCZOS)
            if normalized.mode == 'RGBA':
                alpha = normalized.getchannel('A')
                if not alpha.getbbox():
                    frappe.throw('Choose a logo with visible artwork.')
                # Pick one stable backing for light and dark papers, using visible pixels only.
                visible = alpha.point(lambda v: 255 if v >= 32 else 0)
                luminance = ImageStat.Stat(normalized.convert('L'), mask=visible)
                light_ink = luminance.count[0] and luminance.mean[0] > 185
                plate = Image.new('RGB', normalized.size, '#26292e' if light_ink else 'white')
                plate.paste(normalized, mask=alpha)
                normalized = plate
            normalized.info.clear()
            image = BytesIO()
            normalized.save(image, format='PNG')
            if image.tell() > MAX_LOGO_BYTES:
                # High-entropy transparent artwork can exceed the budget even after resizing.
                normalized.thumbnail((512, 512), Image.Resampling.LANCZOS)
                image = BytesIO()
                normalized.save(image, format='PNG')
        return base64.b64encode(image.getvalue()).decode('ascii')
    except (Base64Error, UnidentifiedImageError, Image.DecompressionBombError, ValueError, OSError, SyntaxError):
        frappe.throw('Choose a readable PNG or JPEG logo.')


def _clean(settings, existing):
    from erp_extensions.invoices import TEMPLATES
    # A client that predates a stationery control must preserve its saved value.
    if isinstance(settings, dict):
        settings = {**{key: existing.get(key, '') for key in OPTIONAL_PROFILE_FIELDS}, **settings}
    if not isinstance(settings, dict) or set(settings) != set(FIELDS):
        frappe.throw('Reload invoice settings before saving.')
    if any(not isinstance(value, str) for value in settings.values()):
        frappe.throw('Enter text for the invoice settings.')
    values = {key: val.strip() for key, val in settings.items()}
    if values['accent_color'] and values['accent_color'] not in ACCENTS:
        frappe.throw('Choose an available invoice accent color.')
    if values['template_id'] not in TEMPLATES:
        frappe.throw('Choose an available default invoice design.')
    if any(len(values[key]) > 100 or re.search(r'[<>\x00-\x1f\x7f]', values[key])
           for key in ('bank_name', 'account_holder', 'upi_name', 'signatory_name', 'print_footer')):
        frappe.throw('Use a single line of up to 100 characters for names and the printed footer.')
    number = re.sub(r'[ -]', '', values['account_number'])
    if number and not re.fullmatch(r'[A-Za-z0-9]{1,34}', number):
        frappe.throw('Enter a bank account number of up to 34 letters or digits.')
    values['account_number'] = number
    values['ifsc'] = values['ifsc'].upper()
    if values['ifsc'] and not re.fullmatch(r'[A-Z]{4}0[A-Z0-9]{6}', values['ifsc']):
        frappe.throw('Enter the 11-character IFSC from your bank.')
    if not number and any(values[key] for key in ('bank_name', 'ifsc', 'account_holder')):
        frappe.throw('Enter the account number for these bank details.')
    vpa = values['upi_id']
    if vpa and (len(vpa) > 100 or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9.-]*', vpa)):
        frappe.throw('Enter a UPI ID in the form name@bank.')
    if not vpa and values['upi_name']:
        frappe.throw('Enter a UPI ID for this payee name.')
    if values['logo_base64'] != existing['logo_base64']:
        values['logo_base64'] = _logo(values['logo_base64'])
    return values


def save(company, settings, revision):
    if not can_manage(company):
        frappe.throw('Only the company owner or a system manager can change invoice settings.', frappe.PermissionError)
    # Serializes first saves as well as edits. A profile row may not exist yet.
    frappe.db.get_value('Company', company, 'name', for_update=True)
    current = read(company, include_details=True, lock=True)
    if revision != current['revision']:
        frappe.throw('Invoice settings have changed. Reload them before saving.', frappe.TimestampMismatchError)
    values = _clean(settings, current['settings'])
    if values == current['settings']:
        return current
    next_revision = int(revision) + 1
    if revision == '0':
        frappe.get_doc({'doctype': PROFILE, 'company': company, **values, 'revision': next_revision}).insert(ignore_permissions=True)
    else:
        frappe.db.set_value(PROFILE, company, {**values, 'revision': next_revision})
    return {'company': company, 'can_manage': True, 'revision': str(next_revision), 'settings': values}


def payment_uri(data, settings):
    if (not settings['upi_id'] or data['docstatus'] != 1 or data['is_return']
            or data['currency'] != 'INR' or data['outstanding_currency'] != 'INR'):
        return ''
    outstanding = Decimal(str(data.get('outstanding_amount') or 0))
    if outstanding <= 0 or outstanding != outstanding.quantize(Decimal('.01')):
        return ''
    amount = format(outstanding, '.2f')
    # A repeat rendering of this bill and balance has the same reference.
    reference = sha256(f"{data['company']}|{data['name']}|{amount}".encode()).hexdigest()[:32]
    params = {'pa': settings['upi_id'], 'pn': settings['upi_name'] or data['seller_name'],
              'tr': reference, 'tn': str(data['name'])[:80], 'am': amount, 'cu': 'INR'}
    return 'upi://pay?' + urlencode(params, quote_via=quote)
