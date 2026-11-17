"""Create local workspaces and redeem owner-issued, company-bound invitations."""
from contextlib import contextmanager
from datetime import timedelta
from hashlib import sha256
import re
import secrets

import frappe
from frappe.rate_limiter import rate_limit
from frappe.utils import now_datetime, validate_email_address

from erp_extensions.knitting.install import field
from erp_extensions.knitting import permissions

MEMBER = 'Workspace Team Member'
INVITE = 'Workspace Staff Invitation'
ROLE_PRESETS = {
    'sales': ('Sales', ('Sales User',)),
    'cashier': ('Cashier', ('Workspace POS Cashier',)),
    'purchasing': ('Purchasing', ('Purchase User',)),
    'accounts': ('Accounts', ('Accounts User',)),
    'stock': ('Inventory', ('Stock User',)),
    'operator': ('Knitting operator', ('Knitting Operator',)),
    'checker': ('Quality checker', ('Knitting Checker',)),
    'planner': ('Production planner', ('Knitting Planner', 'Manufacturing User')),
}
GENERAL_ROLES = ('sales','cashier', 'purchasing', 'stock', 'accounts')
OWNER_ROLES = ('Workspace POS Cashier','Sales User', 'Purchase User', 'Accounts User', 'Stock User', 'Stock Manager', 'Item Manager',
               'Sales Master Manager', 'Purchase Master Manager', 'Manufacturing User', 'Projects User', 'Projects Manager',
               'Quality Manager', 'Knitting Manager')


def install():
    frappe.only_for('System Manager')
    schemas = {
        MEMBER: [field('company', 'Link', 'Company', reqd=1), field('member_user', 'Link', 'User', reqd=1, unique=1), field('team_role', reqd=1)],
        INVITE: [field('company', 'Link', 'Company', reqd=1), field('email', reqd=1), field('team_role', reqd=1),
                 field('token_digest', unique=1, reqd=1), field('expires_at', 'Datetime', reqd=1), field('closed', 'Check')],
    }
    for name, fields in schemas.items():
        if not frappe.db.exists('DocType', name):
            frappe.get_doc({'doctype':'DocType', 'name':name, 'module':'Custom', 'custom':1, 'autoname':'hash',
                            'fields':fields, 'permissions':[{'role':'System Manager', 'read':1}]}).insert()
    for owner in frappe.get_all(MEMBER, filters={'team_role':'owner'}, fields=['company','member_user']):
        company_permission = frappe.db.get_value('User Permission', {'user':owner.member_user, 'allow':'Company',
            'for_value':owner.company, 'apply_to_all_doctypes':1, 'hide_descendants':1}, 'name')
        if company_permission:
            user = frappe.get_doc('User', owner.member_user)
            missing = set(OWNER_ROLES) - {r.role for r in user.roles}
            if missing:
                user.add_roles(*sorted(missing))


def membership(user=None):
    user = user or frappe.session.user
    if user in ('Guest', 'Administrator'):
        return None
    cache = frappe.local.cache.setdefault('native_team_members', {})
    if user not in cache:
        cache[user] = frappe.db.get_value(MEMBER, {'member_user':user}, ['company', 'team_role'], as_dict=True) if frappe.db.exists('DocType', MEMBER, cache=True) else None
    return cache[user]


def can_manage_team(company):
    member = membership()
    return bool(member and member.company == company and member.team_role == 'owner')


def _check_owner(company):
    if not can_manage_team(company) or not permissions.company_allowed(company):
        frappe.throw('Only the owner of this workspace can manage its team.', frappe.PermissionError)


def _email(value):
    email = str(value or '').strip().lower()
    if not email or len(email) > 140 or ',' in email or validate_email_address(email) != email:
        frappe.throw('Enter a single valid email address.')
    return email


def _name(value, label):
    name = str(value or '').strip()
    if not name or len(name) > 100 or re.search(r'[<>\x00-\x1f\x7f]', name):
        frappe.throw(f'Enter a valid {label} of up to 100 characters.')
    return name


@contextmanager
def _provisioning():
    # ERPNext Company and User controllers create dependent records. Restore the complete
    # original request identity, including the caller's SID, after this bounded operation.
    session, form = frappe._dict(frappe.session), frappe.local.form_dict
    frappe.set_user('Administrator')
    try:
        yield
    except frappe.QueryDeadlockError:
        # InnoDB has already rolled back the entire transaction. Frappe resets its
        # commit callbacks when the request unwinds. Retrying needs a fresh request.
        frappe.throw('Another account update is in progress. Please try again.')
    finally:
        frappe.set_user(session.user)
        frappe.local.session.update(session)
        frappe.local.form_dict = form


