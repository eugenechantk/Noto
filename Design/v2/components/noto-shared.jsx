// Noto — shared primitives: tokens, icons, rows, accordion, capsule, pills.
// All-dark, minimal. Pure black bg. Visible markdown syntax (#/##) styled
// lighter than the heading text.

const NOTO = {
  bg:        '#000000',
  // pill / capsule fill
  pill:      '#2C2C2E',
  pillEdge:  'rgba(255,255,255,0.06)',
  // text
  fg:        '#FFFFFF',
  fgMuted:   'rgba(255,255,255,0.55)',
  fgFaint:   'rgba(255,255,255,0.32)',
  // markdown syntax tokens (#, ##, ###, <!-- -->)
  syntax:    'rgba(255,255,255,0.22)',
  // dividers
  hairline:  'rgba(255,255,255,0.07)',
  // metadata accordion bar
  metaBg:    '#15161A',
  metaFg:    'rgba(255,255,255,0.82)',
  font:      '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro", "Helvetica Neue", system-ui, sans-serif',
};

// ─────────────────────────────────────────────────────────────
// Icons — consistent outline language, 1.5–1.8 stroke
// All accept {size, color}; default color: currentColor.
// ─────────────────────────────────────────────────────────────
function NIcon({ name, size = 20, color = 'currentColor', strokeWidth }) {
  const s = size;
  const sw = strokeWidth ?? 1.6;
  const common = { width: s, height: s, viewBox: '0 0 24 24', fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
  switch (name) {
    case 'gear':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1.03 1.56V21a2 2 0 1 1-4 0v-.09A1.7 1.7 0 0 0 9 19.4a1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.56-1.03H3a2 2 0 1 1 0-4h.09A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34H9a1.7 1.7 0 0 0 1-1.56V3a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 1 1.56 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87V9c.27.62.86 1.03 1.51 1.03H21a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.51 1z" />
        </svg>
      );
    case 'doc-plus':
      return (
        <svg {...common}>
          <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
          <path d="M14 3v5h5" />
          <path d="M12 12v6M9 15h6" />
        </svg>
      );
    case 'plus':
      return (
        <svg {...common}>
          <path d="M12 5v14M5 12h14" />
        </svg>
      );
    case 'folder':
      return (
        <svg {...common}>
          <path d="M3 7.2c0-1.1.9-2 2-2h4.2c.5 0 1 .2 1.4.6L12 7.2h7a2 2 0 0 1 2 2v8.6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7.2z" />
        </svg>
      );
    case 'doc':
      return (
        <svg {...common}>
          <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
          <path d="M14 3v5h5" />
        </svg>
      );
    case 'calendar':
      return (
        <svg {...common}>
          <rect x="3.5" y="5" width="17" height="15.5" rx="2.2" />
          <path d="M3.5 9.5h17M8 3v4M16 3v4" />
        </svg>
      );
    case 'search':
      return (
        <svg {...common}>
          <circle cx="10.5" cy="10.5" r="6.5" />
          <path d="M20 20l-4.5-4.5" />
        </svg>
      );
    case 'compose':
      return (
        <svg {...common}>
          <path d="M19 12.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h6.5" />
          <path d="M17 3.5l3.5 3.5L12 15.5H8.5V12L17 3.5z" />
        </svg>
      );
    case 'chevron-left':
      return (
        <svg {...common} strokeWidth={sw + 0.2}>
          <path d="M15 5l-7 7 7 7" />
        </svg>
      );
    case 'chevron-right':
      return (
        <svg {...common} strokeWidth={sw + 0.2}>
          <path d="M9 5l7 7-7 7" />
        </svg>
      );
    case 'ellipsis':
      return (
        <svg width={s} height={s} viewBox="0 0 24 24" fill={color}>
          <circle cx="5" cy="12" r="1.8" />
          <circle cx="12" cy="12" r="1.8" />
          <circle cx="19" cy="12" r="1.8" />
        </svg>
      );
    case 'sidebar':
      return (
        <svg {...common}>
          <rect x="3.5" y="5" width="17" height="14" rx="2.2" />
          <path d="M9.5 5v14" />
        </svg>
      );
    case 'arrow-back':
      return (
        <svg {...common}>
          <path d="M19 12H5M11 6l-6 6 6 6" />
        </svg>
      );
    case 'arrow-fwd':
      return (
        <svg {...common}>
          <path d="M5 12h14M13 6l6 6-6 6" />
        </svg>
      );
    case 'caret-right': // accordion ">" marker
      return (
        <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M9 6l6 6-6 6" />
        </svg>
      );
    case 'caret-down': // toolbar dropdown caret on macOS
      return (
        <svg width={s} height={s} viewBox="0 0 24 24" fill={color}>
          <path d="M7 10l5 5 5-5z" />
        </svg>
      );
    default:
      return null;
  }
}

