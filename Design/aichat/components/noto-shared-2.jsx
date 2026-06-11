// Additional Noto primitives for the second batch of baseline screens.
// Depends on noto-shared.jsx (NOTO, NIcon, NPill, NCircle, etc.).

// ─────────────────────────────────────────────────────────────
// Inline rich text — body with optional italic spans + hyperlinks.
// Pass an array of children: strings, or { italic: '...' }, or { link: '...' }
// ─────────────────────────────────────────────────────────────
function NRichBody({ parts, fontSize = 15, color = NOTO.fg, marginTop, marginBottom, highlights = [] }) {
  // highlights is a list of { word, active } substrings to wrap inline. We
  // do a simple case-insensitive split per plain-text chunk.
  const renderText = (txt, keyPrefix) => {
    if (!highlights.length) return txt;
    const pattern = new RegExp('(' + highlights.map(h => h.word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')', 'gi');
    const pieces = String(txt).split(pattern);
    return pieces.map((p, i) => {
      const hit = highlights.find(h => h.word.toLowerCase() === p.toLowerCase());
      if (!hit) return <React.Fragment key={keyPrefix + '-' + i}>{p}</React.Fragment>;
      return (
        <span key={keyPrefix + '-' + i} style={{
          background: hit.active ? '#E6B62A' : 'rgba(255,255,255,0.18)',
          color: hit.active ? '#1a1100' : NOTO.fg,
          borderRadius: 2,
          padding: '0 1px',
        }}>{p}</span>
      );
    });
  };
  return (
    <p style={{
      color, fontSize, lineHeight: 1.5, letterSpacing: -0.1, margin: 0,
      marginTop, marginBottom,
    }}>
      {parts.map((p, i) => {
        if (typeof p === 'string') return <React.Fragment key={i}>{renderText(p, 'p' + i)}</React.Fragment>;
        if (p.italic !== undefined) return (
          <span key={i} style={{ fontStyle: 'italic', color: NOTO.fgMuted }}>
            <span style={{ color: NOTO.syntax }}>*</span>
            {renderText(p.italic, 'i' + i)}
            <span style={{ color: NOTO.syntax }}>*</span>
          </span>
        );
        if (p.link !== undefined) return (
          <a key={i} href="#" onClick={e => e.preventDefault()} style={{
            color: '#4DA3FF', textDecoration: 'underline', textDecorationColor: 'rgba(77,163,255,0.45)',
            textUnderlineOffset: '3px',
          }}>{renderText(p.link, 'l' + i)}</a>
        );
        if (p.quoted !== undefined) return (
          <span key={i}>"{renderText(p.quoted, 'q' + i)}"</span>
        );
        return null;
      })}
    </p>
  );
}

// Inline image placeholder block — soft gray panel with dimensions
function NImagePlaceholder({ width = '100%', height = 200, label = '1200 × 500', marginTop }) {
  return (
    <div style={{
      width, height, marginTop,
      background: '#D6D6D6',
      borderRadius: 10,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: 'rgba(0,0,0,0.32)', fontSize: Math.min(60, height * 0.30),
      fontWeight: 500, letterSpacing: -1,
      fontFamily: NOTO.font,
    }}>{label}</div>
  );
}

// Blockquote — `> ` prefix in syntax color, content in body color
function NBlockquote({ children, marginTop, fontSize = 15 }) {
  return (
    <div style={{
      marginTop, display: 'flex', gap: 8, alignItems: 'baseline',
      color: NOTO.fg, fontSize, lineHeight: 1.5, letterSpacing: -0.1,
    }}>
      <span style={{ color: NOTO.syntax, flexShrink: 0 }}>&gt;</span>
      <div style={{ flex: 1 }}>{children}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Search field pill (rounded capsule) with leading magnifier + trailing clear
// ─────────────────────────────────────────────────────────────
function NSearchField({ value = '', placeholder = 'Search', showClear = true, height = 44 }) {
  return (
    <div style={{
      height,
      borderRadius: height / 2,
      background: NOTO.pill,
      boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.08)',
      display: 'flex', alignItems: 'center',
      padding: `0 8px 0 16px`, gap: 10,
    }}>
      <NIcon name="search" size={17} color={NOTO.fgMuted} strokeWidth={1.7} />
      <div style={{
        flex: 1, color: value ? NOTO.fg : NOTO.fgMuted, fontSize: 16, letterSpacing: -0.1,
        display: 'flex', alignItems: 'center', gap: 1,
      }}>
        {value || placeholder}
        {value && (
          <span style={{
            display: 'inline-block', width: 1.5, height: 18, background: '#4DA3FF',
            marginLeft: 2, verticalAlign: 'middle',
          }} />
        )}
      </div>
      {showClear && value && (
        <div style={{
          width: 22, height: 22, borderRadius: 11,
          background: 'rgba(255,255,255,0.22)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#1A1A1A', fontSize: 13, fontWeight: 700,
        }}>
          <svg width="10" height="10" viewBox="0 0 10 10" stroke="#1A1A1A" strokeWidth="1.8" strokeLinecap="round">
            <path d="M2 2l6 6M8 2l-6 6" />
          </svg>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Segmented control — "Title + Content ⌘1 / Title ⌘2"
// ─────────────────────────────────────────────────────────────
function NSegmented({ options, selected = 0 }) {
  return (
    <div style={{
      display: 'flex',
      borderRadius: 10,
      background: 'transparent',
      padding: 0,
      gap: 0,
    }}>
      {options.map((o, i) => (
        <div key={i} style={{
          flex: 1, padding: '10px 12px',
          background: i === selected ? 'rgba(255,255,255,0.10)' : 'transparent',
          borderRadius: 8,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          color: NOTO.fg, fontSize: 14, fontWeight: 500, letterSpacing: -0.1,
        }}>
          <span>{o.label}</span>
          {o.kbd && <span style={{ color: NOTO.fgMuted, fontSize: 13 }}>{o.kbd}</span>}
        </div>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Three-line list icon (used as left glyph on search/mention rows)
// ─────────────────────────────────────────────────────────────
function NListGlyph({ size = 20, color = NOTO.fg }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round">
      <path d="M4 7h12M4 12h16M4 17h10" />
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Search result row — list glyph + title + breadcrumb + heading + body
// ─────────────────────────────────────────────────────────────
function NSearchResult({ title, path, headingMatch, body, divider = true, padH = 16 }) {
  return (
    <div style={{ padding: `0 ${padH}px` }}>
      <div style={{
        display: 'flex', gap: 14, padding: '14px 0 14px',
        borderBottom: divider ? `0.5px solid ${NOTO.hairline}` : 'none',
      }}>
        <div style={{ width: 22, flexShrink: 0, paddingTop: 3 }}>
          <NListGlyph size={20} color={NOTO.fg} />
        </div>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{
            color: NOTO.fg, fontSize: 16, fontWeight: 700, letterSpacing: -0.2, lineHeight: 1.25,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{title}</div>
          <div style={{
            color: NOTO.fgMuted, fontSize: 12, marginTop: 3, letterSpacing: -0.05,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{path}</div>
          {headingMatch && (
            <div style={{
              color: NOTO.fg, fontSize: 14, marginTop: 6, lineHeight: 1.35,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}>{headingMatch}</div>
          )}
          {body && (
            <div style={{
              color: NOTO.fgMuted, fontSize: 14, marginTop: 2, lineHeight: 1.35,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}>{body}</div>
          )}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Mention row — bold title + path subtitle + chevron
// ─────────────────────────────────────────────────────────────
function NMentionRow({ title, path, divider = true, padH = 18 }) {
  return (
    <div style={{ padding: `0 ${padH}px` }}>
      <div style={{
        display: 'flex', gap: 10, alignItems: 'center', padding: '12px 0 13px',
        borderBottom: divider ? `0.5px solid ${NOTO.hairline}` : 'none',
      }}>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{
            color: NOTO.fg, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, lineHeight: 1.3,
          }}>{title}</div>
          <div style={{
            color: NOTO.fgMuted, fontSize: 12, marginTop: 2, letterSpacing: -0.05,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{path}</div>
        </div>
        <NIcon name="chevron-right" size={14} color={NOTO.fgFaint} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Settings — section title (eyebrow), grouped card, row, helper text
// ─────────────────────────────────────────────────────────────
function NSettingsLabel({ children, marginTop = 24, padH = 16 }) {
  return (
    <div style={{
      padding: `0 ${padH}px`, marginTop,
      color: NOTO.fg, fontSize: 17, fontWeight: 700, letterSpacing: -0.2,
      marginBottom: 10,
    }}>{children}</div>
  );
}

function NSettingsGroup({ children, padH = 16 }) {
  return (
    <div style={{ padding: `0 ${padH}px` }}>
      <div style={{
        background: '#15161A',
        borderRadius: 14,
        overflow: 'hidden',
      }}>{children}</div>
    </div>
  );
}

function NSettingsRow({ icon, iconNode, title, subtitle, isLast = false, height }) {
  return (
    <div style={{ position: 'relative' }}>
      <div style={{
        minHeight: height || (subtitle ? 64 : 52),
        display: 'flex', alignItems: 'center', gap: 12,
        padding: subtitle ? '12px 16px' : '0 16px',
      }}>
        {iconNode && <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center' }}>{iconNode}</div>}
        {icon && (
          <div style={{ width: 22, flexShrink: 0, display: 'flex' }}>
            <NIcon name={icon} size={20} color={NOTO.fg} strokeWidth={1.6} />
          </div>
        )}
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ color: NOTO.fg, fontSize: 16, letterSpacing: -0.2 }}>{title}</div>
          {subtitle && (
            <div style={{ color: NOTO.fgMuted, fontSize: 13, marginTop: 2, letterSpacing: -0.05 }}>{subtitle}</div>
          )}
        </div>
      </div>
      {!isLast && (
        <div style={{
          position: 'absolute', left: icon || iconNode ? 50 : 16, right: 16, bottom: 0,
          height: 0.5, background: NOTO.hairline,
        }} />
      )}
    </div>
  );
}

function NSettingsHelper({ children, marginTop = 8, padH = 28 }) {
  return (
    <div style={{
      padding: `0 ${padH}px`,
      color: NOTO.fgMuted, fontSize: 13, lineHeight: 1.4, letterSpacing: -0.05,
      marginTop,
    }}>{children}</div>
  );
}

// Refresh icon (custom — circular arrows)
function NRefreshIcon({ size = 20, color = NOTO.fg }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3.5 12a8.5 8.5 0 0 1 14.5-6M20.5 12a8.5 8.5 0 0 1-14.5 6" />
      <path d="M14 6l4 0 0-4M10 18l-4 0 0 4" />
    </svg>
  );
}

Object.assign(window, {
  NRichBody, NImagePlaceholder, NBlockquote,
  NSearchField, NSegmented, NListGlyph,
  NSearchResult, NMentionRow,
  NSettingsLabel, NSettingsGroup, NSettingsRow, NSettingsHelper,
  NRefreshIcon,
});
