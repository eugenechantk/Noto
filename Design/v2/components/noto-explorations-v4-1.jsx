// v4 · Reader-aesthetic editor — three of six.
// Same realistic NOTE as v3, editing state (keyboard up + accessory bar).
// Each direction reimagines Noto's editor through the lens of a different
// news-reader app. Inspired-by-only — original chrome, original layout.
//
// This file: 01 Reeder · 02 Apple News · 03 informed News
// (See noto-explorations-v4-2.jsx for Particle · NYT · Flipboard)

// ─────────────────────────────────────────────────────────────
// Shared helper — render the NOTE.body1 array with custom styles
// (NOTE, renderParts come from noto-explorations-1.jsx on window)
// ─────────────────────────────────────────────────────────────

// Tiny inline link/italic style spreaders so each direction reads cleanly.
const v4LinkStyle = (color) => ({
  color, textDecoration: 'none', borderBottom: '0.5px solid ' + color,
});
const v4ItalicStyle = (color) => ({ fontStyle: 'italic', color });

// Generic vertical scaffold — status reserve, scrollable body, accessory, keyboard.
function V4Scaffold({ dark = true, background, statusReserve = 62, children, accessory, keyboardDark }) {
  return (
    <IOSDevice dark={dark} background={background}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        <div style={{ height: statusReserve, flexShrink: 0 }} />
        <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          {children}
        </div>
        {accessory}
        <IOSKeyboard dark={keyboardDark ?? dark} />
      </div>
    </IOSDevice>
  );
}

