// Noto — iOS 26 sheet template (Apple HIG modal presentation).
// A sheet slides up over a presenting view that recedes onto a black
// backdrop with rounded top corners. Supports .medium / .large detents,
// a grabber handle, and an opaque elevated material. Liquid-Glass shine.
//
// Exports: IOSSheet (the bare sheet shell), IOSSheetTemplate (full device
// frame showing a sheet presented over a recessed note editor).

// ─────────────────────────────────────────────────────────────
// Backdrop card — the presenting view, scaled back + corner-rounded,
// peeking above the sheet on a pure-black backdrop (HIG card stack).
// ─────────────────────────────────────────────────────────────
function SheetBackdropCard({ dark = true }) {
  const bg = dark ? '#000' : '#F2F2F7';
  const fg = dark ? '#FFFFFF' : '#000000';
  const muted = dark ? 'rgba(255,255,255,0.5)' : 'rgba(60,60,67,0.6)';
  const faint = dark ? 'rgba(255,255,255,0.10)' : 'rgba(60,60,67,0.12)';
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
      borderRadius: 40, overflow: 'hidden', background: bg,
    }}>
      <IOSStatusBar dark={dark} />
      <div style={{ padding: '8px 22px 0' }}>
        <div style={{ color: fg, fontSize: 30, fontWeight: 700, letterSpacing: -0.6, lineHeight: 1.15 }}>
          How to Build Strong AI Products
        </div>
        <div style={{ color: muted, fontSize: 13, marginTop: 10, letterSpacing: -0.1 }}>11 fields · saved 2h</div>
        {[92, 100, 86, 96, 70].map((w, i) => (
          <div key={i} style={{ height: 11, width: `${w}%`, background: faint, borderRadius: 4, marginTop: i === 0 ? 22 : 12 }} />
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// IOSSheet — the bare sheet shell. Drop any content as children.
//   detent: 'medium' | 'large'   — controls how far it covers
//   title / leading / trailing   — optional nav row
//   grabber: show the drag handle (default true)
// Sizing is driven by `topInset` (distance from frame top to sheet top).
// ─────────────────────────────────────────────────────────────
function IOSSheet({
  children, dark = true, detent = 'medium',
  title, subtitle, leading = 'Cancel', trailing = 'Done', leadingColor,
  grabber = true, navBar = true, height = 874,
  resizable = true, accent, material, footer, floatingAction, divider = true,
}) {
  // HIG: "large is the height of a fully expanded sheet and medium is about
  // half of the fully expanded height." The fully-expanded sheet stops just
  // below the receded card's peek (expandedTop), so medium ≈ half of THAT —
  // not half of the whole screen.
  const expandedTop = 64;
  const expandedH = height - expandedTop;
  const topInset = detent === 'large' ? expandedTop : Math.round(height - expandedH / 2);
  const sheetH = height - topInset;
  // HIG: "Include a grabber in a resizable sheet." Show it only when the
  // sheet can rest at more than one detent.
  const showGrabber = grabber && resizable;

  const sheetBg = material || (dark ? '#1C1C1E' : '#FFFFFF');
  const fg = dark ? '#FFFFFF' : '#000000';
  const tint = accent || (dark ? '#0A84FF' : '#007AFF');
  const leadTint = leadingColor || tint;
  const sep = dark ? 'rgba(84,84,88,0.55)' : 'rgba(60,60,67,0.12)';

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      height: sheetH,
      borderTopLeftRadius: 40, borderTopRightRadius: 40,
      background: sheetBg,
      // floating-card elevation + a Liquid-Glass top shine
      boxShadow: dark
        ? '0 -1px 0 rgba(255,255,255,0.06), 0 -24px 60px rgba(0,0,0,0.55)'
        : '0 -1px 0 rgba(0,0,0,0.04), 0 -24px 60px rgba(0,0,0,0.22)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
      fontFamily: '-apple-system, system-ui, sans-serif',
      WebkitFontSmoothing: 'antialiased', zIndex: 40,
    }}>
      {/* grabber handle */}
      {showGrabber && (
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 5, paddingBottom: navBar ? 0 : 4 }}>
          <div style={{
            width: 36, height: 5, borderRadius: 100,
            background: dark ? 'rgba(235,235,245,0.3)' : 'rgba(60,60,67,0.3)',
          }} />
        </div>
      )}

      {/* navigation row — leading / (title + subtitle) / trailing.
          Buttons render only when provided, per HIG single-view sheets. */}
      {navBar && (
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          minHeight: 56, padding: '6px 16px', position: 'relative', flexShrink: 0,
        }}>
          <div style={{ display: 'flex', justifyContent: 'flex-start', alignItems: 'center', fontSize: 17, color: leadTint, minWidth: 60 }}>{leading || ''}</div>
          <div style={{
            position: 'absolute', left: 0, right: 0, textAlign: 'center',
            pointerEvents: 'none',
          }}>
            <div style={{ fontSize: 17, fontWeight: 600, color: fg, letterSpacing: -0.3, lineHeight: 1.2 }}>{title}</div>
            {subtitle && (
              <div style={{ fontSize: 12.5, color: dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.6)', marginTop: 2, fontVariantNumeric: 'tabular-nums' }}>{subtitle}</div>
            )}
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'center', fontSize: 17, fontWeight: 600, color: tint, minWidth: 60 }}>{trailing || ''}</div>
        </div>
      )}
      {navBar && divider && <div style={{ height: 0.5, background: sep, flexShrink: 0 }} />}

      {/* content */}
      <div style={{ flex: 1, overflow: 'auto' }}>{children}</div>

      {/* bottom toolbar — sits above the home indicator */}
      {footer && (
        <>
          <div style={{ height: 0.5, background: sep, flexShrink: 0 }} />
          <div style={{
            flexShrink: 0, padding: '10px 20px 30px',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            background: sheetBg,
          }}>{footer}</div>
        </>
      )}

      {/* floating action — centered FAB above the home indicator */}
      {floatingAction && (
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 30,
          display: 'flex', justifyContent: 'center', pointerEvents: 'none', zIndex: 5,
        }}>
          <div style={{ pointerEvents: 'auto' }}>{floatingAction}</div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Sample sheet content — a "Move to folder" picker, on-brand for Noto.
