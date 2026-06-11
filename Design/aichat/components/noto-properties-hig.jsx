// noto-properties-hig.jsx
// ─────────────────────────────────────────────────────────────
// HIG-correct Properties surface for the v7 Minimalist editor.
//   • Inset-grouped iOS list (Lists and tables HIG): rounded group card
//     inset 16pt from the sheet edges, grouped vs. row background, leading
//     SF-symbol-style glyph, primary label, trailing secondary value,
//     44pt min row height, hairline separators inset to the label leading
//     edge, read-only Created/Modified (no chevron), and an accent
//     “Add property” insert row at the bottom of the group.
//   • Pull-down TYPE MENU (overlays, never reflows) for adding a property.
//   • Adding row with the no-layout-shift rule preserved: fixed 120px key
//     column with horizontal scroll + trailing fade, value anchored.
//   • Swipe-to-delete trailing red trash action (kept from the prior design).
//
// Exposes on window: NotoPropertyList, NotoTypeMenu, NOTO_HIG.

(function () {
  const ACCENT    = '#FF6A2E';
  const SHEET_BG  = '#111419';                 // systemGroupedBackground (dark, elevated)
  const CARD      = '#1C2027';                 // secondarySystemGroupedBackground (rows)
  const INK       = '#FFFFFF';
  const SECONDARY = 'rgba(235,235,245,0.62)';  // secondaryLabel
  const TERTIARY  = 'rgba(235,235,245,0.32)';  // tertiaryLabel
  const SEP       = 'rgba(84,84,88,0.55)';     // separator
  const FILL      = 'rgba(118,118,128,0.24)';  // tertiarySystemFill (chips)
  const SANS      = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';

  const GROUP_INSET = 16;   // group inset from sheet side edges (pt)
  const ROW_PAD     = 16;   // row leading/trailing padding
  const ICON_BOX    = 22;   // leading glyph column width
  const ICON_GAP    = 13;   // gap between glyph and label
  const SEP_INSET   = ROW_PAD + ICON_BOX + ICON_GAP; // hairline starts at label leading edge

  // ─── SF-symbol-style glyphs (thin line, 24-box) ───────────────────────
  function Sym({ name, color = SECONDARY, size = 21, sw = 1.7 }) {
    const c = { fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
    const P = (d, extra) => <path d={d} {...c} {...extra} />;
    let body = null;
    switch (name) {
      case 'folder':   body = P('M3 7a2 2 0 012-2h3.6a2 2 0 011.5.7L11 7h6a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V7z'); break;
      case 'calendar': body = <>{P('M4 7a2 2 0 012-2h12a2 2 0 012 2v11a2 2 0 01-2 2H6a2 2 0 01-2-2V7z')}{P('M4 10h16')}{P('M8 3.5v3M16 3.5v3')}</>; break;
      case 'clock':    body = <>{P('M12 21a9 9 0 100-18 9 9 0 000 18z')}{P('M12 7.5V12l3 2')}</>; break;
      case 'tag':      body = <>{P('M4 4h7.2a2 2 0 011.4.6l7 7a2 2 0 010 2.8l-4.8 4.8a2 2 0 01-2.8 0l-7-7A2 2 0 014.6 11V4z')}<circle cx="8" cy="8" r="1.4" fill={color} stroke="none" /></>; break;
      case 'link':     body = <>{P('M9.5 14.5l5-5')}{P('M8 11l-2 2a3.5 3.5 0 005 5l2-2')}{P('M16 13l2-2a3.5 3.5 0 00-5-5l-2 2')}</>; break;
      case 'status':   body = <><circle cx="12" cy="12" r="8.5" {...c} /><circle cx="12" cy="12" r="3.4" fill={color} stroke="none" /></>; break; // smallcircle.filled.circle
      case 'person':   body = <>{P('M12 12.5a4 4 0 100-8 4 4 0 000 8z')}{P('M5 20a7 7 0 0114 0')}</>; break;
      case 'textformat': body = <>{P('M5 18l5-12 5 12')}{P('M6.7 14h6.6')}</>; break; // "A"
      case 'number':   body = <>{P('M5.5 9h13M5 15h13')}{P('M10 4.5L8 19.5M16 4.5L14 19.5')}</>; break; // #
      case 'checklist':body = <>{P('M4 6.5l1.6 1.6L9 4.5')}{P('M4 17.5l1.6 1.6L9 15.5')}{P('M12 7h8M12 18h8')}</>; break;
      case 'plus':     body = <>{P('M12 5.5v13M5.5 12h13')}</>; break;
      case 'chevron':  body = P('M9 6l6 6-6 6'); break;
      case 'check':    body = P('M4.5 12.5l5 5 10-11', { strokeWidth: 2.2 }); break;
      case 'trash':    body = <>{P('M5 7h14')}{P('M9 7V5.5A1.5 1.5 0 0110.5 4h3A1.5 1.5 0 0115 5.5V7')}{P('M7 7l1 12.5A1.5 1.5 0 009.5 21h5a1.5 1.5 0 001.5-1.4L17 7')}</>; break;
      default: body = null;
    }
    return <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block', flexShrink: 0 }}>{body}</svg>;
  }

  // ─── One inset-grouped row ─────────────────────────────────────────────
  // value sits trailing in secondary color; `sep` draws the inset hairline.
  function Row({ icon, label, children, sep = true, chevron = false, accent = false, onTrash, swiped = false, minH = 44, valueScroll = false, valueEdit = false }) {
    const labelColor = accent ? ACCENT : INK;
    const iconColor  = accent ? ACCENT : SECONDARY;
    return (
      <div style={{ position: 'relative', overflow: 'hidden' }}>
        {/* trailing red delete action revealed underneath */}
        {onTrash && (
          <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: 88, background: '#FF3B30', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Sym name="trash" color="#fff" size={22} sw={1.8} />
          </div>
        )}
        <div style={{
          position: 'relative', background: CARD,
          transform: swiped ? 'translateX(-88px)' : 'none',
          transition: 'transform 0.25s cubic-bezier(0.2,0.8,0.2,1)',
          display: 'flex', alignItems: 'center', gap: ICON_GAP,
          minHeight: minH, padding: `0 ${ROW_PAD}px`,
        }}>
          <div style={{ width: ICON_BOX, display: 'flex', justifyContent: 'center', flexShrink: 0 }}>
            <Sym name={icon} color={iconColor} />
          </div>
          <span style={{ color: labelColor, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2, flexShrink: 0 }}>{label}</span>
          <div style={valueScroll ? {
            flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'flex-start', gap: 7,
            overflowX: 'auto', flexWrap: 'nowrap', scrollbarWidth: 'none',
            WebkitMaskImage: 'linear-gradient(to right, #000 88%, transparent 100%)',
            maskImage: 'linear-gradient(to right, #000 88%, transparent 100%)',
          } : valueEdit ? {
            flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 0, overflow: 'hidden',
            WebkitMaskImage: 'linear-gradient(to right, transparent 0%, #000 14%)',
            maskImage: 'linear-gradient(to right, transparent 0%, #000 14%)',
          } : {
            flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 7, overflow: 'hidden',
          }}>{children}</div>
          {chevron && <Sym name="chevron" color={TERTIARY} size={17} sw={2} />}
        </div>
        {sep && !swiped && <div style={{ position: 'absolute', left: SEP_INSET, right: 0, bottom: 0, height: 0.5, background: SEP }} />}
      </div>
    );
  }

  // value primitives ------------------------------------------------------
  const Value = ({ children, dim }) => (
    <span style={{ color: dim ? TERTIARY : SECONDARY, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2, textAlign: 'right', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 }}>{children}</span>
  );
  const Folder = ({ name }) => (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, minWidth: 0, color: SECONDARY, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2 }}>
      <span style={{ width: 7, height: 7, borderRadius: 2, background: ACCENT, flexShrink: 0 }} />
      <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 }}>{name}</span>
    </span>
  );
  const Status = ({ label, color }) => (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, minWidth: 0, color: SECONDARY, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2 }}>
      <span style={{ width: 9, height: 9, borderRadius: 999, background: color, flexShrink: 0, boxShadow: '0 0 0 3px ' + color + '22' }} />
      <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 }}>{label}</span>
    </span>
  );
  const Chip = ({ children }) => (
    <span style={{ display: 'inline-flex', alignItems: 'center', height: 24, padding: '0 9px', borderRadius: 7, background: FILL, color: INK, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1, whiteSpace: 'nowrap' }}>{children}</span>
  );

  // caret for focused fields
  const Caret = () => <span className="noto-hig-caret" style={{ display: 'inline-block', width: 2, height: 19, background: ACCENT, borderRadius: 1, verticalAlign: 'middle', marginLeft: 1 }} />;

  // ─── The inset-grouped property group ──────────────────────────────────
  // view: 'list' | 'adding' | 'delete'
  function NotoPropertyList({ view = 'list' }) {
    const adding = view === 'adding';
    const del    = view === 'delete';
    const editing = view === 'editing';
    return (
      <div style={{
        background: SHEET_BG, minHeight: '100%', padding: `4px 0 26px`,
        // when the keyboard is up (adding), iOS keeps the focused field above
        // it — scroll the group up so the new row sits above the keyboard.
        transform: adding ? 'translateY(-176px)' : 'none',
      }}>
        <style>{`@keyframes notoHigCaret{0%,48%{opacity:1}52%,100%{opacity:0}} .noto-hig-caret{animation:notoHigCaret 1.05s steps(1,end) infinite}`}</style>

        {/* group card */}
        <div style={{ margin: `4px ${GROUP_INSET}px 0`, background: CARD, borderRadius: 11, overflow: 'hidden' }}>
          <Row icon="folder"   label="Folder"   chevron><Folder name="Captures" /></Row>
          <Row icon="calendar" label="Created"><Value dim>May 14, 2026</Value></Row>
          <Row icon="clock"    label="Modified"><Value dim>2h ago</Value></Row>
          <Row icon="tag"      label="Tags" valueScroll onTrash={del} swiped={del}>
            <Chip>field-guide</Chip><Chip>ai</Chip><Chip>product-strategy</Chip><Chip>2026</Chip><Chip>retention</Chip>
          </Row>
          <Row icon="link"     label="Source" valueEdit={editing}>
            {editing ? (
              <><span style={{ color: INK, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2, whiteSpace: 'nowrap' }}>every.to/p/how-to-build-strong-ai-products-in-2026</span><Caret /></>
            ) : (
              <Value>every.to/p/how-to-build-strong-ai-products</Value>
            )}
          </Row>
          <Row icon="status"   label="Status" chevron><Status label="Drafting" color="#E6B62A" /></Row>
          <Row icon="person"   label="Author"><Value>Sahil Lavingia</Value></Row>

          {/* adding: a freshly inserted, focused property row (no layout shift) */}
          {adding && (
            <div style={{ position: 'relative', background: CARD, display: 'flex', alignItems: 'center', gap: ICON_GAP, minHeight: 44, padding: `0 ${ROW_PAD}px` }}>
              <div style={{ width: ICON_BOX, display: 'flex', justifyContent: 'center', flexShrink: 0 }}>
                <Sym name="textformat" color={ACCENT} />
              </div>
              {/* fixed 120px key column: horizontal scroll + trailing fade */}
              <div style={{
                width: 120, flexShrink: 0, overflowX: 'auto', whiteSpace: 'nowrap',
                WebkitMaskImage: 'linear-gradient(to right, #000 84%, transparent 100%)',
                maskImage: 'linear-gradient(to right, #000 84%, transparent 100%)',
                scrollbarWidth: 'none',
              }}>
                <span style={{ color: INK, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2 }}>Reviewed&nbsp;by</span><Caret />
              </div>
              {/* value anchored, fills remaining width */}
              <div style={{ flex: 1, minWidth: 0, textAlign: 'right' }}>
                <span style={{ color: TERTIARY, fontFamily: SANS, fontSize: 16, letterSpacing: -0.2 }}>Value</span>
              </div>
            </div>
          )}

          {/* add-property insert row (Contacts add-field pattern) */}
          {!adding && (
            <Row icon="plus" label="Add property" accent sep={false} minH={44} />
          )}
        </div>
      </div>
    );
  }

  // ─── Pull-down TYPE MENU — overlays content, never reflows the list ────
  // Rendered by the caller inside a dimmed scrim, anchored to the add row.
  function NotoTypeMenu() {
    const types = [
      { name: 'Text',        icon: 'textformat', sel: true },
      { name: 'Tags',        icon: 'tag' },
      { name: 'Date & time', icon: 'calendar' },
    ];
    return (
      <div style={{
        width: 252, borderRadius: 14, overflow: 'hidden',
        background: 'rgba(44,44,48,0.72)',
        backdropFilter: 'blur(28px) saturate(180%)', WebkitBackdropFilter: 'blur(28px) saturate(180%)',
        border: '0.5px solid rgba(255,255,255,0.12)',
        boxShadow: '0 12px 40px rgba(0,0,0,0.5), inset 0 0.5px 0 rgba(255,255,255,0.18)',
        fontFamily: SANS,
      }}>
        {types.map((t, i) => (
          <div key={t.name} style={{
            position: 'relative', display: 'flex', alignItems: 'center', gap: 10,
            height: 44, padding: '0 14px',
            background: t.sel ? 'rgba(255,255,255,0.10)' : 'transparent',
          }}>
            {/* leading checkmark column (reserved so labels align) */}
            <div style={{ width: 18, flexShrink: 0, display: 'flex', justifyContent: 'center' }}>
              {t.sel && <Sym name="check" color={ACCENT} size={18} sw={2.2} />}
            </div>
            <span style={{ flex: 1, color: INK, fontSize: 16, letterSpacing: -0.2 }}>{t.name}</span>
            <Sym name={t.icon} color={t.sel ? ACCENT : 'rgba(235,235,245,0.85)'} size={20} />
            {i < types.length - 1 && <div style={{ position: 'absolute', left: 14, right: 0, bottom: 0, height: 0.5, background: 'rgba(255,255,255,0.08)' }} />}
          </div>
        ))}
      </div>
    );
  }

  Object.assign(window, {
    NotoPropertyList, NotoTypeMenu,
    NOTO_HIG: { ACCENT, SHEET_BG, CARD, INK, SECONDARY, TERTIARY, SEP, SANS, Sym },
  });
})();
