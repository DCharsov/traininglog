import { defineConfig, devices } from '@playwright/test'
export default defineConfig({ testDir: './e2e', use: { baseURL: 'http://127.0.0.1:5173' }, projects:[
 {name:'edge-mobile',use:{browserName:'chromium',channel:process.platform==='win32'?'msedge':undefined,viewport:{width:390,height:844}}},
 {name:'iphone-16-pro-max',use:{...devices['iPhone 16 Pro Max'],browserName:'webkit'}}
], webServer: { command: 'npm run dev -- --host 127.0.0.1 --port 5173 --strictPort', url: 'http://127.0.0.1:5173', reuseExistingServer: !process.env.CI }, reporter: 'list' })
