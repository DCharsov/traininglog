import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
 testDir: './update-tests', workers: 1, timeout: 60000, expect: { timeout: 15000 }, reporter: 'list',
 use: { baseURL: 'http://127.0.0.1:5187' },
 projects: [
  { name: 'edge-mobile', use: { browserName: 'chromium', channel: 'msedge', viewport: { width: 390, height: 844 } } },
  { name: 'iphone-16-pro-max', use: { ...devices['iPhone 16 Pro Max'], browserName: 'webkit' } },
 ],
 webServer: { command: 'node scripts/update-test-server.mjs', url: 'http://127.0.0.1:5187/__update-test__/release', reuseExistingServer: false },
})
