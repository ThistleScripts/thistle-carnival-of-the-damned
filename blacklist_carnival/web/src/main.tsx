import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
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
