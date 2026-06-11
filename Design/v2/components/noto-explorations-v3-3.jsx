// v3 · Focus mode — Digital article.
// Dark canvas, humanist sans. iOS 26 dark keyboard.
// Three states explored:
//   'reading' — keyboard hidden, full bottom navigation toolbar
//   'editing' — keyboard up, 7-icon Noto toolbar (matches baseline reference)
//   'find'    — keyboard up, find-in-note bar above 7-icon toolbar (original)

const ART_BG    = '#15171C';
const ART_INK   = '#E5E5E7';
const ART_HEAD  = '#FAFAFA';
const ART_MUTED = 'rgba(229,229,231,0.55)';
const ART_FAINT = 'rgba(229,229,231,0.32)';
const ART_RULE  = 'rgba(255,255,255,0.08)';
const ART_ACCENT = '#FF5A1F';
const ART_HL    = '#E6B62A';
const ART_SANS  = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

// ─────────────────────────────────────────────────────────────
// Article-voice icons (line-art, 1.7 stroke, rounded caps).
// Tiny + uppercase 9px label, Pocket-style.
// ─────────────────────────────────────────────────────────────
function ArticleIcon({ name, color = ART_FAINT, size = 18 }) {
  const sw = 1.7;
  const c = { fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
  switch (name) {
    case 'sidebar':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <rect x="3" y="4" width="18" height="16" rx="2.5" {...c} />
          <path d="M9 4v16" {...c} />
          <path d="M6 9h.01M6 12h.01M6 15h.01" stroke={color} strokeWidth="2.2" strokeLinecap="round" />
        </svg>
      );
    case 'back':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <path d="M15 5l-7 7 7 7" {...c} />
        </svg>
      );
    case 'forward':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <path d="M9 5l7 7-7 7" {...c} />
        </svg>
      );
    case 'today':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <rect x="3.5" y="5" width="17" height="15" rx="2.5" {...c} />
          <path d="M3.5 10h17" {...c} />
          <path d="M8 3v4M16 3v4" {...c} />
          <circle cx="12" cy="15" r="1.4" fill={color} />
        </svg>
      );
    case 'search':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <circle cx="11" cy="11" r="6" {...c} />
          <path d="M20 20l-5-5" {...c} />
        </svg>
      );
    case 'new':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <path d="M12 5v14M5 12h14" {...c} />
        </svg>
      );
    case 'more':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <circle cx="5"  cy="12" r="1.6" fill={color}/>
          <circle cx="12" cy="12" r="1.6" fill={color}/>
          <circle cx="19" cy="12" r="1.6" fill={color}/>
        </svg>
      );
    default: return null;
  }
}

// Bottom navigation toolbar — reading state (keyboard hidden).
// Three clusters: nav (sidebar/back/fwd) · universal (today/search/new) · more.
// Pocket-style strip; "New" is the accent affordance.
function ArticleBottomNav() {
  const cluster = (items) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
      {items.map((it) => {
        const accent = it.accent;
        const color = accent ? ART_ACCENT : ART_FAINT;
        return (
          <div key={it.name} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
            color, fontFamily: ART_SANS, fontSize: 9.5,
            letterSpacing: 0.5, textTransform: 'uppercase', fontWeight: 500,
          }}>
            <ArticleIcon name={it.name} color={color} size={18} />
            {it.label && <span>{it.label}</span>}
          </div>
        );
      })}
    </div>
  );
  return (
    <div style={{
      padding: '12px 18px 38px',
      borderTop: '0.5px solid ' + ART_RULE,
      background: '#1A1C22',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      flexShrink: 0,
    }}>
      {cluster([
        { name: 'sidebar', label: 'shelf' },
        { name: 'back',    label: 'back' },
        { name: 'forward', label: 'fwd' },
      ])}
      <div style={{ width: 1, height: 22, background: ART_RULE }} />
      {cluster([
        { name: 'today',   label: 'today' },
        { name: 'search',  label: 'search' },
        { name: 'new',     label: 'new', accent: true },
      ])}
      <div style={{ width: 1, height: 22, background: ART_RULE }} />
      {cluster([
        { name: 'more',    label: 'more' },
      ])}
    </div>
  );
}

