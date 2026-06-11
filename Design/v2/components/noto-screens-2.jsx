// Noto baseline screens — batch 2: realistic editor, search, settings, find,
// mention (iPhone variants). Depends on noto-shared.jsx + noto-shared-2.jsx.

// Reusable iPhone status-bar header (time 6:56)
function PhoneTop() {
  return <NStatusBar time="6:56" right={['signal','wifi','battery']} />;
}
function PhoneIsland() {
  return (
    <div style={{
      position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
      width: 124, height: 36, borderRadius: 22, background: '#000', zIndex: 5,
    }} />
  );
}
function PhoneHomeIndicator() {
  return (
    <div style={{
      position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
      width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.55)',
    }} />
  );
}
function PhoneBottomCapsule() {
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 28,
      display: 'flex', justifyContent: 'center', zIndex: 4,
    }}>
      <NFloatingCapsule />
    </div>
  );
}

// Editor top-chrome row: back · Noto › Captures · more (used in realistic
// editor + find/mention overlays)
function PhoneEditorChrome({ dim = false }) {
  const op = dim ? { opacity: 0.4 } : null;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 18px 8px', ...op,
    }}>
      <NCircle icon="chevron-left" size={40} iconSize={20} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: NOTO.fgMuted, fontSize: 14 }}>
        <span>Noto</span>
        <NIcon name="caret-right" size={12} color={NOTO.fgMuted} />
        <span style={{ color: NOTO.fg, fontWeight: 600 }}>Captures</span>
      </div>
      <NCircle icon="ellipsis" size={40} iconSize={20} />
    </div>
  );
}

