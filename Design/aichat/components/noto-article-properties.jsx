// noto-article-properties.jsx
// ─────────────────────────────────────────────────────────────
// Property / metadata surface for the Digital-article reading screen
// (Floating-dock direction). Reworks two baselines into the iOS 26
// Liquid-Glass, dark-first, orange-accent language:
//
//   • v6 "Property pills" (ExpV6PropertyPills) — frontmatter as a pill bin
//     under the H1. Borrowed: the under-H1 placement + tag chips.
//   • "Metadata accordion" (NMetaAccordion) — a collapsed > Metadata [n] row.
//     Borrowed: the collapse-by-default, count-on-the-right idea.
//
// DECISION: a COLLAPSIBLE PROPERTY HEADER, inline above the body.
//   Collapsed by default it is one quiet summary line (folder · n props ·
//   edited) so the reading screen stays minimal. Tapping expands it IN PLACE
//   into a structured Liquid-Glass card — no context switch, no sheet. A sheet
//   would hide reference info behind a tap + a mode change, which fights the
//   "content-first, minimal chrome" floating-dock direction; pure pills get
//   noisy past a few fields and render dates / key-values awkwardly. The card
//   handles tags as chips, source as a link row, dates + folder as icon rows,
//   and shows empty fields as quiet "Add …" affordances.
//
// Exports: ExpArticleProperties({ view })  view ∈ 'collapsed'|'expanded'|'empty'
// Depends on: IOSDevice, ArticleIcon (both on window).

