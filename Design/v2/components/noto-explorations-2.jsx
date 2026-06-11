// Noto · Editor explorations 03–05.
// Depends on noto-explorations-1.jsx (NOTE, renderParts, ExpImage, ExpLegend, sizes).

// ═════════════════════════════════════════════════════════════
// 03 · DIGITAL ARTICLE — Readwise Reader style. Dark, humanist.
// ═════════════════════════════════════════════════════════════
function Exp03Article() {
  const BG = '#15171C';
  const INK = '#E5E5E7';
  const INK_HEAD = '#FAFAFA';
  const INK_MUTED = 'rgba(229,229,231,0.55)';
  const RULE = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF5A1F'; // brand orange
  const SANS = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  // Body 1 with mid-paragraph selection ("compounding products" highlighted under
  // the touch indicator). We split the link text into "halves" by re-using parts.
  return (
    <div style={{
      width: W_EXP, height: H_EXP, background: BG, position: 'relative',
      fontFamily: SANS, overflow: 'hidden',
    }}>
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
        {/* dynamic island */}
        <div style={{
          position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
          width: 124, height: 36, borderRadius: 22, background: '#000',
        }} />

        {/* top: back chevron + centered title, no pills */}
        <div style={{
          padding: '6px 18px 0', display: 'flex', alignItems: 'center',
          height: 36,
        }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={INK_HEAD} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M15 5l-7 7 7 7" />
          </svg>
          <div style={{
            flex: 1, textAlign: 'center', color: INK_HEAD,
            fontSize: 15, fontWeight: 600, letterSpacing: -0.2,
            marginRight: 22,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>The Design of Books</div>
        </div>

        {/* article wrapper */}
        <div style={{ padding: '22px 22px 100px' }}>
          {/* title + meta chip */}
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

          {/* subtitle */}
          <p style={{ margin: '18px 0 0', color: INK, fontSize: 17, lineHeight: 1.55 }}>{NOTE.subtitle}</p>

          {/* image */}
          <ExpImage marginTop={22} height={180} radius={10} background="#2A2C33"
            color="rgba(255,255,255,0.35)" />

          {/* body 1 with inline selection */}
          <div style={{ position: 'relative', marginTop: 22 }}>
            <p style={{ margin: 0, color: INK, fontSize: 17, lineHeight: 1.55, letterSpacing: -0.1 }}>
              {renderParts(NOTE.body1,
                { color: ACCENT, textDecoration: 'underline', textUnderlineOffset: 3, textDecorationColor: 'rgba(255,90,31,0.5)' },
                { fontStyle: 'italic', color: INK_MUTED })}
            </p>
            {/* selection highlight + touch indicator */}
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

          <div style={{
            marginTop: 26, color: INK_HEAD, fontSize: 19, fontWeight: 700, letterSpacing: -0.2,
          }}>{NOTE.h2}</div>
        </div>

        {/* bottom toolbar */}
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 0,
          padding: '14px 8px 28px',
          background: 'linear-gradient(to top, ' + BG + ' 60%, rgba(21,23,28,0))',
          display: 'flex', alignItems: 'center', justifyContent: 'space-around',
        }}>
          {/* app glyph (orange rounded square) */}
          <div style={{
            width: 38, height: 38, borderRadius: 9, background: ACCENT,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontWeight: 800, fontSize: 16, letterSpacing: -0.5,
            boxShadow: '0 2px 8px rgba(255,90,31,0.35)',
          }}>N</div>
          {/* AA */}
          <div style={{ width: 44, display: 'flex', flexDirection: 'column', alignItems: 'center', color: INK }}>
            <span style={{ fontSize: 18, fontWeight: 600, lineHeight: 1 }}>
              <span style={{ fontSize: 13 }}>A</span><span>A</span>
            </span>
          </div>
          {/* bookmark */}
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 4h12v18l-6-4-6 4V4z" />
          </svg>
          {/* comments + badge */}
          <div style={{ position: 'relative' }}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 5h16v12H8l-4 4V5z" />
            </svg>
            <div style={{
              position: 'absolute', top: -4, right: -10,
              padding: '1px 5px', borderRadius: 8, background: '#1F2128',
              color: INK_HEAD, fontSize: 10, fontWeight: 600,
              border: '0.5px solid rgba(255,255,255,0.18)',
            }}>19</div>
          </div>
        </div>

        {/* home indicator */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.55)',
        }} />
      </div>
      <ExpLegend find="AA → find in note" mention="@ pops orange picker" accent={ACCENT} />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 04 · TECHNO — Brutalist tech. Mono chrome, serif body, pure blue links.
// ═════════════════════════════════════════════════════════════
function Exp04Techno() {
  const BG = '#000';
  const INK = '#EFEFEF';
  const INK_MUTED = 'rgba(255,255,255,0.50)';
  const INK_FAINT = 'rgba(255,255,255,0.30)';
  const RULE = 'rgba(255,255,255,0.22)';
  const LINK = '#1A1AFF';
  const MONO = '"JetBrains Mono", ui-monospace, "SF Mono", monospace';
  const SERIF = '"IBM Plex Serif", "Source Serif 4", Georgia, serif';

  return (
    <div style={{
      width: W_EXP, height: H_EXP, background: BG, position: 'relative',
      fontFamily: MONO, overflow: 'hidden',
    }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar — mono */}
        <div style={{
          height: 48, padding: '0 20px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 11, letterSpacing: 0.6, textTransform: 'uppercase',
        }}>
          <span>06:56</span>
          <span>LTE 100%</span>
        </div>
        {/* dynamic island */}
        <div style={{
          position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
          width: 124, height: 36, borderRadius: 22, background: '#000',
          border: '0.5px solid rgba(255,255,255,0.18)',
        }} />

        {/* mono status strip with geometric icon */}
        <div style={{
          padding: '14px 20px 8px',
          borderBottom: '1px solid ' + RULE,
          display: 'flex', alignItems: 'center', gap: 10,
          color: INK_MUTED, fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase',
        }}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={INK} strokeWidth="1.2">
            <circle cx="7" cy="7" r="5.5" />
            <path d="M1.5 7L12.5 7M7 1.5L7 12.5" />
          </svg>
          <span style={{ color: INK }}>NOTO</span>
          <span>/</span>
          <span>CAPTURES</span>
          <span>/</span>
          <span>11 META</span>
          <span style={{ flex: 1 }} />
          <span style={{ color: INK }}>[ × ]</span>
        </div>

        {/* code-block frontmatter (visibly rendered, not collapsed) */}
        <div style={{
          margin: '14px 20px 0', padding: '10px 12px',
          border: '1px solid ' + RULE,
          color: INK_FAINT, fontSize: 11, lineHeight: 1.6, letterSpacing: 0.2,
        }}>
          <div>---</div>
          <div>source: readwise</div>
          <div>type: article</div>
          <div>tags: [ai, products]</div>
          <div>saved: 2026-05-14</div>
          <div>...</div>
          <div>---</div>
        </div>

        {/* oversized monospace title */}
        <div style={{
          padding: '20px 20px 0',
          color: INK, fontSize: 26, lineHeight: 1.05, letterSpacing: -1, fontWeight: 500,
          textTransform: 'uppercase',
        }}>
          # HOW TO<br />BUILD STRONG<br />AI PRODUCTS
        </div>

        {/* mono dashes divider */}
        <div style={{
          padding: '16px 20px 0', color: RULE, fontSize: 11, overflow: 'hidden', whiteSpace: 'nowrap',
        }}>{'-'.repeat(60)}</div>

        {/* subtitle in serif */}
        <p style={{
          margin: '14px 20px 0', color: INK, fontSize: 15, lineHeight: 1.5,
          fontFamily: SERIF,
        }}>{NOTE.subtitle}</p>

        {/* image — sharp corners, hairline frame, mono label */}
        <div style={{ padding: '16px 20px 0' }}>
          <ExpImage height={150} radius={0} background="#0c0c0c"
            frame={{ border: '1px solid ' + RULE }}
            color={INK_MUTED} label="[ IMG 1200×500 ]" />
        </div>

        {/* body in serif w/ blue links */}
        <p style={{
          margin: '18px 20px 0', color: INK, fontSize: 15, lineHeight: 1.5,
          fontFamily: SERIF,
        }}>
          {renderParts(NOTE.body1,
            { color: LINK, textDecoration: 'underline', textUnderlineOffset: 2, textDecorationColor: LINK, textDecorationThickness: '1px' },
            { fontStyle: 'italic', color: INK_MUTED })}
        </p>

        {/* H2 with mono ## prefix */}
        <div style={{
          margin: '18px 20px 0',
          color: INK, fontSize: 18, fontWeight: 600,
          display: 'flex', alignItems: 'baseline', gap: 8,
          fontFamily: SERIF,
        }}>
          <span style={{ color: INK_MUTED, fontFamily: MONO, fontSize: 14 }}>##</span>
          <span style={{ textTransform: 'uppercase', letterSpacing: -0.3 }}>{NOTE.h2}</span>
        </div>

        {/* brutalist bottom toolbar — square brackets */}
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 0,
          borderTop: '1px solid ' + RULE,
          background: BG,
          padding: '14px 14px 28px',
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          color: INK, fontSize: 12, letterSpacing: 1.2, textTransform: 'uppercase',
        }}>
          <span>[ TODAY ]</span>
          <span>[ SEARCH ]</span>
          <span>[ NEW ]</span>
        </div>

        {/* home indicator */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 0, background: 'rgba(255,255,255,0.30)',
        }} />
      </div>
      <ExpLegend find="[ FIND ] command line" mention="@ inserts [[ link ]]" accent={LINK} />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 05 · NATURAL — Calm. Warm blurred gradient, drop-cap, soft pearl.
