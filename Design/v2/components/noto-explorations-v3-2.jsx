// v3 · Focus mode — Book-like.
// Warm cream canvas, serif. iOS 26 light keyboard.
// CONTEXTUAL STATE: @-mention. Accessory bar morphed into "@type a name…"
// search field, one matching result row floating just above.

function Exp02BookV3() {
  const PAGE = '#F2EEE3';
  const INK = '#1A1814';
  const INK_MUTED = '#5B544A';
  const RULE = 'rgba(26,24,20,0.18)';
  const LINK = '#6A4A2A';
  const SERIF = '"EB Garamond", "Cormorant Garamond", Georgia, serif';

  const before = NOTE.body1.slice(0, 6);
  const tail = ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap. That distinction is doing a lot of work in the market right now. By contrast, the wrappers that emerged last cycle \u2014 ones whose entire premise was the model itself \u2014 are already evaporating, replaced by';

  return (
    <IOSDevice dark={false} background={PAGE}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SERIF }}>
        {/* reserve status bar space */}
        <div style={{ height: 62, flexShrink: 0 }} />

        {/* writing surface */}
        <div style={{ flex: 1, minHeight: 0, padding: '24px 28px 0', overflow: 'hidden' }}>
          <div style={{ color: INK, fontSize: 28, lineHeight: 1.08, letterSpacing: -0.4, fontWeight: 500 }}>
            How to Build<br />Strong AI Products
          </div>
          <p style={{ margin: '16px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>{NOTE.subtitle}</p>
          <p style={{ margin: '18px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>
            {renderParts(before,
              { color: LINK, textDecoration: 'none', borderBottom: '0.5px solid ' + LINK },
              { fontStyle: 'italic' })}
            {tail}
            {' '}
            <span style={{
              background: 'rgba(106,74,42,0.16)', color: LINK,
              borderRadius: 2, padding: '0 2px',
            }}>@meet</span>
            <span style={{
              display: 'inline-block', width: 1.5, height: 18,
              background: LINK, verticalAlign: 'text-bottom', marginLeft: 1,
            }} />
          </p>
        </div>

        {/* mention result row floating just above accessory bar */}
        <div style={{ padding: '0 22px 8px', flexShrink: 0 }}>
          <div style={{
            background: '#FFFCF5',
            border: '0.5px solid ' + RULE,
            boxShadow: '0 6px 16px rgba(40,30,15,0.10)',
            borderRadius: 2, padding: '10px 14px',
            display: 'flex', alignItems: 'baseline', gap: 10,
          }}>
            <span style={{
              color: INK, fontSize: 15, fontWeight: 500, fontFamily: SERIF,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1,
            }}>Meeting Notes</span>
            <span style={{ color: INK_MUTED, fontSize: 12, fontStyle: 'italic' }}>
              Captures / meeting-notes.md
            </span>
          </div>
        </div>

        {/* Noto's real 7-icon toolbar — book voice */}
        <NotoToolbarBook wordCount={258} ink={INK_MUTED} rule={RULE} />

        <IOSKeyboard dark={false} />
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp02BookV3 });