(function () {
  const BG     = '#0E1116';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.62)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF6A2E';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';
  const MONO   = '"JetBrains Mono", "SF Mono", ui-monospace, Menlo, monospace';

  // Liquid-Glass card material (matches the dock's glassStyle)
  const cardGlass = {
    background: 'rgba(28,30,36,0.55)',
    backdropFilter: 'blur(28px) saturate(180%)',
    WebkitBackdropFilter: 'blur(28px) saturate(180%)',
    border: '0.5px solid rgba(255,255,255,0.10)',
    boxShadow: [
      '0 1px 1px rgba(0,0,0,0.18)',
      '0 8px 24px rgba(0,0,0,0.30)',
      'inset 0 0.5px 0 rgba(255,255,255,0.18)',
      'inset 0 -0.5px 0 rgba(0,0,0,0.25)',
    ].join(', '),
  };

  // ─── Property glyphs — thin line icons, muted ───────────────
  function PropIcon({ name, color = FAINT, size = 16 }) {
    const c = { fill: 'none', stroke: color, strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round' };
    switch (name) {
      case 'folder':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><path d="M2.5 6.5a2 2 0 012-2h3.3l1.6 2h7.6a2 2 0 012 2v6.5a2 2 0 01-2 2H4.5a2 2 0 01-2-2z" {...c} /></svg>);
      case 'created':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><rect x="3" y="4.5" width="16" height="14" rx="2.4" {...c} /><path d="M3 8.5h16M7 3v3M15 3v3" {...c} /></svg>);
      case 'modified':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><circle cx="11" cy="11" r="7.5" {...c} /><path d="M11 6.5V11l3 2" {...c} /></svg>);
      case 'text':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><path d="M5 6h12M5 11h12M5 16h7" {...c} /></svg>);
      case 'tag':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><path d="M3.5 4.5h6.2l8 8a1.6 1.6 0 010 2.3l-3.7 3.7a1.6 1.6 0 01-2.3 0l-8-8z" {...c} /><circle cx="7" cy="8" r="1.1" fill={color} stroke="none" /></svg>);
      case 'source':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><path d="M9 13a3.5 3.5 0 005 0l3-3a3.5 3.5 0 00-5-5l-1.2 1.2" {...c} /><path d="M13 9a3.5 3.5 0 00-5 0l-3 3a3.5 3.5 0 005 5l1.2-1.2" {...c} /></svg>);
      case 'status':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><circle cx="11" cy="11" r="7.5" {...c} /><path d="M11 11l3.5-2" {...c} /></svg>);
      case 'person':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><circle cx="11" cy="7.5" r="3.2" {...c} /><path d="M4.5 18a6.5 6.5 0 0113 0" {...c} /></svg>);
      case 'caret':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><path d="M7 5l6 6-6 6" {...c} /></svg>);
      case 'plus':
        return (<svg width={size} height={size} viewBox="0 0 22 22"><path d="M11 5v12M5 11h12" {...c} /></svg>);
      default: return null;
    }
  }

  // ─── A single property row inside the expanded card ─────────
  //   label on the leading edge (icon + name), value on the trailing edge.
  //   `empty` renders a quiet "Add …" affordance instead of a value.
  function PropRow({ icon, label, empty, addLabel, children, last }) {
    return (
      <div style={{
        display: 'flex', alignItems: 'flex-start', gap: 12,
        padding: '9px 0', minHeight: 36, boxSizing: 'border-box',
        borderBottom: last ? 'none' : '0.5px solid ' + RULE,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9, width: 104, flexShrink: 0, paddingTop: 1 }}>
          <PropIcon name={icon} color={empty ? FAINT : MUTED} />
          <span style={{ color: empty ? FAINT : MUTED, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1 }}>{label}</span>
        </div>
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 7, justifyContent: 'flex-end' }}>
          {empty ? (
            <button style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              background: 'none', border: 'none', padding: 0, cursor: 'pointer',
              color: FAINT, fontFamily: SANS, fontSize: 14.5,
            }}>
              <PropIcon name="plus" color={FAINT} size={14} />
              {addLabel}
            </button>
          ) : children}
        </div>
      </div>
    );
  }

  // ─── Value primitives ───────────────────────────────────────
  const ValueText = ({ children, mono, dim }) => (
    <span style={{
      color: dim ? MUTED : INK, fontFamily: mono ? MONO : SANS,
      fontSize: mono ? 13 : 14.5, letterSpacing: mono ? 0 : -0.1,
      textAlign: 'right', lineHeight: 1.35,
    }}>{children}</span>
  );

  const FolderValue = ({ name }) => (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: INK, fontFamily: SANS, fontSize: 14.5, letterSpacing: -0.1 }}>
      <span style={{ width: 7, height: 7, borderRadius: 2, background: ACCENT, flexShrink: 0 }} />
      {name}
      <PropIcon name="caret" color={FAINT} size={13} />
    </span>
  );

  const Chip = ({ children }) => (
    <span style={{
      display: 'inline-flex', alignItems: 'center', height: 28, padding: '0 12px',
      borderRadius: 999, background: 'rgba(255,255,255,0.07)',
      border: '0.5px solid rgba(255,255,255,0.10)',
      color: INK, fontFamily: SANS, fontSize: 12.5, fontWeight: 500, whiteSpace: 'nowrap',
    }}>{children}</span>
  );

  const AddChip = () => (
    <span style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      width: 28, height: 28, borderRadius: 999,
      border: '0.5px dashed rgba(255,255,255,0.22)', cursor: 'pointer',
    }}>
      <PropIcon name="plus" color={FAINT} size={13} />
    </span>
  );

  const SourceValue = ({ domain, path }) => (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, maxWidth: '100%' }}>
      <span style={{ width: 14, height: 14, borderRadius: 3, background: 'linear-gradient(135deg,#FF6A2E,#C2185B)', flexShrink: 0 }} />
      <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 14, letterSpacing: -0.1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {domain}<span style={{ color: FAINT }}>{path}</span>
      </span>
    </span>
  );

  const StatusValue = ({ label, color }) => (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, color: INK, fontFamily: SANS, fontSize: 14.5 }}>
      <span style={{ width: 8, height: 8, borderRadius: 999, background: color, flexShrink: 0, boxShadow: '0 0 0 3px ' + color + '22' }} />
      {label}
    </span>
  );

  // expose primitives to the screen builder below
  window.__notoProps = {
    BG, INK, HEAD, MUTED, FAINT, RULE, ACCENT, SANS, MONO, cardGlass,
    PropIcon, PropRow, ValueText, FolderValue, Chip, AddChip, SourceValue, StatusValue,
  };
})();
