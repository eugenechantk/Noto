// v5 · Note-taking-app aesthetics — four of eight.
// Same realistic NOTE as v4, editing state (keyboard up + accessory bar).
//
// This file: 05 Clover · 06 Amie · 07 Otter.ai · 08 Notion
// (See noto-explorations-v5-1.jsx for Bear · Evernote · Craft · Apple Notes)

// ═════════════════════════════════════════════════════════════
// 05 · CLOVER — daily-notes-as-calendar. Date strip at top
// drives the active note; date-band header below; first-class
// todo blocks; rich block library hinted in the accessory bar.
// ═════════════════════════════════════════════════════════════
function ExpCloverV5() {
  const PAGE     = '#FAF8F4';
  const INK      = '#2A2722';
  const HEAD     = '#15110D';
  const MUTED    = '#7E7666';
  const FAINT    = 'rgba(42,39,34,0.30)';
  const RULE     = 'rgba(42,39,34,0.10)';
  const ACCENT   = '#2F8F4F';       // clover green
  const SOFT     = '#F2EFE7';
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
  const SERIF    = '"IBM Plex Serif", "Cormorant Garamond", Georgia, serif';

  // Accessory bar — block library hint: thin pill of glyphs, with
  // a small "Insert block" prefix on the left.
  const ic = NotoIcons({ stroke: INK, size: 16 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 12px' }}>
      <div style={{
        background: SOFT, borderRadius: 999, padding: '4px 6px 4px 12px',
        display: 'flex', alignItems: 'center', gap: 4,
      }}>
        <span style={{
          color: MUTED, fontFamily: SANS, fontSize: 10.5, letterSpacing: 0.5,
          textTransform: 'uppercase', fontWeight: 600, marginRight: 4,
        }}>Block</span>
        <div style={{ width: 1, height: 14, background: RULE }} />
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          {NOTO_TOOLBAR_KEYS.map((k) => (
            <div key={k} style={{
              width: 32, height: 26,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ic[k]}</div>
          ))}
        </div>
      </div>
    </div>
  );

  // Calendar strip — Mon..Sun, today highlighted.
  const days = [
    { d: 'M', n: 11 }, { d: 'T', n: 12 }, { d: 'W', n: 13 }, { d: 'T', n: 14 },
    { d: 'F', n: 15 }, { d: 'S', n: 16, today: true }, { d: 'S', n: 17 },
  ];

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Calendar week strip — drives active note */}
      <div style={{
        padding: '4px 12px 10px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        {days.map((dd, i) => (
          <div key={i} style={{
            width: 40, padding: '6px 0',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            borderRadius: 12,
            background: dd.today ? ACCENT : 'transparent',
            color: dd.today ? '#fff' : INK,
          }}>
            <span style={{
              fontSize: 10, letterSpacing: 1,
              color: dd.today ? 'rgba(255,255,255,0.85)' : MUTED,
              textTransform: 'uppercase', fontWeight: 600,
            }}>{dd.d}</span>
            <span style={{ fontSize: 15, fontWeight: dd.today ? 700 : 500 }}>{dd.n}</span>
          </div>
        ))}
      </div>

      {/* Date-band header */}
      <div style={{
        padding: '6px 22px 12px',
        borderBottom: '0.5px solid ' + RULE,
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        <div>
          <div style={{
            color: ACCENT, fontSize: 11, fontWeight: 700, letterSpacing: 1.2,
            textTransform: 'uppercase',
          }}>Saturday</div>
          <div style={{
            color: HEAD, fontFamily: SERIF, fontWeight: 600, fontSize: 24,
            letterSpacing: -0.3, lineHeight: 1.1, marginTop: 2,
          }}>May 16</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: MUTED, fontSize: 12 }}>
          <svg width="13" height="13" viewBox="0 0 13 13" fill={ACCENT}>
            <circle cx="6.5" cy="6.5" r="6.5" />
            <path d="M3.5 6L5.5 8.2 9.5 4.2" stroke="#fff" strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span>2/4 done</span>
        </div>
      </div>

      {/* H1 of the daily note */}
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SERIF, fontWeight: 600,
          fontSize: 22, lineHeight: 1.18, letterSpacing: -0.3,
        }}>{NOTE.title}</h1>
      </div>

      {/* First-class todo blocks */}
      <div style={{ padding: '12px 22px 0', display: 'flex', flexDirection: 'column', gap: 8, fontFamily: SANS }}>
        {[
          { done: true,  text: 'Read Sahil Lavingia\'s essay' },
          { done: true,  text: 'Sketch the compounding loop' },
          { done: false, text: 'Draft "what makes a sticky AI product"', focused: true },
          { done: false, text: 'Field council prep · 3pm' },
        ].map((row, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '6px 8px', borderRadius: 8,
            background: row.focused ? 'rgba(47,143,79,0.08)' : 'transparent',
            border: row.focused ? '0.5px solid rgba(47,143,79,0.30)' : '0.5px solid transparent',
          }}>
            <div style={{
              width: 18, height: 18, borderRadius: 5, flexShrink: 0,
              border: row.done ? 'none' : '1.5px solid ' + MUTED,
              background: row.done ? ACCENT : 'transparent',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {row.done && (
                <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M2.5 6.5L5 9l4.5-5.5" />
                </svg>
              )}
            </div>
            <span style={{
              color: row.done ? MUTED : INK,
              fontSize: 14, lineHeight: 1.4,
              textDecoration: row.done ? 'line-through' : 'none',
              textDecorationColor: MUTED,
            }}>{row.text}</span>
            {row.focused && (
              <span style={{ marginLeft: 'auto', width: 2, height: 16, background: ACCENT, borderRadius: 1 }} />
            )}
          </div>
        ))}
      </div>

      {/* Journal block opener */}
      <div style={{ padding: '14px 22px 0', fontFamily: SERIF, color: INK, fontSize: 14.5, lineHeight: 1.55 }}>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 10.5, letterSpacing: 1, textTransform: 'uppercase', fontWeight: 600, marginBottom: 6 }}>Journal</div>
        <p style={{ margin: 0 }}>
          {renderParts(NOTE.body1.slice(0, 2), v5LinkStyle(ACCENT), v5ItalicStyle(HEAD))}
        </p>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 06 · AMIE — AI note-taker tied to calendar events. Sticky
