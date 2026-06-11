// v3-glass · Digital article — Liquid Glass top chrome.
// Same single-tier top nav from v3-topbar (shelf · back/fwd · current note ·
// more), restyled in Apple's iOS 26 "Liquid Glass" idiom: floating translucent
// capsules with backdrop blur, soft inner top-edge highlights, faint outer
// shadows. The chrome floats OVER the article body — content scrolls behind
// the glass, with a hero band visible through the capsule to sell the effect.
//
// Pulls shared chrome from v3-3: ArticleIcon, ArticleFindBar, NOTE, IOSDevice,
// IOSKeyboard, NotoToolbarArticle — all on window. v3-topbar must load before
// this so its Exp03ArticleV3TopTabs name doesn't collide (it doesn't — we use
// our own Exp03ArticleV3Glass).

function Exp03ArticleV3Glass({ state = 'reading' }) {
  // Slightly cooler canvas so the glass tints read clearly.
  const BG     = '#0E1116';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.62)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF6A2E';
  const HL     = '#E6B62A';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  // ─── Glass primitives ───────────────────────────────────────
  // Capsule with refraction-style inner highlight + outer halo.
  const glassStyle = {
    background: 'rgba(28,30,36,0.55)',
    backdropFilter: 'blur(28px) saturate(180%)',
    WebkitBackdropFilter: 'blur(28px) saturate(180%)',
    border: '0.5px solid rgba(255,255,255,0.10)',
    boxShadow: [
      // outer halo / drop
      '0 1px 1px rgba(0,0,0,0.18)',
      '0 8px 24px rgba(0,0,0,0.32)',
      // inner top highlight (Liquid Glass "lens")
      'inset 0 0.5px 0 rgba(255,255,255,0.22)',
      // faint inner bottom shade
      'inset 0 -0.5px 0 rgba(0,0,0,0.25)',
    ].join(', '),
  };

  // ─── Highlight rendering for find-state ────────────────────
  const renderHighlighted = (text) => {
    const re = /(compound[a-z]*)/gi;
    const parts = text.split(re);
    let matchIdx = 0;
    return parts.map((p, i) => {
      if (re.test(p)) {
        matchIdx++;
        const active = state === 'find' && matchIdx === 2;
        if (state !== 'find') return <React.Fragment key={i}>{p}</React.Fragment>;
        return (
          <span key={i} style={{
            background: active ? HL : 'rgba(230,182,42,0.22)',
            color: active ? '#1a1100' : INK,
            borderRadius: 2, padding: '0 1px',
          }}>{p}</span>
        );
      }
      return <React.Fragment key={i}>{p}</React.Fragment>;
    });
  };

  const subtitleHL = 'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.';
  const body1HL = 'The defining question for AI products in 2026 is no longer can we build it? \u2014 model capability has caught up to ambition. The harder question is what does this become once people use it every day? As Sahil Lavingia recently argued, durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap.';

  const showKeyboard = state !== 'reading';

  // ─── Floating glass top bar ─────────────────────────────────
  // Three separate Liquid-Glass capsules, the iOS 26 way:
  //   [shelf]   [back fwd]      [   title pill   ]   [more]
  const FloatingTopBar = () => (
    <div style={{
      position: 'absolute', left: 0, right: 0, top: 62,
      padding: '6px 10px',
      display: 'flex', alignItems: 'center', gap: 6,
      zIndex: 10, pointerEvents: 'none',
    }}>
      {/* Shelf — single round glass button */}
      <div style={{
        ...glassStyle,
        width: 38, height: 38, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0, pointerEvents: 'auto',
      }}>
        <ArticleIcon name="sidebar" color={HEAD} size={18} />
      </div>

      {/* Back / forward — paired capsule */}
      <div style={{
        ...glassStyle,
        height: 38, borderRadius: 999,
        display: 'flex', alignItems: 'center',
        padding: '0 2px', flexShrink: 0,
        pointerEvents: 'auto',
      }}>
        <div style={{
          width: 34, height: 34, borderRadius: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <ArticleIcon name="back" color={HEAD} size={17} />
        </div>
        <div style={{
          width: 0.5, height: 16, background: 'rgba(255,255,255,0.14)',
        }} />
        <div style={{
          width: 34, height: 34, borderRadius: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <ArticleIcon name="forward" color={FAINT} size={17} />
        </div>
      </div>

      {/* Title pill — current note (truncating) */}
      <div style={{
        ...glassStyle,
        flex: 1, minWidth: 0, height: 38, borderRadius: 999,
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 14px', pointerEvents: 'auto',
      }}>
        <svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke={ACCENT} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
          <path d="M3.5 1.5h5l3 3V12a1 1 0 01-1 1H3.5a1 1 0 01-1-1V2.5a1 1 0 011-1z" />
          <path d="M8 1.5v3h3.5" />
        </svg>
        <span style={{
          color: HEAD, fontFamily: SANS,
          fontSize: 14, fontWeight: 600, letterSpacing: -0.1,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          minWidth: 0,
        }}>{NOTE.title}</span>
      </div>

      {/* More — single round glass button */}
      <div style={{
        ...glassStyle,
        width: 38, height: 38, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0, pointerEvents: 'auto',
      }}>
        <ArticleIcon name="more" color={HEAD} size={18} />
      </div>
    </div>
  );

  // Glassy accent for the bottom dock too, to keep the system coherent.
  // We don't replace the keyboard toolbar (NotoToolbarArticle), but we can put
  // the find-bar on glass.
  const GlassFindBar = () => (
    <div style={{
      flexShrink: 0,
      padding: '8px 10px',
      background: 'transparent',
    }}>
      <div style={{
        ...glassStyle,
        height: 40, borderRadius: 999,
        display: 'flex', alignItems: 'center',
        padding: '0 6px 0 14px', gap: 10,
      }}>
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={MUTED} strokeWidth="1.7" strokeLinecap="round">
          <circle cx="6" cy="6" r="4" /><path d="M9 9l3 3" />
        </svg>
        <span style={{
          color: HEAD, fontFamily: SANS, fontSize: 14, fontWeight: 500,
          flex: 1, minWidth: 0,
        }}>
          compound
          <span style={{ color: MUTED, marginLeft: 8, fontWeight: 400 }}>2 of 4</span>
        </span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
          <div style={{ width: 28, height: 28, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M2 7l3.5-3.5L9 7" />
            </svg>
          </div>
          <div style={{ width: 28, height: 28, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M2 4l3.5 3.5L9 4" />
            </svg>
          </div>
          <div style={{
            width: 28, height: 28, borderRadius: 999,
            background: 'rgba(255,255,255,0.08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round">
              <path d="M2 2l6 6M8 2l-6 6" />
            </svg>
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <IOSDevice dark={true} background={BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, position: 'relative' }}>
        {/* Floating glass top bar — overlays content */}
        <FloatingTopBar />

        {/* writing surface — content scrolls UNDER the glass top bar.
            Top padding leaves room for status bar + floating capsule. */}
        <div style={{
          flex: 1, minHeight: 0, overflow: 'hidden',
          padding: '116px 22px 0',
        }}>
          {/* meta strip — 11 properties accordion */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            color: MUTED, fontSize: 12, marginBottom: 14,
          }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={MUTED} strokeWidth="1.6" strokeLinecap="round">
              <path d="M2.5 4l3 3 3-3" />
            </svg>
            <span>11 properties</span>
            <span style={{ flex: 1, height: 0.5, background: RULE }} />
            <span style={{ fontVariantNumeric: 'tabular-nums', opacity: 0.7 }}>saved 2h</span>
          </div>

          <div style={{ color: HEAD, fontSize: 24, fontWeight: 700, lineHeight: 1.15, letterSpacing: -0.3 }}>
            {NOTE.title}
          </div>
          <p style={{ margin: '14px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>
            {renderHighlighted(subtitleHL)}
          </p>

          {/* hero image — colorful so the glass refraction reads */}
          <div style={{
            marginTop: 18, height: 132,
            background: 'linear-gradient(135deg, #FF6A2E 0%, #C2185B 45%, #4A148C 100%)',
            borderRadius: 12, border: '0.5px solid ' + RULE,
            position: 'relative', overflow: 'hidden',
          }}>
            {/* faint inner soft-light to suggest depth */}
            <div style={{
              position: 'absolute', inset: 0,
              background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.22), transparent 60%)',
            }} />
          </div>

          <p style={{ margin: '16px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>
            {renderHighlighted(body1HL)}
          </p>
        </div>

        {/* state-specific bottom region — same model as v3-topbar.
            Find uses our GlassFindBar; editing/find both keep the keyboard
            accessory toolbar. */}
        {state === 'find' && <GlassFindBar />}
        {state === 'find' && <NotoToolbarArticle wordCount={258} activeKey="link" />}
        {state === 'editing' && <NotoToolbarArticle wordCount={258} activeKey={null} />}

        {showKeyboard && <IOSKeyboard dark={true} />}
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp03ArticleV3Glass });
