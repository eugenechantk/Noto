// v7 · Minimalist editor — minimal chrome, real editing surface.
// Three states (prop `state`):
//   • 'editing'  — back/more top bar · note body → live caret · system
//                   keyboard toolbar · iOS keyboard.
//   • 'reading'  — back/more top bar · full note body, no keyboard.
//   • 'scrolled' — translucent top bar carrying the note TITLE, with the
//                   body text scrolling underneath/behind it · no keyboard.
// No bottom dock. No word count. No standalone dismiss button.
//
// Pulls shared chrome from window: ArticleIcon, NotoToolbarArticle,
// IOSDevice, IOSKeyboard.

// HIG sheet-header button — a circular control sized for the nav row.
//   kind 'close'   → translucent Liquid-Glass circle with a neutral ✕
//   kind 'confirm' → filled accent circle with a white ✓
function SheetCircleBtn({ kind = 'close', accent = '#FF6A2E', size = 32 }) {
  const isConfirm = kind === 'confirm';
  const stroke = isConfirm ? '#FFFFFF' : 'rgba(235,235,245,0.65)';
  return (
    <div style={{
      width: size, height: size, borderRadius: 999,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: isConfirm ? accent : 'rgba(118,118,128,0.30)',
      backdropFilter: isConfirm ? 'none' : 'blur(20px) saturate(160%)',
      WebkitBackdropFilter: isConfirm ? 'none' : 'blur(20px) saturate(160%)',
      boxShadow: isConfirm
        ? '0 1px 3px rgba(0,0,0,0.25), inset 0 0.5px 0 rgba(255,255,255,0.35)'
        : 'inset 0 0.5px 0 rgba(255,255,255,0.14)',
      cursor: 'pointer',
    }}>
      <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 20 20" fill="none"
        stroke={stroke} strokeWidth={isConfirm ? 2.4 : 2.2} strokeLinecap="round" strokeLinejoin="round">
        {isConfirm ? <path d="M4 10.5l4 4 8-9" /> : <path d="M5 5l10 10M15 5L5 15" />}
      </svg>
    </div>
  );
}

