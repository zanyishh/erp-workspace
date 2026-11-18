import http from 'k6/http';
import { check, sleep } from 'k6';

// Small baseline only. Business journeys and agreed peak-load SLOs are pending.
export const options = {
  vus: 1,
  duration: '15s',
  maxRedirects: 0,
  thresholds: {
    http_req_failed: ['rate==0'],
    checks: ['rate==1'],
  },
};

export default function () {
  const response = http.get('http://127.0.0.1:8081/api/method/ping', { timeout: '5s', redirects: 0 });
  check(response, {
    'HTTP 200': r => r.status === 200,
    'Frappe pong': r => {
      try { return r.json('message') === 'pong'; } catch (_) { return false; }
    },
  });
  sleep(1);
}
