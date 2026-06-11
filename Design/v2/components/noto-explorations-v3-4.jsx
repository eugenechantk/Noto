// v3 · Focus mode — Techno.
// Pure black. Vim/terminal status line accessory bar. Default state.
// iOS 26 dark keyboard — the brutalism is in the chrome above, not the keys.

function Exp04TechnoV3() {
  const BG = '#000';
  const INK = '#EFEFEF';
  const INK_MUTED = 'rgba(255,255,255,0.50)';
  const INK_FAINT = 'rgba(255,255,255,0.30)';
  const RULE = 'rgba(255,255,255,0.22)';
  const LINK = '#1A1AFF';
  const MONO = '"JetBrains Mono", ui-monospace, "SF Mono", monospace';
  const SERIF = '"IBM Plex Serif", "Source Serif 4", Georgia, serif';

  const before = NOTE.body1.slice(0, 6);
  const tail = ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model';
  const after = ' swap. That distinction is doing a lot of work in the market right now.';

  return (
    <IOSDevice dark={true} background={BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: MONO }}>
        {/* reserve status bar space */}
        <div style={{ height: 62, flexShrink: 0 }} />

        {/* writing surface */}
        <div style={{ flex: 1, minHeight: 0, padding: '20px 14px 0', overflow: 'hidden' }}>
          <div style={{
            color: INK, fontSize: 22, lineHeight: 1.05, letterSpacing: -0.8, fontWeight: 500,
            textTransform: 'uppercase',
          }}>
            # HOW TO BUILD STRONG AI PRODUCTS
          </div>
          <p style={{ margin: '16px 0 0', fontSize: 14, lineHeight: 1.5, color: INK, fontFamily: SERIF }}>
            {NOTE.subtitle}
          </p>
          <div style={{ marginTop: 14, color: RULE, fontSize: 11, overflow: 'hidden', whiteSpace: 'nowrap' }}>
            {'-'.repeat(60)}
          </div>
          <p style={{ margin: '14px 0 0', fontSize: 14, lineHeight: 1.5, color: INK, fontFamily: SERIF }}>
            {renderParts(before,
              { color: LINK, textDecoration: 'underline', textUnderlineOffset: 2, textDecorationColor: LINK, textDecorationThickness: '1px' },
              { fontStyle: 'italic', color: INK_MUTED })}
            {tail}
            <span style={{
              display: 'inline-block', width: 8, height: 16,
              background: INK, marginLeft: 1, marginRight: 1,
              verticalAlign: 'text-bottom',
            }} />
            <span style={{ color: INK_FAINT }}>{after}</span>
          </p>
        </div>

        {/* Noto's real 7-icon toolbar — techno voice (mono uppercase) */}
        <NotoToolbarTechno wordCount={258} />

        <IOSKeyboard dark={true} />
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { Exp04TechnoV3 });