// ─────────────────────────────────────────────────────────────
// Capsule pill — base for grouped icon buttons.
// `pad` controls inner horizontal padding; height fixed at `h`.
// ─────────────────────────────────────────────────────────────
function NPill({ children, h = 36, pad = 4, style = {} }) {
  return (
    <div style={{
      height: h,
      borderRadius: h / 2,
      background: NOTO.pill,
      boxShadow: `inset 0 0.5px 0 rgba(255,255,255,0.08), inset 0 -0.5px 0 rgba(0,0,0,0.5)`,
      padding: `0 ${pad}px`,
      display: 'flex',
      alignItems: 'center',
      ...style,
    }}>
      {children}
    </div>
  );
}

// Round circle pill (for single-icon buttons)
function NCircle({ icon, size = 36, iconSize = 18, color = NOTO.fg }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: size / 2,
      background: NOTO.pill,
      boxShadow: `inset 0 0.5px 0 rgba(255,255,255,0.08), inset 0 -0.5px 0 rgba(0,0,0,0.5)`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <NIcon name={icon} size={iconSize} color={color} />
    </div>
  );
}

// Icon-in-pill button (for groups inside a single capsule)
function NPillBtn({ icon, iconSize = 18, gap }) {
  return (
    <div style={{
      width: 36, height: 36, borderRadius: 18,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      marginLeft: gap, marginRight: gap,
    }}>
      <NIcon name={icon} size={iconSize} color={NOTO.fg} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Floating bottom capsule (iOS) — 3 icons: today / search / compose
// ─────────────────────────────────────────────────────────────
function NFloatingCapsule() {
  return (
    <div style={{
      height: 50, borderRadius: 25,
      background: NOTO.pill,
      boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.10), inset 0 -0.5px 0 rgba(0,0,0,0.4), 0 8px 22px rgba(0,0,0,0.6)',
      display: 'flex', alignItems: 'center',
      padding: '0 6px',
    }}>
      {['calendar', 'search', 'compose'].map((n, i) => (
        <div key={n} style={{
          width: 50, height: 50, display: 'flex',
          alignItems: 'center', justifyContent: 'center',
        }}>
          <NIcon name={n} size={20} color={NOTO.fg} strokeWidth={1.7} />
        </div>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Folder row — folder icon + name + count subtitle
// ─────────────────────────────────────────────────────────────
function NFolderRow({ name, count = '0 files, 0 folders', divider = true, padH = 16 }) {
  return (
    <div style={{ padding: `0 ${padH}px` }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 14,
        padding: '11px 0 12px',
        borderBottom: divider ? `0.5px solid ${NOTO.hairline}` : 'none',
      }}>
        <div style={{ width: 28, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <NIcon name="folder" size={26} color={NOTO.fg} strokeWidth={1.3} />
        </div>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ color: NOTO.fg, fontSize: 17, fontWeight: 600, letterSpacing: -0.3, lineHeight: 1.2 }}>{name}</div>
          <div style={{ color: NOTO.fgMuted, fontSize: 13, fontWeight: 400, marginTop: 2, letterSpacing: -0.1 }}>{count}</div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Note row — doc icon + name + time subtitle
// ─────────────────────────────────────────────────────────────
function NNoteRow({ name, time = '52 sec', divider = true, padH = 16 }) {
  return (
    <div style={{ padding: `0 ${padH}px` }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 14,
        padding: '11px 0 12px',
        borderBottom: divider ? `0.5px solid ${NOTO.hairline}` : 'none',
      }}>
        <div style={{ width: 28, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <NIcon name="doc" size={24} color={NOTO.fg} strokeWidth={1.3} />
        </div>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ color: NOTO.fg, fontSize: 17, fontWeight: 600, letterSpacing: -0.3, lineHeight: 1.2 }}>{name}</div>
          <div style={{ color: NOTO.fgMuted, fontSize: 13, fontWeight: 400, marginTop: 2, letterSpacing: -0.1 }}>{time}</div>
        </div>
      </div>
    </div>
  );
}

// Compact note row used inside the macOS list pane
function NCompactNoteRow({ name, time, selected = false }) {
  return (
    <div style={{
      padding: '10px 14px 11px',
      borderRadius: 8,
      background: selected ? 'rgba(255,255,255,0.06)' : 'transparent',
      display: 'flex', flexDirection: 'column', gap: 2,
    }}>
      <div style={{
        color: NOTO.fg, fontSize: 13, fontWeight: 500, letterSpacing: -0.1,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{name}</div>
      <div style={{ color: NOTO.fgMuted, fontSize: 11, letterSpacing: 0 }}>{time}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Metadata accordion (collapsed). `>` caret + "Metadata" + count.
// ─────────────────────────────────────────────────────────────
function NMetaAccordion({ count = 3 }) {
  return (
    <div style={{
      background: NOTO.metaBg,
      borderRadius: 10,
      padding: '12px 16px',
      display: 'flex', alignItems: 'center', gap: 10,
    }}>
      <NIcon name="caret-right" size={14} color={NOTO.metaFg} />
      <div style={{ color: NOTO.metaFg, fontSize: 14, fontWeight: 500, letterSpacing: -0.1, flex: 1 }}>Metadata</div>
      <div style={{ color: NOTO.fgFaint, fontSize: 13, fontVariantNumeric: 'tabular-nums' }}>{count}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Markdown rendering — visible literal #/## chars styled lighter.
// `level` 1 = H1, 2 = H2, 3 = H3. Inline ' # ' acts as decoration.
// ─────────────────────────────────────────────────────────────
function NHeading({ level = 1, children, marginTop, marginBottom }) {
  const sizes = {
    1: { fs: 28, lh: 1.18, hashFs: 28, weight: 700 },
    2: { fs: 20, lh: 1.25, hashFs: 20, weight: 700 },
    3: { fs: 17, lh: 1.3, hashFs: 17, weight: 700 },
  };
  const cfg = sizes[level];
  const hash = '#'.repeat(level);
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', gap: 10,
      marginTop, marginBottom,
      letterSpacing: -0.4,
    }}>
      <span style={{
        color: NOTO.syntax,
        fontSize: cfg.hashFs,
        fontWeight: cfg.weight,
        lineHeight: cfg.lh,
        flexShrink: 0,
      }}>{hash}</span>
      <span style={{
        color: NOTO.fg,
        fontSize: cfg.fs,
        fontWeight: cfg.weight,
        lineHeight: cfg.lh,
      }}>{children}</span>
    </div>
  );
}

function NBody({ children, color = NOTO.fg, marginTop, marginBottom, fontSize = 15 }) {
  return (
    <p style={{
      color,
      fontSize,
      lineHeight: 1.5,
      letterSpacing: -0.1,
      margin: 0,
      marginTop, marginBottom,
    }}>{children}</p>
  );
}

// HTML comment shown as visible markdown syntax (used in macOS sample)
function NComment({ children, marginTop, marginBottom }) {
  return (
    <div style={{
      fontFamily: '"SF Mono", "JetBrains Mono", ui-monospace, monospace',
      color: NOTO.syntax,
      fontSize: 14,
      letterSpacing: 0,
      marginTop, marginBottom,
    }}>{`<!-- ${children} -->`}</div>
  );
}

// iOS / iPadOS status bar — generic dark
function NStatusBar({ time = '6:05', right = ['signal','wifi','battery'], wide = false }) {
  return (
    <div style={{
      height: 54,
      padding: wide ? '0 30px 0 30px' : '0 32px 0 30px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      color: NOTO.fg,
      fontFamily: NOTO.font, fontWeight: 600, fontSize: 15, letterSpacing: 0.2,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>{time}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
        {right.includes('signal') && (
          <svg width="17" height="11" viewBox="0 0 17 11" fill="none">
            <circle cx="2" cy="9" r="1.1" fill="rgba(255,255,255,0.55)" />
            <circle cx="6" cy="9" r="1.1" fill="rgba(255,255,255,0.55)" />
            <circle cx="10" cy="9" r="1.1" fill="rgba(255,255,255,0.55)" />
            <circle cx="14" cy="9" r="1.1" fill="rgba(255,255,255,0.55)" />
          </svg>
        )}
        {right.includes('wifi') && (
          <svg width="17" height="12" viewBox="0 0 17 12" fill="#fff">
            <path d="M8.5 2.3c2.7 0 5.1 1 7 2.7l1.3-1.3A11.5 11.5 0 0 0 0 3.6L1.3 5A10 10 0 0 1 8.5 2.3z"/>
            <path d="M8.5 6c1.5 0 2.8.5 3.8 1.4l1.3-1.3A7.5 7.5 0 0 0 3.4 6L4.7 7.4A5.7 5.7 0 0 1 8.5 6z"/>
            <circle cx="8.5" cy="10" r="1.7"/>
          </svg>
        )}
        {right.includes('battery-text') && (
          <span style={{ fontSize: 13, fontWeight: 500, color: 'rgba(255,255,255,0.85)' }}>100%</span>
        )}
        {right.includes('battery') && (
          <svg width="28" height="13" viewBox="0 0 28 13">
            <rect x="0.5" y="0.5" width="23" height="12" rx="3" fill="none" stroke="rgba(255,255,255,0.45)" />
            <rect x="2" y="2" width="20" height="9" rx="2" fill="#fff" />
            <path d="M25 4v5c.9-.3 1.5-1.2 1.5-2.5S25.9 4.3 25 4z" fill="rgba(255,255,255,0.45)" />
          </svg>
        )}
      </div>
    </div>
  );
}

// macOS traffic lights
function NTrafficLights() {
  const dot = (bg) => (
    <div style={{
      width: 12, height: 12, borderRadius: '50%', background: bg,
      boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)',
    }} />
  );
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      {dot('#ff5f57')}{dot('#febc2e')}{dot('#28c840')}
    </div>
  );
}

Object.assign(window, {
  NOTO,
  NIcon, NPill, NCircle, NPillBtn,
  NFloatingCapsule,
  NFolderRow, NNoteRow, NCompactNoteRow,
  NMetaAccordion,
  NHeading, NBody, NComment,
  NStatusBar, NTrafficLights,
});