def _user(email, full_name, password, roles):
    name = _name(full_name, 'name')
    if not isinstance(password, str) or not 10 <= len(password) <= 128:
        frappe.throw('Choose a password between 10 and 128 characters.')
    first, _, last = name.partition(' ')
    return frappe.get_doc({'doctype':'User', 'email':email, 'first_name':first, 'last_name':last, 'enabled':1,
        'send_welcome_email':0, 'user_type':'System User', 'new_password':password,
        'roles':[{'role':role} for role in roles]}).insert()


def _add_member(user, company, role):
    frappe.get_doc({'doctype':MEMBER, 'member_user':user, 'company':company, 'team_role':role}).insert(ignore_permissions=True)
    frappe.get_doc({'doctype':'User Permission', 'user':user, 'allow':'Company', 'for_value':company,
                    'apply_to_all_doctypes':1, 'is_default':1, 'hide_descendants':1}).insert()
    frappe.defaults.set_user_default('Company', company, user=user)
    frappe.defaults.set_user_default('native_workspace_company', company, user=user)
    frappe.clear_cache(user=user)
    if role == 'cashier':
        from erp_extensions.pos_checkout import assign_default
        assign_default(company,user)


def _knitting_settings(company, email):
    settings = {'state':'Active', 'warehouse':company.default_warehouse,
                'shift_windows':[{'name':'Day', 'start':'08:00', 'end':'20:00'}, {'name':'Night', 'start':'20:00', 'end':'08:00'}]}
    group = frappe.db.get_value('Item Group', {'is_group':0}, 'name', order_by='creation asc')
    for key, label, stock in [('service_item', 'Knitting service', 0), ('fabric_item', 'Knitted fabric', 1)]:
        item = frappe.get_doc({'doctype':'Item', 'item_code':f'{label} - {company.abbr}', 'item_name':label,
                               'item_group':group, 'stock_uom':'Kg', 'is_stock_item':stock, 'is_purchase_item':1,
                               'is_sales_item':1, 'item_defaults':[{'company':company.name, 'default_warehouse':company.default_warehouse}]})
        item.insert()
        # These company masters are created by the owner signup service on the owner's behalf.
        frappe.db.set_value('Item', item.name, 'owner', email, update_modified=False)
        settings[key] = item.name
    return settings


def _check_signup_site():
    if frappe.conf.get('native_owner_signup') != 1:
        frappe.throw('Owner registration is closed on this server.')


def _check_hosted_company():
    # The isolated synthetic site exercises multiple companies. Each hosted customer
    # needs a separately provisioned site, which may be claimed only while empty.
    if frappe.local.site != 'native-test.localhost' and frappe.db.get_value('Company', {}, 'name', for_update=True):
        frappe.throw('This workspace already belongs to a business. Sign in or ask its owner for an invitation.')


@frappe.whitelist(allow_guest=True, xss_safe=True, methods=['POST'])
@rate_limit(limit=12, seconds=3600)
def register_owner(full_name: str, email: str, password: str, company: str, industry: str):
    _check_signup_site()
    if frappe.session.user != 'Guest':
        frappe.throw('Sign out before creating a new owner account.')
    email, company = _email(email), _name(company, 'company name')
    if industry not in ('general', 'knitting'):
        frappe.throw('Choose General ERP or Knitting.')
    with _provisioning():
        # Creating a Company edits shared account and warehouse trees. Serialize
        # signups until the containing request commits, including duplicate checks.
        if frappe.request and not frappe.db.transaction_writes:
            # Cookie validation can open a repeatable-read snapshot before the previous
            # signup commits. Discard only that read-only snapshot. Our very first SQL
            # read acquires the lock, so ERPNext sees the preceding company's accounts.
            frappe.db.rollback()
        frappe.db.sql('select name from `tabDocType` where name=%s for update', MEMBER)
        _check_hosted_company()
        if frappe.db.get_value('User', email, 'name', for_update=True):
            frappe.throw('This account already exists. Sign in with your existing credentials.')
        if frappe.db.get_value('Company', company, 'name', for_update=True):
            frappe.throw('This company name is in use. Choose another name or ask its owner for an invitation.')
        owner = _user(email, full_name, password, OWNER_ROLES)
        defaults = frappe.get_single('Global Defaults')
        country = defaults.country or frappe.get_system_settings('country')
        currency = defaults.default_currency or frappe.db.get_value('Country', country, 'default_currency')
        if not country or not currency:
            frappe.throw('Ask the site administrator to configure the default country and currency.')
        record = frappe.get_doc({'doctype':'Company', 'company_name':company, 'abbr':'W' + secrets.token_hex(3).upper(),
            'country':country, 'default_currency':currency, 'chart_of_accounts':'Standard',
            'create_chart_of_accounts_based_on':'Standard Template'}).insert()
        _add_member(owner.name, record.name, 'owner')
        from erp_extensions.workspace import configure
        configure(record.name, _knitting_settings(record, email) if industry == 'knitting' else {'state':'Inactive'})
    return {'company':record.name, 'email':email}


