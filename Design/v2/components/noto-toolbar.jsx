// Noto's keyboard accessory toolbar — 7 icons in canonical left-to-right order:
//   1. todo (checklist)
//   2. indent-right
//   3. indent-left
//   4. strikethrough
//   5. link
//   6. image
//   7. keyboard-dismiss
//
// Reusable across all v3 explorations. The `variant` prop swaps the visual
// treatment (pill / hairline / mono-uppercase / pearl / strip).

function NotoIcons({ stroke = 'currentColor', size = 18 }) {
  // Pure SVG icon set drawn to a consistent 24x24 viewBox.
  const sw = 1.7;
  return {
    todo: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <circle cx="4.5" cy="6.5" r="1.2" fill={stroke} stroke="none"/>
        <path d="M8 6.5h11" />
        <path d="M3 12.5l1.6 1.6L7 11.5" />
        <path d="M9.5 13h9" />
        <circle cx="4.5" cy="18.5" r="1.2" fill={stroke} stroke="none"/>
        <path d="M8 18.5h11" />
      </svg>
    ),
    indentRight: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 5h18M9 12h12M9 19h12" />
        <path d="M3 9l3 3-3 3" />
      </svg>
    ),
    indentLeft: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 5h18M3 12h12M3 19h18" />
        <path d="M21 9l-3 3 3 3" />
      </svg>
    ),
    strike: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <path d="M16 7c-.7-1.5-2.5-2.5-4.5-2.5C9 4.5 7 6 7 7.9c0 1.4 1 2.5 3 3.1" />
        <path d="M8 16.2c.6 1.5 2.4 2.8 4.7 2.8 3 0 4.8-1.7 4.8-3.6 0-1-.4-1.9-1.4-2.4" />
        <path d="M3.5 12.5h17" />
      </svg>
    ),
    link: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 14a4 4 0 005.7 0l3-3a4 4 0 00-5.7-5.7L11.5 7" />
        <path d="M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 005.7 5.7L12.5 17" />
      </svg>
    ),
    image: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <rect x="3.5" y="4.5" width="17" height="15" rx="2.5" />
        <circle cx="9" cy="10" r="1.5" />
        <path d="M3.5 16l4.5-4 4 4 3-3 5 5" />
      </svg>
    ),
    dismiss: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="5" width="18" height="11" rx="2" />
        <path d="M7 9h.01M11 9h.01M15 9h.01M17 9h.01M7 12h.01M11 12h.01M15 12h.01M17 12h.01" strokeWidth="2.4"/>
        <path d="M8 14.5h8" />
        <path d="M9 19l3 2 3-2" />
      </svg>
    ),
  };
}

// canonical order
const NOTO_TOOLBAR_KEYS = ['todo', 'indentRight', 'indentLeft', 'strike', 'link', 'image', 'dismiss'];