// ═════════════════════════════════════════════════════════════
// 01 · REEDER — quiet, typographic, dark-default reader.
// Charcoal canvas, slab-serif title, plenty of margin, no chrome
// noise. Inspired by Reeder 5's reading view.
// ═════════════════════════════════════════════════════════════
function ExpReederV4() {
  const BG       = '#1B1B1F';
  const SURFACE  = '#1B1B1F';
  const INK      = '#D7D5D0';
  const HEAD     = '#F2EFE8';
  const MUTED    = 'rgba(215,213,208,0.55)';
  const FAINT    = 'rgba(215,213,208,0.30)';
  const RULE     = 'rgba(255,255,255,0.07)';
  const ACCENT   = '#C7A36B';
  const SERIF    = '"IBM Plex Serif", "Charter", "Iowan Old Style", "Cormorant Garamond", Georgia, serif';
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Reeder accessory toolbar — single thin pill, no labels, dim glyphs.
  const ic = NotoIcons({ stroke: 'rgba(215,213,208,0.62)', size: 17 });
  const accessory = (
    <div style={{ padding: '6px 14px 6px', background: SURFACE, borderTop: '0.5px solid ' + RULE }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        {NOTO_TOOLBAR_KEYS.map((k, i) => (
          <React.Fragment key={k}>
            <div style={{ width: 38, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {ic[k]}
            </div>
            {i < NOTO_TOOLBAR_KEYS.length - 1 && (
              <span style={{ width: 0.5, height: 14, background: RULE }} />
            )}
          </React.Fragment>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={true} background={BG} accessory={accessory} keyboardDark={true}>
      {/* Quiet header — feed name + small actions, Reeder-style */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 18px 10px',
        fontFamily: SANS,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, color: MUTED, fontSize: 13 }}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={MUTED} strokeWidth="1.7" strokeLinecap="round">
            <path d="M9 2.5L4 7l5 4.5" />
          </svg>
          <span>Captures</span>
          <span style={{ color: FAINT }}>·</span>
          <span style={{ color: FAINT }}>2,348 unread</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: MUTED }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M19 21l-7-4-7 4V5a2 2 0 012-2h10a2 2 0 012 2z" />
          </svg>
          <svg width="15" height="15" viewBox="0 0 24 24" fill={MUTED}>
            <circle cx="5" cy="12" r="1.5" /><circle cx="12" cy="12" r="1.5" /><circle cx="19" cy="12" r="1.5" />
          </svg>
        </div>
      </div>

      {/* Article header */}
      <div style={{ padding: '8px 22px 0' }}>
        <div style={{
          color: ACCENT, fontFamily: SANS,
          fontSize: 11, letterSpacing: 1.6, textTransform: 'uppercase', fontWeight: 600,
          marginBottom: 10,
        }}>
          Field Notes · Draft
        </div>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 600,
          fontSize: 30, lineHeight: 1.08, letterSpacing: -0.4,
        }}>{NOTE.title}</h1>
        <div style={{
          marginTop: 14, color: MUTED, fontFamily: SANS,
          fontSize: 12, letterSpacing: 0.3,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <span>You · 11 fields</span>
          <span style={{ width: 14, height: 0.5, background: FAINT }} />
          <span>1 min read</span>
          <span style={{ width: 14, height: 0.5, background: FAINT }} />
          <span>saved 2h</span>
        </div>
      </div>

      {/* Subtitle + opening paragraph, Reeder reading rhythm */}
      <div style={{ padding: '18px 22px 0', fontFamily: SERIF, color: INK, fontSize: 16.5, lineHeight: 1.62 }}>
        <p style={{ margin: 0, color: HEAD, fontStyle: 'italic', fontSize: 17 }}>
          {NOTE.subtitle}
        </p>
        <div style={{
          margin: '18px 0 0',
          height: 0.5, background: RULE,
        }} />
        <p style={{ margin: '18px 0 0' }}>
          {renderParts(
            NOTE.body1,
            v4LinkStyle(ACCENT),
            v4ItalicStyle(HEAD),
          )}
        </p>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 02 · APPLE NEWS — editorial masthead, big imagery, magazine.
// "NOTO" wordmark top band, oversized bold headline, hero image,
// AA-style top-right actions. Pure black canvas in dark mode.
// ═════════════════════════════════════════════════════════════
function ExpAppleNewsV4() {
  const BG       = '#000000';
  const SURFACE  = '#0A0A0B';
  const INK      = '#E7E7EA';
  const HEAD     = '#FFFFFF';
  const MUTED    = 'rgba(231,231,234,0.62)';
  const FAINT    = 'rgba(231,231,234,0.35)';
  const RULE     = 'rgba(255,255,255,0.10)';
  const ACCENT   = '#FA2D48';  // News red
  const SANS     = '"SF Pro Display", -apple-system, BlinkMacSystemFont, "Helvetica Neue", system-ui, sans-serif';
  const SERIF    = '"New York", "Charter", "Iowan Old Style", Georgia, serif';

  // Accessory bar — Apple News–style action strip: AA · share · like · dislike · save · back · fwd
  // but with our 7 Noto keys. Sits inside a soft solid surface band.
  const ic = NotoIcons({ stroke: INK, size: 18 });
  const accessory = (
    <div style={{
      background: SURFACE, borderTop: '0.5px solid ' + RULE,
      padding: '10px 18px 10px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 36, height: 36, borderRadius: 18,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{ic[k]}</div>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={true} background={BG} accessory={accessory} keyboardDark={true}>
      {/* "NOTO" masthead band — Apple News logo-strip vibe */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 18px 10px',
        borderBottom: '0.5px solid ' + RULE,
        fontFamily: SANS,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <svg width="22" height="22" viewBox="0 0 24 24">
            <rect x="2" y="2" width="20" height="20" rx="4.5" fill={ACCENT} />
            <path d="M7 17V7l10 10V7" stroke="#fff" strokeWidth="2.2" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span style={{ color: HEAD, fontWeight: 800, fontSize: 18, letterSpacing: -0.2 }}>NOTO</span>
          <span style={{ color: ACCENT, fontWeight: 700, fontSize: 11, letterSpacing: 1.2 }}>+ DRAFT</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, color: MUTED }}>
          <span style={{ fontSize: 11, letterSpacing: 0.4 }}>AA</span>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M18 8a3 3 0 100-6 3 3 0 000 6zM6 15a3 3 0 100-6 3 3 0 000 6zM18 22a3 3 0 100-6 3 3 0 000 6z" />
            <path d="M8.6 13.5l6.8 4M15.4 6.5L8.6 10.5" />
          </svg>
        </div>
      </div>

      {/* Section kicker */}
      <div style={{
        padding: '14px 20px 0', fontFamily: SANS,
        color: ACCENT, fontWeight: 800, fontSize: 11, letterSpacing: 1.4, textTransform: 'uppercase',
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <span>Notebook</span>
        <span style={{ color: FAINT }}>›</span>
        <span style={{ color: MUTED }}>Field Guide</span>
      </div>

      {/* Oversized editorial headline */}
      <div style={{ padding: '6px 20px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 800,
          fontSize: 30, lineHeight: 1.05, letterSpacing: -0.6,
        }}>{NOTE.title}</h1>
        <p style={{
          margin: '12px 0 0', color: INK,
          fontFamily: SERIF, fontStyle: 'italic',
          fontSize: 15.5, lineHeight: 1.45,
        }}>{NOTE.subtitle}</p>
      </div>

      {/* Hero image — full bleed magazine photo placeholder */}
      <div style={{
        margin: '16px 0 0', height: 132,
        background: 'linear-gradient(120deg, #2a2628 0%, #3a3236 60%, #1c1a1c 100%)',
        position: 'relative',
        display: 'flex', alignItems: 'flex-end',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          backgroundImage: 'repeating-linear-gradient(45deg, rgba(255,255,255,0.025) 0 2px, transparent 2px 8px)',
        }} />
        <div style={{
          position: 'relative', padding: '8px 20px', width: '100%',
          color: FAINT, fontFamily: SANS, fontSize: 10, letterSpacing: 0.8,
          textTransform: 'uppercase',
          display: 'flex', justifyContent: 'space-between',
        }}>
          <span>Photograph · 2400 × 1000</span>
          <span>Credit: drop image</span>
        </div>
      </div>

      {/* Byline + body */}
      <div style={{ padding: '12px 20px 0', fontFamily: SANS }}>
        <div style={{
          color: MUTED, fontSize: 12, letterSpacing: 0.2,
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span style={{ color: HEAD, fontWeight: 600 }}>By You</span>
          <span>·</span>
          <span>11 fields</span>
          <span>·</span>
          <span>Saved 2h ago</span>
        </div>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 03 · INFORMED NEWS — soft pastel chrome, friendly headers.
// Lavender masthead band, warm cream canvas, friendly serif
// title, light-mode keyboard.
// ═════════════════════════════════════════════════════════════
function ExpInformedV4() {
  const PAGE     = '#F6F2EC';
  const BAND     = '#C8C0E6';     // pastel lavender
  const BAND_INK = '#2A2547';
  const INK      = '#1F1B1A';
  const HEAD     = '#0F0C0B';
  const MUTED    = '#6B665D';
  const FAINT    = 'rgba(31,27,26,0.32)';
  const RULE     = 'rgba(31,27,26,0.12)';
  const ACCENT   = '#7558D6';     // informed purple
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
  const SERIF    = '"IBM Plex Serif", "Cormorant Garamond", Georgia, serif';

  // Accessory toolbar — friendly soft pastel pill, rounded chips
  const ic = NotoIcons({ stroke: BAND_INK, size: 17 });
  const accessory = (
    <div style={{ padding: '8px 12px', background: PAGE, borderTop: '0.5px solid ' + RULE }}>
      <div style={{
        background: BAND, borderRadius: 16, padding: '6px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        boxShadow: '0 2px 8px rgba(43,32,99,0.10)',
      }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 38, height: 32, borderRadius: 12,
            background: 'rgba(255,255,255,0.55)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{ic[k]}</div>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Pastel masthead band — informed News's signature soft top bar */}
      <div style={{
        background: BAND, padding: '10px 18px 12px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
        borderBottom: '0.5px solid rgba(43,32,99,0.12)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <svg width="24" height="24" viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="11" fill="#fff" />
            <path d="M8 6l8 6-8 6V6z" fill={ACCENT} />
          </svg>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ color: BAND_INK, fontWeight: 700, fontSize: 14, letterSpacing: -0.1 }}>Today's draft</span>
            <span style={{ color: 'rgba(42,37,71,0.62)', fontSize: 11, marginTop: 1 }}>Listen · 1m · saved 2h</span>
          </div>
        </div>
        <div style={{
          background: '#fff', borderRadius: 14, padding: '6px 10px',
          display: 'flex', alignItems: 'center', gap: 6,
          color: BAND_INK, fontSize: 11, fontWeight: 600,
        }}>
          <svg width="11" height="11" viewBox="0 0 11 11" fill={ACCENT}>
            <path d="M3 1.5v8L9 5.5z" />
          </svg>
          Play
        </div>
      </div>

      {/* Friendly title */}
      <div style={{ padding: '20px 22px 0' }}>
        <div style={{
          color: ACCENT, fontFamily: SANS, fontSize: 11, fontWeight: 700,
          letterSpacing: 1.2, textTransform: 'uppercase',
          marginBottom: 8,
        }}>Field Guide</div>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 600,
          fontSize: 26, lineHeight: 1.12, letterSpacing: -0.3,
        }}>{NOTE.title}</h1>
        <p style={{
          margin: '12px 0 0', color: INK,
          fontFamily: SANS, fontSize: 14, lineHeight: 1.5,
        }}>{NOTE.subtitle}</p>
      </div>

      {/* Soft summary card — friendly chrome touch */}
      <div style={{ padding: '14px 22px 0' }}>
        <div style={{
          background: '#fff', border: '0.5px solid ' + RULE, borderRadius: 14,
          padding: '12px 14px',
          fontFamily: SANS,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8,
            color: ACCENT, fontWeight: 700, fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase',
          }}>
            <svg width="12" height="12" viewBox="0 0 24 24" fill={ACCENT}>
              <path d="M12 2l2.6 6.3L21 9l-5 4.4 1.5 6.6L12 16.8 6.5 20 8 13.4 3 9l6.4-.7L12 2z" />
            </svg>
            <span>Key takeaway</span>
          </div>
          <p style={{ margin: 0, color: INK, fontSize: 13.5, lineHeight: 1.5 }}>
            Durable AI products compound with the user's data — the value lives in the accumulated context, not the model swap.
          </p>
        </div>
      </div>

      {/* Body opening */}
      <div style={{ padding: '14px 22px 0' }}>
        <p style={{
          margin: 0, color: INK,
          fontFamily: SERIF, fontSize: 15, lineHeight: 1.55,
        }}>
          {renderParts(
            NOTE.body1.slice(0, 5),
            v4LinkStyle(ACCENT),
            v4ItalicStyle(HEAD),
          )}
        </p>
      </div>
    </V4Scaffold>
  );
}

Object.assign(window, {
  v4LinkStyle, v4ItalicStyle, V4Scaffold,
  ExpReederV4, ExpAppleNewsV4, ExpInformedV4,
});
