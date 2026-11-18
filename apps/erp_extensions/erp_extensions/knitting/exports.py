"""Explicit review exports. No tax filing, provider submission or external delivery."""
import base64
import csv
import html
import io
import json
from xml.etree.ElementTree import Element, SubElement, tostring

import frappe
from frappe.utils import getdate
from . import domain as d, permissions, reports


def safe_cell(value):
    text = "" if value is None else str(value)
    return "'" + text if text.lstrip().startswith(("=", "+", "-", "@", "\t", "\r")) else text


def fiscal_token(value):
    day = getdate(value)
    year = day.year if day.month >= 4 else day.year - 1
    return f"{year}-{str(year + 1)[2:]}"


def roll_token(job, line, weight, roll):
    return f"{roll}|{job}|{line}|{d.kg(weight)}kg"


def gst_review(company, rows):
    return json.dumps({"schema": "erp-workspace.gst-review.v1", "company": company, "purpose": "review_only",
        "invoices": [{k: row.get(k) for k in ("invoice", "posting_date", "currency", "net_amount", "tax_amount", "grand_total")} for row in rows]},
        sort_keys=True, separators=(",", ":"), default=str)


def tally_review(company, rows):
    root = Element("ERPWorkspaceReview", {"schema": "1", "purpose": "review_only", "company": company})
    for row in rows:
        node = SubElement(root, "Invoice")
        for key in ("invoice", "posting_date", "currency", "net_amount", "tax_amount", "grand_total"):
            SubElement(node, key).text = str(row.get(key) or "")
    return tostring(root, encoding="unicode")


