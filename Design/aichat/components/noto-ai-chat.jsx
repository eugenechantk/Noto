// noto-ai-chat.jsx
// ─────────────────────────────────────────────────────────────
// AI Chat — iOS-only. A LARGE-DETENT sheet (grabber + rounded top) over a
// dimmed presenter that peeks at the top with its status bar. Two triggers:
//   • the floating dock's chat icon (over the file list / home)
//   • a note's editor ••• menu → "Chat about this note"
// No back chevron — dismiss by swiping down. The sheet top bar carries the
// chat name (or "New chat") + a ••• menu (New chat · Chat history · Attach
// files · Rename chat · Delete chat).
//
// Two distinct reference systems:
//   • USER MENTIONS — notes the user references in a message. While composing
//     they appear as small tags ABOVE the text field; once sent they're listed
//     as a faint doc-glyph list BELOW that user's bubble. Notes are picked via
//     the Add context sheet (browse folder-by-folder, or search a flat list
//     across all levels; every row shows its vault path breadcrumb).
//   • AI CITATIONS — faint footnote superscripts after cited claims + a quiet
//     "SOURCES" group under the AI reply.
//
// Reuses the established system: dark #0E1116, SF-Pro, orange #FF6A2E,
// IOSDevice / IOSKeyboard / IOSSheet, the glass dock, the vault row style,
// the circular ✕/✓ sheet header.
//
//   NotoAIChat({ state }) — states:
//     'trigger-home' · 'trigger-note' · 'new' · 'compose' · 'convo' ·
//     'convo-multi' · 'menu' · 'history' · 'thinking' · 'attach-browse' ·
//     'attach-search'

