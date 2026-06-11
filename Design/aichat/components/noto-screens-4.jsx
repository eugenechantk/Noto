// Noto baseline screens — batch 4: macOS Settings window
// Depends on noto-shared.jsx + noto-shared-2.jsx.

// Compact macOS-style pill button with optional leading icon
function MacPillBtn({ icon, iconNode, label }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 24, padding: '0 10px',
      background: 'rgba(255,255,255,0.10)',
      borderRadius: 5,
      boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.10), inset 0 -0.5px 0 rgba(0,0,0,0.25)',
      color: NOTO.fg, fontSize: 12.5, letterSpacing: -0.05,
      fontFamily: NOTO.font,
    }}>
      {iconNode && <span style={{ display: 'flex' }}>{iconNode}</span>}
      {icon && <NIcon name={icon} size={13} color={NOTO.fg} strokeWidth={1.6} />}
      <span>{label}</span>
    </div>
  );
}

function ScreenMacSettings() {
  const W = 968, H = 518;
  return (
    <div style={{
      width: W, height: H,
      background: '#1A1B1F',
      borderRadius: 12, overflow: 'hidden', position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg,
      boxShadow: '0 30px 80px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)',
    }}>
      {/* title bar */}
      <div style={{ position: 'relative', height: 80, background: '#202126' }}>
        <div style={{ position: 'absolute', top: 14, left: 16 }}>
          <NTrafficLights />
        </div>
        <div style={{
          position: 'absolute', top: 14, left: 0, right: 0, textAlign: 'center',
          fontSize: 13, fontWeight: 600, color: NOTO.fgMuted, letterSpacing: -0.05,
        }}>Settings</div>
        {/* Done button */}
        <div style={{
          position: 'absolute', top: 40, left: 0, right: 0, display: 'flex', justifyContent: 'center',
        }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            height: 24, padding: '0 18px',
            background: 'rgba(255,255,255,0.06)',
            border: '0.5px solid rgba(255,255,255,0.12)',
            borderRadius: 6,
            color: NOTO.fgMuted, fontSize: 12.5, fontWeight: 500,
          }}>Done</div>
        </div>
        {/* bottom divider */}
        <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 0.5, background: 'rgba(255,255,255,0.10)' }} />
      </div>

      {/* eyebrow strip — Storage */}
      <div style={{
        height: 28, padding: '0 18px', display: 'flex', alignItems: 'center',
        background: '#202126',
        borderBottom: '0.5px solid rgba(255,255,255,0.06)',
        fontSize: 12, fontWeight: 700, color: NOTO.fg, letterSpacing: -0.05,
      }}>Storage</div>

      {/* form content */}
      <div style={{ padding: '14px 18px 16px', fontSize: 12.5, lineHeight: 1.45 }}>
        <div style={{ color: NOTO.fg, fontSize: 14, fontWeight: 500 }}>Vault Location</div>
        <div style={{ color: NOTO.fgMuted, fontSize: 12.5, marginTop: 2 }}>iCloud Drive/Noto</div>
        <div style={{ marginTop: 10 }}>
          <MacPillBtn iconNode={<NRefreshIcon size={13} color={NOTO.fg} />} label="Change Vault" />
        </div>
        <div style={{
          color: NOTO.fg, fontSize: 12.5, marginTop: 14, fontWeight: 600, letterSpacing: -0.05,
        }}>Changing your vault returns you to the welcome screen where you can create or open a different vault.</div>
      </div>

      {/* eyebrow — Search */}
      <div style={{
        height: 24, padding: '0 18px', display: 'flex', alignItems: 'center',
        background: 'transparent',
        fontSize: 12, fontWeight: 700, color: NOTO.fg,
      }}>Search</div>
      <div style={{ padding: '6px 18px 14px' }}>
        <MacPillBtn iconNode={
          <div style={{ width: 14, height: 14, borderRadius: 7, border: `1.2px solid ${NOTO.fg}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <NRefreshIcon size={9} color={NOTO.fg} />
          </div>
        } label="Refresh search index" />
        <div style={{ color: NOTO.fgMuted, fontSize: 12.5, marginTop: 12, lineHeight: 1.45 }}>
          Deletes the local search database and re-indexes every note in the vault. Use this if mention or search results look stale.
        </div>
      </div>

      {/* eyebrow — Readwise Sync */}
      <div style={{
        height: 24, padding: '0 18px', display: 'flex', alignItems: 'center',
        fontSize: 12, fontWeight: 700, color: NOTO.fg,
      }}>Readwise Sync</div>
      <div style={{ padding: '6px 18px 14px', display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'flex-start' }}>
        <MacPillBtn label="Set Token" />
        <MacPillBtn label="Test Connection" />
        <MacPillBtn label="Sync Now" />
      </div>
    </div>
  );
}

Object.assign(window, { ScreenMacSettings });
