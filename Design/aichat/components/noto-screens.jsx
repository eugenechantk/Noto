// Noto baseline screens — 5 screens recreated faithfully from screenshots.
// Each <Screen…> is sized to a single device's pixel canvas; the design canvas
// wraps them in DCArtboards.

// ─────────────────────────────────────────────────────────────
// 1. iPhone — Note list at vault root
// ─────────────────────────────────────────────────────────────
function ScreenPhoneList() {
  const W = 402, H = 874;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      {/* status bar */}
      <NStatusBar time="6:05" right={['signal','wifi','battery']} />

      {/* dynamic island */}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 124, height: 36, borderRadius: 22, background: '#000', zIndex: 5,
      }} />

      {/* top app bar: title + pill button group */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '4px 18px 14px',
      }}>
        <div style={{ fontSize: 26, fontWeight: 700, letterSpacing: -0.4 }}>Notes</div>
        <NPill h={40} pad={4}>
          <NPillBtn icon="gear" iconSize={19} />
          <NPillBtn icon="doc-plus" iconSize={19} />
          <NPillBtn icon="plus" iconSize={20} />
        </NPill>
      </div>

      {/* folder + note list */}
      <div style={{ marginTop: 6 }}>
        <NFolderRow name="Archive"     count="0 files, 0 folders" />
        <NFolderRow name="Captures"    count="2 files, 0 folders" />
        <NFolderRow name="Daily Notes" count="1 file, 0 folders" />
        <NFolderRow name="Projects"    count="0 files, 0 folders" />
        <NNoteRow   name="Long Scrolling Note" time="52 sec" />
        <NNoteRow   name="Project Plan"        time="52 sec" />
        <NNoteRow   name="Shopping List"       time="52 sec" />
        <NNoteRow   name="Meeting Notes"       time="52 sec" />
      </div>

      {/* floating bottom capsule */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 28,
        display: 'flex', justifyContent: 'center',
      }}>
        <NFloatingCapsule />
      </div>

      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.55)',
      }} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 2. iPhone — Note editor for "Meeting Notes"
// ─────────────────────────────────────────────────────────────
function ScreenPhoneEditor() {
  const W = 402, H = 874;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <NStatusBar time="6:05" right={['signal','wifi','battery']} />

      {/* dynamic island */}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 124, height: 36, borderRadius: 22, background: '#000', zIndex: 5,
      }} />

      {/* top chrome: back · Noto · more */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 18px 8px',
      }}>
        <NCircle icon="chevron-left" size={40} iconSize={20} />
        <div style={{ fontSize: 15, fontWeight: 600, color: NOTO.fg, letterSpacing: -0.1 }}>Noto</div>
        <NCircle icon="ellipsis"     size={40} iconSize={20} />
      </div>

      {/* body */}
      <div style={{ padding: '14px 18px 0' }}>
        <NMetaAccordion count={3} />

        <NHeading level={1} marginTop={26}>Meeting Notes</NHeading>

        <NHeading level={2} marginTop={36}>Agenda</NHeading>
        <NBody marginTop={18}>
          Discuss Q2 roadmap and resource allocation for the new mobile app project.
        </NBody>

        <NHeading level={2} marginTop={32}>Action Items</NHeading>
        <NBody marginTop={18}>
          Follow up with the design team about the new landing page mockups.
        </NBody>
        <NBody marginTop={8}>
          Schedule a review meeting for next Thursday.
        </NBody>
      </div>

      {/* floating bottom capsule */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 28,
        display: 'flex', justifyContent: 'center',
      }}>
        <NFloatingCapsule />
      </div>

      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.55)',
      }} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 3. iPad mini portrait — Sidebar overlay opened