(function () {
  const BG     = '#0E1116';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.62)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF6A2E';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';
  const MONO   = '"SF Mono", ui-monospace, "JetBrains Mono", monospace';

  const glassStyle = {
    background: 'rgba(28,30,36,0.55)',
    backdropFilter: 'blur(28px) saturate(180%)',
    WebkitBackdropFilter: 'blur(28px) saturate(180%)',
    border: '0.5px solid rgba(255,255,255,0.10)',
    boxShadow: [
      '0 1px 1px rgba(0,0,0,0.18)', '0 8px 24px rgba(0,0,0,0.32)',
      'inset 0 0.5px 0 rgba(255,255,255,0.22)', 'inset 0 -0.5px 0 rgba(0,0,0,0.25)',
    ].join(', '),
  };

  // ─── glyphs (outline, 1.6–1.8 stroke, consistent set) ───────────────────
  function CIcon({ name, size = 22, color = HEAD, sw = 1.7 }) {
    const c = { fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
    let b = null;
    switch (name) {
      case 'chat':    b = <path d="M4 6a2 2 0 012-2h12a2 2 0 012 2v7a2 2 0 01-2 2h-7.5l-4 3v-3H6a2 2 0 01-2-2V6z" {...c} />; break;
      case 'send':    b = <path d="M12 19V5M6 11l6-6 6 6" {...c} />; break;
      case 'plus':    b = <path d="M12 5.5v13M5.5 12h13" {...c} />; break;
      case 'doc':     b = <><path d="M7 3.5h6.5L18 8v12a1 1 0 01-1 1H7a1 1 0 01-1-1V4.5a1 1 0 011-1z" {...c} /><path d="M13 3.5V8h4.5" {...c} /></>; break;
      case 'x':       b = <path d="M6 6l12 12M18 6L6 18" {...c} />; break;
      case 'calendar':b = <><rect x="3.5" y="4.5" width="17" height="16" rx="2.4" {...c} /><path d="M3.5 9h17M8 2.6v3.6M16 2.6v3.6" {...c} /></>; break;
      case 'search':  b = <><circle cx="10.5" cy="10.5" r="6.5" {...c} /><path d="M20 20l-4.5-4.5" {...c} /></>; break;
      case 'compose': b = <><path d="M19 12.5V19a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h6.5" {...c} /><path d="M17 3.5l3.5 3.5L12 15.5H8.5V12L17 3.5z" {...c} /></>; break;
      case 'clock':   b = <><circle cx="12" cy="12" r="8" {...c} /><path d="M12 7.5V12l3 2" {...c} /></>; break;
      case 'clip':    b = <path d="M16.5 7.5l-7 7a2.4 2.4 0 003.4 3.4l7.2-7.2a4.4 4.4 0 00-6.2-6.2L6.6 11.6a6.4 6.4 0 009 9L20 16" {...c} />; break;
      case 'pencil':  b = <><path d="M4 20l1-4L16 5l3 3L8 19l-4 1z" {...c} /><path d="M14 7l3 3" {...c} /></>; break;
      case 'trash':   b = <path d="M4.5 6.5h15M9 6.5V5a1.5 1.5 0 011.5-1.5h3A1.5 1.5 0 0115 5v1.5M6.5 6.5l.8 12A1.5 1.5 0 008.8 20h6.4a1.5 1.5 0 001.5-1.4l.8-12.1" {...c} />; break;
      case 'share':   b = <><path d="M12 15V4M8 7l4-4 4 4" {...c} /><path d="M6 11H5a1.5 1.5 0 00-1.5 1.5V19A1.5 1.5 0 005 20.5h14A1.5 1.5 0 0020.5 19v-6.5A1.5 1.5 0 0019 11h-1" {...c} /></>; break;
      case 'pin':     b = <><path d="M9 3.5h6l-.7 5.2 2.7 3.1H7l2.7-3.1L9 3.5z" {...c} /><path d="M12 11.8V20.5" {...c} /></>; break;
      default: b = null;
    }
    return <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block', flexShrink: 0 }}>{b}</svg>;
  }

  const Sparkle = ({ size = 13, color = ACCENT }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block', flexShrink: 0 }}>
      <path d="M12 3.5l1.6 5.3 5.3 1.6-5.3 1.6L12 17.3l-1.6-5.3L5.1 10.4l5.3-1.6z" fill={color} />
    </svg>
  );

  function SheetCircleBtn({ kind = 'close', size = 32 }) {
    const isConfirm = kind === 'confirm';
    const stroke = isConfirm ? '#FFFFFF' : 'rgba(235,235,245,0.65)';
    return (
      <div style={{
        width: size, height: size, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: isConfirm ? ACCENT : 'rgba(118,118,128,0.30)',
        backdropFilter: isConfirm ? 'none' : 'blur(20px) saturate(160%)', WebkitBackdropFilter: isConfirm ? 'none' : 'blur(20px) saturate(160%)',
        boxShadow: isConfirm ? '0 1px 3px rgba(0,0,0,0.25), inset 0 0.5px 0 rgba(255,255,255,0.35)' : 'inset 0 0.5px 0 rgba(255,255,255,0.14)',
        cursor: 'pointer',
      }}>
        <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 20 20" fill="none" stroke={stroke} strokeWidth={isConfirm ? 2.4 : 2.2} strokeLinecap="round" strokeLinejoin="round">
          {isConfirm ? <path d="M4 10.5l4 4 8-9" /> : <path d="M5 5l10 10M15 5L5 15" />}
        </svg>
      </div>
    );
  }

  const StatusSpacer = () => <div style={{ height: 62, flexShrink: 0 }} />;

  // ─── floating dock — daily · search · chat · new. `trigger` rings the chat
  //     icon to mark it as the tappable entry point. ────────────────────────
  const Dock = ({ active, trigger = false }) => {
    const isChat = active === 'chat' || trigger;
    return (
      <div style={{ flexShrink: 0, padding: '6px 12px 34px', display: 'flex', alignItems: 'center', gap: 8 }}>
        <div style={{ ...glassStyle, height: 52, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center', flexShrink: 0 }}>
          <div style={{ width: 44, height: 44, borderRadius: 999, position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <CIcon name="calendar" color={HEAD} size={22} sw={1.6} />
            <span style={{ position: 'absolute', left: 0, right: 0, top: 21, textAlign: 'center', color: HEAD, fontFamily: SANS, fontSize: 8, fontWeight: 700 }}>7</span>
          </div>
        </div>
        <div style={{ ...glassStyle, flex: 1, height: 52, borderRadius: 999, padding: '0 18px', gap: 10, display: 'flex', alignItems: 'center' }}>
          <CIcon name="search" color={MUTED} size={19} sw={1.7} />
          <span style={{ color: MUTED, fontFamily: SANS, fontSize: 16, flex: 1 }}>Search</span>
        </div>
        <div style={{ ...glassStyle, height: 52, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center', flexShrink: 0 }}>
          <div style={{
            width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: isChat ? 'rgba(255,106,46,0.22)' : 'transparent',
            border: trigger ? '1px solid rgba(255,106,46,0.65)' : (isChat ? '0.5px solid rgba(255,106,46,0.42)' : '0.5px solid transparent'),
            boxShadow: trigger ? '0 0 0 4px rgba(255,106,46,0.16)' : 'none',
          }}>
            <CIcon name="chat" color={isChat ? ACCENT : HEAD} size={21} sw={1.6} />
          </div>
          <div style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.10)' }} />
          <div style={{ width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <CIcon name="compose" color={HEAD} size={21} sw={1.7} />
          </div>
        </div>
      </div>
    );
  };

  // ─── user turn — light pill; mentioned notes listed faintly BELOW it ─────
  const UserPill = ({ children, mentions = null }) => (
    <div style={{ margin: '0 0 22px' }}>
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <div style={{ maxWidth: '78%', background: 'rgba(255,255,255,0.09)', color: INK, fontFamily: SANS, fontSize: 16, lineHeight: 1.45, letterSpacing: -0.1, padding: '10px 14px', borderRadius: 18, borderBottomRightRadius: 6, border: '0.5px solid rgba(255,255,255,0.07)' }}>{children}</div>
      </div>
      {mentions && mentions.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 5, marginTop: 8 }}>
          {mentions.map((m, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 6, maxWidth: '82%' }}>
              <CIcon name="doc" color="rgba(236,236,238,0.40)" size={13} sw={1.6} />
              <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12.5, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{m}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  // ─── AI citations — footnote superscript + quiet SOURCES group ──────────
  const Cite = ({ n }) => (
    <sup style={{ fontFamily: SANS, fontSize: 9.5, fontWeight: 600, color: 'rgba(255,106,46,0.72)', verticalAlign: 'super', lineHeight: 0, marginLeft: 1.5 }}>{n}</sup>
  );
  const Sources = ({ items }) => (
    <div style={{ marginTop: 18, paddingTop: 12, borderTop: '0.5px solid ' + RULE }}>
      <div style={{ color: FAINT, fontFamily: SANS, fontSize: 11, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase', marginBottom: 7 }}>Sources</div>
      {items.map((it, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 0', cursor: 'pointer' }}>
          <span style={{ color: 'rgba(255,106,46,0.72)', fontFamily: SANS, fontSize: 11.5, fontWeight: 600, width: 11, flexShrink: 0, fontVariantNumeric: 'tabular-nums' }}>{i + 1}</span>
          <CIcon name="doc" color="rgba(236,236,238,0.42)" size={14} sw={1.6} />
          <span style={{ flex: 1, minWidth: 0, color: MUTED, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{it}</span>
        </div>
      ))}
    </div>
  );

  const aiPara = { margin: '12px 0 0', fontFamily: SANS, fontSize: 16, lineHeight: 1.55, color: INK, letterSpacing: -0.1 };
  const aiH2   = { margin: '0', fontFamily: SANS, fontSize: 19, fontWeight: 700, color: HEAD, letterSpacing: -0.3, lineHeight: 1.2 };
  const Code = ({ children }) => (
    <code style={{ fontFamily: MONO, fontSize: 13.5, color: '#FFC9A8', background: 'rgba(255,106,46,0.12)', border: '0.5px solid rgba(255,106,46,0.20)', borderRadius: 5, padding: '1px 5px' }}>{children}</code>
  );
  const B = ({ children }) => <strong style={{ color: HEAD, fontWeight: 600 }}>{children}</strong>;
  const I = ({ children }) => <em style={{ fontStyle: 'italic', color: MUTED }}>{children}</em>;
  const AIEyebrow = () => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 12 }}>
      <Sparkle size={13} />
      <span style={{ color: FAINT, fontFamily: SANS, fontSize: 11.5, fontWeight: 600, letterSpacing: 0.3, textTransform: 'uppercase' }}>Noto</span>
    </div>
  );
  const AIList = ({ items }) => (
    <ul style={{ margin: '10px 0 0', paddingLeft: 22, fontFamily: SANS, fontSize: 16, lineHeight: 1.5, color: INK, letterSpacing: -0.1 }}>
      {items.map((it, i) => <li key={i} style={{ margin: '0 0 7px', paddingLeft: 4 }}>{it}</li>)}
    </ul>
  );
  const AIReplySingle = () => (
    <div style={{ margin: '0 0 8px' }}>
      <AIEyebrow />
      <h2 style={aiH2}>The three deposits</h2>
      <p style={aiPara}>Every session should leave something behind the next one can build on. In <I>How to Build Strong AI Products</I> you frame three:<Cite n={1} /></p>
      <AIList items={[
        <><B>Memory</B> — what the product remembers about you and your work.</>,
        <><B>Preference</B> — your corrections, encoded once.</>,
        <><B>Taste</B> — the rough shape of what you call “good.”</>,
      ]} />
      <p style={aiPara}>They compound because each is additive across sessions — track the effect with a single <Code>day_30_retention</Code> cohort rather than raw usage.<Cite n={1} /></p>
      <Sources items={['How to Build Strong AI Products']} />
    </div>
  );
  const AIReplyMulti = () => (
    <div style={{ margin: '0 0 8px' }}>
      <AIEyebrow />
      <h2 style={aiH2}>Where they overlap</h2>
      <p style={aiPara}>All three circle the same idea: small, repeated deposits beat occasional big pushes.</p>
      <AIList items={[
        <><B>How to Build Strong AI Products</B> — memory, preference and taste accrue per session.<Cite n={1} /></>,
        <><B>Compounding deposits</B> — value is additive; the curve bends late.<Cite n={2} /></>,
        <><B>Dan Koe — the 1-day reset</B> — one focused day re-seeds the habit loop.<Cite n={3} /></>,
      ]} />
      <p style={aiPara}>The shared mechanic is a tight feedback loop you can express as <Code>delta = signal − noise</Code> and protect week to week.</p>
      <Sources items={['How to Build Strong AI Products', 'Compounding deposits', 'Dan Koe — the 1-day reset']} />
    </div>
  );

  // ─── tool trace — note-native, monochrome, no boxes. A left-ruled list of
  //     collapsible tool-step rows (grep ⌕ search · read ▢ doc · list ▦ folder)
  //     under the ✶ NOTO eyebrow, above the answer. Collapsed = the call;
  //     expanded = the result in a faint indented block. ──────────────────────
  const traceRule = { borderLeft: '1.5px solid rgba(255,255,255,0.12)', paddingLeft: 14, marginLeft: 3 };
  const ToolGlyphMap = { grep: 'search', read: 'doc', list: 'folder' };
  const ToolSpinner = () => <span className="noto-tool-spin" style={{ width: 13, height: 13, borderRadius: 999, border: '1.5px solid rgba(236,236,238,0.22)', borderTopColor: 'rgba(236,236,238,0.72)', display: 'inline-block', flexShrink: 0 }} />;
  const ToolCheck = () => <svg width="13" height="13" viewBox="0 0 20 20" fill="none" stroke="rgba(236,236,238,0.5)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M4 10.5l4 4 8-9" /></svg>;
  const ToolChevron = ({ open }) => <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke={FAINT} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, transform: open ? 'rotate(90deg)' : 'none' }}><path d="M9 6l6 6-6 6" /></svg>;
  const ToolStep = ({ tool, action, target, meta, status, open, children }) => (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 0', cursor: 'pointer' }}>
        <CIcon name={ToolGlyphMap[tool]} color="rgba(236,236,238,0.45)" size={15} sw={1.7} />
        <span style={{ flex: 1, minWidth: 0, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', color: MUTED }}>
          {action}{target ? ' ' : ''}<span style={{ color: INK }}>{target}</span>{meta ? <span style={{ color: FAINT }}> · {meta}</span> : null}
        </span>
        {status === 'active' ? <ToolSpinner /> : status === 'check' ? <ToolCheck /> : <ToolChevron open={open} />}
      </div>
      {open && children && <div style={{ margin: '0 0 9px 24px' }}>{children}</div>}
    </div>
  );
  const GrepMatch = ({ note, line }) => (
    <div style={{ fontFamily: SANS, fontSize: 12.5, lineHeight: 1.45, letterSpacing: -0.05, marginBottom: 5 }}>
      <span style={{ color: MUTED }}>{note}</span><span style={{ color: 'rgba(236,236,238,0.28)' }}> › </span><span style={{ color: FAINT }}>{line}</span>
    </div>
  );

  // an inline tool block — one (or a few) step(s) grouped by the left rule,
  // placed BETWEEN text blocks so the trace interleaves with the answer.
  const ToolBlock = ({ children }) => (
    <div style={{ borderLeft: '1.5px solid rgba(255,255,255,0.12)', paddingLeft: 14, margin: '12px 0 12px 3px' }}>{children}</div>
  );

  // WORKING — text streams and tool steps appear inline, chronologically;
  // finished steps carry a check, the active step a spinner, dots at the edge.
  const ToolReplyWorking = () => (
    <div style={{ margin: '0 0 8px' }}>
      <AIEyebrow />
      <ToolBlock>
        <ToolStep tool="grep" action="Searched" target="‘pricing’" meta="4 notes" status="check" />
      </ToolBlock>
      <p style={{ ...aiPara, marginTop: 0 }}>You settled the Q1 floor at <Code>$29</Code> — down from the <Code>$39</Code> champion price.</p>
      <ToolBlock>
        <ToolStep tool="read" action="Read" target="Pricing experiments" status="check" />
      </ToolBlock>
      <p style={aiPara}>The March cohort test held conversion within 3% of baseline, so the lower floor stuck.</p>
      <ToolBlock>
        <ToolStep tool="read" action="Reading" target="Q2 pricing model" status="active" />
      </ToolBlock>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, margin: '11px 0 0 3px' }}>
        <span className="noto-ai-dot" /><span className="noto-ai-dot" style={{ animationDelay: '0.18s' }} /><span className="noto-ai-dot" style={{ animationDelay: '0.36s' }} />
      </div>
    </div>
  );

  // DONE — the finished turn: tool steps interspersed where they occurred in
  // the response (default), each collapsible; one expanded to show its result.
  // "Worked across 4 notes" stays as an optional collapse-all control.
  const ToolReplyDone = () => (
    <div style={{ margin: '0 0 8px' }}>
      <AIEyebrow />
      {/* optional collapse-all control (default: steps shown inline) */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 2, cursor: 'pointer' }}>
        <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12.5, letterSpacing: -0.1 }}>Worked across 4 notes</span>
        <ToolChevron open={true} />
      </div>
      <ToolBlock>
        <ToolStep tool="grep" action="Searched" target="‘pricing’" meta="4 notes" status="chevron" open={true}>
          <GrepMatch note="Pricing experiments" line="…moved the Q1 floor to $29 after the March cohort test…" />
          <GrepMatch note="Q2 pricing model" line="…annual discount capped at two months…" />
          <GrepMatch note="Pricing experiments · Q1" line="…champion price held at $39…" />
        </ToolStep>
      </ToolBlock>
      <h2 style={{ ...aiH2, marginTop: 4 }}>Where you landed on Q1</h2>
      <p style={aiPara}>You settled the floor at <Code>$29</Code> — down from the <Code>$39</Code> champion price.<Cite n={1} /></p>
      <ToolBlock>
        <ToolStep tool="read" action="Read" target="Pricing experiments" status="chevron" />
      </ToolBlock>
      <p style={{ ...aiPara, marginTop: 0 }}>The March cohort test held conversion within 3% of the baseline, so the lower floor stuck rather than denting revenue.<Cite n={1} /></p>
      <ToolBlock>
        <ToolStep tool="list" action="Listed" target="Projects › Alpha" status="chevron" />
      </ToolBlock>
      <p style={{ ...aiPara, marginTop: 0 }}>One caveat: the Q2 model in that folder still assumes <Code>$39</Code>, so it needs reconciling before launch.<Cite n={2} /></p>
      <Sources items={['Pricing experiments', 'Q2 pricing model']} />
    </div>
  );

  // ─── composer mention tag (above the text field while composing) ────────
  const MentionTag = ({ name }) => (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 27, padding: '0 6px 0 9px', borderRadius: 8, background: 'rgba(255,255,255,0.07)', border: '0.5px solid rgba(255,255,255,0.12)', maxWidth: 220 }}>
      <CIcon name="doc" color={FAINT} size={13} sw={1.6} />
      <span style={{ color: INK, fontFamily: SANS, fontSize: 12.5, fontWeight: 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</span>
      <span style={{ display: 'inline-flex', cursor: 'pointer' }}><CIcon name="x" color={MUTED} size={10} sw={2} /></span>
    </div>
  );

  // ─── bottom input bar — optional mention tags above the field ───────────
  const InputBar = ({ keyboard = false, value, placeholder = 'Ask anything…', bottomPad, mentions = null }) => {
    const pb = bottomPad != null ? bottomPad : (keyboard ? 10 : 30);
    return (
      <div style={{ flexShrink: 0, padding: `8px 12px ${pb}px` }}>
        {mentions && mentions.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, margin: '0 2px 8px' }}>
            {mentions.map((m, i) => <MentionTag key={i} name={m} />)}
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, minHeight: 48, borderRadius: 26, padding: '5px 5px 5px 6px', background: 'rgba(255,255,255,0.06)', border: '0.5px solid rgba(255,255,255,0.12)' }}>
          <div style={{ width: 38, height: 38, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, background: 'rgba(255,255,255,0.06)' }}>
            <CIcon name="plus" color={MUTED} size={20} sw={1.8} />
          </div>
          <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', fontFamily: SANS, fontSize: 16, letterSpacing: -0.1 }}>
            {value ? (
              <span style={{ color: INK }}>{value}<span style={{ display: 'inline-block', width: 2, height: 19, background: ACCENT, marginLeft: 1, verticalAlign: 'middle', borderRadius: 1 }} /></span>
            ) : (
              <span style={{ color: FAINT }}>{placeholder}</span>
            )}
          </div>
          <div style={{ width: 38, height: 38, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, background: ACCENT, boxShadow: '0 1px 3px rgba(0,0,0,0.25), inset 0 0.5px 0 rgba(255,255,255,0.35)' }}>
            <CIcon name="send" color="#FFFFFF" size={20} sw={2} />
          </div>
        </div>
      </div>
    );
  };

  // ════════════════════════════════════════════════════════════
  // Presenting views (no device frame) — peek dimmed behind the sheet
  // ════════════════════════════════════════════════════════════
  const BehindFileRow = ({ name, when, active, last }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 20px', borderBottom: last ? 'none' : '0.5px solid ' + RULE, background: active ? 'rgba(255,106,46,0.10)' : 'transparent' }}>
      <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke={active ? ACCENT : MUTED} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M4 1.5h5l3 3V13a1 1 0 01-1 1H4a1 1 0 01-1-1V2.5a1 1 0 011-1z" /><path d="M9 1.5v3h3" /></svg>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: active ? HEAD : INK, fontFamily: SANS, fontSize: 15.5, fontWeight: active ? 600 : 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12.5, marginTop: 2 }}>Edited {when}</div>
      </div>
    </div>
  );
  const FileListBody = ({ trigger = false }) => (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: BG, fontFamily: SANS }}>
      <StatusSpacer />
      <div style={{ flexShrink: 0, height: 48, padding: '0 16px', display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 18 }}>
        <CIcon name="search" color={HEAD} size={20} sw={1.7} />
        <CIcon name="compose" color={HEAD} size={20} sw={1.7} />
      </div>
      <div style={{ padding: '2px 20px 10px' }}>
        <div style={{ color: HEAD, fontFamily: SANS, fontSize: 28, fontWeight: 700, letterSpacing: -0.5 }}>Captures</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 13, marginTop: 3 }}>1 folder · 4 notes</div>
      </div>
      <div style={{ height: 0.5, background: RULE }} />
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
        <BehindFileRow name="How to Build Strong AI Products" when="2h ago" active />
        <BehindFileRow name="Dan Koe — the 1-day reset" when="2d ago" />
        <BehindFileRow name="What is my definition of a “great” life" when="3d ago" />
        <BehindFileRow name="Why Vertical LLM Agents Are The New Moat" when="4d ago" last />
      </div>
      <Dock active={trigger ? null : 'chat'} trigger={trigger} />
    </div>
  );
  const EditorBody = ({ dock = false }) => {
    const para = { margin: '14px 0 0', fontFamily: SANS, fontSize: 16, lineHeight: 1.55, color: INK, letterSpacing: -0.1 };
    const h2 = { margin: '20px 0 6px', fontFamily: SANS, fontSize: 18, fontWeight: 700, color: HEAD, letterSpacing: -0.2 };
    return (
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: BG, fontFamily: SANS }}>
        <StatusSpacer />
        <div style={{ flexShrink: 0, height: 48, padding: '0 10px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <ArticleIcon name="back" color={HEAD} size={22} />
          <ArticleIcon name="more" color={HEAD} size={22} />
        </div>
        <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '6px 24px 0' }}>
          <div style={{ color: HEAD, fontFamily: SANS, fontSize: 25, fontWeight: 700, lineHeight: 1.16, letterSpacing: -0.4 }}>How to Build Strong AI Products</div>
          <p style={{ ...para, marginTop: 12 }}>A field guide for founders shipping AI features in 2026 — what makes a product compound, and what makes it flame out after launch week.</p>
          <div style={{ marginTop: 14, height: 84, borderRadius: 12, background: 'linear-gradient(135deg, #FF6A2E 0%, #C2185B 55%, #4A148C 100%)', border: '0.5px solid rgba(255,255,255,0.08)', position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.22), transparent 60%)' }} />
          </div>
          <h2 style={h2}>The three deposits</h2>
          <p style={para}>Every interaction should leave behind a deposit: memory, preference, and taste.</p>
        </div>
        {dock && (
          <>
            <div style={{ flexShrink: 0, height: 28, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', marginBottom: -28 }} />
            <Dock trigger={true} />
          </>
        )}
      </div>
    );
  };
  const Behind = ({ kind }) => (
    <div style={{ position: 'absolute', inset: 0, borderRadius: 40, overflow: 'hidden', background: BG, transform: 'scale(0.93) translateY(-10px)', transformOrigin: 'top center' }}>
      {kind === 'editor' ? <EditorBody /> : <FileListBody />}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.5)' }} />
    </div>
  );

  // ─── the chat sheet shell — grabber · title · ••• (no back chevron) ─────
  const ChatSheet = ({ title = 'New chat', children, keyboard = false, input = true, placeholder = 'Ask anything…', menuActive = false, dim = false, mentions = null }) => (
    <div style={{
      position: 'absolute', left: 0, right: 0, top: 64, bottom: 0,
      borderTopLeftRadius: 40, borderTopRightRadius: 40, background: BG, overflow: 'hidden',
      display: 'flex', flexDirection: 'column',
      boxShadow: '0 -1px 0 rgba(255,255,255,0.06), 0 -24px 60px rgba(0,0,0,0.55)',
    }}>
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 7, flexShrink: 0 }}>
        <div style={{ width: 36, height: 5, borderRadius: 100, background: 'rgba(235,235,245,0.3)' }} />
      </div>
      <div style={{ position: 'relative', flexShrink: 0, height: 50, display: 'flex', alignItems: 'center', padding: '0 12px' }}>
        <div style={{ position: 'absolute', left: 0, right: 0, textAlign: 'center', pointerEvents: 'none' }}>
          <span style={{ color: HEAD, fontFamily: SANS, fontSize: 17, fontWeight: 600, letterSpacing: -0.3 }}>{title}</span>
        </div>
        <div style={{ marginLeft: 'auto', width: 34, height: 34, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', background: menuActive ? 'rgba(255,255,255,0.10)' : 'transparent' }}>
          <ArticleIcon name="more" color={HEAD} size={22} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '4px 22px 0', position: 'relative' }}>
        {children}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 30, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', pointerEvents: 'none' }} />
      </div>
      {input && <InputBar keyboard={keyboard} placeholder={placeholder} mentions={mentions} bottomPad={keyboard ? 10 : 30} />}
      {keyboard && <IOSKeyboard dark={true} />}
      {dim && <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.42)' }} />}
    </div>
  );

  // ─── menus ──────────────────────────────────────────────────────────────
  const MenuItem = ({ icon, label, danger, accent, last }) => {
    const color = accent ? ACCENT : danger ? '#FF5247' : INK;
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, height: 46, padding: '0 16px', background: accent ? 'rgba(255,106,46,0.14)' : 'transparent', borderBottom: last ? 'none' : '0.5px solid rgba(255,255,255,0.07)' }}>
        <span style={{ flex: 1, color, fontFamily: SANS, fontSize: 15.5, fontWeight: accent ? 600 : 500, letterSpacing: -0.2 }}>{label}</span>
        <CIcon name={icon} color={color} size={19} sw={1.7} />
      </div>
    );
  };
  const FloatMenu = ({ top, children }) => (
    <div style={{ position: 'absolute', top, right: 14, width: 244, zIndex: 50, borderRadius: 14, overflow: 'hidden', background: 'rgba(40,42,48,0.86)', backdropFilter: 'blur(30px) saturate(180%)', WebkitBackdropFilter: 'blur(30px) saturate(180%)', border: '0.5px solid rgba(255,255,255,0.12)', boxShadow: '0 18px 50px rgba(0,0,0,0.55), inset 0 0.5px 0 rgba(255,255,255,0.10)' }}>{children}</div>
  );

  // ════════════════════════════════════════════════════════════
  // Past-chats rows (Chat history sheet)
  // ════════════════════════════════════════════════════════════
  const CHATS = [
    { title: 'Strong AI products — retention', snippet: 'The three deposits compound because each is additive…', when: '2h' },
    { title: 'Where my notes overlap on habits', snippet: 'All three circle the same idea: small repeated deposits…', when: 'Tue' },
    { title: 'Pricing experiments · open questions', snippet: 'You still haven’t decided the Q1 floor — three notes touch…', when: 'Mar 4' },
    { title: 'Weekly review synthesis', snippet: 'Pulled the themes from this week’s captures into five…', when: 'Mar 2' },
    { title: 'What is a “great” life — for me', snippet: 'Drawing on the Dan Koe reset and your definition note…', when: 'Feb 24' },
  ];
  const ChatRow = ({ c, last }) => (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 13, padding: '13px 20px', borderBottom: last ? 'none' : '0.5px solid ' + RULE }}>
      <div style={{ paddingTop: 1, flexShrink: 0 }}><CIcon name="chat" color="rgba(236,236,238,0.55)" size={20} sw={1.6} /></div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
          <div style={{ flex: 1, minWidth: 0, color: HEAD, fontFamily: SANS, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.title}</div>
          <div style={{ color: FAINT, fontFamily: SANS, fontSize: 12.5, flexShrink: 0, fontVariantNumeric: 'tabular-nums' }}>{c.when}</div>
        </div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 13.5, marginTop: 2, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.snippet}</div>
      </div>
    </div>
  );

  // ════════════════════════════════════════════════════════════
  // Vault file picker (Add context) — browse + search, nested paths
  // ════════════════════════════════════════════════════════════
  const folderGlyph = (color) => (
    <svg width="20" height="20" viewBox="0 0 18 18" fill={color} stroke="none"><path d="M2 5a1.6 1.6 0 011.6-1.6h2.9c.55 0 1.06.28 1.36.74l.5.76c.3.46.8.74 1.36.74h4.7A1.6 1.6 0 0116 7v6A1.6 1.6 0 0114.4 14.6H3.6A1.6 1.6 0 012 13V5z" /></svg>
  );
  const fileGlyph = (color) => (
    <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><path d="M4 1.5h5l3 3V13a1 1 0 01-1 1H4a1 1 0 01-1-1V2.5a1 1 0 011-1z" /><path d="M9 1.5v3h3" /></svg>
  );
  const SelectCheck = ({ on }) => (
    on ? (
      <div style={{ width: 22, height: 22, borderRadius: 999, background: ACCENT, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.35)' }}>
        <svg width="13" height="13" viewBox="0 0 20 20" fill="none" stroke="#FFFFFF" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M4 10.5l4 4 8-9" /></svg>
      </div>
    ) : <div style={{ width: 22, height: 22, borderRadius: 999, border: '1.5px solid rgba(236,236,238,0.30)', flexShrink: 0 }} />
  );
  const PickerSearch = ({ query }) => (
    <div style={{ padding: '4px 16px 10px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 38, padding: '0 12px', borderRadius: 10, background: 'rgba(118,118,128,0.20)' }}>
        <CIcon name="search" color={FAINT} size={16} sw={1.7} />
        <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', color: query ? INK : FAINT, fontFamily: SANS, fontSize: 15 }}>
          {query || 'Search notes'}
          {query && <span style={{ display: 'inline-block', width: 2, height: 18, background: ACCENT, marginLeft: 1, borderRadius: 1 }} />}
        </div>
      </div>
    </div>
  );
  const PickerFolderRow = ({ name, count }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 20px', borderBottom: '0.5px solid ' + RULE }}>
      <span style={{ flexShrink: 0, display: 'inline-flex' }}>{folderGlyph('rgba(236,236,238,0.80)')}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: HEAD, fontFamily: SANS, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12.5, marginTop: 2 }}>{count} items</div>
      </div>
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke={FAINT} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M6 3l5 5-5 5" /></svg>
    </div>
  );
  // file row with a faint vault-PATH breadcrumb subtitle (identifies nested notes)
  const PickerFileRow = ({ name, path, on, last }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 20px', borderBottom: last ? 'none' : '0.5px solid ' + RULE, background: on ? 'rgba(255,106,46,0.08)' : 'transparent' }}>
      <span style={{ flexShrink: 0, display: 'inline-flex' }}>{fileGlyph(on ? ACCENT : MUTED)}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: on ? HEAD : INK, fontFamily: SANS, fontSize: 15.5, fontWeight: on ? 600 : 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 3 }}>
          <svg width="12" height="12" viewBox="0 0 18 18" fill="none" stroke="rgba(236,236,238,0.34)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M2 5.2a1.4 1.4 0 011.4-1.4h2.4c.4 0 .8.2 1.05.55l.45.6c.25.34.65.55 1.05.55H14.6A1.4 1.4 0 0116 6.9V13a1.4 1.4 0 01-1.4 1.4H3.4A1.4 1.4 0 012 13V5.2z" /></svg>
          <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12, letterSpacing: -0.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{path}</span>
        </div>
      </div>
      <SelectCheck on={on} />
    </div>
  );

  // ════════════════════════════════════════════════════════════
  // SCREENS
  // ════════════════════════════════════════════════════════════
  const Scene = ({ kind = 'files', children }) => (
    <IOSDevice dark={true} background="#000">
      <div style={{ height: '100%', position: 'relative', fontFamily: SANS }}>
        <Behind kind={kind} />
        {children}
      </div>
    </IOSDevice>
  );

  // 01 · TRIGGER — Home: file list + dock, the chat icon is the entry point
  function TriggerHome() {
    return (
      <IOSDevice dark={true} background={BG}>
        <div style={{ height: '100%', position: 'relative', fontFamily: SANS }}>
          <FileListBody trigger={true} />
        </div>
      </IOSDevice>
    );
  }

  // 02 · TRIGGER — Note: the editor carries the floating dock; its chat icon
  //      is the trigger (ringed + callout). Tapping starts a chat with the
  //      current note pre-attached as context. (Chat is no longer in the
  //      ••• menu, which is just Share · Pin Note · Find in Note · Delete.)
  function TriggerNote() {
    return (
      <IOSDevice dark={true} background={BG}>
        <div style={{ height: '100%', position: 'relative', fontFamily: SANS }}>
          <EditorBody dock={true} />
          {/* callout marking the dock chat icon as the tappable trigger */}
          <div style={{ position: 'absolute', right: 50, bottom: 96, zIndex: 20, display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '7px 12px', borderRadius: 999, background: ACCENT, boxShadow: '0 8px 22px rgba(0,0,0,0.5)' }}>
              <CIcon name="chat" color="#FFFFFF" size={15} sw={1.8} />
              <span style={{ color: '#FFFFFF', fontFamily: SANS, fontSize: 13, fontWeight: 600, letterSpacing: -0.1 }}>Chat about this note</span>
            </div>
            <svg width="16" height="8" viewBox="0 0 16 8" style={{ marginTop: -0.5, marginRight: 24 }}><path d="M0 0h16L8 8z" fill={ACCENT} /></svg>
          </div>
        </div>
      </IOSDevice>
    );
  }

  // 03 · NEW CHAT — simplified empty state (heading + composer)
  function ScreenNew() {
    return (
      <Scene kind="files">
        <ChatSheet title="New chat" keyboard={true} placeholder="Ask anything…">
          <div style={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ color: HEAD, fontFamily: SANS, fontSize: 23, fontWeight: 700, letterSpacing: -0.4 }}>Chat about notes</div>
          </div>
        </ChatSheet>
      </Scene>
    );
  }

  // 04 · COMPOSING — note mention tag above the field (over the editor)
  function ScreenCompose() {
    return (
      <Scene kind="editor">
        <ChatSheet title="New chat" keyboard={true} placeholder="" mentions={['How to Build Strong AI Products']}>
          <div style={{ height: '100%' }} />
        </ChatSheet>
      </Scene>
    );
  }

  // 05 / 06 · CONVERSATION — single / multi (mentions under bubble + AI cites)
  function ScreenConvo({ multi = false }) {
    return (
      <Scene kind="files">
        <ChatSheet title={multi ? 'Notes on habits' : 'Strong AI products'} placeholder="Reply…">
          <UserPill mentions={multi
            ? ['How to Build Strong AI Products', 'Compounding deposits', 'Dan Koe — the 1-day reset']
            : ['How to Build Strong AI Products']}>
            {multi ? 'What do these three notes agree on?' : 'What are the three deposits, and how do they compound?'}
          </UserPill>
          {multi ? <AIReplyMulti /> : <AIReplySingle />}
        </ChatSheet>
      </Scene>
    );
  }

  // 07 · ••• MENU
  function ScreenMenu() {
    return (
      <Scene kind="files">
        <ChatSheet title="Strong AI products" placeholder="Reply…" menuActive dim>
          <UserPill mentions={['How to Build Strong AI Products']}>What are the three deposits, and how do they compound?</UserPill>
          <AIReplySingle />
        </ChatSheet>
        <FloatMenu top={128}>
          <MenuItem icon="compose" label="New chat" />
          <MenuItem icon="clock" label="Chat history" />
          <MenuItem icon="clip" label="Attach files" />
          <MenuItem icon="pencil" label="Rename chat" />
          <MenuItem icon="trash" label="Delete chat" danger last />
        </FloatMenu>
      </Scene>
    );
  }

  // 08 · CHAT HISTORY
  function ScreenHistory() {
    return (
      <Scene kind="files">
        <ChatSheet title="Strong AI products" placeholder="Reply…" dim>
          <UserPill mentions={['How to Build Strong AI Products']}>What are the three deposits, and how do they compound?</UserPill>
          <AIReplySingle />
        </ChatSheet>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.4)', zIndex: 35 }} />
        <IOSSheet dark detent="large" height={874} title="Chat history" subtitle="Vault · Chats"
          leading={<SheetCircleBtn kind="close" />} trailing={null} accent={ACCENT} material={BG} divider={false}>
          <div style={{ height: 0.5, background: RULE, margin: '2px 0 0' }} />
          {CHATS.map((c, i) => <ChatRow key={i} c={c} last={i === CHATS.length - 1} />)}
        </IOSSheet>
      </Scene>
    );
  }

  // 09 · AI THINKING
  function ScreenThinking() {
    const bar = (w) => <div className="noto-ai-shimmer" style={{ height: 13, width: w, margin: '11px 0 0' }} />;
    return (
      <Scene kind="files">
        <style>{`
          @keyframes notoAiShimmer { 0% { background-position: -240px 0 } 100% { background-position: 240px 0 } }
          .noto-ai-shimmer { background: linear-gradient(90deg, rgba(255,255,255,0.05) 25%, rgba(255,255,255,0.13) 37%, rgba(255,255,255,0.05) 63%); background-size: 480px 100%; animation: notoAiShimmer 1.4s ease-in-out infinite; border-radius: 6px; }
          @keyframes notoAiDot { 0%,60%,100% { opacity: .25; transform: translateY(0) } 30% { opacity: 1; transform: translateY(-3px) } }
          .noto-ai-dot { width: 6px; height: 6px; border-radius: 999px; background: ${ACCENT}; animation: notoAiDot 1.1s infinite ease-in-out; }
        `}</style>
        <ChatSheet title="Strong AI products" placeholder="Reply…">
          <UserPill mentions={['How to Build Strong AI Products']}>What are the three deposits, and how do they compound?</UserPill>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <Sparkle size={13} />
            <span style={{ color: FAINT, fontFamily: SANS, fontSize: 11.5, fontWeight: 600, letterSpacing: 0.3, textTransform: 'uppercase' }}>Noto</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginLeft: 2 }}>
              <span className="noto-ai-dot" /><span className="noto-ai-dot" style={{ animationDelay: '0.18s' }} /><span className="noto-ai-dot" style={{ animationDelay: '0.36s' }} />
            </div>
          </div>
          {bar('46%')}{bar('92%')}{bar('84%')}{bar('64%')}
        </ChatSheet>
      </Scene>
    );
  }

  // TOOL USE — agent loop over the vault, surfaced in the AI response.
  function ScreenToolWorking() {
    return (
      <Scene kind="files">
        <style>{`
          @keyframes notoToolSpin { to { transform: rotate(360deg) } }
          .noto-tool-spin { animation: notoToolSpin 0.8s linear infinite; }
          @keyframes notoAiDot { 0%,60%,100% { opacity:.25; transform:translateY(0) } 30% { opacity:1; transform:translateY(-3px) } }
          .noto-ai-dot { width:6px; height:6px; border-radius:999px; background:${ACCENT}; animation:notoAiDot 1.1s infinite ease-in-out; display:inline-block; }
        `}</style>
        <ChatSheet title="Q1 pricing" placeholder="Reply…">
          <UserPill>What did I land on for Q1 pricing across my notes?</UserPill>
          <ToolReplyWorking />
        </ChatSheet>
      </Scene>
    );
  }
  function ScreenToolDone() {
    return (
      <Scene kind="files">
        <ChatSheet title="Q1 pricing" placeholder="Reply…">
          <UserPill>What did I land on for Q1 pricing across my notes?</UserPill>
          <ToolReplyDone />
        </ChatSheet>
      </Scene>
    );
  }

  // Add-context sheet shell (over a dimmed chat) — browse or search
  function AttachScene({ search = false }) {
    return (
      <Scene kind="files">
        <ChatSheet title="Strong AI products" placeholder="Reply…" dim>
          <UserPill mentions={['How to Build Strong AI Products']}>What are the three deposits, and how do they compound?</UserPill>
          <AIReplySingle />
        </ChatSheet>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.4)', zIndex: 35 }} />
        <IOSSheet dark detent="large" height={874} title="Add context"
          subtitle={search ? '1 selected' : 'Captures · 2 selected'}
          leading={<SheetCircleBtn kind="close" />} trailing={<SheetCircleBtn kind="confirm" />}
          accent={ACCENT} material="#111419" divider={false}
          footer={(
            <>
              <span style={{ color: MUTED, fontFamily: SANS, fontSize: 14 }}>{search ? '1 selected' : '2 selected'}</span>
              <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 16, fontWeight: 600 }}>Add to chat</span>
            </>
          )}>
          <PickerSearch query={search ? 'pricing' : ''} />
          {search ? (
            <div>
              <div style={{ color: FAINT, fontFamily: SANS, fontSize: 11, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase', padding: '4px 20px 6px' }}>Results · all notes</div>
              <div style={{ height: 0.5, background: RULE }} />
              <PickerFileRow name="Pricing experiments" path="Projects › Alpha" on={true} />
              <PickerFileRow name="Pricing experiments · Q1" path="Captures › AI Products" on={false} />
              <PickerFileRow name="Pricing strategy memo" path="Journal › Daily › Mar" on={false} />
              <PickerFileRow name="Q2 pricing model" path="Projects › Alpha › Q2" on={false} last={true} />
            </div>
          ) : (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 1, padding: '4px 16px 8px' }}>
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={ACCENT} strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round"><path d="M14 6l-6 6 6 6" /></svg>
                <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 16, fontWeight: 500, letterSpacing: -0.2 }}>Vault</span>
              </div>
              <div style={{ height: 0.5, background: RULE }} />
              <PickerFolderRow name="AI Products" count={4} />
              <PickerFileRow name="How to Build Strong AI Products" path="Captures" on={true} />
              <PickerFileRow name="Dan Koe — the 1-day reset" path="Captures" on={true} />
              <PickerFileRow name="What is my definition of a “great” life" path="Captures" on={false} last={true} />
            </div>
          )}
        </IOSSheet>
      </Scene>
    );
  }

  function NotoAIChat({ state = 'trigger-home' }) {
    switch (state) {
      case 'trigger-note': return <TriggerNote />;
      case 'new':          return <ScreenNew />;
      case 'compose':      return <ScreenCompose />;
      case 'convo':        return <ScreenConvo multi={false} />;
      case 'convo-multi':  return <ScreenConvo multi={true} />;
      case 'menu':         return <ScreenMenu />;
      case 'history':      return <ScreenHistory />;
      case 'thinking':     return <ScreenThinking />;
      case 'tool-working': return <ScreenToolWorking />;
      case 'tool-done':    return <ScreenToolDone />;
      case 'attach-browse':return <AttachScene search={false} />;
      case 'attach-search':return <AttachScene search={true} />;
      case 'trigger-home':
      default:             return <TriggerHome />;
    }
  }

  Object.assign(window, { NotoAIChat });
})();
