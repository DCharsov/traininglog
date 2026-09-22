import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  base: '/training/',
  plugins: [react()],
  server: { proxy: { '/training/api': process.env.TRAINING_API_URL ?? 'http://127.0.0.1:5180' } },
})
