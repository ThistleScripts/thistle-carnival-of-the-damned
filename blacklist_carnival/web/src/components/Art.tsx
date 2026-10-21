import React from 'react';

// Background slot. Owners can drop artwork into web/public/backgrounds/
// (<name>.png or <name>.jpg, rebuilt into web/dist/backgrounds/) and it is
// layered over the CSS fallback. A missing file simply leaves the fallback visible.
export function Backdrop({ name, className, children }: { name: string; className?: string; children?: React.ReactNode }) {
  const style: React.CSSProperties = {
    backgroundImage: `url(backgrounds/${name}.png), url(backgrounds/${name}.jpg), var(--fallback-bg)`,
  };
  return <div className={`backdrop backdrop-${name} ${className ?? ''}`} style={style}>{children}</div>;
}

// Original line icons for each attraction (no third-party artwork).
const PATHS: Record<string, React.ReactNode> = {
  shooting: (
    <>
      <circle cx="12" cy="12" r="8" />
      <circle cx="12" cy="12" r="4" />
      <circle cx="12" cy="12" r="1" fill="currentColor" />
      <path d="M12 1v4M12 19v4M1 12h4M19 12h4" />
    </>
  ),
  wheel: (
    <>
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2" />
      <path d="M12 3v7M12 14v7M3 12h7M14 12h7M5.6 5.6l5 5M13.4 13.4l5 5M18.4 5.6l-5 5M10.6 13.4l-5 5" />
    </>
  ),
  fortune: (
    <>
      <circle cx="12" cy="10" r="7" />
      <path d="M7 19h10l-1.5 3h-7z" />
      <path d="M9 8c1-1.5 3-2 4.5-1" />
    </>
  ),
  puppets: (
    <>
      <path d="M4 3h16M8 3v4M16 3v4M12 3v2" />
      <circle cx="12" cy="8" r="2" />
      <path d="M12 10v6M8 12l4-1 4 1M10 21l2-5 2 5" />
      <path d="M8 7l0 5M16 7l0 5" strokeDasharray="1 1.5" />
    </>
  ),
  deception: (
    <>
      <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" />
      <circle cx="12" cy="12" r="3" />
      <path d="M4 20L20 4" />
    </>
  ),
  horror: (
    <>
      <path d="M12 3c-4.4 0-7 3-7 7 0 2.5 1.2 4.3 3 5.3V19h8v-3.7c1.8-1 3-2.8 3-5.3 0-4-2.6-7-7-7z" />
      <circle cx="9.5" cy="10.5" r="1.5" fill="currentColor" />
      <circle cx="14.5" cy="10.5" r="1.5" fill="currentColor" />
      <path d="M10 19v2M12 19v2M14 19v2" />
    </>
  ),
  ticket: (
    <>
      <path d="M3 7h18v3a2 2 0 000 4v3H3v-3a2 2 0 000-4z" />
      <path d="M14 7v10" strokeDasharray="1.5 1.5" />
    </>
  ),
  crown: <path d="M3 18h18l-2-10-4 4-3-6-3 6-4-4z" />,
  home: (
    <>
      <path d="M3 11l9-7 9 7" />
      <path d="M5 10v10h5v-6h4v6h5V10" />
    </>
  ),
  people: (
    <>
      <circle cx="9" cy="8" r="3.2" />
      <path d="M3 20c.6-3.4 3-5.4 6-5.4s5.4 2 6 5.4" />
      <circle cx="17" cy="9" r="2.4" />
      <path d="M16.5 14.2c2.4.2 4 1.9 4.5 4.8" />
    </>
  ),
  gear: (
    <>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1" />
    </>
  ),
  shield: (
    <>
      <path d="M12 3l8 3v6c0 4.5-3.4 7.8-8 9-4.6-1.2-8-4.5-8-9V6z" />
      <path d="M8.5 12l2.5 2.5 4.5-5" />
    </>
  ),
  coin: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="5.5" />
      <path d="M12 8.5v7" />
    </>
  ),
};

export function Icon({ name, size = 20, className }: { name: string; size?: number; className?: string }) {
  return (
    <svg className={`icon ${className ?? ''}`} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {PATHS[name] ?? <circle cx="12" cy="12" r="8" />}
    </svg>
  );
}
