// Noto · Editor explorations — 5 stylistic directions for the iPhone note
// editor. Each rendered at 402 × 920 (874 phone + 46px legend strip).
// All five render the same realistic note so they're directly comparable.

const W_EXP = 402;
const H_PHONE = 874;
const H_LEGEND = 0;
const H_EXP = H_PHONE + H_LEGEND;

// ─────────────────────────────────────────────────────────────
// Shared note content (verbatim from the baseline realistic editor)
// ─────────────────────────────────────────────────────────────
const NOTE = {
  title: 'How to Build Strong AI Products',
  subtitle: 'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.',
  metaCount: 11,
  body1: [
    'The defining question for AI products in 2026 is no longer ',
    { italic: 'can we build it?' },
    ' \u2014 model capability has caught up to ambition. The harder question is ',
    { italic: 'what does this become once people use it every day?' },
    ' As ',
    { link: 'Sahil Lavingia recently argued' },
    ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap. That distinction is doing a lot of work in the market right now.',
  ],
  h2: 'The compounding loop',
  body2: [
    'A compounding product feels different when you open it on day 30 versus day 1. It remembers what you cared about. It surfaces what you forgot. It connects the dots you didn\u2019t have time to. According to ',
    { link: 'Patrick Collison\u2019s essay on agency' },
    ', the products people stick with are the ones that "make you feel slightly smarter every time you return." That feeling is rarely the model \u2014 it\u2019s the accumulated context.',
  ],
  quote: 'The only moat AI startups have left is the one their users are quietly building for them every day, without realizing it.',
};

// Render rich-body parts (string | {italic} | {link}) with a custom link style.
function renderParts(parts, linkStyle, italicStyle) {
  return parts.map((p, i) => {
    if (typeof p === 'string') return <React.Fragment key={i}>{p}</React.Fragment>;
    if (p.italic !== undefined) return <em key={i} style={italicStyle}>{p.italic}</em>;
    if (p.link !== undefined) return <a key={i} href="#" onClick={e => e.preventDefault()} style={linkStyle}>{p.link}</a>;
    return null;
  });
}

// Legend strip removed per design feedback — bottom bars no longer rendered.
function ExpLegend() { return null; }

// Reusable image placeholder for explorations (style-overrideable)
function ExpImage({ height, radius = 10, label = '1200 \u00d7 500', background = '#D6D6D6', color = 'rgba(0,0,0,0.32)', frame, boxShadow, marginTop }) {
  return (
    <div style={{
      width: '100%', height,
      background, borderRadius: radius,
      ...(frame || {}),
      boxShadow,
      marginTop,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color, fontSize: Math.min(54, height * 0.30), fontWeight: 500, letterSpacing: -1,
    }}>{label}</div>
  );
}

