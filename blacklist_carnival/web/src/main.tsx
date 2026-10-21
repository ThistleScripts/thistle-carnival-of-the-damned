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

loadLocale().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  );
  if (isNui) fetchNui('ready').catch(() => undefined);
});
