// v3-topbar · Digital article — nav moves UP to a tab strip.
// Same 3 states as the original (reading / editing / find), but instead of the
// bottom navigation toolbar from ArticleBottomNav, the screen carries a
// browser-style horizontal TAB BAR at the very top so the reader can quickly
// switch between recently-open notes. The active tab shows the current note
// title; inactive tabs show truncated titles with a close affordance.
//
// In editing/find states, the keyboard accessory toolbar still sits at the
// bottom. In reading state, the bottom region is freed up entirely (no nav),
// since switching notes now lives on the top.
//
// Pulls shared chrome from v3-3: ART_*, ArticleIcon, ArticleFindBar, NOTE,
// IOSDevice, IOSKeyboard, NotoToolbarArticle — all on window.

function Exp03ArticleV3TopTabs({ state = 'reading' }) {
  const ART_BG    = '#15171C';
  const ART_INK   = '#E5E5E7';
  const ART_HEAD  = '#FAFAFA';
  const ART_MUTED = 'rgba(229,229,231,0.55)';
  const ART_FAINT = 'rgba(229,229,231,0.32)';
  const ART_RULE  = 'rgba(255,255,255,0.08)';
  const ART_ACCENT = '#FF5A1F';
  const ART_HL    = '#E6B62A';
  const ART_SANS  = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  // Open-note tabs. The first one is active and represents the current note.
  const tabs = [
    { id: 't1', title: 'How to Build Strong AI Products', active: true },
    { id: 't2', title: 'Weekly review · Mar 11', active: false },
    { id: 't3', title: 'Sahil — compounding deposits', active: false },
    { id: 't4', title: 'Field guide outline', active: false },
    { id: 't5', title: 'Pricing experiments Q1', active: false },
  ];

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
            background: active ? ART_HL : 'rgba(230,182,42,0.22)',
            color: active ? '#1a1100' : ART_INK,
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

  // ─── Single top bar — back/fwd · current note title · more ────
  const TopBar = () => (
    <div style={{
      flexShrink: 0,
      background: ART_BG,
      borderBottom: '0.5px solid ' + ART_RULE,
      padding: '8px 12px',
      display: 'flex', alignItems: 'center', gap: 8,
      height: 48, boxSizing: 'border-box',
    }}>
      {/* back to note list */}
      <div style={{
        width: 32, height: 32, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <ArticleIcon name="sidebar" color={ART_INK} size={18} />
      </div>

      {/* back / forward */}
      <div style={{
        display: 'flex', alignItems: 'center',
        background: 'rgba(255,255,255,0.04)',
        borderRadius: 999, padding: 2,
        flexShrink: 0,
      }}>
        <div style={{ width: 28, height: 28, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="back" color={ART_INK} size={16} />
        </div>
        <div style={{ width: 28, height: 28, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="forward" color={ART_FAINT} size={16} />
        </div>
      </div>

      {/* current note — file glyph + title (truncates) */}
      <div style={{
        flex: 1, minWidth: 0,
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 4px',
      }}>
        <svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke={ART_ACCENT} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
          <path d="M3.5 1.5h5l3 3V12a1 1 0 01-1 1H3.5a1 1 0 01-1-1V2.5a1 1 0 011-1z" />
          <path d="M8 1.5v3h3.5" />
        </svg>
        <span style={{
          color: ART_HEAD, fontFamily: ART_SANS,
          fontSize: 14, fontWeight: 600, letterSpacing: -0.1,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          minWidth: 0,
        }}>{NOTE.title}</span>
      </div>

      {/* more */}
      <div style={{
        width: 32, height: 32, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <ArticleIcon name="more" color={ART_INK} size={18} />
      </div>
    </div>
  );

  return (
    <IOSDevice dark={true} background={ART_BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: ART_SANS }}>
        {/* reserve status bar space */}
        <div style={{ height: 62, flexShrink: 0 }} />

        {/* SINGLE top bar — back/fwd · current note · more */}
        <TopBar />

        {/* writing surface */}
        <div style={{ flex: 1, minHeight: 0, padding: '18px 22px 0', overflow: 'hidden' }}>
          {/* meta strip — 11 properties accordion */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            color: ART_MUTED, fontSize: 12, marginBottom: 14,
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

        {/* state-specific bottom region — no bottom nav since nav lives on top */}
        {state === 'find' && <ArticleFindBar />}
        {state === 'find' && <NotoToolbarArticle wordCount={258} activeKey="link" />}
        {state === 'editing' && <NotoToolbarArticle wordCount={258} activeKey={null} />}

        {showKeyboard && <IOSKeyboard dark={true} />}
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp03ArticleV3TopTabs });
