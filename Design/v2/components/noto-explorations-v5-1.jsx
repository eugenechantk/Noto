// v5 · Note-taking-app aesthetics — four of eight.
// Same realistic NOTE as v4, editing state (keyboard up + accessory bar).
// Translates each reference app's note-taking DNA onto Noto's editor —
// chrome conventions, content model, AI affordances. Inspired-by-only.
//
// This file: 01 Bear · 02 Evernote · 03 Craft · 04 Apple Notes
// (See noto-explorations-v5-2.jsx for Clover · Amie · Otter · Notion)
//
// Depends on V4Scaffold, NOTE, renderParts, NotoIcons, NOTO_TOOLBAR_KEYS,
// IOSDevice, IOSKeyboard — all on window.

// Shared inline-style helpers (mirroring v4's v4LinkStyle/v4ItalicStyle).
const v5LinkStyle = (color) => ({
  color, textDecoration: 'none', borderBottom: '0.5px solid ' + color,
});
const v5ItalicStyle = (color) => ({ fontStyle: 'italic', color });

// ═════════════════════════════════════════════════════════════
// 01 · BEAR — minimal markdown writing-first, soft warm typography.
// Cream paper, soft serif H1, #tag chips rendered inline from
// frontmatter. Tag-drawer hamburger on the left, single editor
// toolbar above the keyboard with formatting glyphs (Aa/B/I/H1
// vibe — re-cast onto our 7 Noto keys).
// ═════════════════════════════════════════════════════════════
function ExpBearV5() {
  const PAGE     = '#FBF8F2';
  const INK      = '#3F3A33';
  const HEAD     = '#191613';
  const MUTED    = '#8B847A';
  const FAINT    = 'rgba(63,58,51,0.30)';
  const RULE     = 'rgba(63,58,51,0.10)';
  const ACCENT   = '#D9341E';       // Bear red
  const TAG_BG   = '#FFF1D8';
  const TAG_INK  = '#A35F18';
  const SERIF    = '"IBM Plex Serif", "Charter", "Iowan Old Style", "Cormorant Garamond", Georgia, serif';
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Bear's editor toolbar — a single quiet row of formatting glyphs.
  const ic = NotoIcons({ stroke: INK, size: 17 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 12px 6px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 38, height: 30,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{ic[k]}</div>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Sidebar-as-drawer trigger + thin chrome row */}
      <div style={{
        padding: '4px 18px 8px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, color: ACCENT }}>
          {/* hamburger → tag drawer */}
          <svg width="20" height="14" viewBox="0 0 20 14" fill="none" stroke={ACCENT} strokeWidth="1.8" strokeLinecap="round">
            <path d="M1 2h18M1 7h18M1 12h18" />
          </svg>
          <span style={{ fontSize: 13, color: MUTED }}>#field-guide</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: MUTED }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round">
            <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
          </svg>
          <svg width="15" height="15" viewBox="0 0 24 24" fill={MUTED}>
            <path d="M3 17.5l3.5-1L19 4l-3-3L3.5 13.5 3 17.5z"/>
          </svg>
        </div>
      </div>

      {/* Soft serif H1 */}
      <div style={{ padding: '8px 22px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 600,
          fontSize: 26, lineHeight: 1.15, letterSpacing: -0.3,
        }}>{NOTE.title}</h1>

        {/* Inline #tag chips, rendered from frontmatter */}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}>
          {['#field-guide', '#ai', '#writing/draft', '#2026'].map((t) => (
            <span key={t} style={{
              fontFamily: SANS, fontSize: 11.5, fontWeight: 500,
              background: TAG_BG, color: TAG_INK,
              padding: '3px 9px', borderRadius: 6,
            }}>{t}</span>
          ))}
        </div>
      </div>

      {/* Subtitle */}
      <div style={{ padding: '14px 22px 0' }}>
        <p style={{
          margin: 0, color: INK,
          fontFamily: SERIF, fontStyle: 'italic',
          fontSize: 15, lineHeight: 1.5,
        }}>{NOTE.subtitle}</p>
      </div>

      {/* Body with markdown syntax visible — Bear's writing-first vibe */}
      <div style={{ padding: '18px 22px 0', fontFamily: SERIF, color: INK, fontSize: 15, lineHeight: 1.6 }}>
        <p style={{ margin: 0 }}>
          {renderParts(NOTE.body1.slice(0, 4), v5LinkStyle(ACCENT), v5ItalicStyle(HEAD))}
        </p>
        <div style={{ marginTop: 16, color: FAINT, fontFamily: SANS, fontSize: 11 }}>
          ## <span style={{ color: HEAD, fontFamily: SERIF, fontSize: 16, fontWeight: 600 }}> {NOTE.h2}</span>
        </div>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 02 · EVERNOTE — classic blue, block-aware, multi-content.
// Fat "+" plus-button on the left of the accessory bar is the
// primary affordance for inserting a block. Body shows mixed
// content: text, a sketch block, a tiny table block.
// ═════════════════════════════════════════════════════════════
function ExpEvernoteV5() {
  const PAGE     = '#FFFFFF';
  const SOFT     = '#F7F8FA';
  const INK      = '#2A2D33';
  const HEAD     = '#0F1116';
  const MUTED    = '#6F757E';
  const FAINT    = 'rgba(42,45,51,0.32)';
  const RULE     = 'rgba(42,45,51,0.12)';
  const ACCENT   = '#1F77E0';       // Evernote-ish blue
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Accessory bar — Evernote pattern: large "+" insert-block on the
  // left, then quiet format glyphs. Block insertion is first-class.
  const ic = NotoIcons({ stroke: INK, size: 17 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 10px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <div style={{
          width: 44, height: 32, borderRadius: 9, background: ACCENT,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#fff', flexShrink: 0,
          boxShadow: '0 2px 6px rgba(31,119,224,0.30)',
        }}>
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round">
            <path d="M10 4v12M4 10h12" />
          </svg>
        </div>
        <div style={{ width: 1, height: 24, background: RULE, margin: '0 2px' }} />
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          {NOTO_TOOLBAR_KEYS.slice(0, 6).map((k) => (
            <div key={k} style={{
              width: 34, height: 30,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ic[k]}</div>
          ))}
        </div>
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Top chrome — classic Evernote: back, breadcrumb-as-notebook, share/more */}
      <div style={{
        padding: '4px 14px 10px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS, borderBottom: '0.5px solid ' + RULE,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: ACCENT }}>
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke={ACCENT} strokeWidth="2" strokeLinecap="round">
            <path d="M13 4l-6 6 6 6" />
          </svg>
          <span style={{ fontSize: 14, fontWeight: 500 }}>Field Notes</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, color: MUTED }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><path d="M16 6l-4-4-4 4"/><path d="M12 2v14"/>
          </svg>
          <svg width="16" height="16" viewBox="0 0 24 24" fill={MUTED}>
            <circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>
          </svg>
        </div>
      </div>

      {/* Title */}
      <div style={{ padding: '14px 18px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SANS, fontWeight: 700,
          fontSize: 22, lineHeight: 1.2, letterSpacing: -0.3,
        }}>{NOTE.title}</h1>
        <div style={{
          marginTop: 6, color: MUTED, fontFamily: SANS, fontSize: 11,
          letterSpacing: 0.2,
          display: 'flex', alignItems: 'center', gap: 6,
        }}>
          <span>Saved 2h</span><span>·</span><span>11 fields</span><span>·</span>
          <span style={{ color: ACCENT, fontWeight: 600 }}>Field Notes</span>
        </div>
      </div>

      {/* Text block */}
      <div style={{ padding: '14px 18px 0' }}>
        <p style={{
          margin: 0, color: INK,
          fontFamily: SANS, fontSize: 14, lineHeight: 1.55,
        }}>
          {renderParts(NOTE.body1.slice(0, 3), v5LinkStyle(ACCENT), v5ItalicStyle(HEAD))}
        </p>
      </div>

      {/* Sketch block — Evernote's "drawings in notes" pattern */}
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{
          height: 84, background: SOFT, border: '0.5px solid ' + RULE, borderRadius: 8,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          position: 'relative', overflow: 'hidden',
        }}>
          {/* squiggle */}
          <svg width="180" height="50" viewBox="0 0 180 50" fill="none" stroke={ACCENT} strokeWidth="1.6" strokeLinecap="round">
            <path d="M6 36 Q 20 8 38 26 T 76 30 Q 90 12 110 30 T 156 22 Q 168 14 174 30" />
            <circle cx="36" cy="42" r="2.4" fill={ACCENT} />
            <circle cx="108" cy="20" r="2.4" fill={ACCENT} />
          </svg>
          <span style={{
            position: 'absolute', top: 6, left: 10,
            color: MUTED, fontFamily: SANS, fontSize: 10, letterSpacing: 0.4, textTransform: 'uppercase',
          }}>Sketch · pen</span>
        </div>
      </div>

      {/* Tiny table block — first-class block type */}
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{
          border: '0.5px solid ' + RULE, borderRadius: 8, overflow: 'hidden',
          fontFamily: SANS, fontSize: 12,
        }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', background: SOFT, color: MUTED, fontWeight: 600 }}>
            <div style={{ padding: '6px 10px', borderRight: '0.5px solid ' + RULE }}>Product</div>
            <div style={{ padding: '6px 10px', borderRight: '0.5px solid ' + RULE }}>Compounds?</div>
            <div style={{ padding: '6px 10px' }}>Note</div>
          </div>
          {[
            ['Notion AI', 'Yes', 'Your docs'],
            ['ChatGPT', 'Partial', 'Memory only'],
          ].map((row, i) => (
            <div key={i} style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
              borderTop: '0.5px solid ' + RULE, color: INK,
            }}>
              <div style={{ padding: '6px 10px', borderRight: '0.5px solid ' + RULE }}>{row[0]}</div>
              <div style={{ padding: '6px 10px', borderRight: '0.5px solid ' + RULE }}>{row[1]}</div>
              <div style={{ padding: '6px 10px', color: MUTED }}>{row[2]}</div>
            </div>
          ))}
        </div>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 03 · CRAFT — refined document-feel canvas. Native typography,
// beautiful cover band, chrome row (back/share/comment/⋯).
// Inline page-reference cards. Selection comment widget.
// ═════════════════════════════════════════════════════════════
function ExpCraftV5() {
  const PAGE     = '#FBFAF8';
  const INK      = '#3B3A37';
  const HEAD     = '#111110';
  const MUTED    = '#8A8782';
  const FAINT    = 'rgba(59,58,55,0.30)';
  const RULE     = 'rgba(59,58,55,0.10)';
  const ACCENT   = '#3A6AE0';       // Craft blue
  const HIGHL    = 'rgba(58,106,224,0.16)';
  const SANS     = '"SF Pro Display", -apple-system, BlinkMacSystemFont, "Helvetica Neue", system-ui, sans-serif';
  const SERIF    = '"New York", "IBM Plex Serif", "Charter", Georgia, serif';

  // Accessory toolbar — Craft keeps it minimal & refined.
  const ic = NotoIcons({ stroke: INK, size: 17 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 36, height: 30, borderRadius: 7,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{ic[k]}</div>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Refined chrome — back · share · comment · ⋯ */}
      <div style={{
        padding: '4px 16px 10px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={INK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <path d="M14 5l-6 6 6 6" />
        </svg>
        <div style={{ display: 'flex', alignItems: 'center', gap: 18, color: INK }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><path d="M16 6l-4-4-4 4"/><path d="M12 2v14"/>
          </svg>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 11.5a8 8 0 01-3.5 6.6L21 21l-3.9-1.4A9 9 0 113 11.5C3 6.8 7 3 12 3s9 3.8 9 8.5z"/>
          </svg>
          <svg width="18" height="18" viewBox="0 0 22 22" fill={INK}>
            <circle cx="5" cy="11" r="1.6"/><circle cx="11" cy="11" r="1.6"/><circle cx="17" cy="11" r="1.6"/>
          </svg>
        </div>
      </div>

      {/* Beautiful cover band — Craft's signature */}
      <div style={{
        margin: '0 16px', height: 76, borderRadius: 12,
        background: 'linear-gradient(135deg, #C2D6FF 0%, #B6F0DC 55%, #FFE0B5 100%)',
        position: 'relative', overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          backgroundImage: 'radial-gradient(circle at 80% 30%, rgba(255,255,255,0.55) 0%, transparent 50%), radial-gradient(circle at 20% 80%, rgba(255,255,255,0.35) 0%, transparent 60%)',
        }} />
      </div>

      {/* Title + meta */}
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 600,
          fontSize: 26, lineHeight: 1.12, letterSpacing: -0.4,
        }}>{NOTE.title}</h1>
        <div style={{
          marginTop: 8, color: MUTED, fontFamily: SANS, fontSize: 11.5, letterSpacing: 0.2,
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span>You</span><span>·</span><span>Edited just now</span><span>·</span>
          <span style={{ color: ACCENT }}>Field Guide</span>
        </div>
      </div>

      {/* Body with inline highlighted selection + comment widget */}
      <div style={{ padding: '14px 22px 0', position: 'relative' }}>
        <p style={{
          margin: 0, color: INK,
          fontFamily: SANS, fontSize: 14.5, lineHeight: 1.6,
        }}>
          The defining question for AI products in 2026 is no longer{' '}
          <em style={v5ItalicStyle(HEAD)}>can we build it?</em> — model capability has caught up to ambition. The harder question is{' '}
          <span style={{ background: HIGHL, borderRadius: 3, padding: '0 2px' }}>
            <em style={v5ItalicStyle(HEAD)}>what does this become once people use it every day?</em>
          </span>
        </p>

        {/* Selection comment widget — Craft's contextual pill */}
        <div style={{
          marginTop: 8, alignSelf: 'flex-end',
          display: 'inline-flex', alignItems: 'center', gap: 8,
          background: '#fff', border: '0.5px solid ' + RULE, borderRadius: 12,
          padding: '6px 10px',
          boxShadow: '0 6px 18px rgba(0,0,0,0.06)',
          fontFamily: SANS, fontSize: 12, color: INK,
          float: 'right',
        }}>
          <svg width="13" height="13" viewBox="0 0 22 22" fill="none" stroke={ACCENT} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 11.5a8 8 0 01-3.5 6.6L21 21l-3.9-1.4A9 9 0 113 11.5C3 6.8 7 3 12 3s9 3.8 9 8.5z"/>
          </svg>
          <span style={{ color: ACCENT, fontWeight: 600 }}>Comment</span>
          <span style={{ color: FAINT }}>·</span>
          <span style={{ color: MUTED }}>AI</span>
        </div>
      </div>

      {/* Inline page-reference card — Craft's nested page pattern */}
      <div style={{ padding: '14px 22px 0', clear: 'both' }}>
        <div style={{
          background: '#fff', border: '0.5px solid ' + RULE, borderRadius: 10,
          padding: '10px 12px',
          display: 'flex', alignItems: 'center', gap: 10,
          boxShadow: '0 2px 6px rgba(0,0,0,0.03)',
        }}>
          <div style={{
            width: 28, height: 28, borderRadius: 6,
            background: 'linear-gradient(135deg, #C2D6FF, #B6F0DC)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: HEAD, fontFamily: SERIF, fontWeight: 700, fontSize: 13,
          }}>F</div>
          <div style={{ flex: 1, fontFamily: SANS }}>
            <div style={{ color: HEAD, fontSize: 13, fontWeight: 600 }}>Field Council · meeting notes</div>
            <div style={{ color: MUTED, fontSize: 11, marginTop: 1 }}>2 pages · 3 referenced fields</div>
          </div>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={MUTED} strokeWidth="1.7" strokeLinecap="round">
            <path d="M5 3l3.5 3.5L5 10" />
          </svg>
        </div>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 04 · APPLE NOTES — stock-iOS feel. Bold-first-line pattern
// (the first line IS the title), system fonts, paper yellow
// accent, inline checklist/bulleted toggles, scan/drawing icons.
// ═════════════════════════════════════════════════════════════
function ExpAppleNotesV5() {
  const PAGE     = '#FFFFFF';
  const INK      = '#1C1C1E';
  const HEAD     = '#000000';
  const MUTED    = '#8E8E93';
  const FAINT    = 'rgba(28,28,30,0.30)';
  const RULE     = 'rgba(60,60,67,0.18)';
  const ACCENT   = '#F0B500';       // Notes paper yellow
  const ACCENT_T = '#C68F00';
  const SYS      = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Accessory bar — Apple Notes pattern: Aa formatting · checklist ·
  // camera · scan · pencil markup · share. We re-cast onto Noto's 7 keys.
  const ic = NotoIcons({ stroke: INK, size: 18 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 14px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {NOTO_TOOLBAR_KEYS.map((k) => (
          <div key={k} style={{
            width: 36, height: 32,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{ic[k]}</div>
        ))}
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Stock-iOS top chrome — back to folder + done */}
      <div style={{
        padding: '4px 14px 6px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SYS,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: ACCENT_T }}>
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={ACCENT_T} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M14 5l-6 6 6 6" />
          </svg>
          <span style={{ fontSize: 16, fontWeight: 400 }}>Notes</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, color: ACCENT_T }}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={ACCENT_T} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><path d="M16 6l-4-4-4 4"/><path d="M12 2v14"/>
          </svg>
          <span style={{ fontSize: 15, fontWeight: 600 }}>Done</span>
        </div>
      </div>

      {/* Bold-first-line "title" — there's no separate title field */}
      <div style={{ padding: '10px 20px 0', fontFamily: SYS }}>
        <div style={{
          color: HEAD, fontWeight: 700, fontSize: 22, lineHeight: 1.18, letterSpacing: -0.3,
        }}>{NOTE.title}</div>
        <div style={{
          marginTop: 2, color: MUTED, fontSize: 12,
        }}>May 16, 2026 at 2:10 PM</div>
      </div>

      {/* Subtitle as plain body */}
      <div style={{ padding: '10px 20px 0' }}>
        <p style={{
          margin: 0, color: INK,
          fontFamily: SYS, fontSize: 15, lineHeight: 1.45,
        }}>{NOTE.subtitle}</p>
      </div>

      {/* Checklist block — Apple Notes' inline checkbox toggle */}
      <div style={{ padding: '12px 20px 0', display: 'flex', flexDirection: 'column', gap: 8, fontFamily: SYS }}>
        {[
          { done: true,  text: 'Compounding loop — value grows with user data' },
          { done: true,  text: 'Not a model-swap dependency' },
          { done: false, text: 'Sticky feeling: "slightly smarter each return"' },
          { done: false, text: 'Draft the field guide intro' },
        ].map((row, i) => (
          <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
            <div style={{
              width: 20, height: 20, borderRadius: 10, flexShrink: 0, marginTop: 1,
              border: row.done ? 'none' : '1.5px solid ' + MUTED,
              background: row.done ? ACCENT : 'transparent',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {row.done && (
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M2.5 6.5L5 9l4.5-5.5" />
                </svg>
              )}
            </div>
            <span style={{
              color: row.done ? MUTED : INK,
              fontSize: 14.5, lineHeight: 1.4,
              textDecoration: row.done ? 'line-through' : 'none',
              textDecorationColor: MUTED,
            }}>{row.text}</span>
          </div>
        ))}
      </div>

      {/* Bulleted continuation */}
      <div style={{ padding: '14px 20px 0', fontFamily: SYS, color: INK, fontSize: 14.5, lineHeight: 1.45 }}>
        <div style={{ display: 'flex', gap: 10 }}>
          <span style={{ color: INK }}>•</span>
          <span>According to <span style={{ color: ACCENT_T, textDecoration: 'underline', textDecorationColor: ACCENT, textUnderlineOffset: 2 }}>Patrick Collison</span>, sticky products make you feel slightly smarter each return.</span>
        </div>
      </div>
    </V4Scaffold>
  );
}

Object.assign(window, {
  v5LinkStyle, v5ItalicStyle,
  ExpBearV5, ExpEvernoteV5, ExpCraftV5, ExpAppleNotesV5,
});
