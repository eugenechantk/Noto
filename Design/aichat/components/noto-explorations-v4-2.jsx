// v4 · Reader-aesthetic editor — three of six.
// Same realistic NOTE as v3, editing state (keyboard up + accessory bar).
//
// This file: 04 Particle · 05 NYT · 06 Flipboard
// (See noto-explorations-v4-1.jsx for Reeder · Apple News · informed)

// ═════════════════════════════════════════════════════════════
// 04 · PARTICLE NEWS — dark, AI summaries, structured bullets.
// Restructures the note as an Overview with bullet points + key
// terms in lime. Signature floating "X questions" pill.
// ═════════════════════════════════════════════════════════════
function ExpParticleV4() {
  const BG       = '#0E1014';
  const SURFACE  = '#15181E';
  const INK      = '#D7DAE0';
  const HEAD     = '#F3F5F8';
  const MUTED    = 'rgba(215,218,224,0.58)';
  const FAINT    = 'rgba(215,218,224,0.32)';
  const RULE     = 'rgba(255,255,255,0.07)';
  const ACCENT   = '#B8FF3C';   // Particle lime
  const BULLET   = '#B8FF3C';
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Accessory toolbar — small dark chips with a lime active glyph (link).
  const accessory = (
    <div style={{ background: SURFACE, borderTop: '0.5px solid ' + RULE, padding: '8px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 4 }}>
        {NOTO_TOOLBAR_KEYS.map((k) => {
          const active = k === 'link';
          const color = active ? '#0E1014' : INK;
          const ic = NotoIcons({ stroke: color, size: 16 });
          return (
            <div key={k} style={{
              width: 40, height: 32, borderRadius: 9,
              background: active ? ACCENT : 'rgba(255,255,255,0.06)',
              border: active ? '0.5px solid ' + ACCENT : '0.5px solid rgba(255,255,255,0.06)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ic[k]}</div>
          );
        })}
      </div>
    </div>
  );

  // Bullet row used in the structured overview.
  const Bullet = ({ children }) => (
    <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
      <div style={{ width: 6, height: 6, borderRadius: 3, background: BULLET, marginTop: 7, flexShrink: 0 }} />
      <div style={{ color: INK, fontSize: 13.5, lineHeight: 1.5, fontFamily: SANS }}>{children}</div>
    </div>
  );
  const Key = ({ children }) => (
    <span style={{ color: ACCENT, fontWeight: 600 }}>{children}</span>
  );

  return (
    <V4Scaffold dark={true} background={BG} accessory={accessory} keyboardDark={true}>
      {/* Top: doc breadcrumb + actions */}
      <div style={{
        padding: '6px 18px 12px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          background: 'rgba(255,255,255,0.05)', border: '0.5px solid ' + RULE,
          borderRadius: 999, padding: '5px 12px 5px 8px',
          color: MUTED, fontSize: 12,
        }}>
          <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={MUTED} strokeWidth="1.7" strokeLinecap="round">
            <path d="M7 2L3.5 5.5 7 9" />
          </svg>
          <span style={{ color: HEAD, fontWeight: 600 }}>Captures</span>
          <span style={{ color: FAINT }}>/</span>
          <span>Draft</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: MUTED }}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M19 21l-7-4-7 4V5a2 2 0 012-2h10a2 2 0 012 2z" />
          </svg>
          <svg width="14" height="14" viewBox="0 0 24 24" fill={MUTED}>
            <circle cx="5" cy="12" r="1.6" /><circle cx="12" cy="12" r="1.6" /><circle cx="19" cy="12" r="1.6" />
          </svg>
        </div>
      </div>

      {/* Title with chip */}
      <div style={{ padding: '0 18px' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SANS, fontWeight: 700,
          fontSize: 22, lineHeight: 1.18, letterSpacing: -0.4,
        }}>{NOTE.title}</h1>
        <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
          <span style={{
            color: ACCENT, fontFamily: SANS,
            fontSize: 10, letterSpacing: 0.8, textTransform: 'uppercase', fontWeight: 700,
            background: 'rgba(184,255,60,0.10)',
            border: '0.5px solid rgba(184,255,60,0.40)',
            borderRadius: 999, padding: '3px 8px',
          }}>AI · 11 fields</span>
          <span style={{
            color: MUTED, fontFamily: SANS,
            fontSize: 10, letterSpacing: 0.8, textTransform: 'uppercase',
            background: 'rgba(255,255,255,0.05)',
            border: '0.5px solid ' + RULE,
            borderRadius: 999, padding: '3px 8px',
          }}>Draft · 2h</span>
        </div>
      </div>

      {/* Structured Overview block — Particle's defining pattern */}
      <div style={{ padding: '14px 18px 0' }}>
        <div style={{
          background: SURFACE, border: '0.5px solid ' + RULE,
          borderRadius: 12, padding: '12px 14px 14px',
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
            color: HEAD, fontFamily: SANS, fontWeight: 600, fontSize: 13,
          }}>
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
              <circle cx="7" cy="7" r="6" stroke={ACCENT} strokeWidth="1.4" />
              <circle cx="7" cy="7" r="2" fill={ACCENT} />
            </svg>
            Overview
            <span style={{ flex: 1 }} />
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={MUTED} strokeWidth="1.6" strokeLinecap="round">
              <path d="M3 4l3.5 3.5L10 4" />
            </svg>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <Bullet>The defining question for AI products in 2026 is no longer <Key>can we build it</Key> — model capability has caught up.</Bullet>
            <Bullet>Durable products are those whose value <Key>compounds with the user's data</Key>, not those that depend on a model swap.</Bullet>
            <Bullet>According to <Key>Patrick Collison</Key>, sticky products make you "feel slightly smarter every time you return."</Bullet>
          </div>
        </div>
      </div>

      {/* Floating "questions" pill — Particle's signature affordance */}
      <div style={{ padding: '10px 18px 0', display: 'flex', justifyContent: 'flex-end' }}>
        <div style={{
          background: ACCENT, color: '#0E1014',
          borderRadius: 999, padding: '6px 12px 6px 10px',
          display: 'flex', alignItems: 'center', gap: 6,
          fontFamily: SANS, fontWeight: 700, fontSize: 11, letterSpacing: 0.3,
          boxShadow: '0 6px 16px rgba(184,255,60,0.22)',
        }}>
          <svg width="11" height="11" viewBox="0 0 11 11" fill="#0E1014">
            <circle cx="5.5" cy="5.5" r="5.5" />
          </svg>
          ASK · 4 QUESTIONS
        </div>
      </div>

      {/* H2 + opening paragraph */}
      <div style={{ padding: '14px 18px 0', fontFamily: SANS }}>
        <div style={{
          color: HEAD, fontWeight: 700, fontSize: 15,
          letterSpacing: -0.1, marginBottom: 6,
        }}>{NOTE.h2}</div>
        <p style={{
          margin: 0, color: INK, fontSize: 13.5, lineHeight: 1.55,
        }}>
          {renderParts(
            NOTE.body2.slice(0, 3),
            v4LinkStyle(ACCENT),
            v4ItalicStyle(HEAD),
          )}
        </p>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 05 · NEW YORK TIMES — serif headlines, photo-led, newsprint.
// White paper, condensed serif kicker, big Cheltenham-style
// headline, italic dek, italic byline, photo with caption.
// ═════════════════════════════════════════════════════════════
function ExpNYTV4() {
  const PAGE     = '#F8F6F1';
  const INK      = '#1A1A1A';
  const HEAD     = '#0A0A0A';
  const MUTED    = '#666563';
  const FAINT    = 'rgba(26,26,26,0.32)';
  const RULE     = 'rgba(26,26,26,0.18)';
  const ACCENT   = '#326891';
  const SERIF_HEAD = '"IBM Plex Serif", "Cheltenham", "Georgia", serif';
  const SERIF_BODY = '"IBM Plex Serif", "Georgia", serif';
  const SANS_SM    = '"Helvetica Neue", "Franklin Gothic", "Helvetica", system-ui, sans-serif';

  // Accessory bar — newsprint-style: thin rules between glyphs, serif word count.
  const ic = NotoIcons({ stroke: INK, size: 18 });
  const accessory = (
    <div style={{ padding: '8px 22px 6px', background: PAGE, borderTop: '0.5px solid ' + RULE }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k, i) => (
          <React.Fragment key={k}>
            <div style={{ width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {ic[k]}
            </div>
            {i < NOTO_TOOLBAR_KEYS.length - 1 && (
              <div style={{ width: 0.5, height: 18, background: RULE }} />
            )}
          </React.Fragment>
        ))}
      </div>
      <div style={{
        textAlign: 'right', marginTop: 2,
        fontFamily: SERIF_BODY, fontStyle: 'italic',
        color: MUTED, fontSize: 11,
      }}>258 words</div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Newsprint masthead — small condensed wordmark + section */}
      <div style={{
        padding: '4px 22px 6px',
        borderBottom: '1px solid ' + INK,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SERIF_HEAD,
      }}>
        <div style={{
          color: HEAD, fontWeight: 700, fontSize: 22,
          letterSpacing: -0.2, fontStyle: 'italic',
        }}>Noto</div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          color: MUTED, fontFamily: SANS_SM, fontSize: 10, letterSpacing: 1.2,
          textTransform: 'uppercase', fontWeight: 600,
        }}>
          <span>Sat · May 16, 2026</span>
          <span style={{ color: FAINT }}>|</span>
          <span style={{ color: HEAD }}>Today's Draft</span>
        </div>
      </div>

      {/* Section bar */}
      <div style={{
        padding: '6px 22px 8px',
        borderBottom: '0.5px solid ' + RULE,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS_SM,
        color: MUTED, fontSize: 10, letterSpacing: 1.2, textTransform: 'uppercase',
      }}>
        <span style={{ color: ACCENT, fontWeight: 700 }}>The Field Guide</span>
        <span>11 fields · saved 2h</span>
      </div>

      {/* Big serif headline */}
      <div style={{ padding: '18px 22px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF_HEAD, fontWeight: 700,
          fontSize: 30, lineHeight: 1.08, letterSpacing: -0.4,
          textAlign: 'center',
        }}>{NOTE.title}</h1>
        <p style={{
          margin: '10px 0 0', color: INK,
          fontFamily: SERIF_HEAD, fontStyle: 'italic', fontWeight: 400,
          fontSize: 14.5, lineHeight: 1.4, textAlign: 'center',
        }}>{NOTE.subtitle}</p>
        <div style={{
          margin: '12px 0 0', color: MUTED,
          fontFamily: SANS_SM, fontSize: 11, textAlign: 'center',
          letterSpacing: 0.4,
        }}>
          <span style={{ color: HEAD }}>By </span>
          <span style={{ color: ACCENT, textDecoration: 'underline', textDecorationThickness: '0.5px', textUnderlineOffset: 2 }}>You</span>
          <span style={{ color: MUTED }}> · </span>
          <span style={{ fontStyle: 'italic', fontFamily: SERIF_BODY }}>Field Notes</span>
        </div>
      </div>

      {/* Photo with caption */}
      <div style={{ padding: '14px 22px 0' }}>
        <div style={{
          height: 124, background: '#D3CCBC',
          backgroundImage: 'repeating-linear-gradient(135deg, rgba(0,0,0,0.04) 0 2px, transparent 2px 8px)',
          border: '0.5px solid ' + RULE,
          display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-end',
          color: 'rgba(0,0,0,0.42)', fontFamily: SANS_SM, fontSize: 10, letterSpacing: 0.6, textTransform: 'uppercase',
          padding: 6,
        }}>1200 × 500</div>
        <p style={{
          margin: '6px 0 0', color: MUTED,
          fontFamily: SERIF_BODY, fontSize: 11.5, fontStyle: 'italic', lineHeight: 1.35,
        }}>
          <span style={{ fontWeight: 700, color: HEAD, fontStyle: 'normal' }}>A field guide.</span>{' '}
          Founders compare AI launches at a 2026 product council. <span style={{ color: FAINT }}>Drop photo credit.</span>
        </p>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 06 · FLIPBOARD — Web | Reader View tabs, comment chrome.
// Tabbed reader at top, large headline + image, "Write a comment…"
// strip at the bottom edge of the editor — above the accessory bar.
// Light, with Flipboard red accent.
// ═════════════════════════════════════════════════════════════
function ExpFlipboardV4() {
  const PAGE     = '#FFFFFF';
  const SOFT     = '#F4F4F6';
  const INK      = '#1A1A1A';
  const HEAD     = '#0A0A0A';
  const MUTED    = '#6E6E73';
  const FAINT    = 'rgba(26,26,26,0.36)';
  const RULE     = 'rgba(26,26,26,0.10)';
  const ACCENT   = '#E12828';   // Flipboard red
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
  const SERIF    = '"IBM Plex Serif", "Georgia", serif';

  // Accessory toolbar — pill chips with red active hue, light.
  const ic = NotoIcons({ stroke: INK, size: 17 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '8px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 38, height: 32, borderRadius: 8,
            background: SOFT,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{ic[k]}</div>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Web | Reader View segmented tab */}
      <div style={{
        padding: '4px 18px 10px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        <div style={{
          background: SOFT, borderRadius: 999, padding: 3,
          display: 'flex', alignItems: 'center', gap: 0,
        }}>
          <span style={{
            padding: '5px 14px', borderRadius: 999, fontSize: 12, fontWeight: 600,
            color: MUTED,
          }}>Web</span>
          <span style={{
            padding: '5px 14px', borderRadius: 999, fontSize: 12, fontWeight: 600,
            color: HEAD, background: '#fff',
            boxShadow: '0 1px 3px rgba(0,0,0,0.10)',
          }}>Reader View</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: MUTED }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M19 21l-7-4-7 4V5a2 2 0 012-2h10a2 2 0 012 2z" />
          </svg>
          <svg width="16" height="16" viewBox="0 0 24 24" fill={MUTED}>
            <circle cx="12" cy="5" r="1.6" /><circle cx="12" cy="12" r="1.6" /><circle cx="12" cy="19" r="1.6" />
          </svg>
        </div>
      </div>

      {/* Source row — magazine attribution */}
      <div style={{
        padding: '0 18px 6px',
        display: 'flex', alignItems: 'center', gap: 8,
        fontFamily: SANS, fontSize: 11, color: MUTED, letterSpacing: 0.3,
      }}>
        <div style={{
          width: 18, height: 18, borderRadius: 4,
          background: ACCENT, color: '#fff',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontWeight: 800, fontSize: 11,
        }}>N</div>
        <span style={{ color: HEAD, fontWeight: 600 }}>Field Notes</span>
        <span>·</span>
        <span>5 HOURS AGO</span>
      </div>

      {/* Headline */}
      <div style={{ padding: '6px 18px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 700,
          fontSize: 26, lineHeight: 1.12, letterSpacing: -0.3,
        }}>{NOTE.title}</h1>
        <p style={{
          margin: '10px 0 0', color: INK,
          fontFamily: SANS, fontSize: 14, lineHeight: 1.5,
        }}>{NOTE.subtitle}</p>
      </div>

      {/* Image card */}
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{
          height: 110, borderRadius: 8,
          background: 'linear-gradient(135deg, #d8d8db 0%, #b9b9bf 60%, #cdcdd1 100%)',
          backgroundImage: 'repeating-linear-gradient(45deg, rgba(0,0,0,0.04) 0 2px, transparent 2px 8px)',
          display: 'flex', alignItems: 'flex-end',
          padding: 10,
          color: 'rgba(0,0,0,0.42)', fontFamily: SANS, fontSize: 10, letterSpacing: 0.4,
        }}>1200 × 500</div>
      </div>

      {/* Comment chrome — pinned just above the accessory bar */}
      <div style={{ flex: 1 }} />
      <div style={{
        padding: '8px 14px',
        borderTop: '0.5px solid ' + RULE,
        background: PAGE,
        display: 'flex', alignItems: 'center', gap: 10,
        flexShrink: 0,
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: 14,
          background: 'linear-gradient(135deg, #f5b6b6, #e12828)',
          flexShrink: 0,
          color: '#fff', fontFamily: SANS, fontWeight: 700, fontSize: 12,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>Y</div>
        <div style={{
          flex: 1, height: 30, borderRadius: 15,
          background: SOFT,
          display: 'flex', alignItems: 'center',
          padding: '0 12px',
          color: MUTED, fontFamily: SANS, fontSize: 12,
        }}>Write a comment…</div>
        <button style={{
          height: 28, padding: '0 14px', borderRadius: 14,
          background: ACCENT, color: '#fff', border: 0,
          fontFamily: SANS, fontWeight: 700, fontSize: 11, letterSpacing: 0.6,
          textTransform: 'uppercase',
        }}>Post</button>
      </div>
    </V4Scaffold>
  );
}

Object.assign(window, {
  ExpParticleV4, ExpNYTV4, ExpFlipboardV4,
});
