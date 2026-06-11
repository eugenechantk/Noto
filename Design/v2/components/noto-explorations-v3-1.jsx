// v3 · Focus mode — Minimalist dark.
// Pure black canvas, no chrome. Default state.
// Wrapped in real iOS 26 device frame (status bar + dynamic island +
// home indicator) and real iOS 26 keyboard via ios-frame.jsx.

function Exp01MinimalV3() {
  const BG = '#000';
  const INK = 'rgba(255,255,255,0.32)';
  const INK_HEAD = 'rgba(255,255,255,0.55)';
  const INK_ANCHOR = 'rgba(255,255,255,0.85)';
  const SYNTAX = 'rgba(255,255,255,0.08)';
  const LINK = 'rgba(180,200,255,0.55)';
  const ACCESSORY = 'rgba(255,255,255,0.32)';

  const linkStyle = { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK };
  const italicStyle = { fontStyle: 'italic', color: INK_HEAD };

  const before = NOTE.body1.slice(0, 6);
  const tail = ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model';
  const after = ' swap. That distinction is doing a lot of work in the market right now.';

  return (
    <IOSDevice dark={true} background={BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: NOTO.font }}>
        {/* reserve status bar space (~62px) */}
        <div style={{ height: 62, flexShrink: 0 }} />
        <EdgeHint color="rgba(255,255,255,0.10)" />

        {/* writing surface */}
        <div style={{ flex: 1, minHeight: 0, padding: '28px 22px 0', overflow: 'hidden' }}>
          <div style={{ color: INK_ANCHOR, fontSize: 22, fontWeight: 700, letterSpacing: -0.3, lineHeight: 1.18 }}>
            <span style={{ color: SYNTAX, marginRight: 8 }}>#</span>How to Build Strong AI Products
          </div>
          <p style={{ margin: '18px 0 0', fontSize: 14, lineHeight: 1.55, color: INK_HEAD }}>{NOTE.subtitle}</p>
          <p style={{ margin: '20px 0 0', fontSize: 14, lineHeight: 1.55, color: INK }}>
            {renderParts(before, linkStyle, italicStyle)}
            {tail}
            <span style={{
              display: 'inline-block', width: 1.5, height: 16,
              background: '#4DA3FF', verticalAlign: 'text-bottom',
              marginLeft: 1, marginRight: 1,
            }} />
            <span style={{ color: 'rgba(255,255,255,0.20)' }}>{after}</span>
          </p>
        </div>

        {/* Noto's real 7-icon toolbar — minimalist voice */}
        <NotoToolbarMinimal wordCount={258} />

        {/* iOS 26 keyboard */}
        <IOSKeyboard dark={true} />
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp01MinimalV3 });
