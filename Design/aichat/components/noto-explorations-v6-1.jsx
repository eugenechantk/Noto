// v6 · Property-pill editor — single direction.
// Frontmatter (Metadata accordion) is rethought as a rounded pill *container*
// directly under the H1 — two rows of compact pills with a trailing "+" handle.
// A three-part floating bottom dock (target capsule + comment input + magnifier
// capsule) replaces the formatting accessory bar. iOS 26 Liquid-glass top
// chrome. Same realistic NOTE.
//
// Depends on V4Scaffold, NOTE, renderParts, IOSDevice, IOSKeyboard — all on window.

function ExpV6PropertyPills() {
  // ─── Palette (light) ────────────────────────────────────────
  const BG       = '#FFFFFF';
  const INK      = '#0A0A0B';     // body
  const HEAD     = '#0A0A0B';     // H1 / H2
  const MUTED    = '#6F7177';
  const FAINT    = '#9CA0A6';
  const CONTAINER= '#F1F1F2';     // pill-bin background
  const INNERPILL= '#FFFFFF';     // each pill inside the bin
  const PILL_BD  = 'rgba(10,10,11,0.06)';
  const RULE_Q   = '#D6D7DA';     // quote left rule
  const CHK_BD   = '#B7B9BE';     // task checkbox border

  // Accent dots — only these carry color.
  const ACC_GRN  = '#3FBE7D';     // ✓ source
  const ACC_BLU  = '#34A3D1';     // capture_status / AC avatar
  const ACC_PURP = '#8B5CF6';     // tag · readwise

  const SANS = '-apple-system, BlinkMacSystemFont, "Inter", "SF Pro Text", system-ui, sans-serif';
  const MONO = '"JetBrains Mono", "SF Mono", ui-monospace, Menlo, monospace';

  // ─── Inner pill primitive (sits inside the container) ───────
  function InnerPill({ children, glyph, mono }) {
    return (
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        height: 26, padding: '0 10px', borderRadius: 999,
        background: INNERPILL,
        color: INK, fontFamily: mono ? MONO : SANS,
        fontSize: 12.5, fontWeight: 500,
        boxShadow: '0 0 0 0.5px ' + PILL_BD,
        whiteSpace: 'nowrap', flexShrink: 0,
      }}>
        {glyph}
        {children}
      </span>
    );
  }

  // ─── Floating glass capsule (top chrome + bottom dock) ──────
  function GlassCapsule({ children, padding = '0 6px', height = 34, gap = 4 }) {
    return (
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap,
        height, padding, borderRadius: 999,
        background: 'rgba(255,255,255,0.92)',
        boxShadow:
          '0 1px 1px rgba(10,10,11,0.04), 0 6px 18px rgba(10,10,11,0.08), 0 0 0 0.5px rgba(10,10,11,0.05)',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
      }}>{children}</div>
    );
  }

  // ─── Bottom dock — target capsule · comment pill · magnifier capsule ─
  const accessory = (
    <div style={{
      background: BG, padding: '6px 12px 8px',
      display: 'flex', alignItems: 'center', gap: 6,
    }}>
      {/* Target / focus — round capsule */}
      <GlassCapsule height={38} padding="0" gap={0}>
        <div style={{ width: 38, height: 38, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {/* dashed-square target with center dot */}
          <svg width="20" height="20" viewBox="0 0 22 22" fill="none">
            <path d="M3 6V4a1 1 0 011-1h2M19 6V4a1 1 0 00-1-1h-2M3 16v2a1 1 0 001 1h2M19 16v2a1 1 0 01-1 1h-2"
              stroke={INK} strokeWidth="1.6" strokeLinecap="round" />
            <circle cx="11" cy="11" r="1.6" fill={INK} />
          </svg>
        </div>
      </GlassCapsule>

      {/* Main comment input pill */}
      <div style={{ flex: 1, display: 'flex' }}>
        <GlassCapsule height={38} padding="0 14px 0 12px" gap={10}>
          <svg width="16" height="16" viewBox="0 0 14 14" fill="none" stroke={INK} strokeWidth="1.8" strokeLinecap="round">
            <path d="M7 2.5v9M2.5 7h9" />
          </svg>
          <span style={{ color: FAINT, fontFamily: SANS, fontSize: 15, flex: 1 }}>Comment</span>
        </GlassCapsule>
      </div>

      {/* Magnifier — find in note */}
      <GlassCapsule height={38} padding="0" gap={0}>
        <div style={{ width: 38, height: 38, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={INK} strokeWidth="1.9" strokeLinecap="round">
            <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
          </svg>
        </div>
      </GlassCapsule>
    </div>
  );

  return (
    <V4Scaffold dark={false} background={BG} accessory={accessory} keyboardDark={false}>
      {/* ─── Floating-glass top chrome ────────────────────── */}
      <div style={{
        padding: '4px 14px 10px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        {/* Back — round glass capsule */}
        <GlassCapsule height={40} padding="0" gap={0}>
          <div style={{ width: 40, height: 40, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="20" height="20" viewBox="0 0 22 22" fill="none" stroke={INK} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 5l-6 6 6 6" />
            </svg>
          </div>
        </GlassCapsule>

        {/* Edit · ⋯ — twin glass capsule */}
        <GlassCapsule height={40} padding="0 4px" gap={0}>
          <div style={{ width: 40, height: 40, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="17" height="17" viewBox="0 0 22 22" fill="none" stroke={INK} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 19l1-4 11-11a2.1 2.1 0 013 3L7 18l-4 1z" />
            </svg>
          </div>
          <div style={{ width: 40, height: 40, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="18" height="18" viewBox="0 0 22 22" fill={INK}>
              <circle cx="5" cy="11" r="1.6" /><circle cx="11" cy="11" r="1.6" /><circle cx="17" cy="11" r="1.6" />
            </svg>
          </div>
        </GlassCapsule>
      </div>

      {/* ─── Scrollable body ───────────────────────────────── */}
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '0 22px 0' }}>
        {/* Tiny issue-ID slug */}
        <div style={{
          fontFamily: MONO, fontSize: 11.5, fontWeight: 500,
          color: MUTED, letterSpacing: 0.4, textTransform: 'uppercase',
          marginBottom: 4,
        }}>
          CAPTURES&nbsp;/&nbsp;HOW-TO-BUILD
        </div>

        {/* H1 */}
        <h1 style={{
          margin: 0, color: HEAD,
          fontFamily: SANS, fontWeight: 700,
          fontSize: 26, lineHeight: 1.18, letterSpacing: -0.5,
        }}>{NOTE.title}</h1>

        {/* ─── Body — tight typography ─────────────────────── */}
        <div style={{
          marginTop: 18, color: INK,
          fontFamily: SANS, fontSize: 15, lineHeight: 1.5,
        }}>
          <p style={{ margin: 0 }}>
            The defining question for AI products in 2026 is no longer{' '}
            <em style={{ fontStyle: 'italic', color: HEAD }}>can we build it?</em> — durable products are the ones whose value compounds with the user’s data.
          </p>

          {/* H2 — Scope (Linear-style compact subhead) */}
          <h2 style={{
            margin: '22px 0 8px', color: HEAD,
            fontFamily: SANS, fontWeight: 700, fontSize: 17, letterSpacing: -0.2,
          }}>Scope</h2>

          {/* Round filled bullets */}
          <ul style={{ margin: 0, paddingLeft: 24, color: INK, fontSize: 15, lineHeight: 1.5 }}>
            <li style={{ marginBottom: 2 }}>Compounding loop — value grows with user data</li>
            <li style={{ marginBottom: 2 }}>Not a model-swap dependency</li>
            <li>Sticky feeling: "slightly smarter each return"</li>
          </ul>

          {/* H2 — Expected Behavior */}
          <h2 style={{
            margin: '22px 0 8px', color: HEAD,
            fontFamily: SANS, fontWeight: 700, fontSize: 17, letterSpacing: -0.2,
          }}>Expected Behavior</h2>

          {/* Quote-style left-rule block */}
          <div style={{
            paddingLeft: 12, borderLeft: '2px solid ' + RULE_Q,
            color: INK, fontSize: 15, lineHeight: 1.5,
          }}>
            The accumulated context is the moat — the model is a swap-out commodity once usage compounds.
          </div>

          {/* H2 — Tasks */}
          <h2 style={{
            margin: '22px 0 10px', color: HEAD,
            fontFamily: SANS, fontWeight: 700, fontSize: 17, letterSpacing: -0.2,
          }}>Tasks</h2>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {[
              'Validate the compounding loop',
              'Pick three deposits',
              'Cut the AI-model-layer story',
              'Draft the field-guide intro',
            ].map((t, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{
                  width: 18, height: 18, borderRadius: 4,
                  border: '1.3px solid ' + CHK_BD, flexShrink: 0,
                  background: 'transparent', boxSizing: 'border-box',
                }} />
                <span style={{ color: INK, fontSize: 15, lineHeight: 1.3 }}>{t}</span>
              </div>
            ))}
          </div>

          <div style={{ height: 20 }} />
        </div>
      </div>
    </V4Scaffold>
  );
}

Object.assign(window, { ExpV6PropertyPills });