// event metadata bar pinned above the title. Highlight pill
// on selected text. AI summary action.
// ═════════════════════════════════════════════════════════════
function ExpAmieV5() {
  const PAGE     = '#F7F4FA';
  const SURFACE  = '#FFFFFF';
  const INK      = '#26222C';
  const HEAD     = '#0D0B12';
  const MUTED    = '#7A7387';
  const FAINT    = 'rgba(38,34,44,0.30)';
  const RULE     = 'rgba(38,34,44,0.10)';
  const ACCENT   = '#6B47E5';       // Amie purple
  const HIGHL    = '#FFE89A';       // highlighter yellow
  const HIGHL_T  = '#7A5A00';
  const SANS     = '"Inter", -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Accessory toolbar — purple-tinted, has an extra "✨ AI" leading chip.
  const ic = NotoIcons({ stroke: INK, size: 16 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 10px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <div style={{
          height: 30, borderRadius: 8, background: ACCENT, color: '#fff',
          display: 'flex', alignItems: 'center', gap: 5, padding: '0 10px',
          fontFamily: SANS, fontSize: 11.5, fontWeight: 600, letterSpacing: 0.2,
          flexShrink: 0,
        }}>
          <svg width="11" height="11" viewBox="0 0 12 12" fill="#fff">
            <path d="M6 0l1.4 3.4L11 4.8 8 7l1 4-3-1.8L3 11l1-4-3-2.2 3.6-1.4L6 0z" />
          </svg>
          Summarize
        </div>
        <div style={{ flex: 1, background: SURFACE, borderRadius: 8, border: '0.5px solid ' + RULE, padding: '2px 4px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          {NOTO_TOOLBAR_KEYS.slice(0, 6).map((k) => (
            <div key={k} style={{
              width: 30, height: 26,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ic[k]}</div>
          ))}
        </div>
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Sticky event metadata bar — Amie's signature link to calendar */}
      <div style={{ padding: '4px 14px 8px' }}>
        <div style={{
          background: SURFACE, border: '0.5px solid ' + RULE, borderRadius: 12,
          padding: '10px 12px',
          fontFamily: SANS,
          boxShadow: '0 1px 0 rgba(38,34,44,0.04), 0 4px 12px rgba(38,34,44,0.04)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              width: 4, height: 28, borderRadius: 2, background: ACCENT, flexShrink: 0,
            }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ color: HEAD, fontSize: 13, fontWeight: 600 }}>Field Council</span>
                <span style={{
                  background: 'rgba(107,71,229,0.10)', color: ACCENT,
                  borderRadius: 4, padding: '1px 6px',
                  fontSize: 10, fontWeight: 700, letterSpacing: 0.4,
                }}>NOW</span>
              </div>
              <div style={{ color: MUTED, fontSize: 11.5, marginTop: 2 }}>
                3:00 — 4:00 PM · 4 guests · Note attached
              </div>
            </div>
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke={MUTED} strokeWidth="1.6" strokeLinecap="round">
              <path d="M6 3l4 4-4 5" />
            </svg>
          </div>
        </div>
      </div>

      {/* Title */}
      <div style={{ padding: '6px 22px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SANS, fontWeight: 700,
          fontSize: 22, lineHeight: 1.18, letterSpacing: -0.4,
        }}>{NOTE.title}</h1>
        <p style={{
          margin: '8px 0 0', color: INK,
          fontFamily: SANS, fontSize: 13.5, lineHeight: 1.5,
        }}>{NOTE.subtitle}</p>
      </div>

      {/* Body with a highlighted selection + floating pill */}
      <div style={{ padding: '14px 22px 0', position: 'relative' }}>
        <p style={{
          margin: 0, color: INK,
          fontFamily: SANS, fontSize: 13.5, lineHeight: 1.55,
        }}>
          The defining question for AI products in 2026 is no longer{' '}
          <em style={v5ItalicStyle(HEAD)}>can we build it?</em> — model capability has caught up.{' '}
          <span style={{ background: HIGHL, color: HIGHL_T, padding: '1px 3px', borderRadius: 3, fontWeight: 500 }}>
            Durable products are the ones whose value compounds with the user's data.
          </span>
        </p>

        {/* Highlight-pill affordance — Amie's contextual chip */}
        <div style={{
          marginTop: 10, display: 'flex', justifyContent: 'flex-end',
        }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center',
            background: HEAD, color: '#fff', borderRadius: 999,
            padding: '4px 4px 4px 12px', gap: 6,
            fontFamily: SANS, fontSize: 11.5, fontWeight: 600,
            boxShadow: '0 6px 18px rgba(0,0,0,0.12)',
          }}>
            <svg width="11" height="11" viewBox="0 0 12 12" fill={HIGHL}>
              <rect x="2" y="2" width="8" height="8" rx="1.5" />
            </svg>
            Highlight
            <span style={{ width: 1, height: 14, background: 'rgba(255,255,255,0.20)', margin: '0 2px' }} />
            <div style={{
              background: ACCENT, color: '#fff', borderRadius: 999,
              padding: '3px 9px',
              display: 'flex', alignItems: 'center', gap: 4,
            }}>
              <svg width="9" height="9" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round">
                <path d="M6 2v8M2 6h8" />
              </svg>
              Add to Inbox
            </div>
          </div>
        </div>
      </div>

      {/* AI summary teaser — Amie's "Notetaker" output */}
      <div style={{ padding: '14px 22px 0' }}>
        <div style={{
          background: SURFACE, border: '0.5px solid ' + RULE, borderRadius: 12,
          padding: '10px 12px',
          fontFamily: SANS, fontSize: 12.5,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6,
            color: ACCENT, fontWeight: 700, fontSize: 10.5, letterSpacing: 0.8, textTransform: 'uppercase',
          }}>
            <svg width="11" height="11" viewBox="0 0 12 12" fill={ACCENT}>
              <path d="M6 0l1.4 3.4L11 4.8 8 7l1 4-3-1.8L3 11l1-4-3-2.2 3.6-1.4L6 0z" />
            </svg>
            AI summary · auto
          </div>
          <div style={{ color: INK, lineHeight: 1.45 }}>
            Durable AI products compound with user data; the moat is the accumulated context, not the model.
          </div>
        </div>
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 07 · OTTER.ai — voice transcription. Persistent waveform/mic
// chip in the chrome, speaker-tagged transcript blocks, AI
// action-items extracted from the body.
// ═════════════════════════════════════════════════════════════
function ExpOtterV5() {
  const PAGE     = '#FFFFFF';
  const SOFT     = '#F4F6F8';
  const INK      = '#1B2330';
  const HEAD     = '#0A1220';
  const MUTED    = '#6E7785';
  const FAINT    = 'rgba(27,35,48,0.30)';
  const RULE     = 'rgba(27,35,48,0.10)';
  const ACCENT   = '#1AA0C2';       // Otter teal/blue
  const REC      = '#E0445C';
  const SANS     = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // Accessory toolbar — light pill, recording is the leading chip.
  const ic = NotoIcons({ stroke: INK, size: 16 });
  const accessory = (
    <div style={{ background: PAGE, borderTop: '0.5px solid ' + RULE, padding: '6px 10px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <div style={{
          height: 30, borderRadius: 999, background: REC, color: '#fff',
          display: 'flex', alignItems: 'center', gap: 6, padding: '0 10px',
          fontFamily: SANS, fontSize: 11.5, fontWeight: 700, letterSpacing: 0.3,
          flexShrink: 0,
        }}>
          <span style={{ width: 7, height: 7, borderRadius: 4, background: '#fff' }} />
          REC · 1:42
        </div>
        <div style={{ flex: 1, background: SOFT, borderRadius: 8, padding: '2px 4px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          {NOTO_TOOLBAR_KEYS.slice(0, 6).map((k) => (
            <div key={k} style={{
              width: 30, height: 26,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ic[k]}</div>
          ))}
        </div>
      </div>
    </div>
  );

  // small inline waveform glyph
  const wave = (bars) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 2, height: 16 }}>
      {bars.map((h, i) => (
        <div key={i} style={{
          width: 2, height: h, borderRadius: 1,
          background: ACCENT,
        }} />
      ))}
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Top chrome — Otter signature: back · live waveform/mic · share */}
      <div style={{
        padding: '4px 14px 8px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
        borderBottom: '0.5px solid ' + RULE,
      }}>
        <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={INK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <path d="M14 5l-6 6 6 6" />
        </svg>
        {/* persistent mic chip with live waveform */}
        <div style={{
          background: SOFT, borderRadius: 999,
          padding: '4px 12px 4px 8px',
          display: 'flex', alignItems: 'center', gap: 8,
          border: '0.5px solid ' + RULE,
        }}>
          <div style={{
            width: 22, height: 22, borderRadius: 11, background: ACCENT,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="#fff" strokeWidth="1.4" strokeLinecap="round">
              <rect x="3.5" y="1" width="4" height="6" rx="2" fill="#fff" stroke="none" />
              <path d="M2 5.5a3.5 3.5 0 007 0M5.5 9v1.5" />
            </svg>
          </div>
          {wave([6, 10, 14, 11, 7, 13, 16, 9, 12, 6, 4, 8])}
          <span style={{ color: HEAD, fontSize: 11.5, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>1:42</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, color: MUTED }}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><path d="M16 6l-4-4-4 4"/><path d="M12 2v14"/>
          </svg>
        </div>
      </div>

      {/* Title */}
      <div style={{ padding: '10px 18px 0' }}>
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SANS, fontWeight: 700,
          fontSize: 21, lineHeight: 1.18, letterSpacing: -0.3,
        }}>{NOTE.title}</h1>
        <div style={{ marginTop: 4, color: MUTED, fontSize: 11.5 }}>
          May 16 · 2 speakers · 1m 42s
        </div>
      </div>

      {/* Action items — AI extracted */}
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{
          background: SOFT, border: '0.5px solid ' + RULE, borderRadius: 10,
          padding: '10px 12px',
          fontFamily: SANS, fontSize: 12.5,
        }}>
          <div style={{
            color: ACCENT, fontWeight: 700, fontSize: 10.5, letterSpacing: 0.8, textTransform: 'uppercase',
            marginBottom: 6,
          }}>Action items · AI</div>
          {[
            'Define "compounding loop" for the field guide',
            'Cite Patrick Collison\'s essay on agency',
            'Draft the day-30 vs day-1 example',
          ].map((t, i) => (
            <div key={i} style={{ display: 'flex', gap: 8, color: INK, marginTop: i === 0 ? 0 : 4 }}>
              <span style={{ color: ACCENT, fontWeight: 700 }}>{i + 1}.</span>
              <span>{t}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Speaker-tagged transcript blocks */}
      <div style={{ padding: '14px 18px 0', display: 'flex', flexDirection: 'column', gap: 10, fontFamily: SANS }}>
        {[
          { who: 'You', t: '0:01', body: 'The defining question for AI products in 2026 is no longer can we build it.', color: ACCENT },
          { who: 'You', t: '0:14', body: 'Durable products are the ones whose value compounds with the user\'s data — not the ones whose value depends on a model swap.', color: ACCENT },
        ].map((b, i) => (
          <div key={i} style={{ display: 'flex', gap: 10 }}>
            <div style={{
              width: 24, height: 24, borderRadius: 12, flexShrink: 0,
              background: b.color, color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 10, fontWeight: 700,
            }}>{b.who[0]}</div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                <span style={{ color: HEAD, fontSize: 12, fontWeight: 700 }}>{b.who}</span>
                <span style={{ color: MUTED, fontSize: 10.5, fontVariantNumeric: 'tabular-nums' }}>{b.t}</span>
              </div>
              <p style={{ margin: '2px 0 0', color: INK, fontSize: 13, lineHeight: 1.5 }}>{b.body}</p>
            </div>
          </div>
        ))}
      </div>
    </V4Scaffold>
  );
}