def _roles(company):
    setup = permissions.profile(company)
    return ROLE_PRESETS.keys() if setup and setup.state in ('Active', 'Closing') else GENERAL_ROLES


@frappe.whitelist(methods=['GET', 'POST'])
def team(company: str):
    _check_owner(company)
    members = frappe.get_all(MEMBER, filters={'company':company}, fields=['member_user as email', 'team_role as role'], order_by='creation')
    for member in members:
        member.full_name = frappe.db.get_value('User', member.email, 'full_name')
    return {'members':members, 'roles':[{'key':key, 'label':ROLE_PRESETS[key][0]} for key in _roles(company)],
            'invitations':frappe.get_all(INVITE, filters={'company':company, 'closed':0, 'expires_at':['>', now_datetime()]},
                fields=['name','email','team_role as role','expires_at'], order_by='creation desc')}


@frappe.whitelist(methods=['POST'])
@rate_limit(limit=60, seconds=3600, user_based=True)
def invite_member(company: str, email: str, role: str):
    _check_owner(company)
    email = _email(email)
    if role not in _roles(company):
        frappe.throw('Choose an available staff role for this workspace.')
    frappe.db.get_value('Company', company, 'name', for_update=True)
    if frappe.db.get_value(MEMBER, {'member_user':email, 'company':company}, for_update=True):
        frappe.throw('This person already belongs to your team.')
    frappe.db.set_value(INVITE, {'company':company, 'email':email, 'closed':0}, 'closed', 1)
    token, expires_at = secrets.token_urlsafe(32), now_datetime() + timedelta(days=3)
    frappe.get_doc({'doctype':INVITE, 'company':company, 'email':email, 'team_role':role, 'expires_at':expires_at,
                    'token_digest':sha256(token.encode()).hexdigest()}).insert(ignore_permissions=True)
    return {'token':token, 'email':email, 'role':role, 'expires_at':expires_at}


@frappe.whitelist(methods=['POST'])
def revoke_invite(company: str, name: str):
    _check_owner(company)
    row = frappe.db.get_value(INVITE, {'company':company, 'name':name}, 'name', for_update=True)
    if not row:
        frappe.throw('This invitation is unavailable.')
    frappe.db.set_value(INVITE, row, 'closed', 1)
    return {'revoked':True}


@frappe.whitelist(allow_guest=True, xss_safe=True, methods=['POST'])
@rate_limit(limit=60, seconds=3600)
def accept_invite(token: str, full_name: str = '', email: str = '', password: str = ''):
    if not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}', token):
        frappe.throw('This invitation is invalid, expired or already used.')
    invite = frappe.db.get_value(INVITE, {'token_digest':sha256(token.encode()).hexdigest()},
        ['name','company','email','team_role','closed','expires_at'], as_dict=True, for_update=True)
    if not invite or invite.closed or invite.expires_at <= now_datetime() or invite.team_role not in _roles(invite.company):
        frappe.throw('This invitation is invalid, expired or already used.')
    actor = frappe.session.user
    if (actor != 'Guest' and actor != invite.email) or (email and _email(email) != invite.email):
        frappe.throw('Use the email address that received this invitation.')
    with _provisioning():
        roles = ROLE_PRESETS[invite.team_role][1]
        account = frappe.db.get_value('User', invite.email, 'name', for_update=True)
        if account:
            if actor != account:
                frappe.throw('Sign in to your existing account to accept this invitation.')
            user = frappe.get_doc('User', account)
            shares = frappe.get_all('DocShare', filters={'user':account}, fields=['share_doctype','share_name'])
            if (not user.enabled or user.user_type != 'Website User' or user.roles or user.role_profiles or
                    frappe.db.get_value(MEMBER, {'member_user':account}, for_update=True) or
                    frappe.db.exists('User Permission', {'user':account}) or
                    any(s.share_doctype != 'User' or s.share_name != account for s in shares)):
                frappe.throw('This account already has ERP access. Ask your site administrator about joining a different team.')
        else:
            if actor != 'Guest' or _email(email) != invite.email:
                frappe.throw('Use the email address that received this invitation.')
            _user(invite.email, full_name, password, roles)
        _add_member(invite.email, invite.company, invite.team_role)
        frappe.db.set_value(INVITE, invite.name, 'closed', 1)
        if account:
            # A user type change revokes live sessions. The pinned User controller
            # may commit while doing so. Finalize the membership and token first.
            user.append_roles(*roles)
            user.save()
    return {'company':invite.company, 'email':invite.email}
