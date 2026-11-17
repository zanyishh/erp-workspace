"""Prepared API smoke contract; broader business API schema is still required."""
from pathlib import Path
import http.client

from hypothesis import settings
import pytest
import schemathesis

schema = schemathesis.openapi.from_path(str(Path(__file__).with_name("openapi.json")))


@schema.parametrize()
@settings(max_examples=10, deadline=None)
def test_synthetic_api(case):
    case.call_and_validate(base_url="http://127.0.0.1:8081", allow_redirects=False)


@pytest.mark.parametrize("unsupported", ["TRACE", "QUERY", "HEAD", "PATCH", "PROPFIND"])
def test_ping_method_rejection_advertises_supported_methods(unsupported):
    """The proxy must preserve TRACE rejection and the endpoint's real contract."""
    connection = http.client.HTTPConnection("127.0.0.1", 8081, timeout=10)
    try:
        connection.request(unsupported, "/api/method/ping?contract_check=1")
        response = connection.getresponse()
        response.read()
        assert response.status == 405
        allowed = {method.strip() for method in (response.getheader("Allow") or "").split(",")}
        assert allowed == {"GET", "POST", "PUT", "DELETE", "OPTIONS"}
        assert response.getheader("X-Content-Type-Options") == "nosniff"
        assert response.getheader("X-Frame-Options") == "SAMEORIGIN"
    finally:
        connection.close()

    for method in sorted(allowed):
        connection = http.client.HTTPConnection("127.0.0.1", 8081, timeout=10)
        try:
            connection.request(method, "/api/method/ping")
            response = connection.getresponse()
            response.read()
            assert response.status == 200, method
            assert response.getheader("Allow") is None
        finally:
            connection.close()
