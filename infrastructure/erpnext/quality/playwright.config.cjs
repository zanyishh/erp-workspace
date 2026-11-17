const { defineConfig } = require('@playwright/test');
const path = require('node:path');
const report = process.env.ERP_QUALITY_REPORT_DIR;
if (!report) throw new Error('Use the quality runner to preserve reports for each run.');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: 'web.spec.cjs',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30000,
  outputDir: path.join(report, 'playwright-results'),
  reporter: [['list'], ['html', { open: 'never', outputFolder: path.join(report, 'playwright-report') }]],
  use: {
    baseURL: 'http://127.0.0.1:8081',
    browserName: 'chromium',
    headless: true,
    serviceWorkers: 'block',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
});