// Find-in-note input strip (the original 'find' state).
function ArticleFindBar() {
  return (
    <div style={{
      padding: '8px 12px', flexShrink: 0,
      borderTop: '0.5px solid ' + ART_RULE,
      background: '#1A1C22',
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={ART_MUTED} strokeWidth="1.8" strokeLinecap="round">
        <circle cx="11" cy="11" r="6" /><path d="M20 20l-5-5" />
      </svg>
      <span style={{ flex: 1, color: ART_HEAD, fontSize: 15 }}>
        compound
        <span style={{ display: 'inline-block', width: 1.5, height: 14, background: ART_ACCENT, marginLeft: 1, verticalAlign: 'text-bottom' }} />
      </span>
      <span style={{ color: ART_MUTED, fontSize: 12, fontVariantNumeric: 'tabular-nums' }}>2 / 6</span>
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={ART_INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 9l4-4 4 4" /></svg>
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={ART_INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 5l4 4 4-4" /></svg>
      <div style={{ width: 22, height: 22, borderRadius: 11, background: 'rgba(255,255,255,0.10)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="10" height="10" viewBox="0 0 14 14" stroke={ART_INK} strokeWidth="1.8" strokeLinecap="round">
          <path d="M3 3l8 8M11 3l-8 8" />
        </svg>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Main component — state-driven.
// ─────────────────────────────────────────────────────────────
function Exp03ArticleV3({ state = 'find' }) {
  const renderHighlighted = (text) => {
    const re = /(compound[a-z]*)/gi;
    const parts = text.split(re);
    let matchIdx = 0;
    return parts.map((p, i) => {
      if (re.test(p)) {
        matchIdx++;
        const active = state === 'find' && matchIdx === 2;
        // outside the find state, no highlights at all
        if (state !== 'find') return <React.Fragment key={i}>{p}</React.Fragment>;
        return (
          <span key={i} style={{
            background: active ? ART_HL : 'rgba(230,182,42,0.22)',
            color: active ? '#1a1100' : ART_INK,
            borderRadius: 2, padding: '0 1px',
          }}>{p}</span>
        );
      }
      return <React.Fragment key={i}>{p}</React.Fragment>;
    });
  };

  // In reading mode, render a caret-free body and let lines breathe more.
  const subtitleHL = 'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.';
  const body1HL = 'The defining question for AI products in 2026 is no longer can we build it? \u2014 model capability has caught up to ambition. The harder question is what does this become once people use it every day? As Sahil Lavingia recently argued, durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap.';

  const showKeyboard = state !== 'reading';

  return (
    <IOSDevice dark={true} background={ART_BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: ART_SANS }}>
        {/* reserve status bar space */}
        <div style={{ height: 62, flexShrink: 0 }} />

        {/* writing surface */}
        <div style={{ flex: 1, minHeight: 0, padding: '20px 22px 0', overflow: 'hidden' }}>
          {/* meta strip — 11 properties accordion */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            color: ART_MUTED, fontSize: 12, marginBottom: 16,
          }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={ART_MUTED} strokeWidth="1.6" strokeLinecap="round">
              <path d="M2.5 4l3 3 3-3" />
            </svg>
            <span>11 properties</span>
            <span style={{ flex: 1, height: 0.5, background: ART_RULE }} />
            <span style={{ fontVariantNumeric: 'tabular-nums', opacity: 0.7 }}>saved 2h</span>
          </div>

          <div style={{ color: ART_HEAD, fontSize: 24, fontWeight: 700, lineHeight: 1.15, letterSpacing: -0.3 }}>
            {NOTE.title}
          </div>
          <p style={{ margin: '14px 0 0', fontSize: 16, lineHeight: 1.55, color: ART_INK }}>
            {renderHighlighted(subtitleHL)}
          </p>

          {/* hero image placeholder */}
          <div style={{
            marginTop: 18, height: 132,
            background: 'linear-gradient(135deg, #2a2d35 0%, #1d2026 100%)',
            borderRadius: 6, border: '0.5px solid ' + ART_RULE,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: ART_FAINT, fontSize: 13, letterSpacing: 0.5,
          }}>1200 × 500</div>

          <p style={{ margin: '16px 0 0', fontSize: 16, lineHeight: 1.55, color: ART_INK }}>
            {renderHighlighted(body1HL)}
          </p>
        </div>

        {/* In reading mode, breadcrumb/meta strip sits just above the bottom
            toolbar so everything above reads as editor view. */}
        {state === 'reading' && (
          <div style={{
            padding: '10px 22px',
            borderTop: '0.5px solid ' + ART_RULE,
            background: ART_BG,
            display: 'flex', alignItems: 'center', gap: 10,
            color: ART_MUTED, fontSize: 11, letterSpacing: 0.5,
            textTransform: 'uppercase',
            flexShrink: 0,
          }}>
            <span style={{ color: ART_ACCENT, fontWeight: 600 }}>Captures</span>
            <span style={{ opacity: 0.5 }}>›</span>
            <span>Draft</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>258w · 1m read</span>
          </div>
        )}

        {/* state-specific bottom region */}
        {state === 'find' && <ArticleFindBar />}
        {state === 'find' && <NotoToolbarArticle wordCount={258} activeKey="link" />}
        {state === 'editing' && <NotoToolbarArticle wordCount={258} activeKey={null} />}
        {state === 'reading' && <ArticleBottomNav />}

        {showKeyboard && <IOSKeyboard dark={true} />}
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp03ArticleV3 });