// ─────────────────────────────────────────────────────────────
function ScreenIpadSidebar() {
  const W = 744, H = 1133;
  const SIDEBAR_W = 328;

  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      {/* status bar (iPad style: time + date left, battery right) */}
      <div style={{
        height: 36, padding: '0 28px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontSize: 13, fontWeight: 600, color: NOTO.fg, letterSpacing: 0.1,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span>6:05 PM</span>
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

      {/* dimmed editor underneath (partially visible to the right of sidebar) */}
      <div style={{
        position: 'absolute', top: 36, left: 0, right: 0, bottom: 0,
        opacity: 0.35,
      }}>
        {/* breadcrumb top right */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 28px 0',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: NOTO.fgMuted, fontSize: 14 }}>
            <span>Noto</span>
            <NIcon name="caret-right" size={12} color={NOTO.fgMuted} />
            <span style={{ color: NOTO.fg }}>Daily Notes</span>
          </div>
          <div style={{ width: 40, height: 40, borderRadius: 20, background: NOTO.pill,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <NIcon name="ellipsis" size={20} color={NOTO.fg} />
          </div>
        </div>

        {/* metadata + dim heading content */}
        <div style={{ padding: '20px 28px 0' }}>
          <NMetaAccordion count={3} />
          <div style={{ marginTop: 56 }}>
            <NHeading level={2}>How are you feeling today?</NHeading>
            <div style={{ height: 48 }} />
            <NHeading level={2}>Why am I feeling this way?</NHeading>
            <div style={{ height: 48 }} />
            <NHeading level={2}>Where is this information?</NHeading>
          </div>
        </div>
      </div>

      {/* sidebar overlay panel — sits above the dimmed editor */}
      <div style={{
        position: 'absolute', top: 36, left: 0,
        width: SIDEBAR_W, height: H - 36,
        background: '#0B0B0D',
        borderRight: `0.5px solid rgba(255,255,255,0.08)`,
        boxShadow: '6px 0 24px rgba(0,0,0,0.5)',
      }}>
        {/* sidebar header */}
        <div style={{
          padding: '20px 20px 16px',
          display: 'flex', alignItems: 'center',
        }}>
          <div style={{ fontSize: 17, fontWeight: 700, color: NOTO.fg, flex: 1, letterSpacing: -0.2 }}>Noto</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <NIcon name="gear"   size={20} color={NOTO.fg} strokeWidth={1.5} />
            <NIcon name="search" size={20} color={NOTO.fg} strokeWidth={1.7} />
          </div>
        </div>

        {/* sidebar list */}
        <NFolderRow name="Archive"     count="0 files, 0 folders" padH={20} />
        <NFolderRow name="Captures"    count="212 files, 0 folders" padH={20} />
        <NFolderRow name="Daily Notes" count="1 file, 0 folders"  padH={20} />
        <NFolderRow name="Projects"    count="0 files, 0 folders" padH={20} />
        <NNoteRow   name="Long Scrolling Note" time="1 minute ago" padH={20} />
        <NNoteRow   name="Project Plan"        time="1 minute ago" padH={20} />
        <NNoteRow   name="Shopping List"       time="1 minute ago" padH={20} />
        <NNoteRow   name="Meeting Notes"       time="1 minute ago" padH={20} />
      </div>

      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 9, right: 22,
        width: 134, height: 5, borderRadius: 3,
        background: 'rgba(255,255,255,0.55)',
        transform: 'rotate(90deg)', transformOrigin: 'right bottom',
      }} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 4. iPad mini — Editor (sidebar closed)
// ─────────────────────────────────────────────────────────────
function ScreenIpadEditor() {
  const W = 744, H = 1133;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      {/* status bar */}
      <div style={{
        height: 36, padding: '0 28px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontSize: 13, fontWeight: 600, color: NOTO.fg, letterSpacing: 0.1,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span>6:05 PM</span>
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

      {/* top chrome: sidebar toggle · Noto · back+more pill */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 20px 4px',
      }}>
        <NCircle icon="sidebar" size={40} iconSize={20} />
        <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.1 }}>Noto</div>
        <NPill h={40} pad={2}>
          <NPillBtn icon="chevron-left" iconSize={18} />
          <NPillBtn icon="ellipsis"     iconSize={20} />
        </NPill>
      </div>

      {/* body */}
      <div style={{ padding: '16px 28px 0' }}>
        <NMetaAccordion count={3} />

        <NHeading level={1} marginTop={28}>Meeting Notes</NHeading>

        <NHeading level={2} marginTop={36}>Agenda</NHeading>
        <NBody marginTop={20} fontSize={16}>
          Discuss Q2 roadmap and resource allocation for the new mobile app project.
        </NBody>

        <NHeading level={2} marginTop={32}>Action Items</NHeading>
        <NBody marginTop={20} fontSize={16}>
          Follow up with the design team about the new landing page mockups.
        </NBody>
        <NBody marginTop={8} fontSize={16}>
          Schedule a review meeting for next Thursday.
        </NBody>
      </div>

      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 9, right: 22,
        width: 134, height: 5, borderRadius: 3,
        background: 'rgba(255,255,255,0.55)',
        transform: 'rotate(90deg)', transformOrigin: 'right bottom',
      }} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 5. macOS — Three-column-ish window
// ─────────────────────────────────────────────────────────────
function ScreenMacWindow() {
  const W = 1280, H = 880;
  const LIST_W = 320;

  const items = [
    { name: 'The blueprint for becoming an emotionall…', time: '2 minutes ago' },
    { name: 'Looking for Alice',                          time: '3 hours ago' },
    { name: 'Dostoevsky as lover',                        time: '3 hours ago' },
    { name: 'Why Vertical LLM Agents Are The New $1…',     time: '5 hours ago' },
    { name: 'Sometimes the reason you can\u2019t find peo…', time: '5 hours ago' },
    { name: 'Relationships are coevolutionary loops',     time: '6 hours ago' },
    { name: 'This is it',                                 time: '6 hours ago' },
    { name: 'A Primer On The Agentic AI Economy',         time: '6 hours ago' },
    { name: '$10M/yr app idea',                           time: '2 days ago' },
    { name: 'how to consistently get high views on Tik…',  time: '2 days ago' },
    { name: 'This app makes $1M/mo helping people ki…',    time: '2 days ago' },
    { name: 'This is how I try to target a US audience.…',  time: '2 days ago' },
    { name: 'Step 2 Account Warmup Protocol',             time: '2 days ago', selected: true },
    { name: 'I speedran a new app from 0 to $2m/year…',    time: '2 days ago' },
    { name: 'Someone\u2019s going to make a lot of money…', time: '2 days ago' },
    { name: 'The Wu Tapes',                               time: '2 days ago' },
    { name: 'Using Claude Code The Unreasonable Eff…',     time: '4 days ago' },
    { name: 'Fuck dropshipping, Fuck claude code, Fu…',    time: '1 week ago' },
    { name: 'the internet where 85% of the money is (…',  time: '1 week ago' },
    { name: 'We are currently in a \u201Conce in a lifetime\u201D…', time: '1 week ago' },
  ];

  return (
    <div style={{
      width: W, height: H,
      background: '#1A1B1F',
      borderRadius: 12, overflow: 'hidden', position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg,
      boxShadow: '0 30px 80px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)',
      display: 'flex',
    }}>
      {/* LEFT pane — list */}
      <div style={{
        width: LIST_W, height: '100%', display: 'flex', flexDirection: 'column',
        background: '#101115',
        borderRight: '0.5px solid rgba(255,255,255,0.07)',
      }}>
        {/* traffic lights row (pane-local title bar) */}
        <div style={{
          height: 46, display: 'flex', alignItems: 'center', padding: '0 16px',
        }}>
          <NTrafficLights />
        </div>
        {/* header: back · Captures · search */}
        <div style={{
          height: 40, display: 'flex', alignItems: 'center',
          padding: '0 14px', gap: 10,
        }}>
          <NIcon name="chevron-left" size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <div style={{ flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 700, letterSpacing: -0.1 }}>Captures</div>
          <NIcon name="search" size={17} color={NOTO.fgMuted} strokeWidth={1.7} />
        </div>
        {/* divider */}
        <div style={{ height: 0.5, background: 'rgba(255,255,255,0.06)' }} />
        {/* scroll list */}
        <div style={{ flex: 1, overflow: 'hidden', padding: '6px 6px 8px' }}>
          {items.map((it, i) => (
            <NCompactNoteRow key={i} name={it.name} time={it.time} selected={it.selected} />
          ))}
        </div>
      </div>

      {/* RIGHT pane — editor */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        {/* toolbar: sidebar · back/fwd · calendar  ·  Noto › Captures  ·  more */}
        <div style={{
          height: 46, display: 'flex', alignItems: 'center', gap: 14,
          padding: '0 18px 0 18px',
        }}>
          <NIcon name="sidebar"      size={19} color={NOTO.fgMuted} strokeWidth={1.7} />
          <NIcon name="arrow-back"   size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <NIcon name="arrow-fwd"    size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <NIcon name="calendar"     size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginLeft: 16 }}>
            <span style={{ color: NOTO.fgMuted, fontSize: 14 }}>Noto</span>
            <NIcon name="caret-right" size={12} color={NOTO.fgMuted} />
            <span style={{ color: NOTO.fg,   fontSize: 14, fontWeight: 600 }}>Captures</span>
          </div>
          <div style={{ flex: 1 }} />
          <div style={{
            display: 'flex', alignItems: 'center', gap: 4,
            padding: '4px 6px 4px 10px',
            background: 'rgba(255,255,255,0.06)',
            borderRadius: 14,
          }}>
            <NIcon name="ellipsis" size={18} color={NOTO.fg} />
            <NIcon name="caret-down" size={14} color={NOTO.fgMuted} />
          </div>
        </div>
        <div style={{ height: 0.5, background: 'rgba(255,255,255,0.06)' }} />

        {/* editor body */}
        <div style={{ flex: 1, overflow: 'hidden', padding: '20px 44px 0' }}>
          <NMetaAccordion count={17} />

          <NHeading level={1} marginTop={28}>Step 2: Account Warmup Protocol</NHeading>

          <NComment marginTop={26}>readwise:highlights:start --</NComment>
          <NComment marginTop={4}>readwise:highlights:end --</NComment>

          <NComment marginTop={20}>readwise:content:start --</NComment>

          <NBody marginTop={20} fontSize={15}>
            ^ Skip this step and the algorithm will bury your new account's content.
          </NBody>

          <NHeading level={3} marginTop={26}>Watch Step 2 Video</NHeading>

          <NHeading level={3} marginTop={26}>Why should you warmup a new account? Do you need to?</NHeading>

          <NBody marginTop={20} fontSize={15}>
            The #1 mistake people make when trying to do organic marketing is they skip the warm up phase,
            or they use an old account with bad history (watching vids or posting vids in a completely
            irrelevant niche). The easiest way to avoid 0 view jail on both tiktok and instagram is to
            warmup a NEW account for 7 days. Warming up means NO POSTING, but just using the account like
            a human who is interested in the content they are watching.
          </NBody>

          <NBody marginTop={20} fontSize={15}>
            The algorithm needs to understand your niche before you post. What you engage with is the
            first audience the algorithm will show your content to. Skipping this step also often flags
            your account as a bot, and you will get 0–100 max views on your first posts.
          </NBody>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  ScreenPhoneList, ScreenPhoneEditor,
  ScreenIpadSidebar, ScreenIpadEditor,
  ScreenMacWindow,
});
