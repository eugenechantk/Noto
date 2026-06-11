// noto-notabs-screens.jsx
// ─────────────────────────────────────────────────────────────
// Two extra screens carried into the No-Tabs floating-dock iteration:
//   1. NoTabsNoteList   — vault file explorer (traversable folder tree)
//   2. NoTabsFindInText — find-within-the-note (glass find bar + keyboard)
//
// Same visual system as Exp03ArticleV3Dock / the properties screen: the bare
// back·forward·more top bar, Liquid-Glass capsules, orange accent, no tabs.
// Depends on ArticleIcon, IOSDevice, IOSKeyboard, NOTE — all on window.

(function () {
  const BG     = '#0E1116';
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const MUTED  = 'rgba(236,236,238,0.62)';
  const FAINT  = 'rgba(236,236,238,0.34)';
  const RULE   = 'rgba(255,255,255,0.08)';
  const ACCENT = '#FF6A2E';
  const HL     = 'rgba(230,182,42,0.32)';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  const glassStyle = {
    background: 'rgba(28,30,36,0.55)',
    backdropFilter: 'blur(28px) saturate(180%)',
    WebkitBackdropFilter: 'blur(28px) saturate(180%)',
    border: '0.5px solid rgba(255,255,255,0.10)',
    boxShadow: [
      '0 1px 1px rgba(0,0,0,0.18)',
      '0 8px 24px rgba(0,0,0,0.32)',
      'inset 0 0.5px 0 rgba(255,255,255,0.22)',
      'inset 0 -0.5px 0 rgba(0,0,0,0.25)',
    ].join(', '),
  };

  // ─── Canonical top bar — identical to the dock / properties screens:
  //     back · forward (left) · spacer · more (right). No glass, no title.
  const TopBar = () => (
    <div style={{
      position: 'absolute', left: 0, right: 0, top: 62, height: 48,
      padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, zIndex: 10,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
        <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="back" color={HEAD} size={20} />
        </div>
        <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="forward" color={FAINT} size={20} />
        </div>
      </div>
      <div style={{ flex: 1 }} />
      <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <ArticleIcon name="more" color={HEAD} size={20} />
      </div>
    </div>
  );

  // ─── Bottom floating dock — no-tabs. `noSidebar` drops the sidebar button
  //     (used in the file explorer, which IS the sidebar): today · search · new
  const FloatingDock = ({ noSidebar = false }) => (
    <div style={{
      flexShrink: 0, padding: '6px 12px 34px',
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <div style={{ ...glassStyle, height: 52, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center', flexShrink: 0 }}>
        {!noSidebar && (
          <>
            <div style={{ width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <ArticleIcon name="sidebar" color={HEAD} size={22} />
            </div>
            <div style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.10)' }} />
          </>
        )}
        <div style={{ width: 44, height: 44, borderRadius: 999, position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3.5" y="4.5" width="15" height="13" rx="2.4" />
            <path d="M3.5 8.5h15" />
            <path d="M7 3v3M15 3v3" />
          </svg>
          <span style={{ position: 'absolute', left: 0, right: 0, top: 21, textAlign: 'center', color: HEAD, fontFamily: SANS, fontSize: 8, fontWeight: 700, pointerEvents: 'none' }}>7</span>
        </div>
      </div>
      <div style={{ ...glassStyle, flex: 1, height: 52, borderRadius: 999, padding: '0 18px', gap: 10, display: 'flex', alignItems: 'center' }}>
        <ArticleIcon name="search" color={MUTED} size={19} />
        <span style={{ color: MUTED, fontFamily: SANS, fontSize: 16, flex: 1, minWidth: 0 }}>Search</span>
      </div>
      <div style={{ ...glassStyle, height: 52, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center', flexShrink: 0 }}>
        <div style={{ width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3.5 5.5a1.8 1.8 0 011.8-1.8h11.4a1.8 1.8 0 011.8 1.8v6.2a1.8 1.8 0 01-1.8 1.8H9.8l-3.6 2.8v-2.8H5.3a1.8 1.8 0 01-1.8-1.8V5.5z" />
          </svg>
        </div>
        <div style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.10)' }} />
        <div style={{
          width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'rgba(255,106,46,0.22)', border: '0.5px solid rgba(255,106,46,0.40)',
        }}>
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke={HEAD} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9.5 4H5.5a2 2 0 00-2 2v10.5a2 2 0 002 2h10.5a2 2 0 002-2V12.5" />
            <path d="M15 3.5l3.5 3.5L11 14.5H7.5V11L15 3.5z" />
          </svg>
        </div>
      </div>
    </div>
  );

  // ════════════════════════════════════════════════════════════
  // 1 · NOTE LIST — vault file explorer (one level per page)
  //   Each page shows ONLY the immediate subfolders + files of one folder.
  //   Tapping a folder pushes the next level; the labelled back button in the
  //   top bar returns to the parent — standard iOS push navigation.
  // ════════════════════════════════════════════════════════════
  const folderGlyph = (color) => (
    <svg width="20" height="20" viewBox="0 0 18 18" fill={color} stroke="none">
      <path d="M2 5a1.6 1.6 0 011.6-1.6h2.9c.55 0 1.06.28 1.36.74l.5.76c.3.46.8.74 1.36.74h4.7A1.6 1.6 0 0116 7v6A1.6 1.6 0 0114.4 14.6H3.6A1.6 1.6 0 012 13V5z" />
    </svg>
  );
  const fileGlyph = (color) => (
    <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 1.5h5l3 3V13a1 1 0 01-1 1H4a1 1 0 01-1-1V2.5a1 1 0 011-1z" />
      <path d="M9 1.5v3h3" />
    </svg>
  );

  // The vault, keyed by folder id. Each entry lists ONLY its direct children.
  const VAULT = {
    root: {
      name: 'Vault', parent: null,
      folders: [
        { id: 'captures',   name: 'Captures',   count: 12 },
        { id: 'journal',    name: 'Journal',    count: 16 },
        { id: 'highlights', name: 'Highlights', count: 31 },
        { id: 'drafts',     name: 'Drafts',     count: 7 },
        { id: 'projects',   name: 'Projects',   count: 9 },
      ],
      files: [
        { name: '_INBOX',     when: '1w ago' },
        { name: 'Scratchpad', when: '3w ago' },
      ],
    },
    captures: {
      name: 'Captures', parent: 'root', parentName: 'Vault',
      folders: [
        { id: 'ai-products', name: 'AI Products', count: 4 },
      ],
      files: [
        { name: 'How to Build Strong AI Products',          when: '2h ago', active: true },
        { name: 'Dan Koe — the 1-day reset',                when: '2d ago' },
        { name: 'What is my definition of a “great” life',  when: '3d ago' },
        { name: 'Why Vertical LLM Agents Are The New Moat', when: '4d ago' },
      ],
    },
    'ai-products': {
      name: 'AI Products', parent: 'captures', parentName: 'Captures',
      folders: [],
      files: [
        { name: 'Field guide outline',      when: '5d ago' },
        { name: 'Pricing experiments · Q1', when: 'Mar 4' },
        { name: 'The three deposits',       when: 'Mar 2' },
      ],
    },
  };

  // Explorer top bar — minimal navigation toolbar: a leading back button to the
  // parent level (when there is one) and trailing actions, all as bare
  // icon/text bar buttons (no glass pill).
  const ExplorerTopBar = ({ folder }) => {
    const f = VAULT[folder];
    return (
      <div style={{
        position: 'absolute', left: 0, right: 0, top: 60, height: 48,
        padding: '0 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, zIndex: 10,
      }}>
        {/* leading — back button */}
        {f.parent ? (
          <button style={{ display: 'flex', alignItems: 'center', gap: 1, background: 'none', border: 'none', padding: 0, cursor: 'pointer', flexShrink: 0, maxWidth: 200 }}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={ACCENT} strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round"><path d="M14 6l-6 6 6 6" /></svg>
            <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 16, fontWeight: 500, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{f.parentName}</span>
          </button>
        ) : <span />}

        {/* trailing — actions: new folder · sort · more */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 18, flexShrink: 0 }}>
          <svg width="20" height="20" viewBox="0 0 18 18" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="M2 5.5a1.6 1.6 0 011.6-1.6h2.6c.5 0 1 .26 1.3.7l.5.7c.3.44.8.7 1.3.7H14.4A1.6 1.6 0 0116 7.6V13a1.6 1.6 0 01-1.6 1.6H3.6A1.6 1.6 0 012 13V5.5z" />
            <path d="M9 8.4v3.4M7.3 10.1h3.4" />
          </svg>
          <svg width="19" height="19" viewBox="0 0 16 16" fill="none" stroke={HEAD} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 4.5h10M4.5 8h7M6.5 11.5h3" />
          </svg>
          <ArticleIcon name="more" color={HEAD} size={20} />
        </div>
      </div>
    );
  };

  const FolderRow = ({ fo, last }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 20px', borderBottom: last ? 'none' : '0.5px solid ' + RULE }}>
      <span style={{ flexShrink: 0, display: 'inline-flex' }}>{folderGlyph('rgba(236,236,238,0.80)')}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: HEAD, fontFamily: SANS, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{fo.name}</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12.5, marginTop: 2 }}>{fo.count} items</div>
      </div>
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke={FAINT} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M6 3l5 5-5 5" /></svg>
    </div>
  );

  const FileRow = ({ fi, last }) => (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 13, padding: '13px 20px',
      borderBottom: last ? 'none' : '0.5px solid ' + RULE,
      ...(fi.active ? { background: 'rgba(255,106,46,0.10)' } : {}),
    }}>
      <span style={{ flexShrink: 0, display: 'inline-flex' }}>{fileGlyph(fi.active ? ACCENT : MUTED)}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ color: fi.active ? HEAD : INK, fontFamily: SANS, fontSize: 15.5, fontWeight: fi.active ? 600 : 500, letterSpacing: -0.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{fi.name}</div>
        <div style={{ color: MUTED, fontFamily: SANS, fontSize: 12.5, marginTop: 2 }}>Edited {fi.when}</div>
      </div>
    </div>
  );

  function NoTabsNoteList({ folder = 'root' }) {
    const f = VAULT[folder];
    const nFolders = f.folders.length;
    const nFiles = f.files.length;
    const sub = [
      nFolders ? nFolders + ' folder' + (nFolders > 1 ? 's' : '') : null,
      nFiles ? nFiles + ' note' + (nFiles > 1 ? 's' : '') : null,
    ].filter(Boolean).join(' · ');

    return (
      <IOSDevice dark={true} background={BG}>
        <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, position: 'relative', background: BG }}>
          <ExplorerTopBar folder={folder} />

          <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '116px 0 0' }}>
            {/* large folder title + counts (HIG large-title; actions live in the toolbar) */}
            <div style={{ padding: '0 20px 10px' }}>
              <div style={{ color: HEAD, fontFamily: SANS, fontSize: 28, fontWeight: 700, letterSpacing: -0.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{f.name}</div>
              <div style={{ color: MUTED, fontFamily: SANS, fontSize: 13, marginTop: 3 }}>{sub}</div>
            </div>

            <div style={{ height: 0.5, background: RULE }} />

            {/* immediate subfolders, then immediate files */}
            {f.folders.map((fo, i) => <FolderRow key={'fo' + i} fo={fo} last={false} />)}
            {f.files.map((fi, i) => <FileRow key={'fi' + i} fi={fi} last={i === nFiles - 1} />)}
          </div>

          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 92, height: 40, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', pointerEvents: 'none', zIndex: 5 }} />

          <FloatingDock noSidebar={true} />
        </div>
      </IOSDevice>
    );
  }

  // ════════════════════════════════════════════════════════════
  // 2 · FIND IN TEXT — search within the open note
  // ════════════════════════════════════════════════════════════
  // glass find bar floating above the keyboard. `count` = total matches.
  const FindBar = ({ count }) => (
    <div style={{ flexShrink: 0, padding: '8px 12px 10px', display: 'flex', alignItems: 'center', gap: 8 }}>
      <div style={{ ...glassStyle, flex: 1, height: 48, borderRadius: 999, padding: '0 8px 0 16px', gap: 8, display: 'flex', alignItems: 'center' }}>
        <ArticleIcon name="search" color={MUTED} size={18} />
        <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', color: HEAD, fontFamily: SANS, fontSize: 16, fontWeight: 500 }}>
          <span>compound</span>
          <span style={{ display: 'inline-block', width: 1.5, height: 18, background: ACCENT, marginLeft: 2 }} />
        </div>
        <span style={{ color: MUTED, fontFamily: SANS, fontSize: 13, fontVariantNumeric: 'tabular-nums', flexShrink: 0 }}>{'1 / ' + count}</span>
        <div style={{ width: 34, height: 34, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <svg width="15" height="15" viewBox="0 0 14 14" fill="none" stroke={INK} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M3 9l4-4 4 4" /></svg>
        </div>
        <div style={{ width: 34, height: 34, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <svg width="15" height="15" viewBox="0 0 14 14" fill="none" stroke={INK} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M3 5l4 4 4-4" /></svg>
        </div>
      </div>
      <div style={{ ...glassStyle, height: 48, borderRadius: 999, padding: '0 18px', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 16, fontWeight: 600 }}>Done</span>
      </div>
    </div>
  );

  function NoTabsFindInText() {
    const matches = window.countCompound();
    const hl = window.makeCompoundHL(); // shared across lede + body so first hit is active
    return (
      <IOSDevice dark={true} background={BG}>
        <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, position: 'relative', background: BG }}>
          <TopBar />

          <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '116px 22px 0', position: 'relative' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: MUTED, fontSize: 12, marginBottom: 14 }}>
              <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke={MUTED} strokeWidth="1.6" strokeLinecap="round"><path d="M2.5 4l3 3 3-3" /></svg>
              <span>11 properties</span>
              <span style={{ flex: 1, height: 0.5, background: RULE }} />
              <span style={{ color: ACCENT, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{matches + ' matches'}</span>
            </div>

            <div style={{ color: HEAD, fontSize: 24, fontWeight: 700, lineHeight: 1.15, letterSpacing: -0.3 }}>{NOTE.title}</div>
            <p style={{ margin: '14px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>{hl(window.NOTO_LEDE)}</p>

            <div style={{
              marginTop: 18, height: 120,
              background: 'linear-gradient(135deg, #FF6A2E 0%, #C2185B 45%, #4A148C 100%)',
              borderRadius: 12, border: '0.5px solid ' + RULE, position: 'relative', overflow: 'hidden',
            }}>
              <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 80% 0%, rgba(255,255,255,0.22), transparent 60%)' }} />
            </div>

            <div style={{ marginTop: 16 }}>{window.renderNotoDoc({ from: 0, hl })}</div>

            {/* fade the body to BG so the translucent find bar samples clean background */}
            <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 52, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', pointerEvents: 'none' }} />
          </div>

          <FindBar count={matches} />
          <IOSKeyboard dark={true} />
        </div>
      </IOSDevice>
    );
  }

  Object.assign(window, { NoTabsNoteList, NoTabsFindInText, FloatingDock });
})();
