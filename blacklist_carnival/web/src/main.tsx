import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
// Bundled display/body fonts (SIL Open Font License) so the UI looks the same offline.
import '@fontsource/cinzel/latin-400.css';
import '@fontsource/cinzel/latin-600.css';
import '@fontsource/cinzel/latin-700.css';
import '@fontsource/cinzel-decorative/latin-700.css';
import '@fontsource/cormorant-garamond/latin-500.css';
import '@fontsource/cormorant-garamond/latin-500-italic.css';
import '@fontsource/cormorant-garamond/latin-600.css';
import '@fontsource/inter/latin-400.css';
import '@fontsource/inter/latin-500.css';
import '@fontsource/inter/latin-600.css';
import '@fontsource/inter/latin-700.css';
import './styles.css';
import { fetchNui, isNui } from './nui';
import { loadLocale } from './i18n';
import { installBridge } from './bridge';

installBridge();

// Scale every panel to the screen: designed at 2400×1350, so about 0.8 at
// 1080p and 1 at 1440p and above. Players can make it bigger or smaller with
// /carnivalui (uiScale message from Lua).
let uiScale = 1;
function applyZoom() {
  const fit = Math.min(window.innerWidth / 2400, window.innerHeight / 1350);
  const zoom = Math.max(0.45, Math.min(1.4, fit * uiScale));
  document.documentElement.style.setProperty('--ui-zoom', zoom.toFixed(3));
}
window.addEventListener('resize', applyZoom);
window.addEventListener('message', (ev) => {
  const m = ev.data;
  if (m && m.action === 'uiScale' && typeof m.data?.scale === 'number') {
    uiScale = Math.max(0.5, Math.min(1.5, m.data.scale));
    applyZoom();
  }
});
applyZoom();

loadLocale().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  );
  if (isNui) fetchNui('ready').catch(() => undefined);
});
