import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// NUI is served from nui://blacklist_carnival/web/dist/index.html, so all asset
// URLs must be relative.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsDir: 'assets',
    chunkSizeWarningLimit: 1200,
    sourcemap: false,
  },
  test: {
    globals: true,
    environment: 'node',
  },
});