function NotoMinimalEditor({ state = 'editing' }) {
  const BG    = '#0E1116';
  const INK   = '#ECECEE';
  const HEAD  = '#FFFFFF';
  const FAINT = 'rgba(236,236,238,0.34)';
  const SANS  = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';
  const TITLE = 'How to Build Strong AI Products';

  const isEditing  = state === 'editing';
  const isScrolled = state === 'scrolled';
  // properties surface — several HIG sub-views share the sheet presentation
  const isProperties = state.indexOf('properties') === 0;
  const propView   = state === 'properties-add' ? 'adding' : state === 'properties-delete' ? 'delete' : state === 'properties-edit' ? 'editing' : 'list';
  const showTypeMenu = state === 'properties-menu';
  const propsKeyboard = state === 'properties-add' || state === 'properties-edit';
  const propDetent = (state === 'properties-add' || state === 'properties-menu' || state === 'properties-edit' || state === 'properties-expanded') ? 'large' : 'medium';

  const para = { margin: '14px 0 0', fontFamily: SANS, fontSize: 16, lineHeight: 1.55, color: INK, letterSpacing: -0.1 };
  const h2   = { margin: '20px 0 6px', fontFamily: SANS, fontSize: 18, fontWeight: 700, color: HEAD, letterSpacing: -0.2 };

  const Caret = () => (
    <span className="noto-min-caret" style={{
      display: 'inline-block', width: 2, height: '1.05em',
      background: '#FF6A2E', borderRadius: 1,
      verticalAlign: 'text-bottom', marginLeft: 1, transform: 'translateY(2px)',
    }} />
  );

  // Inline figure — a real-looking note image on the dark surface.
  const Figure = ({ tint, label, caption, h = 92, mt = 14 }) => (
    <figure style={{ margin: mt + 'px 0 0' }}>
      <div style={{
        width: '100%', height: h, borderRadius: 12,
        background: tint, position: 'relative', overflow: 'hidden',
        border: '0.5px solid rgba(255,255,255,0.08)',
        display: 'flex', alignItems: 'flex-end', padding: 10, boxSizing: 'border-box',
      }}>
        <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.22), transparent 60%)' }} />
        <span style={{
          position: 'relative', fontFamily: '"SF Mono", ui-monospace, monospace',
          fontSize: 10.5, letterSpacing: 0.3, color: 'rgba(255,255,255,0.78)',
          background: 'rgba(0,0,0,0.28)', borderRadius: 5, padding: '3px 7px',
        }}>{label}</span>
      </div>
      {caption && (
        <figcaption style={{ margin: '7px 2px 0', fontFamily: SANS, fontSize: 12.5, color: FAINT, letterSpacing: -0.05 }}>{caption}</figcaption>
      )}
    </figure>
  );

  const Bullet = ({ children }) => (<li style={{ margin: '0 0 7px', paddingLeft: 6 }}>{children}</li>);

  // ─── Top bar ──────────────────────────────────────────────────────────
  //   reading/editing: bare back + more, inline, no fill.
  //   scrolled: a top-anchored GRADIENT SCRIM — solid BG at the very top
  //             fading to transparent at the bottom, so body text scrolling
  //             up dissolves into the top. Title + controls ride the scrim.
  const TopBar = () => {
    if (!isScrolled) {
      return (
        <div style={{
          position: 'relative', flexShrink: 0, height: 48, padding: '0 10px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <ArticleIcon name="back" color={HEAD} size={22} />
          </div>
          <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <ArticleIcon name="more" color={HEAD} size={22} />
          </div>
        </div>
      );
    }
    return (
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, zIndex: 8,
        height: 138, pointerEvents: 'none',
        background: 'linear-gradient(to bottom, ' + BG + ' 0%, ' + BG + ' 54%, rgba(14,17,22,0.92) 74%, rgba(14,17,22,0) 100%)',
      }}>
        <div style={{
          position: 'absolute', top: 62, left: 0, right: 0, height: 48,
          padding: '0 10px', display: 'flex', alignItems: 'center', gap: 4,
          pointerEvents: 'auto',
        }}>
          <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <ArticleIcon name="back" color={HEAD} size={22} />
          </div>
          <div style={{ flex: 1, minWidth: 0, textAlign: 'center', padding: '0 4px' }}>
            <span style={{
              color: HEAD, fontFamily: SANS, fontSize: 15, fontWeight: 600, letterSpacing: -0.2,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'block',
            }}>{TITLE}</span>
          </div>
          <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <ArticleIcon name="more" color={HEAD} size={22} />
          </div>
        </div>
      </div>
    );
  };

  // ─── Body content — top of the note (title-first). ────────────────────
  const TopOfNote = () => (
    <>
      <div style={{ color: HEAD, fontFamily: SANS, fontSize: 25, fontWeight: 700, lineHeight: 1.16, letterSpacing: -0.4 }}>
        {TITLE}
      </div>

      <p style={{ ...para, marginTop: 12 }}>
        A field guide for founders shipping AI features in 2026 — what makes a
        product compound, and what makes it flame out after launch week.
      </p>

      <Figure tint="linear-gradient(135deg, #FF6A2E 0%, #C2185B 55%, #4A148C 100%)" label="cover.png" h={84} mt={14} />

      <h2 style={h2}>The three deposits</h2>
      <p style={para}>Every interaction should leave behind a deposit:</p>
      <ul style={{ margin: '8px 0 0', paddingLeft: 22, fontFamily: SANS, fontSize: 16, lineHeight: 1.5, color: INK, letterSpacing: -0.1 }}>
        <Bullet><strong style={{ color: HEAD, fontWeight: 600 }}>Memory</strong> — what it remembers about you and your work.</Bullet>
        <Bullet><strong style={{ color: HEAD, fontWeight: 600 }}>Preference</strong> — your corrections, encoded once.</Bullet>
        <Bullet><strong style={{ color: HEAD, fontWeight: 600 }}>Taste</strong> — the rough shape of what you call “good.”</Bullet>
      </ul>

      <p style={para}>
        None of these require a frontier model — only a product that treats every
        discarded draft as signal rather than exhaust{isEditing ? <Caret /> : '.'}
      </p>
    </>
  );

  // ─── Body content — scrolled deep into the note (mid-paragraph at top so
  //     real text tucks up behind the translucent bar). ──────────────────
  const ScrolledNote = () => (
    <>
      <p style={{ ...para, marginTop: 0 }}>
        loop that matters is the one where the system gets measurably better at
        helping <em style={{ fontStyle: 'italic' }}>you</em> specifically — not
        better in the aggregate, better for you. When the loop is tight, every
        session deposits something the next one can draw on.
      </p>

      <h2 style={h2}>The three deposits</h2>
      <p style={para}>Every interaction should leave behind a deposit:</p>
      <ul style={{ margin: '8px 0 0', paddingLeft: 22, fontFamily: SANS, fontSize: 16, lineHeight: 1.5, color: INK, letterSpacing: -0.1 }}>
        <Bullet><strong style={{ color: HEAD, fontWeight: 600 }}>Memory</strong> — what it remembers about you and your work.</Bullet>
        <Bullet><strong style={{ color: HEAD, fontWeight: 600 }}>Preference</strong> — your corrections, encoded once.</Bullet>
        <Bullet><strong style={{ color: HEAD, fontWeight: 600 }}>Taste</strong> — the rough shape of what you call “good.”</Bullet>
      </ul>

      <Figure tint="linear-gradient(135deg, #1F6FEB 0%, #163172 100%)" label="retention-curve.png" caption="Day-30 retention, two cohorts: compounding vs. novelty." h={150} />

      <h2 style={h2}>Why the model layer is interchangeable</h2>
      <p style={para}>
        Two years from now you’ll still have a usable product even if you swap the
        underlying weights — provided the deposits survive the swap.
      </p>
    </>
  );

  const Surface = () => (
    <div style={{
      flex: 1, minHeight: 0, overflow: 'hidden', position: 'relative',
      padding: isScrolled ? '2px 24px 0' : '6px 24px 0',
    }}>
      {isScrolled ? <ScrolledNote /> : <TopOfNote />}

      {/* below the fold for the top-of-note states — gives real length */}
      {!isEditing && !isScrolled && (
        <>
          <Figure tint="linear-gradient(135deg, #1F6FEB 0%, #163172 100%)" label="retention-curve.png" caption="Day-30 retention, two cohorts: compounding vs. novelty." h={150} />
          <h2 style={h2}>Why the model layer is interchangeable</h2>
          <p style={para}>
            Two years from now you’ll still have a usable product even if you swap the
            underlying weights — provided the deposits survive the swap.
          </p>
        </>
      )}

      {/* fade the long body out toward the bottom edge when no keyboard */}
      {!isEditing && (
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 64, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', pointerEvents: 'none' }} />
      )}
    </div>
  );

  // ─── 'properties' — the editor recedes onto black and a Properties sheet
  //     slides up over it (Apple HIG sheet presentation). Sub-views:
  //     list · type menu · adding (key field) · swipe-to-delete. ──────────
  if (isProperties) {
    const ACCENT = '#FF6A2E';
    return (
      <IOSDevice dark={true} background="#000">
        <div style={{ height: '100%', position: 'relative', fontFamily: SANS }}>
          {/* receded presenting editor — scaled back + dimmed onto black */}
          <div style={{
            position: 'absolute', inset: 0, borderRadius: 40, overflow: 'hidden', background: BG,
            transform: 'scale(0.93) translateY(-10px)', transformOrigin: 'top center',
          }}>
            <div style={{ height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
              <div style={{ height: 62, flexShrink: 0 }} />
              <TopBar />
              <Surface />
            </div>
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.5)' }} />
          </div>

          {/* the Properties sheet (grouped material as the sheet background).
              HIG sheet header: paired circular buttons — glass Close (✕) on
              the leading edge, filled orange confirm (✓) on the trailing. */}
          <IOSSheet
            dark detent={propDetent} height={874}
            title="Properties"
            leading={<SheetCircleBtn kind="close" />}
            trailing={<SheetCircleBtn kind="confirm" accent={ACCENT} />}
            accent={ACCENT} material={window.NOTO_HIG.SHEET_BG} divider={false}
          >
            <NotoPropertyList view={propView} />
          </IOSSheet>

          {/* pull-down TYPE MENU — dimmed scrim + floating menu, drops down
              directly below the Add property row (which sits at ~y490 in the
              large detent), overlaying the list without reflowing it. */}
          {showTypeMenu && (
            <div style={{ position: 'absolute', inset: 0, zIndex: 50 }}>
              <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.22)' }} />
              <div style={{ position: 'absolute', left: 16, top: 494 }}>
                <NotoTypeMenu />
              </div>
            </div>
          )}

          {/* keyboard rises while naming the new property's key */}
          {propsKeyboard && (
            <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 60 }}>
              <IOSKeyboard dark={true} />
            </div>
          )}
        </div>
      </IOSDevice>
    );
  }

  // ─── 'notelist' — a minimal, navigable FILE SYSTEM (notes + folders).
  //     Large iOS title collapses into the translucent top bar on scroll;
  //     folders carry a single trailing chevron (the only affordance), notes
  //     are plain title-only rows. Two levels: root ('notelist') and a
  //     drilled-in folder ('notelist-captures') with a back button. ────────
  if (state.indexOf('notelist') === 0) {
    const FS = {
      root: {
        title: 'Notes', back: null,
        items: [
          { type: 'folder', name: 'Daily Notes' },
          { type: 'folder', name: 'Projects' },
          { type: 'folder', name: 'Captures' },
          { type: 'note', name: 'Reflection 2025' },
        ],
      },
      captures: {
        title: 'Captures', back: 'Notes',
        items: [
          { type: 'note', name: 'How to Build Strong AI Products' },
          { type: 'note', name: 'Weekly review — Mar 11' },
          { type: 'note', name: 'Compounding deposits' },
          { type: 'note', name: 'Dan Koe — 1 day exercise' },
          { type: 'note', name: 'What is my definition of a ‘great’ life' },
        ],
      },
      projects: {
        title: 'Projects', back: 'Notes',
        items: [
          { type: 'folder', name: 'Project Alpha' },
          { type: 'folder', name: 'Project Beta' },
          { type: 'folder', name: 'Archive' },
          { type: 'note', name: 'Hiring plan' },
          { type: 'note', name: 'Roadmap Q2' },
        ],
      },
    };
    const level = state === 'notelist-captures' ? FS.captures : state === 'notelist-projects' ? FS.projects : FS.root;
    // ordering rule: subdirectories first, then notes; alphabetical within each group
    const byName = (a, b) => a.name.localeCompare(b.name);
    const orderedItems = [
      ...level.items.filter(it => it.type === 'folder').sort(byName),
      ...level.items.filter(it => it.type === 'note').sort(byName),
    ];
    const Plus = () => (
      <svg width="25" height="25" viewBox="0 0 24 24" fill="none" stroke={HEAD} strokeWidth="1.7" strokeLinecap="round">
        <path d="M12 5.5v13M5.5 12h13" />
      </svg>
    );
    const FolderChevron = () => (
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={FAINT} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
        <path d="M9 6l6 6-6 6" />
      </svg>
    );
    return (
      <IOSDevice dark={true} background={BG}>
        <div style={{ height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
          <div style={{ height: 62, flexShrink: 0 }} />

          {/* nav bar — back (if nested) on the leading edge, subtle + trailing */}
          <div style={{ position: 'relative', flexShrink: 0, height: 48, padding: '0 10px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 1, minWidth: 36, height: 36 }}>
              {level.back && (
                <>
                  <ArticleIcon name="back" color={HEAD} size={22} />
                  <span style={{ color: HEAD, fontFamily: SANS, fontSize: 17, letterSpacing: -0.2 }}>{level.back}</span>
                </>
              )}
            </div>
            <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Plus />
            </div>
          </div>

          {/* large title + single-line rows */}
          <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '2px 24px 0' }}>
            <div style={{ color: HEAD, fontFamily: SANS, fontSize: 33, fontWeight: 700, letterSpacing: -0.7, padding: '2px 0 12px' }}>
              {level.title}
            </div>
            {orderedItems.map((it, i) => (
              <div key={i} style={{ position: 'relative', minHeight: 44, display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ flex: 1, minWidth: 0, color: INK, fontFamily: SANS, fontSize: 17, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{it.name}</span>
                {it.type === 'folder' && <FolderChevron />}
                {i < orderedItems.length - 1 && (
                  <div style={{ position: 'absolute', left: 0, right: -24, bottom: 0, height: 0.5, background: 'rgba(236,236,238,0.10)' }} />
                )}
              </div>
            ))}
          </div>
        </div>
      </IOSDevice>
    );
  }

  return (
    <IOSDevice dark={true} background={BG}>
      <style>{`
        @keyframes notoMinCaretBlink { 0%,48% { opacity: 1 } 52%,100% { opacity: 0 } }
        .noto-min-caret { animation: notoMinCaretBlink 1.05s steps(1,end) infinite; }
      `}</style>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
        {/* reserve space for the absolutely-positioned status bar */}
        <div style={{ height: 62, flexShrink: 0 }} />
        {!isScrolled && <TopBar />}
        <Surface />
        {isScrolled && <TopBar />}
        {/* editor now carries the floating dock (daily · search · chat · new),
            hidden while typing where the keyboard toolbar takes over */}
        {!isEditing && <window.FloatingDock noSidebar={true} />}
        {isEditing && <NotoToolbarArticle wordCount={258} activeKey={null} />}
        {isEditing && <IOSKeyboard dark={true} />}
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { NotoMinimalEditor });
