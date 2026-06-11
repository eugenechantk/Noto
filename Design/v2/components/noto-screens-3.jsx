// Noto baseline screens — batch 3: iPad mini variants.
// Depends on noto-shared.jsx + noto-shared-2.jsx.

const IPAD_W = 744, IPAD_H = 1133;

// Status bar shared across iPad screens (time 6:56 PM Thu May 14)
function IpadStatusBar() {
  return (
    <div style={{
      height: 36, padding: '0 28px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      fontSize: 13, fontWeight: 600, color: NOTO.fg, letterSpacing: 0.1,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <span>6:56 PM</span>
        <span>Thu May 14</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <svg width="17" height="12" viewBox="0 0 17 12" fill="#fff">
          <path d="M8.5 2.3c2.7 0 5.1 1 7 2.7l1.3-1.3A11.5 11.5 0 0 0 0 3.6L1.3 5A10 10 0 0 1 8.5 2.3z"/>
          <path d="M8.5 6c1.5 0 2.8.5 3.8 1.4l1.3-1.3A7.5 7.5 0 0 0 3.4 6L4.7 7.4A5.7 5.7 0 0 1 8.5 6z"/>
          <circle cx="8.5" cy="10" r="1.7"/>
        </svg>
        <span style={{ fontSize: 13, fontWeight: 500 }}>100%</span>
        <svg width="28" height="13" viewBox="0 0 28 13">
          <rect x="0.5" y="0.5" width="23" height="12" rx="3" fill="none" stroke="rgba(255,255,255,0.45)" />
          <rect x="2" y="2" width="20" height="9" rx="2" fill="#fff" />
          <path d="M25 4v5c.9-.3 1.5-1.2 1.5-2.5S25.9 4.3 25 4z" fill="rgba(255,255,255,0.45)" />
        </svg>
      </div>
    </div>
  );
}

function IpadHomeIndicator() {
  return (
    <div style={{
      position: 'absolute', bottom: 9, right: 22,
      width: 134, height: 5, borderRadius: 3,
      background: 'rgba(255,255,255,0.55)',
      transform: 'rotate(90deg)', transformOrigin: 'right bottom',
    }} />
  );
}

// Editor top chrome row: sidebar toggle · breadcrumb · back+more pill
function IpadEditorChrome({ dim = false, breadcrumb = ['Noto', 'Captures'] }) {
  const style = dim ? { opacity: 0.4 } : null;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 20px 4px', ...style,
    }}>
      <NCircle icon="sidebar" size={40} iconSize={20} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 14 }}>
        <span style={{ color: NOTO.fgMuted }}>{breadcrumb[0]}</span>
        <NIcon name="caret-right" size={12} color={NOTO.fgMuted} />
        <span style={{ color: NOTO.fg, fontWeight: 600 }}>{breadcrumb[1]}</span>
      </div>
      <NPill h={40} pad={2}>
        <NPillBtn icon="chevron-left" iconSize={18} />
        <NPillBtn icon="ellipsis" iconSize={20} />
      </NPill>
    </div>
  );
}

