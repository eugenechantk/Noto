// v3-split2 · Digital article — refined split nav.
// Top:    [shelf] [back/fwd]  [   title (static)   ]  [count→tabs]  [more]
// Bottom: [   search   ]   [today]   [+ new note]
// Key differences from v3-split:
//   • Sidebar moves UP into the top bar.
//   • Title is no longer tappable; the trailing tab-count badge becomes the
//     dedicated tab-switcher button (clearer affordance).
//   • Bottom row drops the shelf since sidebar lives on top; search becomes a
//     prominent flex pill on the left.

function Exp03ArticleV3Split2({ state = 'reading' }) {
  const BG     = '#0E1116';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.62)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF6A2E';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  const glassStyle = {
    background: 'rgba(28,30,36,0.55)',
    backdropFilter: 'blur(28px) saturate(180%)',
    WebkitBackdropFilter: 'blur(28px) saturate(180%)',
    border: '0.5px solid rgba(255,255,255,0.10)',
    boxShadow: [
      '0 1px 1px rgba(0,0,0,0.18)',
      '0 8px 24px rgba(0,0,0,0.32)',
      'inset 0 0.5px 0 rgba(255,255,255,0.22)',
      'inset 0 -0.5px 0 rgba(0,0,0,0.25)',
    ].join(', '),
  };

  const TABS = [
    { id: 't1', active: true,  title: 'How to Build Strong AI Products', snippet: 'A field guide for founders shipping AI features in 2026 — what separates the products that compound.', folder: 'Captures',  meta: 'edited 2h ago',     tint: 'linear-gradient(135deg, #FF6A2E 0%, #C2185B 55%, #4A148C 100%)' },
    { id: 't2', active: false, title: 'Weekly review · Mar 11',         snippet: 'Wrapped the AC pricing experiment. Three things to follow up on next week.',                          folder: 'Journal',   meta: 'edited yesterday', tint: 'linear-gradient(135deg, #1F6FEB 0%, #163172 100%)' },
    { id: 't3', active: false, title: 'Sahil — compounding deposits',   snippet: 'Quoting the substack post about durable AI products. The data is the moat.',                          folder: 'Highlights', meta: 'edited 3d ago',   tint: 'linear-gradient(135deg, #2EB67D 0%, #064E3B 100%)' },
    { id: 't4', active: false, title: 'Field guide outline',            snippet: '1. The compounding loop. 2. The three deposits. 3. The AI-model-layer story.',                       folder: 'Drafts',    meta: 'edited 5d ago',    tint: 'linear-gradient(135deg, #E6B62A 0%, #7C4A00 100%)' },
    { id: 't5', active: false, title: 'Pricing experiments Q1',         snippet: 'Three lever ideas: per-seat with usage cap, hybrid base+usage, and a metered drip.',                  folder: 'Projects',  meta: 'edited Mar 4',     tint: 'linear-gradient(135deg, #8B5CF6 0%, #312E81 100%)' },
  ];

  // ─── TOP glass bar ──────────────────────────────────────────
  // [shelf] [back/fwd] [   title (static)   ] [count→tabs] [more]
  const FloatingTopBar = ({ titleOverride = null, accent = false }) => (
    <div style={{
      position: 'absolute', left: 0, right: 0, top: 62,
      padding: '6px 10px',
      display: 'flex', alignItems: 'center', gap: 6,
      zIndex: 10, pointerEvents: 'none',
    }}>
      {/* Shelf */}
      <div style={{
        ...glassStyle,
        width: 38, height: 38, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0, pointerEvents: 'auto',
      }}>
        <ArticleIcon name="sidebar" color={HEAD} size={18} />
      </div>

      {/* Back / forward — paired */}
      <div style={{
        ...glassStyle,
        height: 38, borderRadius: 999,
        display: 'flex', alignItems: 'center',
        padding: '0 2px', flexShrink: 0, pointerEvents: 'auto',
      }}>
        <div style={{ width: 30, height: 34, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="back" color={HEAD} size={16} />
        </div>
        <div style={{ width: 0.5, height: 16, background: 'rgba(255,255,255,0.14)' }} />
        <div style={{ width: 30, height: 34, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="forward" color={FAINT} size={16} />
        </div>
      </div>

      {/* Title — static, NOT a button */}
      <div style={{
        flex: 1, minWidth: 0, height: 38,
        display: 'flex', alignItems: 'center', gap: 6,
        padding: '0 4px',
        pointerEvents: 'none',
      }}>
        <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke={ACCENT} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
          <path d="M3.5 1.5h5l3 3V12a1 1 0 01-1 1H3.5a1 1 0 01-1-1V2.5a1 1 0 011-1z" />
          <path d="M8 1.5v3h3.5" />
        </svg>
        <span style={{
          color: HEAD, fontFamily: SANS,
          fontSize: 13, fontWeight: 600, letterSpacing: -0.1,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          minWidth: 0,
        }}>{titleOverride || NOTE.title}</span>
      </div>

      {/* Tab-count → opens switcher (its own button) */}
      <div style={{
        ...glassStyle,
        height: 38, minWidth: 44, borderRadius: 999,
        padding: '0 12px',
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        flexShrink: 0, pointerEvents: 'auto',
        ...(accent ? {
          border: '0.5px solid rgba(255,106,46,0.55)',
          background: 'rgba(255,106,46,0.18)',
        } : {}),
      }}>
        {/* small "tabs" stack glyph */}
        <svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke={HEAD} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
          <rect x="2" y="4" width="8" height="7" rx="1.5" />
          <path d="M4 4V3a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1h-1" />
        </svg>
        <span style={{
          color: HEAD, fontFamily: SANS,
          fontSize: 12, fontWeight: 600,
          fontVariantNumeric: 'tabular-nums',
        }}>{TABS.length}</span>
      </div>

      {/* More */}
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

  // ─── BOTTOM glass nav: search · today · new note ──────────
  const FloatingBottomNav = () => (
    <div style={{
      flexShrink: 0,
      padding: '8px 10px 34px',
      display: 'flex', alignItems: 'center', gap: 6,
    }}>
      {/* Search — wide flex pill */}
      <div style={{
        ...glassStyle,
        flex: 1, height: 44, borderRadius: 999,
        padding: '0 16px', gap: 8,
        display: 'flex', alignItems: 'center',
      }}>
        <ArticleIcon name="search" color={HEAD} size={17} />
        <span style={{ color: HEAD, fontFamily: SANS, fontSize: 14, fontWeight: 500 }}>Search</span>
      </div>

      {/* Today */}
      <div style={{
        ...glassStyle,
        width: 44, height: 44, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <ArticleIcon name="today" color={HEAD} size={18} />
      </div>

      {/* + New note — accent */}
      <div style={{
        ...glassStyle,
        height: 44, borderRadius: 999,
        padding: '0 16px 0 14px', gap: 8,
        display: 'flex', alignItems: 'center', flexShrink: 0,
        border: '0.5px solid rgba(255,106,46,0.55)',
        background: 'rgba(255,106,46,0.18)',
      }}>
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={HEAD} strokeWidth="2" strokeLinecap="round">
          <path d="M7 2v10M2 7h10" />
        </svg>
        <span style={{ color: HEAD, fontFamily: SANS, fontSize: 14, fontWeight: 600 }}>New</span>
      </div>
    </div>
  );

  // ─── Article body ──────────────────────────────────────────
  const ArticleBody = () => (
    <div style={{
      flex: 1, minHeight: 0, overflow: 'hidden',
      padding: '116px 22px 0',
    }}>
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
        A field guide for founders shipping AI features in 2026 — what separates the products that compound from the ones that flame out after a launch week.
      </p>

      <div style={{
        marginTop: 18, height: 132,
        background: 'linear-gradient(135deg, #FF6A2E 0%, #C2185B 45%, #4A148C 100%)',
        borderRadius: 12, border: '0.5px solid ' + RULE,
        position: 'relative', overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.22), transparent 60%)',
        }} />
      </div>

      <p style={{ margin: '16px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>
        The defining question for AI products in 2026 is no longer can we build it? — model capability has caught up to ambition. The harder question is what does this become once people use it every day?
      </p>
    </div>
  );

  // ─── Tab switcher body ─────────────────────────────────────
  const TabView = () => (
    <div style={{
      flex: 1, minHeight: 0, overflow: 'hidden',
      padding: '116px 14px 0',
      position: 'relative',
    }}>
      <div style={{
        padding: '0 6px 12px',
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      }}>
        <span style={{ color: HEAD, fontFamily: SANS, fontSize: 13, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase' }}>
          Open notes
        </span>
        <span style={{ color: MUTED, fontFamily: SANS, fontSize: 12 }}>
          {TABS.length} tabs · 1 active
        </span>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, overflow: 'hidden' }}>
        {TABS.map((t) => (
          <div key={t.id} style={{
            ...glassStyle,
            borderRadius: 16, padding: 12,
            display: 'flex', flexDirection: 'column', gap: 8,
            ...(t.active ? { border: '1px solid rgba(255,106,46,0.6)' } : {}),
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10,
                background: t.tint, flexShrink: 0, position: 'relative', overflow: 'hidden',
                boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.25)',
              }}>
                <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.28), transparent 60%)' }} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{
                  color: HEAD, fontFamily: SANS, fontSize: 14, fontWeight: 600,
                  letterSpacing: -0.1, lineHeight: 1.25,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                }}>{t.title}</div>
                <div style={{ marginTop: 2, color: MUTED, fontFamily: SANS, fontSize: 11, display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ color: t.active ? ACCENT : MUTED, fontWeight: t.active ? 600 : 400 }}>{t.folder}</span>
                  <span style={{ opacity: 0.4 }}>·</span>
                  <span>{t.meta}</span>
                  {t.active && (<><span style={{ opacity: 0.4 }}>·</span><span style={{ color: ACCENT, fontWeight: 600 }}>Active</span></>)}
                </div>
              </div>
              <div style={{
                width: 26, height: 26, borderRadius: 999,
                background: 'rgba(255,255,255,0.06)',
                border: '0.5px solid rgba(255,255,255,0.10)',
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              }}>
                <svg width="9" height="9" viewBox="0 0 9 9" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round">
                  <path d="M2 2l5 5M7 2l-5 5" />
                </svg>
              </div>
            </div>
            <div style={{
              color: INK, fontFamily: SANS, fontSize: 13, lineHeight: 1.45, opacity: 0.78,
              display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
            }}>{t.snippet}</div>
          </div>
        ))}
      </div>
    </div>
  );

  // ─── Bottom in switcher = + New + Done ─────────────────────
  const SwitcherDoneBar = () => (
    <div style={{
      flexShrink: 0,
      padding: '8px 10px 34px',
      display: 'flex', alignItems: 'center', gap: 6,
    }}>
      <div style={{
        ...glassStyle,
        flex: 1, height: 44, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      }}>
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={HEAD} strokeWidth="2" strokeLinecap="round">
          <path d="M7 2v10M2 7h10" />
        </svg>
        <span style={{ color: HEAD, fontFamily: SANS, fontSize: 15, fontWeight: 600 }}>New note</span>
      </div>
      <div style={{
        ...glassStyle,
        height: 44, padding: '0 22px', borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 15, fontWeight: 700 }}>Done</span>
      </div>
    </div>
  );

  const inSwitcher = state === 'switcher';

  return (
    <IOSDevice dark={true} background={BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, position: 'relative' }}>
        <FloatingTopBar
          titleOverride={inSwitcher ? 'Tabs' : null}
          accent={inSwitcher}
        />

        {inSwitcher ? <TabView /> : <ArticleBody />}

        {state === 'reading'  && <FloatingBottomNav />}
        {state === 'switcher' && <SwitcherDoneBar />}
        {state === 'editing'  && <NotoToolbarArticle wordCount={258} activeKey={null} />}
        {state === 'editing'  && <IOSKeyboard dark={true} />}
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp03ArticleV3Split2 });
