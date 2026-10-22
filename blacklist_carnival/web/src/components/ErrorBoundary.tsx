import React from 'react';
import { fetchNui, isNui } from '../nui';

// Reports interface errors to the game client, which prints them in F8, so a
// problem in game shows up as a readable message instead of a blank screen.
export function reportError(message: string, stack?: string) {
  if (!isNui) return;
  fetchNui('nuiError', { message: String(message).slice(0, 500), stack: String(stack ?? '').slice(0, 2000) }).catch(() => undefined);
}

export function installErrorReporting() {
  window.addEventListener('error', (e) => reportError(e.message, e.error?.stack));
  window.addEventListener('unhandledrejection', (e) => reportError(String((e.reason && e.reason.message) || e.reason), e.reason?.stack));
}

interface State { error: Error | null }

// If a screen fails to draw, show what went wrong (and a way out) instead of
// leaving the player with an empty screen and a mouse cursor.
export class ErrorBoundary extends React.Component<{ onReset: () => void; children: React.ReactNode }, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    reportError(error.message, `${error.stack ?? ''}\n${info.componentStack ?? ''}`);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="overlay-center">
        <div className="panel-frame crash-card">
          <h2>The carnival interface hit a problem</h2>
          <p className="muted">This screen could not be drawn. The details are also printed in your F8 console; please send them to the server owner.</p>
          <pre className="pre">{this.state.error.message}</pre>
          <button className="btn btn-gold" onClick={() => { this.setState({ error: null }); this.props.onReset(); }}>Close</button>
        </div>
      </div>
    );
  }
}