// ═════════════════════════════════════════════════════════════
// 08 · NOTION — slash-command-first editor. Caret in body with
// `/` open, slash-menu floating block-insertion palette above
// the keyboard, callout blocks visible in the rendered body.
// ═════════════════════════════════════════════════════════════
function ExpNotionV5() {
  const PAGE     = '#FFFFFF';
  const SOFT     = '#F7F6F3';
  const INK      = '#2F2F2D';
  const HEAD     = '#191918';
  const MUTED    = '#8C8A85';
  const FAINT    = 'rgba(47,47,45,0.30)';
  const RULE     = 'rgba(47,47,45,0.10)';
  const ACCENT   = '#2E6FDB';
  const CALLOUT_BG = '#F1F1EF';
  const SANS     = '"Inter", -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // The slash-menu replaces a plain accessory — it IS the accessory
  // surface for this exploration. Floating block palette above keyboard.
  const slashItems = [
    { icon: 'T', label: 'Text',     hint: 'Start writing with plain text' },
    { icon: 'H', label: 'Heading 2',hint: 'Medium section heading' },
    { icon: '▤', label: 'Page',     hint: 'Embed a sub-page inside' },
    { icon: '★', label: 'Callout',  hint: 'Make writing stand out',  active: true },
    { icon: '▸', label: 'Toggle',   hint: 'Hide content inside' },
    { icon: '▦', label: 'Database', hint: 'Inline table view' },
  ];
  const accessory = (
    <div style={{ padding: '0 8px 6px', background: 'transparent' }}>
      <div style={{
        background: '#fff', border: '0.5px solid ' + RULE,
        borderRadius: 10, boxShadow: '0 10px 30px rgba(15,15,15,0.16), 0 2px 6px rgba(15,15,15,0.06)',
        overflow: 'hidden',
      }}>
        <div style={{
          padding: '6px 12px',
          color: MUTED, fontFamily: SANS, fontSize: 10.5, letterSpacing: 0.5,
          textTransform: 'uppercase', fontWeight: 600,
          borderBottom: '0.5px solid ' + RULE,
          display: 'flex', alignItems: 'center', gap: 6,
        }}>
          <span>Basic blocks</span>
          <span style={{
            background: SOFT, color: INK, borderRadius: 4,
            padding: '1px 5px', fontSize: 10, textTransform: 'none', letterSpacing: 0,
            fontFamily: '"JetBrains Mono", ui-monospace, Menlo, monospace',
          }}>/cal</span>
        </div>
        <div style={{ maxHeight: 168, overflow: 'hidden' }}>
          {slashItems.map((it, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 10, padding: '6px 12px',
              background: it.active ? SOFT : 'transparent',
              fontFamily: SANS,
            }}>
              <div style={{
                width: 28, height: 28, borderRadius: 5,
                background: '#fff', border: '0.5px solid ' + RULE,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: INK, fontSize: 13, fontWeight: 600,
              }}>{it.icon}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ color: HEAD, fontSize: 13, fontWeight: 500 }}>{it.label}</div>
                <div style={{ color: MUTED, fontSize: 10.5, marginTop: 1 }}>{it.hint}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={PAGE} accessory={accessory} keyboardDark={false}>
      {/* Top chrome — share · comments · ⋯ */}
      <div style={{
        padding: '4px 14px 6px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontFamily: SANS,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: MUTED, fontSize: 12 }}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={MUTED} strokeWidth="1.7" strokeLinecap="round">
            <path d="M9 2L4 7l5 5" />
          </svg>
          <span>Captures</span>
          <span style={{ color: FAINT }}>/</span>
          <span style={{ color: HEAD, fontWeight: 500 }}>Field Guide</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: MUTED }}>
          <span style={{ fontSize: 12, color: HEAD, fontWeight: 600 }}>Share</span>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 11.5a8.5 8.5 0 01-12.5 7.5L3 21l1-5A8.5 8.5 0 1121 11.5z" />
          </svg>
          <svg width="15" height="15" viewBox="0 0 22 22" fill={MUTED}>
            <circle cx="5" cy="11" r="1.5"/><circle cx="11" cy="11" r="1.5"/><circle cx="17" cy="11" r="1.5"/>
          </svg>
        </div>
      </div>

      {/* Title with emoji icon — Notion's page pattern */}
      <div style={{ padding: '8px 22px 0', fontFamily: SANS }}>
        <div style={{ fontSize: 30, marginBottom: 4, lineHeight: 1 }}>📓</div>
        <h1 style={{
          margin: 0, color: HEAD,
          fontWeight: 700, fontSize: 24, lineHeight: 1.18, letterSpacing: -0.4,
        }}>{NOTE.title}</h1>
      </div>

      {/* Callout block — Notion's signature */}
      <div style={{ padding: '12px 22px 0' }}>
        <div style={{
          background: CALLOUT_BG, borderRadius: 6,
          padding: '10px 12px',
          display: 'flex', gap: 10,
          fontFamily: SANS, fontSize: 13.5, lineHeight: 1.5,
        }}>
          <span style={{ fontSize: 16, lineHeight: 1.3, flexShrink: 0 }}>💡</span>
          <span style={{ color: INK }}>
            The harder question is{' '}
            <em style={v5ItalicStyle(HEAD)}>what does this become once people use it every day?</em>
          </span>
        </div>
      </div>

      {/* Body opening with active caret + visible /-trigger */}
      <div style={{ padding: '12px 22px 0', fontFamily: SANS }}>
        <p style={{
          margin: 0, color: INK, fontSize: 14, lineHeight: 1.55,
        }}>
          Durable products are the ones whose value compounds with the user's data — not the ones whose value depends on a model swap.
        </p>
        <div style={{
          marginTop: 8, color: MUTED, fontSize: 14,
          fontFamily: SANS, display: 'flex', alignItems: 'center',
        }}>
          <span style={{ color: HEAD, fontFamily: '"JetBrains Mono", ui-monospace, Menlo, monospace', background: SOFT, borderRadius: 3, padding: '0 4px', fontSize: 12.5 }}>/cal</span>
          <span style={{
            display: 'inline-block', width: 1.5, height: 17,
            background: HEAD, marginLeft: 1,
            animation: 'noto-caret-blink 1s steps(2) infinite',
          }} />
        </div>
        <style>{`@keyframes noto-caret-blink { 50% { opacity: 0; } }`}</style>
      </div>

      {/* Sub-page link block — Notion's nested page chip */}
      <div style={{ padding: '12px 22px 0' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0',
          fontFamily: SANS, fontSize: 13.5, color: HEAD,
        }}>
          <span style={{ fontSize: 14 }}>📄</span>
          <span style={{ textDecoration: 'underline', textDecorationColor: FAINT, textUnderlineOffset: 2 }}>
            Compounding Loop · day-1 vs day-30
          </span>
        </div>
      </div>
    </V4Scaffold>
  );
}

Object.assign(window, {
  ExpCloverV5, ExpAmieV5, ExpOtterV5, ExpNotionV5,
});