// Used to make the template read as a real sheet rather than an empty box.
// ─────────────────────────────────────────────────────────────
function SheetSampleContent({ dark = true }) {
  const fg = dark ? '#FFFFFF' : '#000000';
  const muted = dark ? 'rgba(235,235,245,0.6)' : 'rgba(60,60,67,0.6)';
  const sep = dark ? 'rgba(84,84,88,0.45)' : 'rgba(60,60,67,0.1)';
  const accent = dark ? '#0A84FF' : '#007AFF';
  const rows = [
    { name: 'Notes', count: '128 files', sel: false },
    { name: 'Drafts', count: '12 files', sel: true },
    { name: 'Reading', count: '34 files', sel: false },
    { name: 'Archive', count: '301 files', sel: false },
    { name: 'Shared with me', count: '8 files', sel: false },
  ];
  return (
    <div style={{ padding: '6px 0' }}>
      {rows.map((r, i) => (
        <div key={r.name} style={{
          display: 'flex', alignItems: 'center', gap: 14,
          padding: '0 20px', height: 56, position: 'relative',
        }}>
          <NIcon name="folder" size={26} color={r.sel ? accent : fg} strokeWidth={1.4} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ color: fg, fontSize: 17, letterSpacing: -0.3, lineHeight: 1.2 }}>{r.name}</div>
            <div style={{ color: muted, fontSize: 13, marginTop: 1 }}>{r.count}</div>
          </div>
          {r.sel && (
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={accent} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 12l5 5L20 6" />
            </svg>
          )}
          {i < rows.length - 1 && (
            <div style={{ position: 'absolute', bottom: 0, left: 60, right: 0, height: 0.5, background: sep }} />
          )}
        </div>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// IOSSheetTemplate — full 402×874 device frame with a presented sheet.
// detent: 'medium' | 'large'
// ─────────────────────────────────────────────────────────────
function IOSSheetTemplate({ dark = true, detent = 'medium', width = 402, height = 874 }) {
  return (
    <div style={{
      width, height, borderRadius: 48, overflow: 'hidden', position: 'relative',
      background: '#000',
      boxShadow: '0 40px 80px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.12)',
      fontFamily: '-apple-system, system-ui, sans-serif', WebkitFontSmoothing: 'antialiased',
    }}>
      {/* receded presenting view — scaled back + dimmed onto the black backdrop */}
      <div style={{
        position: 'absolute', inset: 0,
        transform: 'scale(0.93) translateY(-10px)', transformOrigin: 'top center',
      }}>
        <SheetBackdropCard dark={dark} />
        <div style={{ position: 'absolute', inset: 0, borderRadius: 40, background: 'rgba(0,0,0,0.42)' }} />
      </div>

      {/* dynamic island */}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 126, height: 37, borderRadius: 24, background: '#000', zIndex: 50,
      }} />

      {/* the sheet */}
      <IOSSheet dark={dark} detent={detent} title="Move to" height={height}>
        <SheetSampleContent dark={dark} />
      </IOSSheet>

      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 60,
        height: 34, display: 'flex', justifyContent: 'center', alignItems: 'flex-end',
        paddingBottom: 8, pointerEvents: 'none',
      }}>
        <div style={{ width: 139, height: 5, borderRadius: 100, background: dark ? 'rgba(255,255,255,0.7)' : 'rgba(0,0,0,0.3)' }} />
      </div>
    </div>
  );
}

Object.assign(window, { IOSSheet, IOSSheetTemplate, SheetSampleContent, SheetBackdropCard });
