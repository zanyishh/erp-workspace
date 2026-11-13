"""Explicit local factory operating windows, including overnight shifts."""
from datetime import datetime, timedelta
import re
import frappe


def validate(windows):
    if not isinstance(windows, list) or not 1 <= len(windows) <= 12:
        frappe.throw("Configure one to twelve named shift windows.")
    seen = set()
    for window in windows:
        if not isinstance(window, dict) or set(window) != {"name", "start", "end"}:
            frappe.throw("Each shift needs a name, start and finish time.")
        name = window['name']
        if not isinstance(name, str) or not name.strip() or len(name) > 40 or name in seen:
            frappe.throw("Use distinct shift names of up to 40 characters.")
        seen.add(name)
        for key in ('start', 'end'):
            if not isinstance(window[key], str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', window[key]):
                frappe.throw("Use 24-hour shift times, such as 08:00 and 16:00.")
    return windows


def require_available(windows, start, end, allowed=None, selected=None):
    windows = validate(windows)
    if allowed:
        windows = [w for w in windows if w['name'] in allowed]
    if selected:
        windows = [w for w in windows if w['name'] == selected]
    cursor = start
    while cursor < end:
        finish = cursor
        for offset in (-1, 0):
            day = cursor.date() + timedelta(days=offset)
            for w in windows:
                begins = datetime.combine(day, datetime.strptime(w['start'], '%H:%M').time())
                ends = datetime.combine(day, datetime.strptime(w['end'], '%H:%M').time())
                if ends <= begins:
                    ends += timedelta(days=1)
                if begins <= cursor < ends:
                    finish = max(finish, ends)
        if finish == cursor:
            frappe.throw("The allocation includes time outside this machine's configured shifts.")
        cursor = min(finish, end)
