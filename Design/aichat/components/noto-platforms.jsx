// noto-platforms.jsx
// ─────────────────────────────────────────────────────────────
// Native iPad + macOS adaptations of the minimal Noto iteration.
// Regular size class → NavigationSplitView: a persistent file-system
// sidebar + an editor detail pane. No scaled-up iPhone chrome.
//   • NotoIPad  state: 'reading' | 'editing' | 'properties'
//   • NotoMac   state: 'reading' | 'editing' | 'inspector'
// Reuses the minimal palette / type scale / orange accent, the
// folders-first-with-› file outline, and window.NotoPropertyList for
// the inset-grouped property rows.

(function () {
  const BG     = '#0E1116';
  const PANEL  = '#15181E';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.60)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(236,236,238,0.10)';
  const ACCENT = '#FF6A2E';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';
  const TITLE  = 'How to Build Strong AI Products';

  // blinking caret keyframes (injected once per platform root)
  const caretCSS = `@keyframes notoPlatCaret{0%,48%{opacity:1}52%,100%{opacity:0}} .noto-plat-caret{animation:notoPlatCaret 1.05s steps(1,end) infinite}`;
  const Caret = () => (
    <span className="noto-plat-caret" style={{ display: 'inline-block', width: 2, height: '1.05em', background: ACCENT, borderRadius: 1, verticalAlign: 'text-bottom', marginLeft: 1, transform: 'translateY(2px)' }} />
  );

  // ─── glyphs ────────────────────────────────────────────────────────────
  function Glyph({ name, color = MUTED, size = 17, sw = 1.7 }) {
    const c = { fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
    const P = (d) => <path d={d} {...c} />;
    let b = null;
    switch (name) {
      case 'chevron':   b = P('M9 6l6 6-6 6'); break;
      case 'back':      b = P('M15 6l-6 6 6 6'); break;
      case 'disclosure':b = P('M8 5l7 7-7 7'); break;
      case 'folder':    b = P('M3 7a2 2 0 012-2h3.6a2 2 0 011.5.7L11 7h6a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V7z'); break;
      case 'doc':       b = <>{P('M7 3.5h6.5L18 8v12.5a1 1 0 01-1 1H7a1 1 0 01-1-1v-16a1 1 0 011-1z')}{P('M13 3.5V8h4.5')}</>; break;
      case 'search':    b = <><circle cx="10" cy="10" r="6.5" {...c} />{P('M15 15l5 5')}</>; break;
      case 'plus':      b = P('M12 5.5v13M5.5 12h13'); break;
      case 'close':     b = P('M6 6l12 12M18 6L6 18'); break;
      case 'check':     b = P('M5 12.5l5 5 9-10'); break;
      case 'sidebar':   b = <>{P('M4 6a2 2 0 012-2h12a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6z')}{P('M9.5 4v16')}</>; break;
      case 'inspector': b = <>{P('M4 6a2 2 0 012-2h12a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6z')}{P('M15 4v16')}</>; break;
      case 'more':      b = <>{[6, 12, 18].map((cx, i) => <circle key={i} cx={cx} cy="12" r="1.5" fill={color} stroke="none" />)}</>; break;
      case 'bold':      b = <>{P('M7 5h6a3.5 3.5 0 010 7H7zM7 12h7a3.5 3.5 0 010 7H7z')}</>; break;
      case 'italic':    b = <>{P('M11 5h6M7 19h6M14 5l-4 14')}</>; break;
      case 'list':      b = <>{P('M9 7h11M9 12h11M9 17h11')}{P('M4.5 7h.01M4.5 12h.01M4.5 17h.01')}</>; break;
      case 'link':      b = <>{P('M9.5 14.5l5-5')}{P('M8 11l-2 2a3.5 3.5 0 005 5l2-2')}{P('M16 13l2-2a3.5 3.5 0 00-5-5l-2 2')}</>; break;
      default: b = null;
    }
    return <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block', flexShrink: 0 }}>{b}</svg>;
  }

  // ─── shared article body (wider columns than the phone) ──────────────────
  function Article({ editing = false, big = true, maxW = 720 }) {
    const para = { margin: '15px 0 0', fontFamily: SANS, fontSize: 17, lineHeight: 1.6, color: INK, letterSpacing: -0.1 };
    const h2 = { margin: '26px 0 6px', fontFamily: SANS, fontSize: 21, fontWeight: 700, color: HEAD, letterSpacing: -0.3 };
    const Fig = ({ tint, label, caption, h }) => (
      <figure style={{ margin: '18px 0 0' }}>
        <div style={{ width: '100%', height: h, borderRadius: 14, background: tint, position: 'relative', overflow: 'hidden', border: '0.5px solid rgba(255,255,255,0.08)', display: 'flex', alignItems: 'flex-end', padding: 12, boxSizing: 'border-box' }}>
          <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.22), transparent 60%)' }} />
          <span style={{ position: 'relative', fontFamily: '"SF Mono", ui-monospace, monospace', fontSize: 11, letterSpacing: 0.3, color: 'rgba(255,255,255,0.78)', background: 'rgba(0,0,0,0.28)', borderRadius: 5, padding: '3px 8px' }}>{label}</span>
        </div>
        {caption && <figcaption style={{ margin: '8px 2px 0', fontFamily: SANS, fontSize: 13, color: FAINT }}>{caption}</figcaption>}
      </figure>
    );
    return (
      <div style={{ maxWidth: maxW, margin: '0 auto' }}>
        <div style={{ color: HEAD, fontFamily: SANS, fontSize: big ? 34 : 30, fontWeight: 700, lineHeight: 1.12, letterSpacing: -0.6 }}>{TITLE}</div>
        <p style={{ ...para, marginTop: 14, fontSize: 19, color: MUTED, lineHeight: 1.5 }}>
          A field guide for founders shipping AI features in 2026 — what makes a
          product compound, and what makes it flame out after launch week.
        </p>
        <Fig tint="linear-gradient(135deg, #FF6A2E 0%, #C2185B 55%, #4A148C 100%)" label="cover.png" h={150} />
        <h2 style={h2}>The three deposits</h2>
        <p style={para}>Every interaction should leave behind a deposit:</p>
        <ul style={{ margin: '10px 0 0', paddingLeft: 24, fontFamily: SANS, fontSize: 17, lineHeight: 1.6, color: INK, letterSpacing: -0.1 }}>
          <li style={{ margin: '0 0 8px' }}><strong style={{ color: HEAD, fontWeight: 600 }}>Memory</strong> — what it remembers about you and your work.</li>
          <li style={{ margin: '0 0 8px' }}><strong style={{ color: HEAD, fontWeight: 600 }}>Preference</strong> — your corrections, encoded once.</li>
          <li style={{ margin: '0 0 8px' }}><strong style={{ color: HEAD, fontWeight: 600 }}>Taste</strong> — the rough shape of what you call “good.”</li>
        </ul>
        <p style={para}>
          None of these require a frontier model — only a product that treats every
          discarded draft as signal rather than exhaust{editing ? <Caret /> : '.'}
        </p>
        <Fig tint="linear-gradient(135deg, #1F6FEB 0%, #163172 100%)" label="retention-curve.png" caption="Day-30 retention, two cohorts: compounding vs. novelty." h={170} />
        <h2 style={h2}>Why the model layer is interchangeable</h2>
        <p style={para}>
          Two years from now you’ll still have a usable product even if you swap the
          underlying weights — provided the deposits survive the swap.
        </p>
      </div>
    );
  }

  // ─── file-system outline (folders first, then notes) ─────────────────────
  // Captures is expanded to reveal the selected note. `mac` switches to the
  // source-list treatment (leading folder/doc SF glyph + disclosure triangle).
  function FileOutline({ mac = false }) {
    const sel = '#FF6A2E';
    const selBg = 'rgba(255,106,46,0.16)';
    const rowBase = { display: 'flex', alignItems: 'center', height: mac ? 30 : 38, borderRadius: 8, fontFamily: SANS, letterSpacing: -0.2, cursor: 'pointer' };
    const Folder = ({ name, open }) => (
      <div style={{ ...rowBase, padding: mac ? '0 8px' : '0 12px', gap: mac ? 6 : 10, color: INK }}>
        {mac && <span style={{ width: 14, display: 'flex', justifyContent: 'center' }}><Glyph name={open ? 'chevron' : 'disclosure'} color={FAINT} size={12} sw={2.2} style={open ? { transform: 'rotate(90deg)' } : null} /></span>}
        {mac && <Glyph name="folder" color={ACCENT} size={16} />}
        <span style={{ flex: 1, minWidth: 0, fontSize: mac ? 13 : 16, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</span>
        {!mac && <span style={{ transform: open ? 'rotate(90deg)' : 'none', display: 'inline-flex' }}><Glyph name="chevron" color={FAINT} size={16} sw={2} /></span>}
      </div>
    );
    const Note = ({ name, selected, indent }) => (
      <div style={{ ...rowBase, padding: mac ? `0 8px 0 ${indent ? 28 : 8}px` : `0 12px 0 ${indent ? 26 : 12}px`, gap: mac ? 6 : 0, position: 'relative', background: selected ? selBg : 'transparent' }}>
        {mac && <Glyph name="doc" color={ACCENT} size={15} />}
        <span style={{ flex: 1, minWidth: 0, fontSize: mac ? 13 : 16, color: selected ? (mac ? HEAD : sel) : INK, fontWeight: selected ? 600 : 400, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</span>
      </div>
    );
    const captures = [
      'How to Build Strong AI Products',
      'Weekly review — Mar 11',
      'Compounding deposits',
      'Dan Koe — 1 day exercise',
      'What is my definition of a ‘great’ life',
    ];
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 1, padding: mac ? '2px 8px' : '2px 6px' }}>
        <Folder name="Daily Notes" />
        <Folder name="Projects" />
        <Folder name="Captures" open />
        {captures.map((n, i) => <Note key={i} name={n} indent selected={i === 0} />)}
        <Note name="Reflection 2025" />
      </div>
    );
  }

  // ─── macOS Finder-style source list — sectioned headers + leading SF
  // ─── macOS traffic lights ────────────────────────────────────────────────
  function TrafficLights() {
    const dot = (bg) => <div style={{ width: 12, height: 12, borderRadius: '50%', background: bg }} />;
    return <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>{dot('#ff5f57')}{dot('#febc2e')}{dot('#28c840')}</div>;
  }

  // ─── circular sheet-header buttons (HIG ✕ / ✓) ───────────────────────────
  function CircleBtn({ kind = 'close', size = 30 }) {
    const confirm = kind === 'confirm';
    return (
      <div style={{ width: size, height: size, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', background: confirm ? ACCENT : 'rgba(118,118,128,0.30)', boxShadow: confirm ? '0 1px 3px rgba(0,0,0,0.25), inset 0 0.5px 0 rgba(255,255,255,0.35)' : 'inset 0 0.5px 0 rgba(255,255,255,0.14)', cursor: 'pointer' }}>
        <Glyph name={confirm ? 'check' : 'close'} color={confirm ? '#fff' : 'rgba(235,235,245,0.7)'} size={size * 0.52} sw={confirm ? 2.4 : 2.2} />
      </div>
    );
  }

  // ─── shared properties CARD — the iPad form-sheet treatment: a centered
  //     rounded card (circular ✕/✓ header + inset-grouped list) over a dimmed
  //     backdrop. Used by both iPad (form sheet) and macOS (inspector). ──────
  function PropsCard() {
    return (
      <div style={{ position: 'absolute', inset: 0, zIndex: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.45)' }} />
        <div style={{ position: 'relative', width: 540, maxHeight: 660, borderRadius: 16, overflow: 'hidden', background: window.NOTO_HIG.SHEET_BG, boxShadow: '0 30px 80px rgba(0,0,0,0.5)', display: 'flex', flexDirection: 'column' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 16px', position: 'relative', flexShrink: 0 }}>
            <CircleBtn kind="close" />
            <div style={{ position: 'absolute', left: 0, right: 0, textAlign: 'center', pointerEvents: 'none', color: HEAD, fontFamily: SANS, fontSize: 17, fontWeight: 600 }}>Properties</div>
            <CircleBtn kind="confirm" />
          </div>
          <div style={{ flex: 1, overflow: 'auto' }}><window.NotoPropertyList view="list" /></div>
        </div>
      </div>
    );
  }
  //     explorer: large folder title + counts, a leading back-to-parent, and
  //     folder-then-file rows) living inside the floating translucent
  //     Liquid-Glass panel. Same rows, glyphs and active-note highlight. ────
  const RULE2 = 'rgba(255,255,255,0.08)';
  const sidebarFolderGlyph = (color) => (
    <svg width="20" height="20" viewBox="0 0 18 18" fill={color} stroke="none">
      <path d="M2 5a1.6 1.6 0 011.6-1.6h2.9c.55 0 1.06.28 1.36.74l.5.76c.3.46.8.74 1.36.74h4.7A1.6 1.6 0 0116 7v6A1.6 1.6 0 0114.4 14.6H3.6A1.6 1.6 0 012 13V5z" />
    </svg>
  );
  const sidebarFileGlyph = (color) => (
    <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 1.5h5l3 3V13a1 1 0 01-1 1H4a1 1 0 01-1-1V2.5a1 1 0 011-1z" />
      <path d="M9 1.5v3h3" />
    </svg>
  );
  const SidebarFolderRow = ({ name, count }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px', borderBottom: '0.5px solid ' + RULE2 }}>
      <span style={{ flexShrink: 0, display: 'inline-flex' }}>{sidebarFolderGlyph('rgba(236,236,238,0.80)')}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: HEAD, fontFamily: SANS, fontSize: 15, fontWeight: 600, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12, marginTop: 2 }}>{count} items</div>
      </div>
      <Glyph name="chevron" color={FAINT} size={15} sw={2} />
    </div>
  );
  const SidebarFileRow = ({ name, when, active }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px', borderBottom: '0.5px solid ' + RULE2, background: active ? 'rgba(255,106,46,0.12)' : 'transparent' }}>
      <span style={{ flexShrink: 0, display: 'inline-flex' }}>{sidebarFileGlyph(active ? ACCENT : MUTED)}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: active ? HEAD : INK, fontFamily: SANS, fontSize: 15, fontWeight: active ? 600 : 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12, marginTop: 2 }}>Edited {when}</div>
      </div>
    </div>
  );
  // shared explorer body — the iPhone file view (nav row · title · counts ·
  // folder-then-file rows). Used by iPhone, iPad and macOS sidebars alike.
  function VaultSidebarContent() {
    return (
      <>
        {/* explorer nav row — back to parent · trailing new-folder + more */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 14px 2px', flexShrink: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 1, cursor: 'pointer' }}>
            <Glyph name="back" color={ACCENT} size={20} sw={2.1} />
            <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 16, fontWeight: 500, letterSpacing: -0.2 }}>Vault</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <svg width="20" height="20" viewBox="0 0 18 18" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
              <path d="M2 5.5a1.6 1.6 0 011.6-1.6h2.6c.5 0 1 .26 1.3.7l.5.7c.3.44.8.7 1.3.7H14.4A1.6 1.6 0 0116 7.6V13a1.6 1.6 0 01-1.6 1.6H3.6A1.6 1.6 0 012 13V5.5z" />
              <path d="M9 8.4v3.4M7.3 10.1h3.4" />
            </svg>
            <Glyph name="more" color={HEAD} size={20} />
          </div>
        </div>
        {/* large folder title + counts */}
        <div style={{ padding: '6px 16px 10px', flexShrink: 0 }}>
          <div style={{ color: HEAD, fontFamily: SANS, fontSize: 24, fontWeight: 700, letterSpacing: -0.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>Captures</div>
          <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12.5, marginTop: 3 }}>1 folder · 4 notes</div>
        </div>
        <div style={{ height: 0.5, background: RULE2, flexShrink: 0 }} />
        {/* immediate subfolders, then files (active note highlighted) */}
        <div style={{ flex: 1, overflow: 'hidden' }}>
          <SidebarFolderRow name="AI Products" count={4} />
          <SidebarFileRow name="How to Build Strong AI Products" when="2h ago" active />
          <SidebarFileRow name="Dan Koe — the 1-day reset" when="2d ago" />
          <SidebarFileRow name="What is my definition of a “great” life" when="3d ago" />
          <SidebarFileRow name="Why Vertical LLM Agents Are The New Moat" when="4d ago" />
        </div>
      </>
    );
  }
  function IPadSidebar() {
    return (
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden',
        borderRadius: 20,
        background: 'rgba(34,38,46,0.55)',
        backdropFilter: 'blur(50px) saturate(180%)', WebkitBackdropFilter: 'blur(50px) saturate(180%)',
        boxShadow: '0 22px 60px rgba(0,0,0,0.40), inset 0 0.5px 0 rgba(255,255,255,0.12)' }}>
        <VaultSidebarContent />
      </div>
    );
  }

  // ─── iPad keyboard + formatting (shortcut) bar ───────────────────────────
  function IPadKeyboard() {
    const keyBg = '#6B6B71', glyph = '#FFFFFF';
    const Key = ({ ch, flex = 1, w }) => (
      <div style={{ flex: w ? '0 0 ' + w + 'px' : flex, height: 46, borderRadius: 7, background: keyBg, boxShadow: '0 1px 0 rgba(0,0,0,0.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: glyph, fontFamily: SANS, fontSize: 18 }}>{ch}</div>
    );
    const Row = ({ chars, pad = 0 }) => (
      <div style={{ display: 'flex', gap: 8, padding: '0 ' + pad + 'px' }}>{chars.split('').map((c, i) => <Key key={i} ch={c} />)}</div>
    );
    return (
      <div style={{ flexShrink: 0, display: 'flex', flexDirection: 'column' }}>
        {/* accessory toolbar — identical to the iPhone (NotoToolbarArticle) */}
        <window.NotoToolbarArticle wordCount={258} activeKey={null} />
        <div style={{ background: '#2A2A2D', padding: '8px 16px 12px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <Row chars="qwertyuiop" />
          <Row chars="asdfghjkl" pad={24} />
          <div style={{ display: 'flex', gap: 8 }}>
            <Key ch="⇧" w={64} />
            {'zxcvbnm'.split('').map((c, i) => <Key key={i} ch={c} />)}
            <Key ch="⌫" w={64} />
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <Key ch="123" w={84} />
            <Key ch="" flex={6} />
            <Key ch="return" w={120} />
          </div>
        </div>
      </div>
    );
  }

  // ─── iPad shell (landscape, status bar + home indicator, no notch) ───────
  function NotoIPad({ state = 'reading' }) {
    const editing = state === 'editing';
    const props = state === 'properties';

    // ─── shared bits ──────────────────────────────────────────────────────
    const StatusBar = () => (
      <div style={{ position: 'absolute', top: 8, left: 0, right: 0, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 30px', zIndex: 30, pointerEvents: 'none' }}>
        <span style={{ color: HEAD, fontSize: 14, fontWeight: 600, letterSpacing: 0.2 }}>9:41</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <svg width="18" height="12" viewBox="0 0 18 12" fill={HEAD}><path d="M9 2.5c2 0 3.8.8 5.2 2.1l1.3-1.4A9.5 9.5 0 009 .6 9.5 9.5 0 002.5 3.2l1.3 1.4A7.4 7.4 0 019 2.5z"/><path d="M9 6c1 0 2 .4 2.7 1.1l1.3-1.4A6 6 0 009 4a6 6 0 00-4 1.7l1.3 1.4A3.8 3.8 0 019 6z"/><circle cx="9" cy="9.4" r="1.6"/></svg>
          <div style={{ width: 24, height: 12, borderRadius: 3, border: '1px solid rgba(255,255,255,0.6)', position: 'relative', padding: 1.5 }}><div style={{ width: '80%', height: '100%', background: HEAD, borderRadius: 1.5 }} /></div>
        </div>
      </div>
    );
    const PropsFormSheet = () => <PropsCard />;
    const HomeIndicator = ({ w = 320 }) => (
      <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)', width: w, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.32)', zIndex: 50 }} />
    );
    // bottom floating dock — transplanted from the iPhone (today · search ·
    // new), glass capsules. Sidebar lives in the top bar so it's dropped here.
    const dockGlass = {
      background: 'rgba(28,30,36,0.55)',
      backdropFilter: 'blur(28px) saturate(180%)', WebkitBackdropFilter: 'blur(28px) saturate(180%)',
      border: '0.5px solid rgba(255,255,255,0.10)',
      boxShadow: '0 1px 1px rgba(0,0,0,0.18), 0 8px 24px rgba(0,0,0,0.32), inset 0 0.5px 0 rgba(255,255,255,0.22), inset 0 -0.5px 0 rgba(0,0,0,0.25)',
    };
    const BottomDock = ({ searchW = 320 }) => (
      <div style={{ flexShrink: 0, padding: '6px 16px 30px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
        <div style={{ ...dockGlass, height: 52, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center' }}>
          <div style={{ width: 44, height: 44, borderRadius: 999, position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3.5" y="4.5" width="15" height="13" rx="2.4" /><path d="M3.5 8.5h15" /><path d="M7 3v3M15 3v3" />
            </svg>
            <span style={{ position: 'absolute', left: 0, right: 0, top: 21, textAlign: 'center', color: HEAD, fontFamily: SANS, fontSize: 8, fontWeight: 700, pointerEvents: 'none' }}>7</span>
          </div>
        </div>
        <div style={{ ...dockGlass, width: searchW, height: 52, borderRadius: 999, padding: '0 18px', gap: 10, display: 'flex', alignItems: 'center' }}>
          <Glyph name="search" color={MUTED} size={19} />
          <span style={{ color: MUTED, fontFamily: SANS, fontSize: 16 }}>Search</span>
        </div>
        <div style={{ ...dockGlass, height: 52, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center' }}>
          <div style={{ width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(255,106,46,0.22)', border: '0.5px solid rgba(255,106,46,0.40)' }}>
            <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
              <path d="M9.5 4H5.5a2 2 0 00-2 2v10.5a2 2 0 002 2h10.5a2 2 0 002-2V12.5" />
              <path d="M15 3.5l3.5 3.5L11 14.5H7.5V11L15 3.5z" />
            </svg>
          </div>
        </div>
      </div>
    );
    // plain toolbar button — bare SF symbol, no bordered/circular background
    const PlainBtn = ({ name, prominent }) => (
      <div style={{ width: 40, height: 40, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
        <Glyph name={name} color={prominent ? ACCENT : HEAD} size={22} />
      </div>
    );

    // ─── PORTRAIT — content-first: collapsed sidebar, full-width editor with
    //     a leading sidebar-toggle; sidebar + properties present as overlays. ─
    if (state.indexOf('portrait') === 0) {
      const pFiles = state === 'portrait-files';
      const pProps = state === 'portrait-properties';
      const dimmed = pFiles || pProps;
      const TopBtn = ({ name, prominent }) => (
        <div style={{ width: 40, height: 40, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Glyph name={name} color={prominent ? ACCENT : HEAD} size={22} />
        </div>
      );
      return (
        <div style={{ width: 834, height: 1194, borderRadius: 26, overflow: 'hidden', position: 'relative', background: BG, boxShadow: '0 40px 90px rgba(0,0,0,0.4)', fontFamily: SANS }}>
          <style>{caretCSS}</style>
          <StatusBar />
          {/* editor (full width) — dims behind overlays */}
          <div style={{ position: 'absolute', inset: 0, paddingTop: 30, display: 'flex', flexDirection: 'column' }}>
            {/* toolbar: LEADING sidebar toggle + back · TRAILING find-in-text + more */}
            <div style={{ flexShrink: 0, height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 14px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <TopBtn name="sidebar" />
                <TopBtn name="back" />
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <TopBtn name="search" />
                <TopBtn name="more" />
              </div>
            </div>
            <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '14px 96px 0', position: 'relative' }}>
              <Article editing={false} maxW={600} />
            </div>
          </div>

          {/* bottom floating dock — liquid-glass; content passes UNDER it so the
              blur samples the live article. Sits below the dim overlay. */}
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 15 }}>
            <BottomDock searchW={220} />
          </div>

          {/* dim layer behind any overlay */}
          {dimmed && <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 20 }} />}

          {/* sidebar overlay — floating Liquid-Glass panel from the leading edge */}
          {pFiles && (
            <div style={{ position: 'absolute', top: 42, left: 12, bottom: 12, width: 330, zIndex: 30 }}>
              <IPadSidebar />
            </div>
          )}

          {/* properties form sheet over the dimmed editor */}
          {pProps && <PropsFormSheet />}

          <HomeIndicator w={260} />
        </div>
      );
    }

    return (
      <div style={{ width: 1194, height: 834, borderRadius: 26, overflow: 'hidden', position: 'relative', background: BG, boxShadow: '0 40px 90px rgba(0,0,0,0.4)', fontFamily: SANS }}>
        <style>{caretCSS}</style>
        <StatusBar />

        {/* content layer — bg + toolbar + editor span full width and extend
            beneath the floating sidebar (background-extension look) */}
        <div style={{ position: 'absolute', inset: 0, paddingTop: 30, display: 'flex', flexDirection: 'column' }}>
          <div style={{ marginLeft: 324, height: '100%', minWidth: 0, display: 'flex', flexDirection: 'column' }}>
            {/* detail toolbar — LEADING sidebar toggle + back · TRAILING find-in-text + more */}
            <div style={{ flexShrink: 0, height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 26px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <PlainBtn name="sidebar" />
                <PlainBtn name="back" />
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <PlainBtn name="search" />
                <PlainBtn name="more" />
              </div>
            </div>
            <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '2px 64px 0 24px', position: 'relative' }}>
              <Article editing={editing} maxW={600} />
            </div>
            {editing && <IPadKeyboard />}
          </div>
        </div>

        {/* bottom floating dock — liquid-glass over the detail pane; content
            passes under it. Hidden while the keyboard is up. */}
        {!editing && (
          <div style={{ position: 'absolute', left: 324, right: 0, bottom: 0, zIndex: 8 }}>
            <BottomDock searchW={220} />
          </div>
        )}

        {/* floating translucent Liquid-Glass sidebar */}
        <div style={{ position: 'absolute', top: 42, left: 12, bottom: 12, width: 300, zIndex: 10 }}>
          <IPadSidebar />
        </div>

        {/* properties — centered FORM SHEET over a dimmed split */}
        {props && <PropsFormSheet />}

        <HomeIndicator />
      </div>
    );
  }

  // ─── macOS window (dark, traffic lights, floating source-list sidebar) ───
  function NotoMac({ state = 'reading' }) {
    const editing = state === 'editing';
    const inspector = state === 'inspector';
    // plain toolbar button — bare SF symbol, no bordered/circular background;
    // the bar itself is the container. Accent only for the prominent action
    // and the active inspector toggle.
    const TBtn = ({ name, prominent, active }) => (
      <div style={{ width: 30, height: 30, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
        <Glyph name={name} color={prominent ? ACCENT : (active ? ACCENT : MUTED)} size={18} />
      </div>
    );
    // toolbar button matching the iPad's plain white SF-symbol treatment
    const MacBtn = ({ name, prominent }) => (
      <div style={{ width: 36, height: 36, borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
        <Glyph name={name} color={prominent ? ACCENT : HEAD} size={20} />
      </div>
    );
    const glassPanel = {
      overflow: 'hidden', borderRadius: 14,
      background: 'rgba(34,38,46,0.55)',
      backdropFilter: 'blur(50px) saturate(180%)', WebkitBackdropFilter: 'blur(50px) saturate(180%)',
      boxShadow: '0 18px 50px rgba(0,0,0,0.35), inset 0 0.5px 0 rgba(255,255,255,0.10)',
      display: 'flex', flexDirection: 'column',
    };
    return (
      <div style={{ width: 1280, height: 800, borderRadius: 12, overflow: 'hidden', background: BG, boxShadow: '0 0 0 1px rgba(0,0,0,0.5), 0 30px 80px rgba(0,0,0,0.5)', display: 'flex', fontFamily: SANS, position: 'relative', padding: 8, boxSizing: 'border-box', gap: 8 }}>
        <style>{caretCSS}</style>

        {/* full-height source-list sidebar — spans the window minus padding,
            traffic lights ride INSIDE its top-left (Finder window chrome). */}
        <div style={{ width: 230, flexShrink: 0, ...glassPanel, boxShadow: 'inset -0.5px 0 0 rgba(0,0,0,0.30), inset 0 0.5px 0 rgba(255,255,255,0.10)' }}>
          <div style={{ height: 44, flexShrink: 0, display: 'flex', alignItems: 'center', padding: '0 16px' }}>
            <TrafficLights />
          </div>
          <VaultSidebarContent />
        </div>

        {/* detail pane — toolbar identical to iPad: LEADING sidebar + back ·
            TRAILING find-in-text + more. Then the editor. */}
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
          <div style={{ height: 44, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 10px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <MacBtn name="sidebar" />
              <MacBtn name="back" />
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <MacBtn name="search" />
              <MacBtn name="more" />
            </div>
          </div>

          <div style={{ flex: 1, minHeight: 0, display: 'flex' }}>
            <div style={{ flex: 1, minWidth: 0, overflow: 'hidden', paddingTop: 8, paddingLeft: 8, paddingRight: 8 }}>
              <Article editing={editing} big={false} />
            </div>
          </div>
        </div>

        {/* properties — iPad-style centered form-sheet card over a dimmed window */}
        {inspector && <PropsCard />}
      </div>
    );
  }

  // ─── macOS with TABS — exploration of multiple open notes in the top bar.
  //     Three treatments via `variant`:
  //       'bar'     — classic full-width segmented tab bar below the toolbar
  //       'capsule' — modern rounded capsule tabs in their own strip
  //       'inline'  — compact capsule tabs living inside the toolbar row
  // ─────────────────────────────────────────────────────────────────────────
  function NotoMacTabs({ variant = 'bar', count = 3, picker = false }) {
    const glassPanel = {
      overflow: 'hidden', borderRadius: 14,
      background: 'rgba(34,38,46,0.55)',
      backdropFilter: 'blur(50px) saturate(180%)', WebkitBackdropFilter: 'blur(50px) saturate(180%)',
      boxShadow: 'inset -0.5px 0 0 rgba(0,0,0,0.30), inset 0 0.5px 0 rgba(255,255,255,0.10)',
      display: 'flex', flexDirection: 'column',
    };
    const HAIR = '0.5px solid rgba(255,255,255,0.08)';
    const MacBtn = ({ name, prominent }) => (
      <div style={{ width: 36, height: 36, borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
        <Glyph name={name} color={prominent ? ACCENT : HEAD} size={20} />
      </div>
    );
    const tabsAll = [
      'How to Build Strong AI Products',
      'Dan Koe — the 1-day reset',
      'Compounding deposits',
      'Weekly review — Mar 11',
      'What is my definition of a “great” life',
      'Why Vertical LLM Agents Are The New Moat',
      'Pricing experiments · Q1',
    ];
    const tabs = tabsAll.slice(0, count).map((title, i) => ({ title, active: i === 0 }));
    const scrolls = tabs.length > 4; // overflow → horizontal scroll
    const CloseX = ({ c = 'rgba(236,236,238,0.62)', s = 13 }) => (
      <svg width={s} height={s} viewBox="0 0 14 14" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" style={{ flexShrink: 0 }}><path d="M4 4l6 6M10 4l-6 6" /></svg>
    );
    const AddTab = ({ ml = 0, active }) => (
      <div style={{ width: 28, height: 28, marginLeft: ml, flexShrink: 0, borderRadius: 7, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: active ? 'rgba(255,106,46,0.16)' : 'transparent' }}>
        <Glyph name="plus" color={active ? ACCENT : MUTED} size={16} />
      </div>
    );

    // ── new-tab PICKER popover — anchored under the +; create a new note or
    //    open an existing one as a tab. ────────────────────────────────────
    const popoverGlass = {
      borderRadius: 12, overflow: 'hidden',
      background: 'rgba(28,30,36,0.96)',
      backdropFilter: 'blur(40px) saturate(180%)', WebkitBackdropFilter: 'blur(40px) saturate(180%)',
      border: '0.5px solid rgba(255,255,255,0.12)',
      boxShadow: '0 24px 70px rgba(0,0,0,0.55), inset 0 0.5px 0 rgba(255,255,255,0.10)',
    };
    const pickerNotes = [
      { title: 'Dan Koe — the 1-day reset', meta: 'Captures · 2d ago' },
      { title: 'What is my definition of a “great” life', meta: 'Captures · 3d ago' },
      { title: 'The three deposits', meta: 'AI Products · Mar 2' },
      { title: 'Weekly review — Mar 11', meta: 'Journal · Mar 11' },
      { title: 'Field guide outline', meta: 'AI Products · 5d ago' },
      { title: 'Pricing experiments · Q1', meta: 'AI Products · Mar 4' },
    ];
    const PickerRow = ({ title, meta, hi }) => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px', borderRadius: 7, background: hi ? 'rgba(255,255,255,0.08)' : 'transparent', cursor: 'pointer' }}>
        <Glyph name="doc" color={FAINT} size={15} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ color: HEAD, fontFamily: SANS, fontSize: 13, fontWeight: 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
          <div style={{ color: MUTED, fontFamily: SANS, fontSize: 11.5, marginTop: 1 }}>{meta}</div>
        </div>
        {hi && <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12 }}>↵</span>}
      </div>
    );
    const NewTabPicker = () => (
      <div style={{ position: 'absolute', inset: 0, zIndex: 50 }}>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.20)' }} />
        <div style={{ position: 'absolute', top: 52, right: 92, width: 360, maxHeight: 540, display: 'flex', flexDirection: 'column', ...popoverGlass }}>
          {/* search field */}
          <div style={{ padding: '10px 10px 6px', flexShrink: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 34, padding: '0 10px', borderRadius: 8, background: 'rgba(118,118,128,0.22)' }}>
              <Glyph name="search" color={FAINT} size={15} />
              <span style={{ color: FAINT, fontFamily: SANS, fontSize: 13.5, flex: 1 }}>Open a note…</span>
              <span style={{ display: 'inline-block', width: 1.5, height: 16, background: ACCENT }} />
            </div>
          </div>
          {/* primary action — new note */}
          <div style={{ padding: '2px 8px', flexShrink: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 7, cursor: 'pointer' }}>
              <div style={{ width: 24, height: 24, borderRadius: 6, flexShrink: 0, background: 'rgba(255,106,46,0.18)', border: '0.5px solid rgba(255,106,46,0.40)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <svg width="14" height="14" viewBox="0 0 22 22" fill="none" stroke={ACCENT} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M9.5 4H5.5a2 2 0 00-2 2v10.5a2 2 0 002 2h10.5a2 2 0 002-2V12.5" /><path d="M15 3.5l3.5 3.5L11 14.5H7.5V11L15 3.5z" /></svg>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ color: HEAD, fontFamily: SANS, fontSize: 13, fontWeight: 600 }}>New note</div>
                <div style={{ color: MUTED, fontFamily: SANS, fontSize: 11.5, marginTop: 1 }}>Create a blank note in Captures</div>
              </div>
              <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12, fontVariantNumeric: 'tabular-nums' }}>⌘N</span>
            </div>
          </div>
          <div style={{ height: 0.5, background: 'rgba(255,255,255,0.08)', margin: '2px 0', flexShrink: 0 }} />
          {/* open existing */}
          <div style={{ padding: '6px 8px 8px', overflow: 'auto' }}>
            <div style={{ color: FAINT, fontFamily: SANS, fontSize: 11, fontWeight: 600, letterSpacing: 0.2, padding: '2px 10px 4px' }}>Recent</div>
            {pickerNotes.map((n, i) => <PickerRow key={i} title={n.title} meta={n.meta} hi={i === 0} />)}
          </div>
        </div>
      </div>
    );

    // classic macOS segmented tab bar (full-width segments, hairline dividers)
    const ClassicBar = () => (
      <div style={{ display: 'flex', alignItems: 'stretch', height: 34, flexShrink: 0, background: 'rgba(0,0,0,0.22)', borderBottom: HAIR }}>
        {tabs.map((t, i) => (
          <div key={i} style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 7, padding: '0 12px', borderRight: HAIR, background: t.active ? 'rgba(255,255,255,0.07)' : 'transparent' }}>
            {t.active ? <CloseX /> : <span style={{ width: 13, flexShrink: 0 }} />}
            <Glyph name="doc" color={t.active ? ACCENT : FAINT} size={14} />
            <span style={{ flex: 1, minWidth: 0, color: t.active ? HEAD : MUTED, fontFamily: SANS, fontSize: 12.5, fontWeight: t.active ? 600 : 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{t.title}</span>
          </div>
        ))}
        <div style={{ display: 'flex', alignItems: 'center', padding: '0 6px' }}><AddTab /></div>
      </div>
    );

    // modern rounded capsule tabs, active accent-tinted glass
    const Capsule = ({ t, i, fixed }) => (
      <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 7, height: 28, padding: '0 10px', borderRadius: 8, minWidth: 0, cursor: 'pointer', ...(fixed ? { flex: '0 0 auto', width: 190 } : { flex: '1 1 0', maxWidth: 230 }), background: t.active ? 'rgba(255,106,46,0.16)' : 'rgba(255,255,255,0.05)', border: t.active ? '0.5px solid rgba(255,106,46,0.40)' : '0.5px solid rgba(255,255,255,0.06)' }}>
        <Glyph name="doc" color={t.active ? ACCENT : FAINT} size={14} />
        <span style={{ flex: 1, minWidth: 0, color: t.active ? HEAD : MUTED, fontFamily: SANS, fontSize: 12.5, fontWeight: t.active ? 600 : 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{t.title}</span>
        {t.active && <CloseX s={12} />}
      </div>
    );
    const CapsuleStrip = () => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, height: 40, padding: '0 10px', flexShrink: 0, borderBottom: HAIR }}>
        {tabs.map((t, i) => <Capsule key={i} t={t} i={i} />)}
        <AddTab />
      </div>
    );

    const isInline = variant === 'inline';
    return (
      <div style={{ width: 1280, height: 800, borderRadius: 12, overflow: 'hidden', background: BG, boxShadow: '0 0 0 1px rgba(0,0,0,0.5), 0 30px 80px rgba(0,0,0,0.5)', display: 'flex', fontFamily: SANS, position: 'relative', padding: 8, boxSizing: 'border-box', gap: 8 }}>
        <style>{caretCSS}</style>

        {/* full-height sidebar — same vault explorer, traffic lights inside */}
        <div style={{ width: 230, flexShrink: 0, ...glassPanel }}>
          <div style={{ height: 44, flexShrink: 0, display: 'flex', alignItems: 'center', padding: '0 16px' }}>
            <TrafficLights />
          </div>
          <VaultSidebarContent />
        </div>

        {/* detail pane */}
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
          {/* toolbar */}
          <div style={{ height: 44, flexShrink: 0, display: 'flex', alignItems: 'center', gap: 8, padding: '0 10px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0 }}>
              <MacBtn name="sidebar" />
              <MacBtn name="back" />
            </div>
            {isInline ? (
              <>
                <div style={{ width: 1, height: 26, background: 'rgba(255,255,255,0.16)', flexShrink: 0, margin: '0 6px' }} />
                <div className="noto-tabscroll" style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 6,
                  overflowX: scrolls ? 'auto' : 'visible', overflowY: 'hidden', scrollbarWidth: 'none',
                  WebkitMaskImage: scrolls ? 'linear-gradient(to right, #000 calc(100% - 26px), transparent)' : 'none' }}>
                  <style>{`.noto-tabscroll::-webkit-scrollbar{display:none}`}</style>
                  {tabs.map((t, i) => <Capsule key={i} t={t} i={i} fixed={scrolls} />)}
                </div>
                <AddTab ml={2} active={picker} />
                <div style={{ width: 1, height: 26, background: 'rgba(255,255,255,0.16)', flexShrink: 0, margin: '0 6px' }} />
              </>
            ) : <div style={{ flex: 1 }} />}
            <div style={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0 }}>
              <MacBtn name="search" />
              <MacBtn name="more" />
            </div>
          </div>

          {/* tab strip (non-inline variants) */}
          {variant === 'bar' && <ClassicBar />}
          {variant === 'capsule' && <CapsuleStrip />}

          {/* editor */}
          <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', paddingTop: 8, paddingLeft: 8, paddingRight: 8 }}>
            <Article editing={false} big={false} />
          </div>
        </div>

        {/* new-tab file picker popover */}
        {picker && <NewTabPicker />}
      </div>
    );
  }

  Object.assign(window, { NotoIPad, NotoMac, NotoMacTabs });
})();