// ═════════════════════════════════════════════════════════════
// 01 · MINIMALIST DARK — Dune reader. Low-contrast monk page.
// ═════════════════════════════════════════════════════════════
function Exp01Minimal() {
  const BG = '#000';
  const INK_ANCHOR = 'rgba(255,255,255,0.85)';
  const INK = 'rgba(255,255,255,0.32)';       // body text — very faded
  const INK_HEAD = 'rgba(255,255,255,0.55)';  // headings
  const SYNTAX = 'rgba(255,255,255,0.08)';    // # ## > nearly invisible
  const LINK = 'rgba(180,200,255,0.55)';

  // Body 1 with first letter "T" anchored brighter
  const body1FirstLetter = 'T';
  const body1Rest = NOTE.body1.slice(); body1Rest[0] = (body1Rest[0]).slice(1);

  return (
    <div style={{
      width: W_EXP, height: H_EXP, background: BG, position: 'relative',
      fontFamily: NOTO.font, overflow: 'hidden',
    }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar — bare */}
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

        {/* dynamic island */}
        <div style={{
          position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
          width: 124, height: 36, borderRadius: 22, background: '#000',
        }} />

        {/* top chrome — unstyled text only */}
        <div style={{
          padding: '14px 22px 0', display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
          color: INK_HEAD, fontSize: 12, letterSpacing: 0.3,
        }}>
          <span>← captures</span>
          <span style={{ color: 'rgba(255,255,255,0.18)' }}>•••</span>
        </div>

        {/* title row — "How to Build Strong AI Products — saved 2h" */}
        <div style={{ padding: '22px 22px 0' }}>
          <span style={{ color: INK_ANCHOR, fontWeight: 700, fontSize: 16, letterSpacing: -0.2 }}>How to Build Strong AI Products</span>
          <span style={{ color: 'rgba(255,255,255,0.30)', fontSize: 14, marginLeft: 6 }}>— saved 2h</span>
        </div>

        {/* metadata single line */}
        <div style={{ padding: '6px 22px 0', color: 'rgba(255,255,255,0.22)', fontSize: 12, letterSpacing: 0.3 }}>
          11 fields
        </div>

        {/* body — first letter anchored, rest dim */}
        <div style={{ padding: '24px 22px 0', fontSize: 14, lineHeight: 1.55, color: INK, letterSpacing: 0 }}>
          <p style={{ margin: 0 }}>
            <span style={{ color: INK_HEAD }}>{NOTE.subtitle}</span>
          </p>
          <div style={{ marginTop: 18 }}>
            <ExpImage height={150} radius={2} background="#0a0a0c"
              frame={{ border: '0.5px solid rgba(255,255,255,0.10)' }}
              color="rgba(255,255,255,0.20)" label="1200 × 500" />
          </div>
          <p style={{ margin: '20px 0 0' }}>
            <span style={{ color: INK_ANCHOR, fontWeight: 600 }}>{body1FirstLetter}</span>
            {renderParts(body1Rest,
              { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
              { fontStyle: 'italic', color: INK_HEAD })}
          </p>
          {/* H2 — ## nearly invisible */}
          <div style={{ marginTop: 22, display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <span style={{ color: SYNTAX, fontSize: 15 }}>##</span>
            <span style={{ color: INK_HEAD, fontSize: 15, fontWeight: 600 }}>{NOTE.h2}</span>
          </div>
          <p style={{ margin: '14px 0 0' }}>
            {renderParts(NOTE.body2,
              { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
              { fontStyle: 'italic', color: INK_HEAD })}
          </p>
          {/* blockquote with faint > */}
          <div style={{ marginTop: 22, display: 'flex', gap: 8, color: 'rgba(255,255,255,0.20)', fontStyle: 'italic' }}>
            <span style={{ color: SYNTAX }}>&gt;</span>
            <span>{NOTE.quote}</span>
          </div>
        </div>

        {/* bottom: progress line + two text controls */}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}>
          <div style={{ height: 0.5, background: 'rgba(255,255,255,0.15)', margin: '0 22px' }}>
            <div style={{ width: '38%', height: '100%', background: 'rgba(255,255,255,0.55)' }} />
          </div>
          <div style={{
            display: 'flex', justifyContent: 'space-between', padding: '18px 22px 28px',
            color: 'rgba(255,255,255,0.55)', fontSize: 13, letterSpacing: 0.3,
          }}>
            <span>find</span>
            <span>more</span>
          </div>
        </div>

        {/* home indicator */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.30)',
        }} />
      </div>
      <ExpLegend find="bottom-left tap" mention="inline @ chip" accent="rgba(255,255,255,0.7)" />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 02 · BOOK-LIKE — Gilbert White journal. Warm cream, serif.
// ═════════════════════════════════════════════════════════════
function Exp02Book() {
  const PAGE = '#F2EEE3';
  const INK = '#1A1814';
  const INK_MUTED = '#5B544A';
  const RULE = 'rgba(26,24,20,0.18)';
  const LINK = '#6A4A2A'; // sepia
  const SERIF = '"EB Garamond", "Cormorant Garamond", Georgia, serif';

  const tocItems = [
    ['Mar 12, 2026', 'Compounding products'],
    ['Mar 04, 2026', 'Notes on context'],
    ['Feb 28, 2026', 'Why agency matters'],
  ];

  return (
    <div style={{
      width: W_EXP, height: H_EXP, background: PAGE, position: 'relative',
      fontFamily: SERIF, overflow: 'hidden',
    }}>
      <div style={{ height: H_PHONE, position: 'relative', overflow: 'hidden' }}>
        {/* status bar */}
        <div style={{
          height: 48, padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 14, fontWeight: 600, fontFamily: '-apple-system, system-ui',
        }}>
          <span>6:56</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <svg width="17" height="11" viewBox="0 0 17 11" fill="#1A1814">
              <circle cx="2" cy="9" r="1.1" /><circle cx="6" cy="9" r="1.1" />
              <circle cx="10" cy="9" r="1.1" /><circle cx="14" cy="9" r="1.1" />
            </svg>
            <svg width="17" height="12" viewBox="0 0 17 12" fill="#1A1814">
              <path d="M8.5 2.3c2.7 0 5.1 1 7 2.7l1.3-1.3A11.5 11.5 0 0 0 0 3.6L1.3 5A10 10 0 0 1 8.5 2.3z"/>
              <path d="M8.5 6c1.5 0 2.8.5 3.8 1.4l1.3-1.3A7.5 7.5 0 0 0 3.4 6L4.7 7.4A5.7 5.7 0 0 1 8.5 6z"/>
              <circle cx="8.5" cy="10" r="1.7"/>
            </svg>
            <svg width="28" height="13" viewBox="0 0 28 13">
              <rect x="0.5" y="0.5" width="23" height="12" rx="3" fill="none" stroke="#1A1814" strokeOpacity="0.6" />
              <rect x="2" y="2" width="20" height="9" rx="2" fill="#1A1814" />
              <path d="M25 4v5c.9-.3 1.5-1.2 1.5-2.5S25.9 4.3 25 4z" fill="#1A1814" fillOpacity="0.5" />
            </svg>
          </span>
        </div>
        {/* dynamic island */}
        <div style={{
          position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
          width: 124, height: 36, borderRadius: 22, background: '#000',
        }} />

        {/* header: N monogram + hamburger */}
        <div style={{
          padding: '22px 28px 0',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          color: INK, fontSize: 18, letterSpacing: -0.2,
        }}>
          <span style={{ fontWeight: 500 }}>N.<span style={{ color: INK_MUTED, fontStyle: 'italic' }}>tk</span></span>
          <svg width="24" height="14" viewBox="0 0 24 14" stroke={INK} strokeWidth="1.3" strokeLinecap="round">
            <path d="M2 3h20M2 7h20M2 11h20" />
          </svg>
        </div>

        {/* title */}
        <div style={{ padding: '24px 28px 0', color: INK, fontSize: 32, lineHeight: 1.1, letterSpacing: -0.5 }}>
          How to Build Strong<br />AI Products
        </div>

        {/* meta as journal date line */}
        <div style={{ padding: '14px 28px 0', color: INK_MUTED, fontSize: 14 }}>
          <div>← Go back</div>
          <div style={{ marginTop: 2, fontStyle: 'italic' }}>May 14, 2026 · 11 fields</div>
        </div>

        {/* body */}
        <div style={{ padding: '20px 28px 0', color: INK, fontSize: 16, lineHeight: 1.55 }}>
          <p style={{ margin: 0 }}>{NOTE.subtitle}</p>

          {/* tipped-in plate — double thin border */}
          <div style={{ marginTop: 18, padding: 4, border: '0.5px solid ' + RULE }}>
            <ExpImage height={130} radius={0} background="#C9C2B0"
              frame={{ border: '0.5px solid ' + RULE }}
              color="rgba(0,0,0,0.30)" label="plate i" />
          </div>

          <p style={{ margin: '20px 0 0' }}>
            {renderParts(NOTE.body1,
              { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
              { fontStyle: 'italic' })}
          </p>

          <div style={{
            marginTop: 22, color: INK, fontSize: 22, lineHeight: 1.2,
          }}>{NOTE.h2}</div>
        </div>

        {/* journal index at bottom */}
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 0,
          padding: '12px 28px 22px',
          borderTop: '0.5px solid ' + RULE,
          background: PAGE,
        }}>
          <div style={{ display: 'flex', color: INK_MUTED, fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', paddingBottom: 6 }}>
            <div style={{ width: 110 }}>Date</div>
            <div style={{ flex: 1 }}>Recent</div>
            <div>Search</div>
          </div>
          {tocItems.map(([d, t], i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'baseline', padding: '6px 0',
              borderTop: '0.5px solid ' + RULE,
              fontSize: 14, color: INK,
            }}>
              <div style={{ width: 110, color: INK_MUTED, fontVariantNumeric: 'tabular-nums', fontFamily: SERIF }}>{d}</div>
              <div style={{ flex: 1 }}>{t}</div>
            </div>
          ))}
        </div>

        {/* home indicator (dark on light) */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 3, background: 'rgba(0,0,0,0.30)',
        }} />
      </div>
      <ExpLegend find="hamburger → find" mention="@ opens journal index" accent="#caa97c" />
    </div>
  );
}

Object.assign(window, {
  NOTE, renderParts, ExpImage, ExpLegend,
  Exp01Minimal, Exp02Book,
  W_EXP, H_PHONE, H_LEGEND, H_EXP,
});
