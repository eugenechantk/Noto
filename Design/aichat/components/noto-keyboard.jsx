// Shared keyboard primitives for v3 focus mode.
// Renders a compact iOS-style keyboard (dark or light) sized to fit a 402px
// wide artboard. Plus a reusable EdgeHint chevron tab for top-chrome
// affordance discoverability.

function EdgeHint({ color = 'rgba(255,255,255,0.25)' }) {
  // 2px-tall hairline that bulges in the center as a faint chevron tab.
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 14,
      pointerEvents: 'none', zIndex: 4,
      display: 'flex', justifyContent: 'center', alignItems: 'flex-start',
    }}>
      <div style={{
        width: 40, height: 4, marginTop: 4, borderRadius: 2,
        background: color,
      }} />
    </div>
  );
}

function FocusKeyboard({ dark = true }) {
  // Compact stylized keyboard. Drawn statically (no images, no deps).
  // Approx 282px tall — together with the accessory bar this gives the
  // ~40% bottom footprint specified.
  const ROWS = [
    ['q','w','e','r','t','y','u','i','o','p'],
    ['a','s','d','f','g','h','j','k','l'],
    ['z','x','c','v','b','n','m'],
  ];
  const inkOn  = dark ? '#ffffff' : '#000000';
  const keyBg  = dark ? 'rgba(120,123,135,0.55)' : '#FCFCFC';
  const fnBg   = dark ? 'rgba(80,82,90,0.85)'   : 'rgba(174,179,191,0.75)';
  const bg     = dark ? '#2C2C2E' : '#D1D4DB';
  const sugBg  = dark ? 'rgba(255,255,255,0.10)' : '#fff';
  const sugFg  = dark ? '#fff' : '#000';

  const K = ({ ch, flex = 1, w, fn = false }) => (
    <div style={{
      flex: w ? '0 0 ' + w + 'px' : flex,
      height: 42, borderRadius: 5,
      background: fn ? fnBg : keyBg,
      boxShadow: '0 1px 0 rgba(0,0,0,0.18)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: inkOn, fontSize: 22, fontWeight: 400,
      fontFamily: '-apple-system, "SF Pro Text", system-ui',
    }}>{ch}</div>
  );

  return (
    <div style={{ background: bg, padding: '6px 4px 8px', position: 'relative' }}>
      {/* autosuggest strip */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-around',
        padding: '4px 8px 6px', color: sugFg,
        fontSize: 14, fontFamily: '-apple-system, system-ui',
      }}>
        <span style={{
          padding: '2px 10px', borderRadius: 4, background: sugBg,
        }}>"compounding"</span>
        <span style={{ opacity: 0.7 }}>compound</span>
        <span style={{ opacity: 0.7 }}>compounded</span>
      </div>
      {/* rows */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ display: 'flex', gap: 4, padding: '0 2px' }}>
          {ROWS[0].map((c, i) => <K key={i} ch={c} />)}
        </div>
        <div style={{ display: 'flex', gap: 4, padding: '0 18px' }}>
          {ROWS[1].map((c, i) => <K key={i} ch={c} />)}
        </div>
        <div style={{ display: 'flex', gap: 4, padding: '0 2px' }}>
          <K ch="⇧" w={36} fn />
          {ROWS[2].map((c, i) => <K key={i} ch={c} />)}
          <K ch="⌫" w={36} fn />
        </div>
        <div style={{ display: 'flex', gap: 4, padding: '0 2px' }}>
          <K ch="123" w={72} fn />
          <K ch="🌐" w={36} fn />
          <K ch="space" flex={3} />
          <K ch="return" w={88} fn />
        </div>
      </div>
      {/* bottom safe area */}
      <div style={{ height: 12 }} />
    </div>
  );
}

Object.assign(window, { EdgeHint, FocusKeyboard });
