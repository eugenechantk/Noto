// Noto · Editor explorations · v2 — top chrome rewrite.
// All functional controls (back, title, more, find, search, today, new)
// move to the top. Bottom toolbar emptied. Body content verbatim from v1.
// Each style pushed further into its own aesthetic.
// Depends on NOTE, renderParts, ExpImage, ExpLegend, W_EXP/H_PHONE/H_EXP
// from components/noto-explorations-1.jsx and NOTO from noto-shared.jsx.

// Reusable iOS dynamic-island dot
function Island() {
  return (
    <div style={{
      position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
      width: 124, height: 36, borderRadius: 22, background: '#000', zIndex: 5,
    }} />
  );
}

// ═════════════════════════════════════════════════════════════
// 01 · MINIMALIST DARK v2 — chrome dissolves into faded text row.
// All 6 affordances expressed as slash-separated words, no icons.
// ═════════════════════════════════════════════════════════════
function Exp01MinimalV2() {
  const BG = '#000';
  const INK_ANCHOR = 'rgba(255,255,255,0.85)';
  const INK = 'rgba(255,255,255,0.32)';
  const INK_HEAD = 'rgba(255,255,255,0.55)';
  const DOT = 'rgba(255,255,255,0.18)';
  const SYNTAX = 'rgba(255,255,255,0.08)';
  const LINK = 'rgba(180,200,255,0.55)';
  const linkStyle = { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK };
  const italicStyle = { fontStyle: 'italic', color: INK_HEAD };
  const body1Rest = NOTE.body1.slice();
  body1Rest[0] = body1Rest[0].slice(1);

  return (
    <div style={{ width: W_EXP, height: H_EXP, background: BG, position: 'relative', fontFamily: NOTO.font, overflow: 'hidden' }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar */}
        <div style={{
          height: 48, padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: 'rgba(255,255,255,0.45)', fontSize: 13, fontWeight: 500,
        }}>
          <span>14:10</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span>•••</span><span>LTE 68%</span>
          </span>
        </div>
        <Island />

        {/* TOP CHROME — single faded row */}
        <div style={{
          padding: '16px 22px 0',
          display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
          color: INK_HEAD, fontSize: 12, letterSpacing: 0.3,
        }}>
          <span>← captures</span>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <span>today</span><span style={{ color: DOT }}>·</span>
            <span>find</span><span style={{ color: DOT }}>·</span>
            <span>search</span><span style={{ color: DOT }}>·</span>
            <span>new</span><span style={{ color: DOT }}>·</span>
            <span style={{ color: DOT }}>⋯</span>
          </span>
        </div>

        {/* title */}
        <div style={{ padding: '22px 22px 0' }}>
          <span style={{ color: INK_ANCHOR, fontWeight: 700, fontSize: 16, letterSpacing: -0.2 }}>How to Build Strong AI Products</span>
          <span style={{ color: 'rgba(255,255,255,0.30)', fontSize: 14, marginLeft: 6 }}>— saved 2h</span>
        </div>
        <div style={{ padding: '6px 22px 0', color: 'rgba(255,255,255,0.22)', fontSize: 12, letterSpacing: 0.3 }}>11 fields</div>

        {/* body — verbatim v1 */}
        <div style={{ padding: '24px 22px 0', fontSize: 14, lineHeight: 1.55, color: INK }}>
          <p style={{ margin: 0 }}><span style={{ color: INK_HEAD }}>{NOTE.subtitle}</span></p>
          <div style={{ marginTop: 18 }}>
            <ExpImage height={150} radius={2} background="#0a0a0c"
              frame={{ border: '0.5px solid rgba(255,255,255,0.10)' }}
              color="rgba(255,255,255,0.20)" label="1200 × 500" />
          </div>
          <p style={{ margin: '20px 0 0' }}>
            <span style={{ color: INK_ANCHOR, fontWeight: 600 }}>T</span>
            {renderParts(body1Rest, linkStyle, italicStyle)}
          </p>
          <div style={{ marginTop: 22, display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <span style={{ color: SYNTAX, fontSize: 15 }}>##</span>
            <span style={{ color: INK_HEAD, fontSize: 15, fontWeight: 600 }}>{NOTE.h2}</span>
          </div>
          <p style={{ margin: '14px 0 0' }}>{renderParts(NOTE.body2, linkStyle, italicStyle)}</p>
          <div style={{ marginTop: 22, display: 'flex', gap: 8, color: 'rgba(255,255,255,0.20)', fontStyle: 'italic' }}>
            <span style={{ color: SYNTAX }}>&gt;</span><span>{NOTE.quote}</span>
          </div>
        </div>

        {/* home indicator only — bottom emptied */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.30)',
        }} />
      </div>
      <ExpLegend find="top-row 'find' word" mention="@ inline chip" accent="rgba(255,255,255,0.7)" />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 02 · BOOK v2 — chrome becomes a running head + chapter actions.
// Top hairline · CAPTURES (folder) · iii. (roman page) · second
// hairline · italic small-caps action row · final hairline.
// ═════════════════════════════════════════════════════════════
function Exp02BookV2() {
  const PAGE = '#F2EEE3';
  const INK = '#1A1814';
  const INK_MUTED = '#5B544A';
  const RULE = 'rgba(26,24,20,0.18)';
  const LINK = '#6A4A2A';
  const SERIF = '"EB Garamond", "Cormorant Garamond", Georgia, serif';

  return (
    <div style={{ width: W_EXP, height: H_EXP, background: PAGE, position: 'relative',
      fontFamily: SERIF, overflow: 'hidden' }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar */}
        <div style={{
          height: 48, padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 14, fontWeight: 600, fontFamily: '-apple-system, system-ui',
        }}>
          <span>6:56</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <svg width="17" height="11" viewBox="0 0 17 11" fill={INK}>
              <circle cx="2" cy="9" r="1.1" /><circle cx="6" cy="9" r="1.1" />
              <circle cx="10" cy="9" r="1.1" /><circle cx="14" cy="9" r="1.1" />
            </svg>
            <svg width="17" height="12" viewBox="0 0 17 12" fill={INK}>
              <path d="M8.5 2.3c2.7 0 5.1 1 7 2.7l1.3-1.3A11.5 11.5 0 0 0 0 3.6L1.3 5A10 10 0 0 1 8.5 2.3z"/>
              <path d="M8.5 6c1.5 0 2.8.5 3.8 1.4l1.3-1.3A7.5 7.5 0 0 0 3.4 6L4.7 7.4A5.7 5.7 0 0 1 8.5 6z"/>
              <circle cx="8.5" cy="10" r="1.7"/>
            </svg>
            <svg width="28" height="13" viewBox="0 0 28 13">
              <rect x="0.5" y="0.5" width="23" height="12" rx="3" fill="none" stroke={INK} strokeOpacity="0.6" />
              <rect x="2" y="2" width="20" height="9" rx="2" fill={INK} />
              <path d="M25 4v5c.9-.3 1.5-1.2 1.5-2.5S25.9 4.3 25 4z" fill={INK} fillOpacity="0.5" />
            </svg>
          </span>
        </div>
        <Island />

        {/* RUNNING HEAD */}
        <div style={{ padding: '12px 28px 0' }}>
          <div style={{ height: 0.5, background: RULE }} />
          <div style={{
            display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
            padding: '8px 0', color: INK_MUTED, fontSize: 11, letterSpacing: 2.4,
            textTransform: 'uppercase',
          }}>
            <span>← back</span>
            <span style={{ color: INK }}>captures</span>
            <span style={{ fontStyle: 'italic', textTransform: 'none', letterSpacing: 0, fontSize: 13 }}>iii.</span>
          </div>
          <div style={{ height: 0.5, background: RULE }} />
          {/* chapter action row */}
          <div style={{
            display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
            padding: '10px 0',
            color: INK_MUTED, fontSize: 11, letterSpacing: 2,
            textTransform: 'uppercase', fontFamily: SERIF, fontStyle: 'italic',
          }}>
            <span>today</span>
            <span style={{ color: RULE }}>—</span>
            <span>find</span>
            <span style={{ color: RULE }}>—</span>
            <span>search</span>
            <span style={{ color: RULE }}>—</span>
            <span>new</span>
            <span style={{ color: RULE }}>—</span>
            <span>more</span>
          </div>
          <div style={{ height: 0.5, background: RULE }} />
        </div>

        {/* title */}
        <div style={{ padding: '22px 28px 0', color: INK, fontSize: 32, lineHeight: 1.1, letterSpacing: -0.5 }}>
          How to Build<br />Strong AI Products
        </div>
        <div style={{ padding: '10px 28px 0', color: INK_MUTED, fontSize: 14, fontStyle: 'italic' }}>
          May 14, 2026 · 11 fields
        </div>

        {/* body — verbatim */}
        <div style={{ padding: '18px 28px 0', color: INK, fontSize: 16, lineHeight: 1.55 }}>
          <p style={{ margin: 0 }}>{NOTE.subtitle}</p>
          <div style={{ marginTop: 18, padding: 4, border: '0.5px solid ' + RULE }}>
            <ExpImage height={130} radius={0} background="#C9C2B0"
              frame={{ border: '0.5px solid ' + RULE }}
              color="rgba(0,0,0,0.30)" label="plate i" />
          </div>
          <p style={{ margin: '18px 0 0' }}>
            {renderParts(NOTE.body1,
              { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
              { fontStyle: 'italic' })}
          </p>
          <div style={{ marginTop: 20, color: INK, fontSize: 22, lineHeight: 1.2 }}>{NOTE.h2}</div>
        </div>

        <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(0,0,0,0.30)' }} />
      </div>
      <ExpLegend find="chapter action 'find'" mention="@ chapter index" accent="#caa97c" />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 03 · ARTICLE v2 — Pocket/Reader controls all-up. Two chrome rows
// + reading progress bar between them.
// ═════════════════════════════════════════════════════════════
function Exp03ArticleV2() {
  const BG = '#15171C';
  const INK = '#E5E5E7';
  const INK_HEAD = '#FAFAFA';
  const INK_MUTED = 'rgba(229,229,231,0.55)';
  const RULE = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF5A1F';
  const SANS = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  const TopIcon = ({ children, label, fg }) => (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, flex: 1 }}>
      <div style={{
        width: 36, height: 36, borderRadius: 18,
        background: 'rgba(255,255,255,0.06)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: fg || INK,
      }}>{children}</div>
      <span style={{ fontSize: 10, color: INK_MUTED, letterSpacing: 0.2 }}>{label}</span>
    </div>
  );

  return (
    <div style={{ width: W_EXP, height: H_EXP, background: BG, position: 'relative',
      fontFamily: SANS, overflow: 'hidden' }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar */}
        <div style={{
          height: 48, padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK_HEAD, fontSize: 15, fontWeight: 600,
        }}>
          <span>9:41</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <svg width="17" height="11" viewBox="0 0 17 11" fill={INK_HEAD}>
              <circle cx="2" cy="9" r="1.1" /><circle cx="6" cy="9" r="1.1" />
              <circle cx="10" cy="9" r="1.1" /><circle cx="14" cy="9" r="1.1" />
            </svg>
            <svg width="17" height="12" viewBox="0 0 17 12" fill={INK_HEAD}>
              <path d="M8.5 2.3c2.7 0 5.1 1 7 2.7l1.3-1.3A11.5 11.5 0 0 0 0 3.6L1.3 5A10 10 0 0 1 8.5 2.3z"/>
              <path d="M8.5 6c1.5 0 2.8.5 3.8 1.4l1.3-1.3A7.5 7.5 0 0 0 3.4 6L4.7 7.4A5.7 5.7 0 0 1 8.5 6z"/>
              <circle cx="8.5" cy="10" r="1.7"/>
            </svg>
            <svg width="28" height="13" viewBox="0 0 28 13">
              <rect x="0.5" y="0.5" width="23" height="12" rx="3" fill="none" stroke="rgba(255,255,255,0.55)" />
              <rect x="2" y="2" width="20" height="9" rx="2" fill={INK_HEAD} />
              <path d="M25 4v5c.9-.3 1.5-1.2 1.5-2.5S25.9 4.3 25 4z" fill="rgba(255,255,255,0.55)" />
            </svg>
          </span>
        </div>
        <Island />

        {/* CHROME ROW 1 · app glyph + back + breadcrumb + more */}
        <div style={{
          padding: '6px 18px 8px', display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <div style={{
            width: 28, height: 28, borderRadius: 7, background: ACCENT,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontWeight: 800, fontSize: 13, letterSpacing: -0.5,
            boxShadow: '0 2px 8px rgba(255,90,31,0.35)',
          }}>N</div>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={INK_HEAD} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M15 5l-7 7 7 7" />
          </svg>
          <div style={{
            flex: 1, color: INK_MUTED, fontSize: 13,
            display: 'flex', alignItems: 'center', gap: 6, minWidth: 0,
          }}>
            <span>Captures</span>
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke={INK_MUTED} strokeWidth="2">
              <path d="M9 5l7 7-7 7" />
            </svg>
            <span style={{ color: INK_HEAD, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              How to Build Strong AI Products
            </span>
          </div>
          <svg width="22" height="6" viewBox="0 0 22 6" fill={INK_HEAD}>
            <circle cx="3" cy="3" r="2" /><circle cx="11" cy="3" r="2" /><circle cx="19" cy="3" r="2" />
          </svg>
        </div>

        {/* reading-progress bar */}
        <div style={{ height: 2, background: 'rgba(255,255,255,0.06)' }}>
          <div style={{ width: '38%', height: '100%', background: ACCENT }} />
        </div>

        {/* CHROME ROW 2 · icon toolbar */}
        <div style={{
          padding: '10px 6px 8px',
          display: 'flex', alignItems: 'center',
        }}>
          <TopIcon label="AA">
            <span style={{ fontWeight: 600, color: INK }}>
              <span style={{ fontSize: 10 }}>A</span><span style={{ fontSize: 14 }}>A</span>
            </span>
          </TopIcon>
          <TopIcon label="find">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round">
              <circle cx="11" cy="11" r="6" /><path d="M20 20l-5-5" />
            </svg>
          </TopIcon>
          <TopIcon label="search">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3.5" y="3.5" width="17" height="17" rx="3" />
              <path d="M3.5 9.5h17M9.5 3.5v17" />
            </svg>
          </TopIcon>
          <TopIcon label="today">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3.5" y="5" width="17" height="15.5" rx="2.2" />
              <path d="M3.5 9.5h17M8 3v4M16 3v4" />
            </svg>
          </TopIcon>
          <TopIcon label="new">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round">
              <path d="M12 5v14M5 12h14" />
            </svg>
          </TopIcon>
          <TopIcon label="save" fg={ACCENT}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill={ACCENT} stroke={ACCENT} strokeWidth="1.5" strokeLinejoin="round">
              <path d="M6 4h12v18l-6-4-6 4V4z" />
            </svg>
          </TopIcon>
        </div>
        <div style={{ height: 0.5, background: RULE }} />

        {/* body — verbatim v1 */}
        <div style={{ padding: '18px 22px 0' }}>
          <div style={{
            color: INK_HEAD, fontSize: 22, fontWeight: 700, lineHeight: 1.18, letterSpacing: -0.3,
          }}>{NOTE.title}</div>
          <div style={{
            marginTop: 10, display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 10px', borderRadius: 999,
            background: 'rgba(255,255,255,0.06)',
            color: INK_MUTED, fontSize: 12, letterSpacing: 0.1,
          }}>
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke={INK_MUTED} strokeWidth="2" strokeLinecap="round">
              <path d="M4 7h12M4 12h16M4 17h10" />
            </svg>
            11 fields · saved 2h
          </div>
          <p style={{ margin: '16px 0 0', color: INK, fontSize: 17, lineHeight: 1.55 }}>{NOTE.subtitle}</p>
          <ExpImage marginTop={18} height={160} radius={10} background="#2A2C33"
            color="rgba(255,255,255,0.35)" />
          <div style={{ position: 'relative', marginTop: 20 }}>
            <p style={{ margin: 0, color: INK, fontSize: 17, lineHeight: 1.55, letterSpacing: -0.1 }}>
              {renderParts(NOTE.body1,
                { color: ACCENT, textDecoration: 'underline', textUnderlineOffset: 3, textDecorationColor: 'rgba(255,90,31,0.5)' },
                { fontStyle: 'italic', color: INK_MUTED })}
            </p>
            <span style={{
              position: 'absolute', left: 142, top: 132, width: 142, height: 22,
              background: 'rgba(255,255,255,0.14)', borderRadius: 3,
            }} />
            <div style={{
              position: 'absolute', left: 188, top: 124,
              width: 44, height: 44, borderRadius: 22,
              background: 'rgba(255,255,255,0.30)',
              boxShadow: '0 0 0 1px rgba(255,255,255,0.40), 0 6px 18px rgba(0,0,0,0.35)',
              backdropFilter: 'blur(4px)',
            }} />
          </div>
          <div style={{ marginTop: 22, color: INK_HEAD, fontSize: 19, fontWeight: 700, letterSpacing: -0.2 }}>{NOTE.h2}</div>
        </div>

        <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.55)' }} />
      </div>
      <ExpLegend find="top toolbar 'find' icon" mention="@ orange picker" accent={ACCENT} />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 04 · TECHNO v2 — vim-style status line + key-binding row.
// Black status row with white NORMAL block, file path, line counter.
// Mono key-bindings row below: [←] BACK · [F]IND · [S]EARCH · [T]ODAY · [N]EW · [⋯]
// ═════════════════════════════════════════════════════════════
function Exp04TechnoV2() {
  const BG = '#000';
  const INK = '#EFEFEF';
  const INK_MUTED = 'rgba(255,255,255,0.50)';
  const INK_FAINT = 'rgba(255,255,255,0.30)';
  const RULE = 'rgba(255,255,255,0.22)';
  const LINK = '#1A1AFF';
  const MONO = '"JetBrains Mono", ui-monospace, "SF Mono", monospace';
  const SERIF = '"IBM Plex Serif", "Source Serif 4", Georgia, serif';

  const KB = ({ k, w }) => (
    <span style={{ display: 'inline-flex', alignItems: 'baseline' }}>
      <span style={{ color: INK_MUTED }}>[</span>
      <span>{k}</span>
      <span style={{ color: INK_MUTED }}>]</span>
      {w && <span style={{ color: INK_MUTED, marginLeft: 1 }}>{w}</span>}
    </span>
  );

  return (
    <div style={{ width: W_EXP, height: H_EXP, background: BG, position: 'relative',
      fontFamily: MONO, overflow: 'hidden' }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar */}
        <div style={{
          height: 48, padding: '0 20px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 11, letterSpacing: 0.6, textTransform: 'uppercase',
        }}>
          <span>06:56</span>
          <span>LTE 100%</span>
        </div>
        <div style={{ position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
          width: 124, height: 36, borderRadius: 22, background: '#000',
          border: '0.5px solid rgba(255,255,255,0.18)' }} />

        {/* CHROME ROW 1 · vim modeline */}
        <div style={{
          padding: '10px 14px 10px',
          borderTop: '1px solid ' + RULE,
          borderBottom: '1px solid ' + RULE,
          background: '#0a0a0a',
          display: 'flex', alignItems: 'center', gap: 10,
          color: INK, fontSize: 10.5, letterSpacing: 0.6, textTransform: 'uppercase',
        }}>
          <span style={{ padding: '2px 6px', background: INK, color: '#000', fontWeight: 700 }}>NORMAL</span>
          <span style={{ color: INK_MUTED, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1, minWidth: 0 }}>
            ~/captures/strong-ai-products.md
          </span>
          <span style={{ color: INK_MUTED }}>11 META</span>
          <span style={{ color: INK_MUTED }}>L1/142</span>
        </div>

        {/* CHROME ROW 2 · key bindings */}
        <div style={{
          padding: '12px 14px',
          borderBottom: '1px solid ' + RULE,
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          color: INK, fontSize: 10.5, letterSpacing: 0.5, textTransform: 'uppercase',
        }}>
          <KB k="←" w=" BACK" />
          <KB k="F" w="IND" />
          <KB k="S" w="EARCH" />
          <KB k="T" w="ODAY" />
          <KB k="N" w="EW" />
          <KB k="⋯" />
        </div>

        {/* frontmatter code block */}
        <div style={{
          margin: '12px 14px 0', padding: '8px 12px',
          border: '1px solid ' + RULE,
          color: INK_FAINT, fontSize: 11, lineHeight: 1.55, letterSpacing: 0.2,
        }}>
          <div>---</div>
          <div>source: readwise</div>
          <div>tags: [ai, products]</div>
          <div>saved: 2026-05-14</div>
          <div>---</div>
        </div>

        {/* title */}
        <div style={{
          padding: '16px 14px 0',
          color: INK, fontSize: 24, lineHeight: 1.05, letterSpacing: -1, fontWeight: 500,
          textTransform: 'uppercase',
        }}>
          # HOW TO<br />BUILD STRONG<br />AI PRODUCTS
        </div>

        <div style={{
          padding: '12px 20px 0', color: RULE, fontSize: 11, overflow: 'hidden', whiteSpace: 'nowrap',
        }}>{'-'.repeat(60)}</div>

        <p style={{
          margin: '12px 14px 0', color: INK, fontSize: 14, lineHeight: 1.5,
          fontFamily: SERIF,
        }}>{NOTE.subtitle}</p>

        <div style={{ padding: '12px 14px 0' }}>
          <ExpImage height={120} radius={0} background="#0c0c0c"
            frame={{ border: '1px solid ' + RULE }}
            color={INK_MUTED} label="[ IMG 1200×500 ]" />
        </div>

        <p style={{
          margin: '12px 14px 0', color: INK, fontSize: 14, lineHeight: 1.5,
          fontFamily: SERIF,
        }}>
          {renderParts(NOTE.body1,
            { color: LINK, textDecoration: 'underline', textUnderlineOffset: 2, textDecorationColor: LINK, textDecorationThickness: '1px' },
            { fontStyle: 'italic', color: INK_MUTED })}
        </p>

        <div style={{
          margin: '12px 14px 0',
          color: INK, fontSize: 18, fontWeight: 600,
          display: 'flex', alignItems: 'baseline', gap: 8,
          fontFamily: SERIF,
        }}>
          <span style={{ color: INK_MUTED, fontFamily: MONO, fontSize: 14 }}>##</span>
          <span style={{ textTransform: 'uppercase', letterSpacing: -0.3 }}>{NOTE.h2}</span>
        </div>

        <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 0, background: 'rgba(255,255,255,0.30)' }} />
      </div>
      <ExpLegend find="[F]IND keypress" mention="@ → [[ link ]]" accent={LINK} />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 05 · NATURAL v2 — chrome dissolves into 6 dew-drop pearls.
// Mantra phrase above, soft circular pearls below, each holding
// one functional glyph in dusty rose.
// ═════════════════════════════════════════════════════════════
function Exp05NaturalV2() {
  const INK = '#2A1F1A';
  const INK_MUTED = 'rgba(42,31,26,0.55)';
  const LINK = '#B0716E';
  const DISPLAY = '"Cormorant Garamond", "EB Garamond", Georgia, serif';
  const BODY = '"EB Garamond", "Cormorant Garamond", Georgia, serif';

  const gradient = `
    radial-gradient(120% 60% at 20% 10%, rgba(232,210,190,0.95) 0%, rgba(232,210,190,0) 60%),
    radial-gradient(80% 50% at 80% 30%, rgba(214,196,178,0.9) 0%, rgba(214,196,178,0) 60%),
    radial-gradient(70% 45% at 65% 60%, rgba(208,158,138,0.8) 0%, rgba(208,158,138,0) 60%),
    radial-gradient(80% 50% at 25% 80%, rgba(170,182,160,0.7) 0%, rgba(170,182,160,0) 65%),
    radial-gradient(60% 40% at 80% 95%, rgba(196,178,160,0.85) 0%, rgba(196,178,160,0) 60%),
    linear-gradient(to bottom, #E8DDCE, #D7C8B4)
  `;

  const Pearl = ({ children, size = 38 }) => (
    <div style={{
      width: size, height: size, borderRadius: size / 2,
      background: 'radial-gradient(circle at 35% 30%, #FFFCF6 0%, #EDE3D2 70%, #C8B89E 100%)',
      boxShadow: '0 4px 12px rgba(50,30,20,0.18), inset 0 1px 0 rgba(255,255,255,0.7)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: LINK,
    }}>{children}</div>
  );

  return (
    <div style={{ width: W_EXP, height: H_EXP, background: '#E5DCC9', position: 'relative',
      fontFamily: BODY, overflow: 'hidden' }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden', background: gradient }}>
        {/* status bar */}
        <div style={{
          height: 48, padding: '0 26px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 13, fontWeight: 500, fontFamily: '-apple-system, system-ui',
        }}>
          <span>08:10</span>
          <span>19.08</span>
        </div>
        <Island />

        {/* mantra */}
        <div style={{
          padding: '10px 26px 0', textAlign: 'center',
          color: INK_MUTED, fontSize: 13, fontStyle: 'italic', fontFamily: BODY,
        }}>morning · soft rain · 19.08</div>

        {/* dew-drop row */}
        <div style={{
          padding: '12px 16px 0',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <Pearl>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={LINK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
              <path d="M15 5l-7 7 7 7"/>
            </svg>
          </Pearl>
          <Pearl>
            <svg width="16" height="16" viewBox="0 0 24 24">
              <circle cx="12" cy="12" r="3.5" fill={LINK}/>
              <g stroke={LINK} strokeWidth="1.4" strokeLinecap="round">
                <path d="M12 4v2M12 18v2M4 12h2M18 12h2M6 6l1.5 1.5M16.5 16.5L18 18M6 18l1.5-1.5M16.5 7.5L18 6"/>
              </g>
            </svg>
          </Pearl>
          <Pearl>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={LINK} strokeWidth="1.7" strokeLinecap="round">
              <circle cx="11" cy="11" r="6"/><path d="M20 20l-5-5"/>
            </svg>
          </Pearl>
          <Pearl>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={LINK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3.5" y="3.5" width="17" height="17" rx="3"/>
              <path d="M3.5 9.5h17M9.5 3.5v17"/>
            </svg>
          </Pearl>
          <Pearl>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={LINK} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 21V11"/>
              <path d="M12 11c0-3 2-5 6-5 0 4-2 6-6 6z" fill="none"/>
              <path d="M12 11c0-3-2-5-6-5 0 4 2 6 6 6z" fill="none"/>
            </svg>
          </Pearl>
          <Pearl>
            <svg width="16" height="16" viewBox="0 0 24 24" fill={LINK}>
              <circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/>
            </svg>
          </Pearl>
        </div>

        {/* title */}
        <div style={{
          padding: '20px 26px 0', color: INK, fontFamily: DISPLAY,
          fontSize: 34, lineHeight: 1.0, letterSpacing: -0.5, fontWeight: 500,
        }}>
          How to Build<br />Strong AI<br />Products
        </div>

        <div style={{
          padding: '10px 26px 0', color: INK_MUTED, fontSize: 13, fontStyle: 'italic', fontFamily: BODY,
        }}>saved 2 hours ago · 11 fields</div>

        {/* body — verbatim */}
        <div style={{ padding: '14px 26px 0' }}>
          <p style={{ margin: 0, color: INK, fontSize: 15, lineHeight: 1.5, fontStyle: 'italic' }}>{NOTE.subtitle}</p>
          <div style={{ marginTop: 14, borderRadius: 18, overflow: 'hidden',
            boxShadow: '0 12px 32px rgba(170,120,90,0.25), 0 2px 6px rgba(0,0,0,0.06)' }}>
            <ExpImage height={100} radius={18}
              background="linear-gradient(135deg, #C9B5A0, #E2D2BD)"
              color="rgba(60,40,30,0.30)" label="1200 × 500" />
          </div>
          <div style={{ marginTop: 14, fontSize: 15, lineHeight: 1.55, color: INK }}>
            <span style={{
              float: 'left', fontFamily: DISPLAY, fontSize: 48, lineHeight: 0.85,
              padding: '4px 8px 0 0', color: INK, fontWeight: 500,
            }}>{NOTE.body1[0].slice(0, 1)}</span>
            <span>
              {(() => {
                const rest = NOTE.body1.slice();
                rest[0] = rest[0].slice(1);
                return renderParts(rest,
                  { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
                  { fontStyle: 'italic', color: INK_MUTED });
              })()}
            </span>
            <div style={{ clear: 'both' }} />
          </div>
          <div style={{
            marginTop: 14, color: INK, fontFamily: DISPLAY, fontSize: 22, lineHeight: 1.15, fontWeight: 500,
          }}>{NOTE.h2}</div>
        </div>

        <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(0,0,0,0.30)' }} />
      </div>
      <ExpLegend find="lens pearl tap" mention="@ blooms inline" accent="#D9A89E" />
    </div>
  );
}

Object.assign(window, {
  Exp01MinimalV2, Exp02BookV2, Exp03ArticleV2, Exp04TechnoV2, Exp05NaturalV2,
});
