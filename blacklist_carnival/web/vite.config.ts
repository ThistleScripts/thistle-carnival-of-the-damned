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
    // FiveM's NUI runs an older embedded Chromium than desktop browsers. Compile
    // modern syntax (?. ?? etc.) and CSS shorthands (inset, ...) down so the page
    // never fails to start or lays out wrongly in game.
    target: ['es2019', 'chrome75'],
    cssTarget: ['chrome75'],
    chunkSizeWarningLimit: 1200,
    sourcemap: false,
  },
  test: {
    globals: true,
    environment: 'node',
  },
});
