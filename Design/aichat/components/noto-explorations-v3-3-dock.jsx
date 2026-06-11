// v3-dock · Digital article — minimal top, 5-slot bottom dock.
// Updated per direction:
//   • Top bar buttons have NO glass underlay — bare icons only.
//   • Title is hidden when at the top of the note (the body's H1 IS the
//     title). When scrolled, the title fades in to the top bar and a hairline
//     bottom border appears.
//   • Bottom dock is a 5-slot tab bar:
//         sidebar · today · search · tabs · new note
//
// Pulls shared chrome: ArticleIcon, NOTE, IOSDevice, IOSKeyboard,
// NotoToolbarArticle — all on window.

function Exp03ArticleV3Dock({ state = 'reading', noTabs = false }) {
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

  // States that need the bottom dock vs. the keyboard.
  const isReading  = state === 'reading' || state === 'scrolled';
  const isScrolled = state === 'scrolled';
  const inSwitcher = state === 'switcher';
  const showTopTitle = isScrolled;

  // ─── TOP — no underlays; appears only as icons; gains a
  //          backdrop + bottom border when scrolled. ─────────
  const FloatingTopBar = () => (
    <div style={{
      position: 'absolute', left: 0, right: 0, top: 62,
      height: 48,
      padding: '0 14px',
      display: 'flex', alignItems: 'center', gap: 6,
      zIndex: 10,
      // bare when at top; gets a glass underlay + hairline when scrolled.
      ...(showTopTitle ? {
        background: 'rgba(14,17,22,0.72)',
        backdropFilter: 'blur(20px) saturate(180%)',
        WebkitBackdropFilter: 'blur(20px) saturate(180%)',
        borderBottom: '0.5px solid rgba(255,255,255,0.10)',
      } : {}),
    }}>
      {/* Back / forward — bare icons, no glass */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
        <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="back" color={HEAD} size={20} />
        </div>
        <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="forward" color={FAINT} size={20} />
        </div>
      </div>

      {/* Title — appears only when scrolled (or in switcher) */}
      <div style={{
        flex: 1, minWidth: 0, height: '100%',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '0 8px 0 0',
        opacity: showTopTitle ? 1 : 0,
        transition: 'opacity 120ms ease',
      }}>
        <span style={{
          color: HEAD, fontFamily: SANS,
          fontSize: 14, fontWeight: 600, letterSpacing: -0.1,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          minWidth: 0, textAlign: 'center',
        }}>{NOTE.title}</span>
      </div>

      {/* More — bare icon, no glass */}
      <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <ArticleIcon name="more" color={HEAD} size={20} />
      </div>
    </div>
  );

  // ─── BOTTOM DOCK — paired buttons · wide search · paired buttons ──
  // Outer left  pair: [sidebar · today]
  // Center pill     : Search (wide, HIG search-field)
  // Outer right pair: [tabs · new note]
  const FloatingDock = () => (
    <div style={{
      flexShrink: 0,
      padding: '6px 12px 34px',
      position: 'relative', zIndex: 10,
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      {/* Left paired capsule — sidebar + today */}
      <div style={{
        ...glassStyle,
        height: 52, borderRadius: 999,
        padding: '0 4px',
        display: 'flex', alignItems: 'center',
        flexShrink: 0,
      }}>
        <div style={{
          width: 44, height: 44, borderRadius: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <ArticleIcon name="sidebar" color={HEAD} size={22} />
        </div>
        <div style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.10)' }} />
        <div style={{
          width: 44, height: 44, borderRadius: 999, position: 'relative',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3.5" y="4.5" width="15" height="13" rx="2.4" />
            <path d="M3.5 8.5h15" />
            <path d="M7 3v3M15 3v3" />
          </svg>
          <span style={{
            position: 'absolute', left: 0, right: 0, top: 21,
            textAlign: 'center',
            color: HEAD, fontFamily: SANS, fontSize: 8, fontWeight: 700,
            pointerEvents: 'none',
          }}>7</span>
        </div>
      </div>

      {/* Center — full search pill */}
      <div style={{
        ...glassStyle,
        flex: 1, height: 52, borderRadius: 999,
        padding: '0 18px', gap: 10,
        display: 'flex', alignItems: 'center',
      }}>
        <ArticleIcon name="search" color={MUTED} size={19} />
        <span style={{
          color: MUTED, fontFamily: SANS, fontSize: 16,
          flex: 1, minWidth: 0,
        }}>Search</span>
      </div>

      {/* Right capsule — new note (tabs pill removed in the no-tabs variant) */}
      <div style={{
        ...glassStyle,
        height: 52, borderRadius: 999,
        padding: '0 4px',
        display: 'flex', alignItems: 'center',
        flexShrink: 0,
      }}>
        {!noTabs && (
          <>
            <div style={{
              height: 44, padding: '0 14px',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
              borderRadius: 999,
              ...(inSwitcher ? { background: 'rgba(255,106,46,0.18)' } : {}),
            }}>
              <svg width="20" height="20" viewBox="0 0 14 14" fill="none" stroke={HEAD} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="2" y="4" width="8" height="7" rx="1.5" />
                <path d="M4 4V3a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1h-1" />
              </svg>
              <span style={{ color: HEAD, fontFamily: SANS, fontSize: 13, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{TABS.length}</span>
            </div>
            <div style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.10)' }} />
          </>
        )}
        <div style={{
          width: 44, height: 44, borderRadius: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'rgba(255,106,46,0.22)',
          border: '0.5px solid rgba(255,106,46,0.40)',
        }}>
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9.5 4H5.5a2 2 0 00-2 2v10.5a2 2 0 002 2h10.5a2 2 0 002-2V12.5" />
            <path d="M15 3.5l3.5 3.5L11 14.5H7.5V11L15 3.5z" />
          </svg>
        </div>
      </div>
    </div>
  );

  // ─── Article body ──────────────────────────────────────────
  // Reading mode shows the H1 large at top. Scrolled mode shows the body
  // scrolled down — H1 is gone, deeper content visible.
  const ArticleBody = () => (
    <div style={{
      flex: 1, minHeight: 0, overflow: 'hidden',
      padding: '116px 22px 0',
    }}>
      {!isScrolled && (
        <>
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

          <div style={{ marginTop: 16 }}>
            {window.renderNotoDoc({ from: 0 })}
          </div>
        </>
      )}

      {isScrolled && (
        <>
          {/* deeper into the article — long-form body, scrolled past the top */}
          {window.renderNotoDoc({ from: 5 })}
        </>
      )}
    </div>
  );

  // ─── Tab switcher body — rendered inside a sheet ───────────
  const TabView = () => (
    <div style={{
      padding: '8px 14px 40px', position: 'relative',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, overflow: 'hidden' }}>
        {TABS.map((t) => (
          <div key={t.id} style={{
            ...glassStyle, borderRadius: 16, padding: 12,
            display: 'flex', flexDirection: 'column', gap: 8,
            ...(t.active ? { border: '1px solid rgba(255,106,46,0.6)' } : {}),
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
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

  return (
    <IOSDevice dark={true} background={inSwitcher ? '#000' : BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, position: 'relative' }}>
        {inSwitcher ? (
          <>
            {/* Presenting view recedes onto black, per Apple's sheet card-stack */}
            <div style={{
              position: 'absolute', inset: 0, borderRadius: 40, overflow: 'hidden',
              background: BG,
              transform: 'scale(0.93) translateY(-10px)', transformOrigin: 'top center',
            }}>
              <FloatingTopBar />
              <ArticleBody />
              <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.45)' }} />
            </div>

            {/* Tabs sheet — two Liquid Glass icon chips flanking the centered title */}
            <IOSSheet
              dark detent="large" height={874}
              title="Tabs" divider={false}
              accent={ACCENT} material="#15181E"
              leading={(
                <button aria-label="Close" style={{
                  width: 38, height: 38, borderRadius: 999, cursor: 'pointer', padding: 0,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'rgba(60,60,67,0.45)',
                  WebkitBackdropFilter: 'blur(24px) saturate(180%)',
                  backdropFilter: 'blur(24px) saturate(180%)',
                  border: '0.5px solid rgba(255,255,255,0.22)',
                  boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.28), 0 4px 12px rgba(0,0,0,0.4)',
                }}>
                  <svg width="15" height="15" viewBox="0 0 14 14" fill="none" stroke="rgba(235,235,245,0.7)" strokeWidth="1.8" strokeLinecap="round">
                    <path d="M3 3l8 8M11 3l-8 8" />
                  </svg>
                </button>
              )}
              trailing={(
                <button aria-label="New tab" style={{
                  width: 38, height: 38, borderRadius: 999, cursor: 'pointer', padding: 0,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'rgba(60,60,67,0.45)',
                  WebkitBackdropFilter: 'blur(24px) saturate(180%)',
                  backdropFilter: 'blur(24px) saturate(180%)',
                  border: '0.5px solid rgba(255,255,255,0.22)',
                  boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.28), 0 4px 12px rgba(0,0,0,0.4)',
                }}>
                  <svg width="19" height="19" viewBox="0 0 22 22" fill="none" stroke={ACCENT} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M9.5 4H5.5a2 2 0 00-2 2v10.5a2 2 0 002 2h10.5a2 2 0 002-2V12.5" />
                    <path d="M15 3.5l3.5 3.5L11 14.5H7.5V11L15 3.5z" />
                  </svg>
                </button>
              )}
            >
              <TabView />
            </IOSSheet>
          </>
        ) : (
          <>
            <FloatingTopBar />
            <ArticleBody />
            {isReading && <div style={{ position: 'absolute', left: 0, right: 0, bottom: 92, height: 56, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', pointerEvents: 'none', zIndex: 5 }} />}
            {isReading           && <FloatingDock />}
            {state === 'editing' && <NotoToolbarArticle wordCount={258} activeKey={null} />}
            {state === 'editing' && <IOSKeyboard dark={true} />}
          </>
        )}
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp03ArticleV3Dock });