// ─── variant 1: minimalist dark — dark pill, faded gray glyphs ────────────
function NotoToolbarMinimal({ wordCount = 258 }) {
  const ic = NotoIcons({ stroke: 'rgba(255,255,255,0.62)', size: 17 });
  return (
    <div style={{ padding: '4px 14px 0', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
      <div style={{
        background: 'rgba(30,30,32,0.92)',
        border: '0.5px solid rgba(255,255,255,0.08)',
        borderRadius: 999, padding: '6px 12px',
        display: 'flex', alignItems: 'center', gap: 14,
        boxShadow: '0 4px 14px rgba(0,0,0,0.4)',
      }}>
        {NOTO_TOOLBAR_KEYS.map((k) => <div key={k} style={{ display: 'flex' }}>{ic[k]}</div>)}
      </div>
      <span style={{ color: 'rgba(255,255,255,0.22)', fontSize: 10, letterSpacing: 0.4 }}>{wordCount}</span>
    </div>
  );
}

// ─── variant 2: book — serif, hairline-separated icons on cream ────────────
function NotoToolbarBook({ wordCount = 258, ink = '#5B544A', rule = 'rgba(26,24,20,0.18)' }) {
  const ic = NotoIcons({ stroke: ink, size: 18 });
  return (
    <div style={{ padding: '6px 22px 4px', display: 'flex', flexDirection: 'column', gap: 4 }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        borderTop: '0.5px solid ' + rule,
        paddingTop: 8,
      }}>
        {NOTO_TOOLBAR_KEYS.map((k, i) => (
          <React.Fragment key={k}>
            <div style={{ display: 'flex' }}>{ic[k]}</div>
            {i < 6 && <span style={{ width: 0.5, height: 14, background: rule }} />}
          </React.Fragment>
        ))}
      </div>
      <div style={{ display: 'flex', justifyContent: 'flex-end',
        fontFamily: '"EB Garamond", serif', fontStyle: 'italic',
        fontSize: 11, color: ink, opacity: 0.7 }}>{wordCount} words</div>
    </div>
  );
}

// ─── variant 3: digital article — Pocket-style strip, orange-active ───────
// Horizontally scrollable rail of formatting icons, with a fixed Done pinned
// to the right behind a vertical hairline divider. Done is always visible no
// matter how many tools are added to the scrolling area.
function NotoToolbarArticle({ wordCount = 258, activeKey = null, extraKeys = [] }) {
  const ACCENT = '#FF5A1F';
  const idle = 'rgba(229,229,231,0.62)';
  const RULE = 'rgba(255,255,255,0.10)';
  const BG = '#1A1C22';

  // Scrolling area: everything except "dismiss" (Done is pinned).
  const scrollKeys = NOTO_TOOLBAR_KEYS.filter((k) => k !== 'dismiss').concat(extraKeys);

  const iconBtn = (k, sticky = false) => {
    const active = k === activeKey;
    const color = active ? ACCENT : idle;
    const ic = NotoIcons({ stroke: color, size: 18 });
    return (
      <div
        key={k}
        style={{
          width: 36, height: 36, flexShrink: 0, borderRadius: 8,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color,
        }}
      >
        {ic[k]}
      </div>
    );
  };

  return (
    <div style={{
      padding: '6px 0 4px',
      borderTop: '0.5px solid ' + RULE,
      background: BG,
      display: 'flex', alignItems: 'stretch',
    }}>
      {/* Scrolling rail */}
      <div style={{
        flex: 1, minWidth: 0,
        overflowX: 'auto', overflowY: 'hidden',
        WebkitOverflowScrolling: 'touch',
        scrollbarWidth: 'none',
        display: 'flex', alignItems: 'center', gap: 4,
        padding: '0 8px',
      }}>
        {scrollKeys.map((k) => iconBtn(k))}
      </div>

      {/* Pinned Done with hairline divider */}
      <div style={{
        display: 'flex', alignItems: 'center',
        paddingLeft: 6, paddingRight: 8,
        borderLeft: '0.5px solid ' + RULE,
        background: BG,
      }}>
        {iconBtn('dismiss', true)}
      </div>
    </div>
  );
}

// ─── variant 4: techno — square mono icons + bracketed letter labels ──────
function NotoToolbarTechno({ wordCount = 258 }) {
  const INK = '#EFEFEF';
  const RULE = 'rgba(255,255,255,0.22)';
  const ic = NotoIcons({ stroke: INK, size: 14 });
  const letters = {
    todo: '[T]', indentRight: '[→]', indentLeft: '[←]',
    strike: '[S]', link: '[L]', image: '[I]', dismiss: '[K]',
  };
  return (
    <div style={{
      padding: '8px 14px',
      borderTop: '1px solid ' + RULE,
      borderBottom: '1px solid ' + RULE,
      background: '#0a0a0a',
      fontFamily: '"JetBrains Mono", ui-monospace, "SF Mono", monospace',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
            <span style={{ color: INK, fontSize: 9, letterSpacing: 1 }}>{letters[k]}</span>
            <div style={{
              border: '1px solid ' + RULE,
              padding: 4, borderRadius: 0,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ic[k]}</div>
          </div>
        ))}
      </div>
      <div style={{
        textAlign: 'right', marginTop: 6,
        color: 'rgba(255,255,255,0.50)', fontSize: 10, letterSpacing: 1,
        textTransform: 'uppercase',
      }}>{wordCount}W</div>
    </div>
  );
}

// ─── variant 5: natural — hand-drawn pearl glyphs, no pill, fades into bg ─
function NotoToolbarNatural({ wordCount = 258, ink = '#2A1F1A' }) {
  const ic = NotoIcons({ stroke: ink, size: 17 });
  return (
    <div style={{ padding: '6px 22px 4px', display: 'flex', flexDirection: 'column', gap: 2 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 32, height: 32, borderRadius: 999,
            background: 'rgba(255,250,243,0.55)',
            border: '0.5px solid rgba(42,31,26,0.10)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: '0 2px 6px rgba(120,80,60,0.10)',
          }}>{ic[k]}</div>
        ))}
      </div>
      <div style={{
        textAlign: 'right',
        fontFamily: '"EB Garamond", serif', fontStyle: 'italic',
        fontSize: 11, color: 'rgba(42,31,26,0.55)',
      }}>{wordCount} words</div>
    </div>
  );
}

Object.assign(window, {
  NotoIcons, NOTO_TOOLBAR_KEYS,
  NotoToolbarMinimal, NotoToolbarBook,
  NotoToolbarArticle, NotoToolbarTechno, NotoToolbarNatural,
});
