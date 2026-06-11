// NotoExpFrame — iPhone bezel + iOS 26 status chrome + iOS 26 keyboard
// around an exploration's writing surface. Each v3 exploration supplies
// only its writing-area content + accessory bar; everything else (bezel,
// status bar, dynamic island, home indicator, keyboard) comes from here.
//
// Depends on IOSDevice and IOSKeyboard from ios-frame.jsx.

// Status bar in IOSDevice = 21 + 22 + 19 = 62px tall (absolutely positioned).
// Children must reserve this space at the top.
const NOTO_FRAME_STATUS_H = 62;
// Keyboard height (autocorrect bar + 4 rows + bottom row).
// Used for sizing artboard expectations and accessory bar position.
const NOTO_FRAME_KBD_H   = 318;

function NotoExpFrame({
  dark = true,
  background,         // override BG paint behind the writing surface
  children,           // writing surface (fills available height)
  accessory,          // optional accessory bar shown above keyboard
  fontFamily = '-apple-system, system-ui, sans-serif',
}) {
  return (
    <IOSDevice dark={dark} background={background}>
      <div style={{
        height: '100%', display: 'flex', flexDirection: 'column',
        fontFamily,
      }}>
        {/* reserve space for the absolutely-positioned status bar */}
        <div style={{ height: NOTO_FRAME_STATUS_H, flexShrink: 0 }} />
        {/* writing surface fills available vertical space */}
        <div style={{ flex: 1, minHeight: 0, position: 'relative', overflow: 'hidden' }}>
          {children}
        </div>
        {/* accessory bar (optional) — sits just above keyboard */}
        {accessory && (
          <div style={{ flexShrink: 0 }}>{accessory}</div>
        )}
        {/* iOS 26 keyboard */}
        <IOSKeyboard dark={dark} />
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { NotoExpFrame, NOTO_FRAME_STATUS_H, NOTO_FRAME_KBD_H });
