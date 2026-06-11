// v3-search · Digital article — full search view.
// Sheet that opens when the user taps the dock search pill. Stays in the same
// Liquid-Glass dark visual system. Built per the attached reference:
//   • Big multi-line header at the top: small Noto AI avatar + "Search Tsz
//     Kiu Eugene's Workspace" or "Ask AI anything in Workspace" depending on
//     intent.
//   • Sections (in order):
//       1. Tabs                 (always shown)
//       2. Last edited          (when no keywords)
//       2. Search results       (when keywords; includes segmented control)
//   • Floating search pill at the bottom (above the keyboard) with
//     magnifier + input + filter chip + outside × close button.
//
// Two states are exposed:
//   "empty"   → no keywords; sections: Tabs · Last edited
//   "results" → keywords entered; sections: Tabs · Search results
//
// Pulls shared chrome: ArticleIcon, IOSDevice, IOSKeyboard — all on window.

function Exp03ArticleV3Search({ state = 'empty' }) {
  const BG     = '#0E1116';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.62)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(255,255,255,0.06)';
  const ACCENT = '#FF6A2E';
  const HL     = 'rgba(230,182,42,0.32)';
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

  // Open tabs
  const TABS = [
    { id: 't1', active: true,  title: 'How to Build Strong AI Products', folder: 'Captures' },
    { id: 't2', active: false, title: 'Weekly review · Mar 11',         folder: 'Journal' },
    { id: 't3', active: false, title: 'Sahil — compounding deposits',   folder: 'Highlights' },
    { id: 't4', active: false, title: 'Field guide outline',            folder: 'Drafts' },
    { id: 't5', active: false, title: 'Pricing experiments Q1',         folder: 'Projects' },
  ];

  // Recent (last-edited) notes — used in empty state
  const RECENT = [
    { title: 'How to Build Strong AI Products',            folder: 'Captures',   when: '2h ago' },
    { title: 'Weekly review · Mar 11',                     folder: 'Journal',    when: 'Yesterday' },
    { title: 'Dan Koe — 1 day exercise',                   folder: 'Captures',   when: '2d ago' },
    { title: 'What is my definition of a "great" life',    folder: 'Captures',   when: '3d ago' },
    { title: 'Reflection 2025',                            folder: 'Journal',    when: '5d ago' },
    { title: '_INBOX',                                     folder: 'Drafts',     when: 'a week ago' },
  ];

  // Hypothetical query for the results state.
  const QUERY = 'compound';

  // Search results (title + body matches) when QUERY is active.
  // `inTitle` flags items that match the title; matters when the segmented
  // control flips to "Title only".
  const SEG = 'all'; // 'all' (Title + body) | 'title' (Title only)
  const RESULTS_ALL = [
    { title: 'How to Build Strong AI Products', folder: 'Captures',   when: '2h ago',  snippet: 'durable products are the ones whose value <hl>compound</hl>s with the user\u2019s data', inTitle: false },
    { title: 'Compounding deposits — Sahil',     folder: 'Highlights', when: '3d ago',  snippet: 'three deposits that <hl>compound</hl> across years: writing, taste, distribution',  inTitle: true  },
    { title: 'Pricing experiments Q1',           folder: 'Projects',   when: 'Mar 4',   snippet: 'the metered drip lets revenue <hl>compound</hl> with usage rather than seat count',  inTitle: false },
    { title: 'Compound interest mental models',  folder: 'Highlights', when: 'Feb 18',  snippet: 'analogies for <hl>compound</hl>ing in non-financial contexts — habits, taste, trust', inTitle: true  },
  ];

  // ─── header ───────────────────────────────────────────────
  const Header = () => (
    <div style={{
      flexShrink: 0,
      padding: '12px 18px 10px',
      display: 'flex', alignItems: 'flex-start', gap: 12,
    }}>
      {/* Avatar — small round Noto AI face */}
      <div style={{
        width: 44, height: 44, borderRadius: 999,
        background: 'rgba(255,255,255,0.06)',
        border: '0.5px solid rgba(255,255,255,0.10)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        {/* the cheeky face glyph */}
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="9.5" cy="11" r="1" fill={HEAD} />
          <circle cx="15"  cy="11" r="1" fill={HEAD} />
          <path d="M9 15c1.2 1 4.8 1 6 0" />
          <path d="M17 4.5c1.8 0 3 1.3 3 3" />
        </svg>
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          color: HEAD, fontFamily: SANS,
          fontSize: 22, fontWeight: 700, letterSpacing: -0.3,
          lineHeight: 1.18,
        }}>
          {state === 'results' ? (
            <>
              <span>Results for </span>
              <span style={{ color: ACCENT }}>“{QUERY}”</span>
            </>
          ) : (
            <>Search or ask in <br /><span style={{ color: ACCENT }}>Eugene’s workspace</span></>
          )}
        </div>
      </div>
    </div>
  );

  // ─── section header ───────────────────────────────────────
  const SectionTitle = ({ children, right }) => (
    <div style={{
      padding: '14px 18px 6px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    }}>
      <span style={{
        color: MUTED, fontFamily: SANS,
        fontSize: 11, fontWeight: 600,
        letterSpacing: 0.6, textTransform: 'uppercase',
      }}>{children}</span>
      {right}
    </div>
  );

  // ─── segmented control (Title + body / Title only) ────────
  const Segmented = ({ value = SEG }) => (
    <div style={{
      display: 'flex', alignItems: 'stretch',
      background: 'rgba(255,255,255,0.06)',
      border: '0.5px solid rgba(255,255,255,0.08)',
      borderRadius: 999, padding: 3, gap: 3,
      height: 34, width: '100%',
    }}>
      {[
        { id: 'all',   label: 'Title + body' },
        { id: 'title', label: 'Title only' },
      ].map((opt) => {
        const active = opt.id === value;
        return (
          <div key={opt.id} style={{
            flex: 1,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            borderRadius: 999,
            background: active ? 'rgba(255,255,255,0.12)' : 'transparent',
            boxShadow: active ? 'inset 0 0.5px 0 rgba(255,255,255,0.18)' : 'none',
            color: active ? HEAD : MUTED,
            fontFamily: SANS, fontSize: 13, fontWeight: active ? 600 : 500,
            letterSpacing: -0.1,
          }}>{opt.label}</div>
        );
      })}
    </div>
  );

  // ─── row primitives ───────────────────────────────────────
  const fileGlyph = (color = MUTED) => (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 1.5h5l3 3V13a1 1 0 01-1 1H4a1 1 0 01-1-1V2.5a1 1 0 011-1z" />
      <path d="M9 1.5v3h3" />
    </svg>
  );

  // Render a snippet string with <hl>match</hl> highlighted.
  const renderSnippet = (s) => {
    if (!s) return null;
    const parts = s.split(/<hl>|<\/hl>/);
    return parts.map((p, i) => i % 2 === 1
      ? <span key={i} style={{ background: HL, color: HEAD, borderRadius: 2, padding: '0 2px' }}>{p}</span>
      : <React.Fragment key={i}>{p}</React.Fragment>);
  };

  const Row = ({ title, sub, snippet, accent, glyphColor }) => (
    <div style={{
      padding: '12px 18px',
      display: 'flex', alignItems: 'flex-start', gap: 12,
      borderBottom: '0.5px solid ' + RULE,
    }}>
      <div style={{ marginTop: 1, flexShrink: 0 }}>{fileGlyph(glyphColor || MUTED)}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          color: HEAD, fontFamily: SANS,
          fontSize: 15, fontWeight: 500, letterSpacing: -0.1,
          lineHeight: 1.3,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{title}</div>
        {sub && (
          <div style={{
            color: MUTED, fontFamily: SANS, fontSize: 12,
            marginTop: 2,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{sub}</div>
        )}
        {snippet && (
          <div style={{
            color: INK, fontFamily: SANS, fontSize: 12.5, lineHeight: 1.45,
            marginTop: 4, opacity: 0.85,
            display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
          }}>{renderSnippet(snippet)}</div>
        )}
      </div>
      {accent}
    </div>
  );

  // ─── body — empty vs results ─────────────────────────────
  const Body = () => (
    <div style={{
      flex: 1, minHeight: 0, overflow: 'hidden',
      paddingBottom: 8,
    }}>
      {/* Last edited / Search results — single section, no Tabs section */}
      {state === 'empty' ? (
        <>
          <SectionTitle>Last edited</SectionTitle>
          {RECENT.slice(0, 5).map((r, i) => (
            <Row
              key={i}
              title={r.title}
              sub={'in ' + r.folder + ' · ' + r.when}
            />
          ))}
        </>
      ) : (
        <>
          <SectionTitle>Search results</SectionTitle>
          {RESULTS_ALL.slice(0, 4).map((r, i) => (
            <Row
              key={i}
              title={r.title}
              sub={'in ' + r.folder + ' · ' + r.when}
              snippet={r.snippet}
            />
          ))}
        </>
      )}
    </div>
  );

  // ─── bottom: floating search pill + outside × close ──────
  const SearchDock = () => (
    <div style={{
      flexShrink: 0,
      padding: '8px 12px 12px',
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <div style={{
        ...glassStyle,
        flex: 1, height: 46, borderRadius: 999,
        padding: '0 14px', gap: 10,
        display: 'flex', alignItems: 'center',
      }}>
        <ArticleIcon name="search" color={MUTED} size={17} />
        {state === 'results' ? (
          <div style={{
            color: HEAD, fontFamily: SANS, fontSize: 15, fontWeight: 500,
            flex: 1, minWidth: 0, display: 'flex', alignItems: 'center',
          }}>
            <span>{QUERY}</span>
            <span style={{
              display: 'inline-block', width: 1, height: 18,
              background: ACCENT, marginLeft: 2,
            }} />
          </div>
        ) : (
          <span style={{
            color: MUTED, fontFamily: SANS, fontSize: 15,
            flex: 1, minWidth: 0,
          }}>Search or ask AI</span>
        )}
        {/* filter chip */}
        <div style={{
          width: 28, height: 28, borderRadius: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke={HEAD} strokeWidth="1.5" strokeLinecap="round">
            <path d="M2 4h12M4 8h8M6 12h4" />
          </svg>
        </div>
      </div>

      {/* outside × close */}
      <div style={{
        ...glassStyle,
        width: 46, height: 46, borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke={HEAD} strokeWidth="2" strokeLinecap="round">
          <path d="M3 3l7 7M10 3l-7 7" />
        </svg>
      </div>
    </div>
  );

  return (
    <IOSDevice dark={true} background={BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, background: BG }}>
        {/* status bar reserve */}
        <div style={{ height: 62, flexShrink: 0 }} />

        <Body />
        {state === 'results' && (
          <div style={{ flexShrink: 0, padding: '4px 12px 8px' }}>
            <Segmented value="all" />
          </div>
        )}
        <SearchDock />
        <IOSKeyboard dark={true} />
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp03ArticleV3Search });
