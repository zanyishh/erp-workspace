#!/usr/bin/env python3
"""Read back synthetic local test accounts through the real HTTP API. GPL-3.0."""
import http.cookiejar
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = "http://127.0.0.1:8081"


def verify():
    accounts = json.loads((ROOT / ".local/windows-test/accounts.json").read_text(encoding="utf-8-sig"))
    for edition, company in (("general", "Meridian Trading"), ("knitting", "Kaveri Loomworks")):
        session = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

        def rpc(method, **fields):
            request = urllib.request.Request(
                ORIGIN + "/api/method/" + method,
                data=urllib.parse.urlencode(fields).encode(),
            )
            with session.open(request, timeout=60) as response:
                return json.load(response)["message"]

        rpc("login", usr=accounts[edition]["email"], pwd=accounts[edition]["password"])
        context = rpc("erp_extensions.workspace.context")
        assert [row["name"] for row in context["companies"]] == [company], (edition, "company scope")
        assert bool(context["knitting_enabled"]) == (edition == "knitting"), (edition, "industry scope")
        register = rpc("erp_extensions.invoices.register", company=company)
        assert len(register["rows"]) >= 3, (edition, "sample invoices")
        other = "Kaveri Loomworks" if edition == "general" else "Meridian Trading"
        try:
            rpc("erp_extensions.invoices.register", company=other)
        except urllib.error.HTTPError as error:
            assert error.code in (403, 417), (edition, "unexpected access response", error.code)
        else:
            raise AssertionError((edition, "other company must be inaccessible"))
        print(f"PASS: {edition} login, exact company scope, industry, sample invoices and cross-company rejection")


if __name__ == "__main__":
    verify()
