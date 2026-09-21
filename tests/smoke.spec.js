const { test, expect } = require('@playwright/test');

test('Playwright home page exposes the getting-started guide', async ({ page }) => {
  await page.goto('https://playwright.dev');

  await expect(page.getByRole('link', { name: 'Get started' })).toBeVisible();
});