// Shared body block for the "How to Build Strong AI Products" note,
// adapted to a phone column. Accepts highlights for find-in-note.
function PhoneEditorBody({ highlights = [] }) {
  return (
    <div style={{ padding: '14px 18px 0' }}>
      <NMetaAccordion count={11} />

      <NHeading level={1} marginTop={26}>How to Build Strong AI Products</NHeading>

      <NRichBody marginTop={28} fontSize={15} parts={[
        'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.',
      ]} highlights={highlights} />

      <NImagePlaceholder marginTop={24} height={200} label="1200 × 500" />

      <NRichBody marginTop={26} fontSize={15} parts={[
        'The defining question for AI products in 2026 is no longer ',
        { italic: 'can we build it?' },
        ' \u2014 model capability has caught up to ambition. The harder question is ',
        { italic: 'what does this become once people use it every day?' },
        ' As ',
        { link: 'Sahil Lavingia recently argued' },
        ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap. That distinction is doing a lot ',
      ]} highlights={highlights} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPhone 02b — Editor with realistic content (replaces minimal #02)
// ─────────────────────────────────────────────────────────────
function ScreenPhoneEditorRealistic() {
  const W = 402, H = 874;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <PhoneTop />
      <PhoneIsland />
      <PhoneEditorChrome />
      <PhoneEditorBody />
      <PhoneBottomCapsule />
      <PhoneHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPhone 03 — Search modal (with query + results)
// ─────────────────────────────────────────────────────────────
function ScreenPhoneSearch() {
  const W = 402, H = 874;
  const results = [
    {
      title: 'Two Powerful Claude Code Plugins: gst\u2026',
      path: 'Captures/Two Powerful Claude Code Plugins gstack vs\u2026',
      heading: 'You end up with the speed of gstack\u2019s',
      body: 'opinionated defaults and the compounding qu\u2026',
    },
    {
      title: '21 Lessons From 14 Years at Google',
      path: 'Captures/21 Lessons From 14 Years at Google.md/## 21\u2026',
      heading: '\u2026There are no shortcuts, but there is',
      body: 'compounding\u2026.',
    },
    {
      title: 'How to Build Strong AI Products',
      path: 'Captures/How to Build Strong AI Products.md/## The c\u2026',
      heading: 'The compounding loop',
      body: 'A compounding product feels different when\u2026',
    },
    {
      title: 'I Stored 100 Prompts in Obsidian and L\u2026',
      path: 'Captures/I Stored 100 Prompts in Obsidian and Let Clau\u2026',
      heading: 'The Compounding Effect Nobody Talks About',
      body: 'Here\u2019s the part that doesn\u2019t get enough attent\u2026',
    },
    {
      title: '\uD83D\uDCE6 do you understand what two Anthrop\u2026',
      path: 'Captures/\uD83D\uDCE6 do you understand what two Anthropic eng\u2026',
      heading: 'While most traders ignored them, this account',
      body: 'executed thousands of small probabilistic edg\u2026',
    },
    {
      title: 'Step-by-step guide to get Ralph workin\u2026',
      path: 'Captures/Step-by-step guide to get Ralph working and\u2026',
      heading: '',
      body: '',
    },
  ];
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <PhoneTop />
      <PhoneIsland />

      {/* sheet grab handle */}
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 6 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.28)' }} />
      </div>

      {/* search field row + close */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '18px 18px 14px',
      }}>
        <div style={{ flex: 1 }}>
          <NSearchField value="Compounding" />
        </div>
        <NCircle icon="plus" size={40} iconSize={18} color={NOTO.fg} />
        <div style={{
          position: 'absolute', right: 18, top: 26, width: 40, height: 40, borderRadius: 20,
          background: NOTO.pill, display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="14" height="14" viewBox="0 0 14 14" stroke="#fff" strokeWidth="1.8" strokeLinecap="round">
            <path d="M3 3l8 8M11 3l-8 8" />
          </svg>
        </div>
      </div>

      {/* segmented control */}
      <div style={{ padding: '0 18px 8px' }}>
        <NSegmented selected={0} options={[
          { label: 'Title + Content', kbd: '\u23181' },
          { label: 'Title',           kbd: '\u23182' },
        ]} />
      </div>

      {/* results */}
      <div style={{ marginTop: 6 }}>
        {results.map((r, i) => (
          <NSearchResult key={i} title={r.title} path={r.path}
            headingMatch={r.heading} body={r.body} />
        ))}
      </div>

      <PhoneHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPhone 04 — Settings
// ─────────────────────────────────────────────────────────────
function ScreenPhoneSettings() {
  const W = 402, H = 874;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <PhoneTop />
      <PhoneIsland />

      {/* top chrome */}
      <div style={{
        display: 'flex', alignItems: 'center', padding: '6px 18px 14px',
      }}>
        <NCircle icon="chevron-left" size={40} iconSize={20} />
        <div style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, marginLeft: -40 }}>Settings</div>
      </div>

      {/* Storage */}
      <NSettingsLabel marginTop={6}>Storage</NSettingsLabel>
      <NSettingsGroup>
        <NSettingsRow title="Vault Location" subtitle="On This Device" />
        <NSettingsRow iconNode={<NRefreshIcon size={20} color={NOTO.fg} />} title="Change Vault" isLast />
      </NSettingsGroup>
      <NSettingsHelper>
        Changing your vault returns you to the welcome screen where you can create or open a different vault.
      </NSettingsHelper>

      {/* Search */}
      <NSettingsLabel>Search</NSettingsLabel>
      <NSettingsGroup>
        <NSettingsRow iconNode={
          <div style={{ width: 22, height: 22, borderRadius: 11, border: `1.4px solid ${NOTO.fg}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <NRefreshIcon size={13} color={NOTO.fg} />
          </div>
        } title="Refresh search index" isLast />
      </NSettingsGroup>
      <NSettingsHelper>
        Deletes the local search database and re-indexes every note in the vault. Use this if mention or search results look stale.
      </NSettingsHelper>

      {/* Readwise Sync */}
      <NSettingsLabel>Readwise Sync</NSettingsLabel>
      <NSettingsGroup>
        <NSettingsRow title="Set Token" />
        <NSettingsRow title="Test Connection" />
        <NSettingsRow title="Sync Now" isLast />
      </NSettingsGroup>
      <NSettingsHelper>
        Token saved in secure storage.<br />
        Last sync: 1 Reader save and 1 Readwise save.<br />
        Last synced: May 14, 2026 at 7:35 PM
      </NSettingsHelper>

      <PhoneBottomCapsule />
      <PhoneHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPhone 05 — Find in note (pill find bar over editor)
// ─────────────────────────────────────────────────────────────
function ScreenPhoneFind() {
  const W = 402, H = 874;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <PhoneTop />
      <PhoneIsland />
      <PhoneEditorChrome />
      <PhoneEditorBody highlights={[{ word: 'compound', active: true }]} />

      {/* dim editor slightly, then float find bar on top */}
      <div style={{
        position: 'absolute', top: 110, left: 18, right: 18,
        display: 'flex', alignItems: 'center', gap: 10, zIndex: 6,
      }}>
        <div style={{
          flex: 1, height: 40, borderRadius: 20, background: NOTO.pill,
          boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.08), 0 8px 20px rgba(0,0,0,0.6)',
          display: 'flex', alignItems: 'center', padding: '0 12px', gap: 10,
        }}>
          <NIcon name="search" size={15} color={NOTO.fgMuted} strokeWidth={1.7} />
          <div style={{ flex: 1, color: NOTO.fg, fontSize: 15, display: 'flex', alignItems: 'center' }}>
            compound
            <span style={{ display: 'inline-block', width: 1.5, height: 16, background: '#4DA3FF', marginLeft: 2 }} />
          </div>
          <div style={{
            width: 20, height: 20, borderRadius: 10, background: 'rgba(255,255,255,0.22)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="9" height="9" viewBox="0 0 10 10" stroke="#1A1A1A" strokeWidth="1.8" strokeLinecap="round">
              <path d="M2 2l6 6M8 2l-6 6" />
            </svg>
          </div>
          <div style={{ width: 1, height: 20, background: 'rgba(255,255,255,0.15)' }} />
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={NOTO.fg} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 9l4-4 4 4" />
          </svg>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={NOTO.fg} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 5l4 4 4-4" />
          </svg>
        </div>
        <NCircle icon="plus" size={36} iconSize={14} />
        {/* swap plus for an actual × overlay */}
        <div style={{
          position: 'absolute', right: 0, top: 0, width: 36, height: 36, borderRadius: 18,
          background: NOTO.pill, display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="13" height="13" viewBox="0 0 14 14" stroke="#fff" strokeWidth="1.8" strokeLinecap="round">
            <path d="M3 3l8 8M11 3l-8 8" />
          </svg>
        </div>
      </div>

      <PhoneBottomCapsule />
      <PhoneHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPhone 06 — Mention menu (bottom sheet, populated)
// ─────────────────────────────────────────────────────────────
function ScreenPhoneMention() {
  const W = 402, H = 874;
  const SHEET_TOP = 408;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <PhoneTop />
      <PhoneIsland />

      {/* dimmed editor underneath */}
      <div style={{ opacity: 0.35 }}>
        <PhoneEditorChrome />
        <div style={{ padding: '14px 18px 0' }}>
          <NMetaAccordion count={11} />
          <NHeading level={1} marginTop={26}>How to Build Strong AI Products</NHeading>
          <NRichBody marginTop={28} fontSize={15} parts={[
            'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.',
          ]} />
        </div>
      </div>

      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, top: SHEET_TOP, bottom: 0,
        background: '#0E0E10',
        borderTopLeftRadius: 18, borderTopRightRadius: 18,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.5)',
        zIndex: 6,
      }}>
        {/* grab handle */}
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.28)' }} />
        </div>
        {/* header: title + close */}
        <div style={{
          display: 'flex', alignItems: 'center', padding: '18px 18px 12px',
        }}>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, letterSpacing: -0.2 }}>Mention Document</div>
          <div style={{
            position: 'absolute', right: 18, top: 22, width: 32, height: 32, borderRadius: 16,
            background: NOTO.pill, display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="12" height="12" viewBox="0 0 14 14" stroke="#fff" strokeWidth="1.8" strokeLinecap="round">
              <path d="M3 3l8 8M11 3l-8 8" />
            </svg>
          </div>
        </div>
        {/* search field */}
        <div style={{ padding: '0 18px 12px' }}>
          <NSearchField value="meet" />
        </div>
        {/* results */}
        <NMentionRow title="Meeting Notes" path="Meeting Notes.md" />
        <NMentionRow title="Pocket (@heypocket) is your notetaker for real world meetings"
          path="Captures/Pocket (@heypocket) is your notetaker for real world meetings.md" />
        <NMentionRow title="Meet 19 startups in social networking, dating, and AI that investors have their eyes on"
          path="Captures/Meet 19 startups in social networking, dating, and AI that investors have their eyes on.md" />
        <NMentionRow title="Sometimes the reason you can’t find people you resonate with is because you misread the ones you meet"
          path="Captures/Sometimes the reason you can’t find people you resonate with is because you misread the ones you mee.md" />
      </div>

      <PhoneHomeIndicator />
    </div>
  );
}

Object.assign(window, {
  ScreenPhoneEditorRealistic,
  ScreenPhoneSearch,
  ScreenPhoneSettings,
  ScreenPhoneFind,
  ScreenPhoneMention,
});