// Shared body block for the realistic note on iPad — wider line lengths,
// more content visible (## H2 mid-screen, blockquote at bottom).
function IpadEditorBody({ highlights = [] }) {
  return (
    <div style={{ padding: '16px 60px 0' }}>
      <NMetaAccordion count={11} />

      <NHeading level={1} marginTop={28}>How to Build Strong AI Products</NHeading>

      <NRichBody marginTop={28} fontSize={16} parts={[
        'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.',
      ]} highlights={highlights} />

      <NImagePlaceholder marginTop={24} height={260} label="1200 × 500" />

      <NRichBody marginTop={28} fontSize={16} parts={[
        'The defining question for AI products in 2026 is no longer ',
        { italic: 'can we build it?' },
        ' \u2014 model capability has caught up to ambition. The harder question is ',
        { italic: 'what does this become once people use it every day?' },
        ' As ',
        { link: 'Sahil Lavingia recently argued' },
        ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap. That distinction is doing a lot of work in the market right now.',
      ]} highlights={highlights} />

      <NHeading level={2} marginTop={36}>The compounding loop</NHeading>

      <NRichBody marginTop={26} fontSize={16} parts={[
        'A compounding product feels different when you open it on day 30 versus day 1. It remembers what you cared about. It surfaces what you forgot. It connects the dots you didn\u2019t have time to. According to ',
        { link: 'Patrick Collison\u2019s essay on agency' },
        ', the products people stick with are the ones that "make you feel slightly smarter every time you return." That feeling is rarely the model \u2014 it\u2019s the accumulated context.',
      ]} highlights={highlights} />

      <NBlockquote marginTop={28} fontSize={16}>
        The only moat AI startups have left is the one their users are quietly building for them every day, without realizing it.
      </NBlockquote>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPad 03b — Editor (realistic)
// ─────────────────────────────────────────────────────────────
function ScreenIpadEditorRealistic() {
  return (
    <div style={{
      width: IPAD_W, height: IPAD_H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <IpadStatusBar />
      <IpadEditorChrome />
      <IpadEditorBody />
      <IpadHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPad 05 — Search modal (sheet from top, full width)
// ─────────────────────────────────────────────────────────────
function ScreenIpadSearch() {
  const results = [
    {
      title: 'Two Powerful Claude Code Plugins: gstack vs CE',
      path: 'Captures/Two Powerful Claude Code Plugins gstack vs CE.md/## You end up with the speed of gstack\u2019s opinionate\u2026',
      heading: 'You end up with the speed of gstack\u2019s opinionated defaults and the compounding quality curve',
      body: 'of Compound Engineering\u2019s methodology. Together they make\u2026',
    },
    {
      title: '21 Lessons From 14 Years at Google',
      path: 'Captures/21 Lessons From 14 Years at Google.md/## 21. There are no shortcuts, but there is compounding.',
      heading: '\u2026There are no shortcuts, but there is compounding.',
      body: 'Expertise comes from deliberate practice \u2014 pushing slightly beyond your current skill, reflecting\u2026',
    },
    {
      title: 'How to Build Strong AI Products',
      path: 'Captures/How to Build Strong AI Products.md/## The compounding loop',
      heading: 'The compounding loop',
      body: 'A compounding product feels different when you open it on day 30 versus day 1. It remembers\u2026',
    },
    {
      title: 'I Stored 100 Prompts in Obsidian and Let Claude Code Run Them. Here\u2019s What H\u2026',
      path: 'Captures/I Stored 100 Prompts in Obsidian and Let Claude Code Run Them. Here\u2019s What Happened.md/## The Co\u2026',
      heading: 'The Compounding Effect Nobody Talks About',
      body: 'Here\u2019s the part that doesn\u2019t get enough attention.\u2026.',
    },
    {
      title: '\uD83D\uDCE6 do you understand what two Anthropic engineers just explained in\u2026',
      path: 'Captures/\uD83D\uDCE6 do you understand what two Anthropic engineers just explained in\u2026.md/## While most traders ignored\u2026',
      heading: 'While most traders ignored them, this account executed thousands of small probabilistic edges,',
      body: 'compounding 300%\u201349,000% returns into consistent five-figure monthly profit\u2026',
    },
    {
      title: 'Step-by-step guide to get Ralph working and shipping code',
      path: 'Captures/Step-by-step guide to get Ralph working and shipping code.md/## Learnings compound. By story 10, Ral\u2026',
      heading: 'Learnings compound. By story 10, Ralph knew our patterns.',
      body: '',
    },
    {
      title: 'How to Design Using AI in 2026',
      path: 'Captures/How to Design Using AI in 2026.md/## Why this compounds: once your constraints live as skills, every fu\u2026',
      heading: 'Why this compounds: once your constraints live as skills, every future UI inherits them by default',
      body: 'which mean less rework, fewer regressions and  more\u2026',
    },
    {
      title: 'Two Powerful Claude Code Plugins: gstack vs CE',
      path: 'Captures/Two Powerful Claude Code Plugins gstack vs CE.md/## The Power User Stack: Use Both',
      heading: '',
      body: '',
    },
  ];

  return (
    <div style={{
      width: IPAD_W, height: IPAD_H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <IpadStatusBar />

      {/* grab handle */}
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 6 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.28)' }} />
      </div>

      {/* "Search" title + close */}
      <div style={{ position: 'relative', padding: '14px 28px 12px' }}>
        <div style={{ textAlign: 'center', fontSize: 17, fontWeight: 600, color: NOTO.fg, letterSpacing: -0.2 }}>Search</div>
        <div style={{
          position: 'absolute', right: 28, top: 6, width: 40, height: 40, borderRadius: 20,
          background: NOTO.pill, display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="13" height="13" viewBox="0 0 14 14" stroke="#fff" strokeWidth="1.8" strokeLinecap="round">
            <path d="M3 3l8 8M11 3l-8 8" />
          </svg>
        </div>
      </div>

      <div style={{ padding: '0 28px' }}>
        <NSearchField value="Compounding" />
      </div>
      <div style={{ padding: '14px 28px 6px' }}>
        <NSegmented selected={0} options={[
          { label: 'Title + Content', kbd: '\u23181' },
          { label: 'Title',           kbd: '\u23182' },
        ]} />
      </div>

      <div style={{ marginTop: 6, padding: '0 12px' }}>
        {results.map((r, i) => (
          <NSearchResult key={i} title={r.title} path={r.path}
            headingMatch={r.heading} body={r.body} padH={16} />
        ))}
      </div>

      <IpadHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPad 06 — Settings (centered modal sheet with sidebar partly visible)
// ─────────────────────────────────────────────────────────────
function ScreenIpadSettings() {
  const SIDEBAR_W = 240;
  const MODAL_W = 540;
  const MODAL_L = 100;
  const MODAL_T = 240;

  return (
    <div style={{
      width: IPAD_W, height: IPAD_H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <IpadStatusBar />

      {/* dimmed sidebar (left side, partly visible behind modal) */}
      <div style={{ position: 'absolute', top: 36, left: 0, width: SIDEBAR_W, bottom: 0, opacity: 0.42 }}>
        <div style={{
          padding: '20px 18px 16px',
          display: 'flex', alignItems: 'center',
        }}>
          <div style={{ fontSize: 17, fontWeight: 700, color: NOTO.fg, flex: 1 }}>Noto</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <NIcon name="gear" size={18} color={NOTO.fg} strokeWidth={1.5} />
            <NIcon name="search" size={18} color={NOTO.fg} strokeWidth={1.7} />
          </div>
        </div>
        <NFolderRow name="Archive"     count="0 files, 0 folders"     padH={18} />
        <NFolderRow name="Captures"    count="734 files, 0 folders"   padH={18} />
        <NFolderRow name="Daily Notes" count="1 file, 0 folders"      padH={18} />
        <NFolderRow name="Projects"    count="0 files, 0 folders"     padH={18} />
        <NNoteRow   name="Long Scrolling Note" time="2 hours ago" padH={18} />
        <NNoteRow   name="Project Plan"        time="2 hours ago" padH={18} />
        <NNoteRow   name="Shopping List"       time="2 hours ago" padH={18} />
        <NNoteRow   name="Meeting Notes"       time="2 hours ago" padH={18} />
      </div>

      {/* dimmed editor (right side) */}
      <div style={{ position: 'absolute', top: 36, left: SIDEBAR_W, right: 0, bottom: 0, opacity: 0.32 }}>
        <IpadEditorChrome breadcrumb={['Noto', 'Daily Notes']} />
        <IpadEditorBody />
      </div>

      {/* modal sheet */}
      <div style={{
        position: 'absolute', top: MODAL_T, left: MODAL_L, width: MODAL_W,
        background: 'rgba(20,20,22,0.95)',
        backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        borderRadius: 18,
        boxShadow: '0 30px 80px rgba(0,0,0,0.6), 0 0 0 0.5px rgba(255,255,255,0.08)',
        zIndex: 6, paddingBottom: 18,
      }}>
        {/* header */}
        <div style={{ position: 'relative', height: 56, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ fontSize: 17, fontWeight: 600 }}>Settings</div>
          <div style={{ position: 'absolute', left: 18, top: 12 }}>
            <NCircle icon="chevron-left" size={36} iconSize={18} />
          </div>
        </div>

        <NSettingsLabel marginTop={4} padH={20}>Storage</NSettingsLabel>
        <NSettingsGroup padH={20}>
          <NSettingsRow title="Vault Location" subtitle="On This Device" />
          <NSettingsRow iconNode={<NRefreshIcon size={20} color={NOTO.fg} />} title="Change Vault" isLast />
        </NSettingsGroup>
        <NSettingsHelper padH={30}>
          Changing your vault returns you to the welcome screen where you can create or open a different vault.
        </NSettingsHelper>

        <NSettingsLabel padH={20}>Search</NSettingsLabel>
        <NSettingsGroup padH={20}>
          <NSettingsRow iconNode={
            <div style={{ width: 22, height: 22, borderRadius: 11, border: `1.4px solid ${NOTO.fg}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <NRefreshIcon size={13} color={NOTO.fg} />
            </div>
          } title="Refresh search index" isLast />
        </NSettingsGroup>
        <NSettingsHelper padH={30}>
          Deletes the local search database and re-indexes every note in the vault. Use this if mention or search results look stale.
        </NSettingsHelper>

        <NSettingsLabel padH={20}>Readwise Sync</NSettingsLabel>
        <NSettingsGroup padH={20}>
          <NSettingsRow title="Set Token" />
          <NSettingsRow title="Test Connection" />
          <NSettingsRow title="Sync Now" isLast />
        </NSettingsGroup>
        <NSettingsHelper padH={30}>
          Token saved in secure storage.<br />
          Last sync: 1 Reader save and 1 Readwise save.
        </NSettingsHelper>
      </div>

      <IpadHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPad 07 — Find in note (compact find bar top-right)
// ─────────────────────────────────────────────────────────────
function ScreenIpadFind() {
  return (
    <div style={{
      width: IPAD_W, height: IPAD_H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <IpadStatusBar />
      <IpadEditorChrome />
      <IpadEditorBody highlights={[
        { word: 'compound',   active: true },
        { word: 'compounds',  active: false },
        { word: 'compounding', active: false },
      ]} />

      {/* find bar top-right, narrower */}
      <div style={{
        position: 'absolute', top: 92, right: 80, display: 'flex', alignItems: 'center', gap: 10, zIndex: 6,
      }}>
        <div style={{
          width: 320, height: 40, borderRadius: 20, background: NOTO.pill,
          boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.08), 0 6px 18px rgba(0,0,0,0.5)',
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
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={NOTO.fg} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 9l4-4 4 4" /></svg>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={NOTO.fg} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 5l4 4 4-4" /></svg>
        </div>
        <div style={{
          width: 40, height: 40, borderRadius: 20, background: NOTO.pill,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="13" height="13" viewBox="0 0 14 14" stroke="#fff" strokeWidth="1.8" strokeLinecap="round">
            <path d="M3 3l8 8M11 3l-8 8" />
          </svg>
        </div>
      </div>

      <IpadHomeIndicator />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// iPad 08 — Mention menu (bottom sheet, wider)
// ─────────────────────────────────────────────────────────────
function ScreenIpadMention() {
  const SHEET_TOP = 540;
  return (
    <div style={{
      width: IPAD_W, height: IPAD_H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <IpadStatusBar />

      {/* dimmed editor underneath */}
      <div style={{ opacity: 0.32 }}>
        <IpadEditorChrome />
        <div style={{ padding: '16px 60px 0' }}>
          <NMetaAccordion count={11} />
          <NHeading level={1} marginTop={28}>How to Build Strong AI Products</NHeading>
          <NRichBody marginTop={28} fontSize={16} parts={[
            'A field guide for founders shipping AI features in 2026 \u2014 what separates the products that compound from the ones that flame out after a launch week.',
          ]} />
          <NImagePlaceholder marginTop={24} height={260} label="1200 × 500" />
        </div>
      </div>

      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, top: SHEET_TOP, bottom: 0,
        background: '#0E0E10', borderTopLeftRadius: 18, borderTopRightRadius: 18,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.5)', zIndex: 6,
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.28)' }} />
        </div>
        <div style={{ position: 'relative', padding: '14px 28px 12px' }}>
          <div style={{ textAlign: 'center', fontSize: 17, fontWeight: 600, letterSpacing: -0.2 }}>Mention Document</div>
          <div style={{
            position: 'absolute', right: 28, top: 6, width: 40, height: 40, borderRadius: 20,
            background: NOTO.pill, display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="13" height="13" viewBox="0 0 14 14" stroke="#fff" strokeWidth="1.8" strokeLinecap="round">
              <path d="M3 3l8 8M11 3l-8 8" />
            </svg>
          </div>
        </div>
        <div style={{ padding: '0 28px 14px' }}>
          <NSearchField value="meet" />
        </div>
        <NMentionRow padH={28} title="Meeting Notes" path="Meeting Notes.md" />
        <NMentionRow padH={28} title="Pocket (@heypocket) is your notetaker for real world meetings"
          path="Captures/Pocket (@heypocket) is your notetaker for real world meetings.md" />
        <NMentionRow padH={28} title="Meet 19 startups in social networking, dating, and AI that investors have their eyes on"
          path="Captures/Meet 19 startups in social networking, dating, and AI that investors have their eyes on.md" />
        <NMentionRow padH={28} title="Sometimes the reason you can’t find people you resonate with is because you misread the ones you meet"
          path="Captures/Sometimes the reason you can’t find people you resonate with is because you misread the ones you mee.md" />
        <NMentionRow padH={28} title="Meet The Guy Who Solved Growing Apps (Hunter Isaacson Interview)"
          path="Captures/Meet The Guy Who Solved Growing Apps (Hunter Isaacson Interview).md" />
        <NMentionRow padH={28} title="Meet The Guy Dominating The App Store"
          path="Captures/Meet The Guy Dominating The App Store.md" />
      </div>

      <IpadHomeIndicator />
    </div>
  );
}

Object.assign(window, {
  ScreenIpadEditorRealistic,
  ScreenIpadSearch,
  ScreenIpadSettings,
  ScreenIpadFind,
  ScreenIpadMention,
});
