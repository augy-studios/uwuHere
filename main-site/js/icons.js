// Inline SVG icons. No emoji anywhere in this app.
// viewBox "0 0 24 24", stroke="currentColor", stroke-width 1.8, round caps
// and joins, fill="none". Icons inherit colour via currentColor, so never
// hardcode a fill or stroke colour.

const svg = (body) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

export const icons = {
  // The four the theme spec asks for.
  sun: svg(`<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>`),
  moon: svg(`<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>`),
  close: svg(`<path d="M18 6 6 18M6 6l12 12"/>`),
  clock: svg(`<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>`),

  // The edge tray's tab. Points right, "push away"; CSS turns it round.
  chevronRight: svg(`<path d="m9 5 7 7-7 7"/>`),

  home: svg(`<path d="M3 11l9-7 9 7"/><path d="M5 10v10h5v-6h4v6h5V10"/>`),
  settings: svg(`<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>`),
  download: svg(`<path d="M12 4v11M7 10l5 5 5-5"/><path d="M4 20h16"/>`),
  copy: svg(`<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>`),
  trash: svg(`<path d="M4 7h16M10 11v6M14 11v6"/><path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/><path d="M9 7V4h6v3"/>`),
  check: svg(`<path d="M20 6 9 17l-5-5"/>`),
  plus: svg(`<path d="M12 5v14M5 12h14"/>`),
  pause: svg(`<path d="M9 5v14M15 5v14"/>`),
  play: svg(`<path d="M7 4.5v15l12-7.5z"/>`),
  stop: svg(`<rect x="6" y="6" width="12" height="12" rx="2"/>`),
  pin: svg(`<path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/>`),
  wifi: svg(`<path d="M2 8.8a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><path d="M12 19.5v.01"/>`),
  users: svg(`<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14a6.5 6.5 0 0 1 3 6"/>`),
  hand: svg(`<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11"/><path d="M11 10V4.5a1.5 1.5 0 0 1 3 0V11"/><path d="M14 10.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5a6 6 0 0 1-4.6-2.2L2.6 15.6a1.5 1.5 0 0 1 2.3-1.9L8 16"/>`),
  door: svg(`<path d="M14 4H6v16h8"/><path d="M14 4l5 1.5v13L14 20z"/><path d="M11 12h.01"/>`),
  lock: svg(`<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>`),
  qr: svg(`<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 17h4v4h-4"/>`),
  link: svg(`<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>`),
  alert: svg(`<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.01"/>`),
  // The Android app's tray buttons: notifications, and checking for a new
  // version (a download in a circle, apart from the CSV's plain download).
  bell: svg(`<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>`),
  appUpdate: svg(`<circle cx="12" cy="12" r="9"/><path d="M12 7.5v8M8.5 12l3.5 3.5 3.5-3.5"/>`),
  refresh: svg(`<path d="M3 12a9 9 0 0 1 15.5-6.3L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15.5 6.3L3 16"/><path d="M3 21v-5h5"/>`),
};

export function icon(name) {
  return icons[name] || "";
}