// ═════════════════════════════════════════════════════════════
function Exp05Natural() {
  const INK = '#2A1F1A';
  const INK_MUTED = 'rgba(42,31,26,0.55)';
  const INK_FAINT = 'rgba(42,31,26,0.32)';
  const LINK = '#B0716E'; // dusty rose
  const DISPLAY = '"Cormorant Garamond", "EB Garamond", Georgia, serif';
  const BODY = '"EB Garamond", "Cormorant Garamond", Georgia, serif';

  // build the blurred gradient as a stack of soft radials
  const gradient = `
    radial-gradient(120% 60% at 20% 10%, rgba(232,210,190,0.95) 0%, rgba(232,210,190,0) 60%),
    radial-gradient(80% 50% at 80% 30%, rgba(214,196,178,0.9) 0%, rgba(214,196,178,0) 60%),
    radial-gradient(70% 45% at 65% 60%, rgba(208,158,138,0.8) 0%, rgba(208,158,138,0) 60%),
    radial-gradient(80% 50% at 25% 80%, rgba(170,182,160,0.7) 0%, rgba(170,182,160,0) 65%),
    radial-gradient(60% 40% at 80% 95%, rgba(196,178,160,0.85) 0%, rgba(196,178,160,0) 60%),
    linear-gradient(to bottom, #E8DDCE, #D7C8B4)
  `;

  return (
    <div style={{
      width: W_EXP, height: H_EXP, background: '#E5DCC9', position: 'relative',
      fontFamily: BODY, overflow: 'hidden',
    }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden', background: gradient }}>
        {/* invisible chrome: time / single icon */}
        <div style={{
          height: 48, padding: '0 26px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 13, fontWeight: 500, fontFamily: '-apple-system, system-ui',
        }}>
          <span>08:10</span>
          <span>19.08</span>
        </div>
        {/* dynamic island */}
        <div style={{
          position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
          width: 124, height: 36, borderRadius: 22, background: '#000',
        }} />

        {/* top chrome — back + more, almost invisible */}
        <div style={{
          padding: '12px 26px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK_MUTED, fontSize: 14,
        }}>
          <span>←</span>
          <span style={{ fontStyle: 'italic', fontSize: 13 }}>Captures · Noto</span>
          <span>…</span>
        </div>

        {/* large serif title */}
        <div style={{
          padding: '24px 26px 0', color: INK, fontFamily: DISPLAY,
          fontSize: 40, lineHeight: 1.0, letterSpacing: -0.6, fontWeight: 500,
        }}>
          How to Build<br />Strong AI<br />Products
        </div>

        {/* italic greeting line as metadata */}
        <div style={{
          padding: '14px 26px 0', color: INK_MUTED, fontSize: 14, fontStyle: 'italic', fontFamily: BODY,
        }}>saved 2 hours ago · 11 fields</div>

        {/* body w/ drop-cap on first letter */}
        <div style={{ padding: '20px 26px 0' }}>
          {/* subtitle */}
          <p style={{ margin: 0, color: INK, fontSize: 16, lineHeight: 1.5, fontStyle: 'italic' }}>{NOTE.subtitle}</p>

          {/* soft-bloomed image */}
          <div style={{ marginTop: 18, borderRadius: 18, overflow: 'hidden',
            boxShadow: '0 12px 32px rgba(170,120,90,0.25), 0 2px 6px rgba(0,0,0,0.06)',
            transform: 'translateZ(0)',
          }}>
            <ExpImage height={150} radius={18}
              background="linear-gradient(135deg, #C9B5A0, #E2D2BD)"
              color="rgba(60,40,30,0.30)" label="1200 × 500" />
          </div>

          <div style={{ marginTop: 20, fontSize: 16, lineHeight: 1.55, color: INK }}>
            {/* drop-cap */}
            <span style={{
              float: 'left',
              fontFamily: DISPLAY, fontSize: 54, lineHeight: 0.85,
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

          {/* H2 */}
          <div style={{
            marginTop: 22, color: INK, fontFamily: DISPLAY, fontSize: 26, lineHeight: 1.15, fontWeight: 500,
          }}>{NOTE.h2}</div>
        </div>

        {/* soft pearl button at bottom */}
        <div style={{
          position: 'absolute', left: '50%', bottom: 56, transform: 'translateX(-50%)',
          width: 56, height: 56, borderRadius: 28,
          background: 'radial-gradient(circle at 35% 30%, #FFFCF6 0%, #EDE3D2 70%, #D6C8B2 100%)',
          boxShadow: '0 10px 26px rgba(50,30,20,0.20), 0 2px 4px rgba(0,0,0,0.08), inset 0 1px 0 rgba(255,255,255,0.7)',
        }} />

        {/* "access to library" floating hint */}
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 130,
          textAlign: 'center', color: INK_MUTED, fontSize: 13, fontStyle: 'italic', fontFamily: BODY,
        }}>tap pearl · today · search · compose</div>

        {/* home indicator (dark on light) */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(0,0,0,0.30)',
        }} />
      </div>
      <ExpLegend find="long-press pearl" mention="@ blooms inline picker" accent="#D9A89E" />
    </div>
  );
}

Object.assign(window, { Exp03Article, Exp04Techno, Exp05Natural });