def render(company, format, value=None):
    value = frappe.parse_json(value) if isinstance(value, str) else value or {}
    f = reports.filters(value)
    if format == 'delivery_challan':
        permissions.require(company, 'delivery', history=True)
        event = d.reference('Knitting Event', f.get('event'), company)
        permissions.require_event_scope(event)
        event.check_permission('print')
        if event.kind not in ('deliver', 'deliver_batch') or event.cancelled:
            frappe.throw('Select an active confirmed delivery.')
        job = d.reference('Knitting Job', event.job, company)
        value = d.json_value(event.result, {})
        batch = event.kind == 'deliver_batch'
        identifier = 'batch' if batch else 'roll'
        count = value['roll_count'] if batch else len(value['rolls'])
        rows = ''.join('<tr>' + ''.join('<td>' + html.escape(str(cell)) + '</td>' for cell in
            (row[identifier], row['programme_line'], row['rolls'] if batch else 1, row['quantity_kg'])) + '</tr>'
            for row in value.get('sources', []))
        def text(key): return html.escape(str(value.get(key) or 'Not recorded'))
        from frappe.utils.pdf import get_pdf
        content = get_pdf(f'''<html><body style="font-family:Arial,sans-serif;padding:24px;color:#191b19">
          <h1>DELIVERY CHALLAN</h1><p>{html.escape(company)}</p><hr><h2>{html.escape(event.name)}</h2>
          <p>Confirmed {html.escape(str(event.occurred_at))}<br>Customer {html.escape(job.customer)}<br>Job {html.escape(job.name)}</p>
          <p>Destination: {text('destination')}<br>Transport: {text('transport')}<br>Transport reference: {text('transport_reference')}</p>
          <p>Material ownership: {html.escape(job.material_mode)}. This challan records physical delivery; it is not a tax invoice.</p>
          <table border="1" cellpadding="7"><thead><tr><th>{identifier.title()}</th><th>Programme</th><th>Rolls / pieces</th><th>Actual kg</th></tr></thead><tbody>{rows}</tbody></table>
          <h2>Total {text('quantity_kg')} kg · {html.escape(str(count))} rolls / pieces</h2>
          <p>Dispatched by: ____________________ &nbsp; Received by: ____________________</p></body></html>''', options={'disable-javascript':''})
        return {'name':event.name+'-challan.pdf','mime':'application/pdf','content':base64.b64encode(content).decode()}
    if format == "roll_label":
        caps = permissions.capabilities()
        capability = next((key for key in ("production", "quality", "reports") if key in caps), "reports")
        permissions.require(company, capability, history=True)
        doc = d.reference("Knitting Roll", f.get("roll"), company)
        doc.check_permission("print")
        from frappe.utils.pdf import get_pdf
        token = roll_token(doc.job, doc.programme_line, doc.weight_kg, doc.name)
        from frappe.utils.print_format_generator import get_qr_code
        qr = get_qr_code(token)
        text = f'''<html><body style="font-family:Arial,sans-serif;padding:20px;color:#191b19">
        <h2>ROLL · {html.escape(doc.name)}</h2><p>{html.escape(company)}</p><hr>
        <h1>{html.escape(doc.weight_kg)} kg</h1><p>Job {html.escape(doc.job)} · Line {html.escape(doc.programme_line or '')}</p>
        <p>Machine {html.escape(doc.machine or 'Manual')} · {html.escape(doc.state)}</p>
        <p>Produced {html.escape(str(doc.produced_at))}</p><img src="{qr}" width="120" height="120"><p style="font-family:monospace">{html.escape(token)}</p>
        <p>Fiscal reference {fiscal_token(doc.produced_at)}</p></body></html>'''
        content = get_pdf(text, options={"page-width": "110mm", "page-height": "150mm", "disable-javascript": ""})
        return {"name": doc.name + "-label.pdf", "mime": "application/pdf", "content": base64.b64encode(content).decode()}
    permissions.require(company, "reports", history=True)
    report = f.get("report", "jobs")
    if format in ("gst_review", "tally_review"):
        report = "billing"
        value = {**value, "group_by": None}
    source_type = {"yarn": "Knitting Ledger Entry", "yarn_inwards": "Knitting Ledger Entry", "yarn_returns": "Knitting Ledger Entry", "fabric": "Knitting Roll", "rolls": "Knitting Roll"}.get(report, "Knitting Job")
    if not frappe.has_permission(source_type, "export"):
        frappe.throw("This account cannot export these records.", frappe.PermissionError)
    result = reports.run(company, report, value, paged=False)
    if len(result["rows"]) > 10000:
        frappe.throw("Narrow the export to at most 10,000 rows.")
    if format == "csv":
        output = io.StringIO(newline="")
        writer = csv.writer(output, lineterminator="\r\n")
        keys = [c["key"] for c in result["columns"]]
        writer.writerow(keys)
        writer.writerows([[safe_cell(row.get(key)) for key in keys] for row in result["rows"]])
        content, suffix, mime = output.getvalue().encode("utf-8-sig"), "csv", "text/csv"
    elif format == "gst_review":
        content, suffix, mime = gst_review(company, result["rows"]).encode(), "json", "application/json"
    elif format == "tally_review":
        content, suffix, mime = tally_review(company, result["rows"]).encode(), "xml", "application/xml"
    elif format == "pdf":
        from frappe.utils.pdf import get_pdf
        columns = result["columns"]
        header = "".join(f"<th>{html.escape(c['label'])}</th>" for c in columns)
        body = "".join("<tr>" + "".join(f"<td>{html.escape(str(row.get(c['key']) or ''))}</td>" for c in columns) + "</tr>" for row in result["rows"])
        content = get_pdf(f"<html><body><h2>{html.escape(result['title'])}</h2><p>{html.escape(company)} · {result['mode']} · {result['from_date']} to {result['to_date']}</p><table border='1' cellpadding='5'><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table></body></html>", options={"orientation": "Landscape", "disable-javascript": ""})
        suffix, mime = "pdf", "application/pdf"
    else:
        frappe.throw("Choose CSV, PDF, roll label, GST review or Tally review.")
    return {"name": f"knitting-{report}-{format}.{suffix}", "mime": mime, "content": base64.b64encode(content).decode()}
