const { test, expect } = require('@playwright/test');

// This is an ERPNext login smoke test; it is not native Flutter UI coverage.
test('synthetic site exposes the login form', async ({ page }) => {
  const origin = 'http://127.0.0.1:8081';
  await page.route('**/*', route => {
    const target = new URL(route.request().url());
    return target.origin === origin ? route.continue() : route.abort();
  });
  await page.goto('/login');
  expect(new URL(page.url()).origin).toBe(origin);
  await expect(page.locator('#login_email')).toBeVisible();
  await expect(page.locator('#login_password')).toBeVisible();
});
