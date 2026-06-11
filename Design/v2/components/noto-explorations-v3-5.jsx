// v3 · Focus mode — Natural.
// Soft warm gradient backdrop. Serif body. iOS 26 light keyboard.
// CONTEXTUAL STATE: mention. Bar morphs into a serif "— mention —" field
// with one matching note as a small dusty-rose chip just above.

function Exp05NaturalV3() {
  const INK = '#2A1F1A';
  const INK_MUTED = 'rgba(42,31,26,0.55)';
  const LINK = '#B0716E';
  const DISPLAY = '"Cormorant Garamond", "EB Garamond", Georgia, serif';
  const BODY = '"EB Garamond", "Cormorant Garamond", Georgia, serif';

  const gradient = `
    radial-gradient(120% 60% at 20% 10%, rgba(232,210,190,0.95) 0%, rgba(232,210,190,0) 60%),
    radial-gradient(80% 50% at 80% 30%, rgba(214,196,178,0.9) 0%, rgba(214,196,178,0) 60%),
    radial-gradient(70% 45% at 65% 60%, rgba(208,158,138,0.8) 0%, rgba(208,158,138,0) 60%),
    radial-gradient(80% 50% at 25% 80%, rgba(170,182,160,0.7) 0%, rgba(170,182,160,0) 65%),
    radial-gradient(60% 40% at 80% 95%, rgba(196,178,160,0.85) 0%, rgba(196,178,160,0) 60%),
    linear-gradient(to bottom, #E8DDCE, #D7C8B4)
  `;

  const before = NOTE.body1.slice(0, 6);
  const tail = ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap.';

  return (
    <IOSDevice dark={false} background={gradient}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: BODY }}>
        {/* reserve status bar space */}
        <div style={{ height: 62, flexShrink: 0 }} />

        {/* writing surface */}
        <div style={{ flex: 1, minHeight: 0, padding: '20px 26px 0', overflow: 'hidden' }}>
          <div style={{
            color: INK, fontFamily: DISPLAY,
            fontSize: 30, lineHeight: 1.0, letterSpacing: -0.4, fontWeight: 500,
          }}>
            How to Build<br />Strong AI<br />Products
          </div>
          <p style={{ margin: '14px 0 0', fontSize: 15, lineHeight: 1.55, color: INK, fontStyle: 'italic' }}>
            {NOTE.subtitle}
          </p>
          <p style={{ margin: '14px 0 0', fontSize: 15, lineHeight: 1.55, color: INK }}>
            {renderParts(before,
              { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
              { fontStyle: 'italic', color: INK_MUTED })}
            {tail}
            {' '}
            <span style={{
              background: 'rgba(176,113,110,0.18)', color: LINK,
              borderRadius: 999, padding: '1px 8px', fontStyle: 'italic',
            }}>@morning thoughts</span>
            <span style={{
              display: 'inline-block', width: 1.5, height: 16,
              background: LINK, marginLeft: 1, verticalAlign: 'text-bottom',
            }} />
          </p>
        </div>

        {/* dusty-rose mention result chip */}
        <div style={{ padding: '0 26px 10px', display: 'flex', flexShrink: 0 }}>
          <div style={{
            display: 'inline-flex', alignItems: 'baseline', gap: 8,
            padding: '6px 14px',
            background: 'rgba(255,250,243,0.85)',
            border: '0.5px solid rgba(176,113,110,0.40)',
            borderRadius: 999,
            boxShadow: '0 4px 10px rgba(120,80,60,0.10)',
            color: INK, fontFamily: BODY,
          }}>
            <span style={{ color: LINK, fontSize: 14, fontStyle: 'italic' }}>Morning Thoughts</span>
            <span style={{ color: INK_MUTED, fontSize: 11, fontStyle: 'italic' }}>daily notes</span>
          </div>
        </div>

        {/* Noto's real 7-icon toolbar — natural pearl voice */}
        <NotoToolbarNatural wordCount={258} ink={INK} />

        <IOSKeyboard dark={false} />
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp05NaturalV3 });
