// noto-article-properties-screen.jsx
// The reading screen that hosts the property surface in three views.
// Depends on window.__notoProps (from noto-article-properties.jsx),
// IOSDevice and ArticleIcon (on window).

function ExpArticleProperties({ view = 'collapsed', noTabs = false }) {
  const P = window.__notoProps;
  const {
    BG, INK, HEAD, MUTED, FAINT, RULE, ACCENT, SANS, cardGlass,
    PropIcon, PropRow, ValueText, FolderValue, Chip, AddChip, SourceValue, StatusValue,
  } = P;

  const expanded = view === 'expanded' || view === 'empty' || view === 'minimal';
  const minimal  = view === 'minimal';
  const sparse   = view === 'empty';
  const editing  = view === 'editing';
  const adding   = view === 'adding';
  const addkv    = view === 'addkv';
  const deleting = view === 'delete';
  const overlayMode = minimal || editing || adding || addkv || deleting; // overlays the article on glass
  const keyboardUp  = editing || addkv;                      // text entry implies the keyboard

  // ─── Overlay material — iOS 26 Liquid Glass, lifted clearly off the page.
  //   Heavier dark fill (obscures the title/body beneath), faint white inner
  //   highlight rim, soft outer glow, generous rounded bottom (top stays flush
  //   with the nav row). Still glass, not a flat solid card.
  const overlayGlass = {
    background: 'rgba(18,21,27,0.88)',
    backdropFilter: 'blur(34px) saturate(180%)',
    WebkitBackdropFilter: 'blur(34px) saturate(180%)',
    borderTopLeftRadius: 16, borderTopRightRadius: 16,
    borderBottomLeftRadius: 30, borderBottomRightRadius: 30,
    boxShadow: [
      'inset 0 0.75px 0 rgba(255,255,255,0.22)',   // top highlight rim
      'inset 0 0 0 0.5px rgba(255,255,255,0.06)',  // faint full rim
      'inset 0 -0.5px 0 rgba(0,0,0,0.4)',
      '0 18px 48px rgba(0,0,0,0.5)',               // soft outer lift
      '0 4px 14px rgba(0,0,0,0.35)',
    ].join(', '),
  };

  // ─── Top bar — bare icons, matches the dock reading state ───
  const TopBar = () => (
    <div style={{
      position: 'absolute', left: 0, right: 0, top: 62, height: 48,
      padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, zIndex: 10,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
        <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="back" color={HEAD} size={20} />
        </div>
        <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <ArticleIcon name="forward" color={FAINT} size={20} />
        </div>
      </div>
      <div style={{ flex: 1 }} />
      <div style={{ width: 36, height: 36, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <ArticleIcon name="more" color={HEAD} size={20} />
      </div>
    </div>
  );

  // ─── Collapsed summary — one quiet, tappable line ───────────
  const CollapsedSummary = () => (
    <button style={{
      width: '100%', textAlign: 'left', cursor: 'pointer',
      ...cardGlass, borderRadius: 14, padding: '11px 13px',
      display: 'flex', alignItems: 'center', gap: 10,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 2, background: ACCENT, flexShrink: 0 }} />
      <span style={{ color: INK, fontFamily: SANS, fontSize: 13.5, fontWeight: 600, letterSpacing: -0.1, flexShrink: 0 }}>Captures</span>
      <span style={{ width: 0.5, height: 13, background: RULE, flexShrink: 0 }} />
      <span style={{ color: MUTED, fontFamily: SANS, fontSize: 13.5, flexShrink: 0 }}>{sparse ? '2 properties' : '11 properties'}</span>
      <span style={{ flex: 1 }} />
      <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12.5, fontVariantNumeric: 'tabular-nums' }}>edited 2h</span>
      <span style={{ transform: 'rotate(90deg)', display: 'inline-flex' }}>
        <PropIcon name="caret" color={FAINT} size={15} />
      </span>
    </button>
  );

  // ─── Expanded property card ─────────────────────────────────
  const ExpandedCard = () => (
    <div style={{ ...cardGlass, borderRadius: 18, padding: '4px 15px 8px' }}>
      {/* header — title + collapse caret */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '12px 0 4px',
      }}>
        <span style={{ color: HEAD, fontFamily: SANS, fontSize: 13, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase' }}>
          Properties
        </span>
        <span style={{ transform: 'rotate(-90deg)', display: 'inline-flex' }}>
          <PropIcon name="caret" color={FAINT} size={15} />
        </span>
      </div>

      <PropRow icon="folder" label="Folder">
        <FolderValue name="Captures" />
      </PropRow>

      <PropRow icon="created" label="Created">
        <ValueText dim>May 14, 2026</ValueText>
      </PropRow>

      <PropRow icon="modified" label="Modified">
        <ValueText>2h ago<span style={{ color: FAINT }}> · 5:42 PM</span></ValueText>
      </PropRow>

      <PropRow icon="tag" label="Tags" empty={sparse} addLabel="Add tags">
        <Chip>field-guide</Chip>
        <Chip>ai</Chip>
        <Chip>writing/draft</Chip>
        <Chip>2026</Chip>
        <AddChip />
      </PropRow>

      <PropRow icon="source" label="Source" empty={sparse} addLabel="Add source">
        <SourceValue domain="every.to" path="/p/strong-ai-products" />
      </PropRow>

      <PropRow icon="status" label="Status" empty={sparse} addLabel="Set status">
        <StatusValue label="Drafting" color="#E6B62A" />
      </PropRow>

      <PropRow icon="person" label="Author" empty={sparse} addLabel="Add author">
        <ValueText>Sahil Lavingia</ValueText>
      </PropRow>

      {/* always-present add-property action */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '13px 0 11px' }}>
        <PropIcon name="plus" color={ACCENT} size={16} />
        <span style={{ color: MUTED, fontFamily: SANS, fontSize: 14.5, letterSpacing: -0.1 }}>Add property</span>
      </div>
    </div>
  );

  // ─── Minimal expanded — the pill, unfolded vertically ───────
  //   No card, no hairlines, no fixed label column. Each property is a quiet
  //   inline line in the same dimmed-secondary type as the collapsed pill.
  // Comfortable touch-target sizing for every property row. Each line is a
  // full-width tap area at least ROW_MIN tall (≈ Apple HIG 44pt), so the field
  // is easy to hit even though the visible type stays quiet and compact.
  const ROW_MIN = 32;
  const MiniLine = ({ icon, label, children, addLabel }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', lineHeight: 1.4, minHeight: ROW_MIN, padding: '2px 0' }}>
      <span style={{ display: 'inline-flex', alignItems: 'center', alignSelf: 'center', flexShrink: 0 }}>
        <PropIcon name={icon} color={FAINT} size={14} />
      </span>
      <span style={{ color: MUTED, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1, flexShrink: 0 }}>{label}</span>
      {addLabel ? (
        <button style={{
          display: 'inline-flex', alignItems: 'center', gap: 4,
          background: 'none', border: 'none', padding: 0, cursor: 'pointer',
          color: FAINT, fontFamily: SANS, fontSize: 13.5,
        }}>
          <PropIcon name="plus" color={FAINT} size={12} />{addLabel}
        </button>
      ) : (
        <span style={{ display: 'inline-flex', alignItems: 'center', flexWrap: 'wrap', gap: 6 }}>{children}</span>
      )}
    </div>
  );

  const MiniTag = ({ children, removable }) => (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5, height: 28, padding: removable ? '0 6px 0 11px' : '0 11px',
      borderRadius: 999, background: 'rgba(255,255,255,0.06)',
      color: INK, fontFamily: SANS, fontSize: 12.5, fontWeight: 500, whiteSpace: 'nowrap',
    }}>
      {children}
      {removable && (
        <span style={{
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          width: 18, height: 18, borderRadius: 999, background: 'rgba(255,255,255,0.14)', cursor: 'pointer',
        }}>
          <svg width="8" height="8" viewBox="0 0 8 8" fill="none" stroke="rgba(236,236,238,0.8)" strokeWidth="1.4" strokeLinecap="round"><path d="M1 1l6 6M7 1l-6 6" /></svg>
        </span>
      )}
    </span>
  );

  // a blinking text caret for active inputs
  const Caret = () => (
    <span style={{
      display: 'inline-block', width: 2, height: 15, background: ACCENT,
      borderRadius: 1, marginLeft: 1, transform: 'translateY(2px)',
      animation: 'notoCaret 1s steps(1) infinite',
    }} />
  );

  // subtle highlight behind the row being edited
  const RowHL = ({ children }) => (
    <div style={{
      margin: '-5px -10px', padding: '5px 10px', borderRadius: 12,
      background: 'rgba(255,255,255,0.06)',
      boxShadow: 'inset 0 0 0 0.5px rgba(255,122,46,0.30)',
    }}>{children}</div>
  );

  // collapse header — shared by all overlay states
  const CollapseHeader = () => (
    <button style={{
      display: 'flex', alignItems: 'center', gap: 8, minHeight: ROW_MIN,
      background: 'none', border: 'none', padding: '2px 0', cursor: 'pointer', marginBottom: 1,
    }}>
      <span style={{ display: 'inline-flex', transform: 'rotate(-90deg)' }}>
        <PropIcon name="caret" color={FAINT} size={14} />
      </span>
      <span style={{ color: MUTED, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1 }}>11 properties</span>
      <span style={{ color: FAINT, fontFamily: SANS, fontSize: 13.5 }}>· {deleting ? 'edit · swipe to delete' : (editing || adding ? 'editing' : 'saved 2h')}</span>
    </button>
  );

  // ─── Swipe-to-delete row — a property slid left to reveal a red Delete
  //   action on its trailing edge (the standard iOS gesture for removing a
  //   property). The leading icon/label slide under the edge as it opens.
  const SwipeDeleteRow = ({ children }) => (
    <div style={{ position: 'relative', overflow: 'hidden', borderRadius: 10 }}>
      <div style={{
        position: 'absolute', top: 1, bottom: 1, right: 0, width: 78,
        background: '#E5484D', borderRadius: 10,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="19" height="19" viewBox="0 0 22 22" fill="none" stroke="#fff" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <path d="M4 6h14M9 6V4.5a1.5 1.5 0 011.5-1.5h1A1.5 1.5 0 0113 4.5V6M6.5 6l.7 11a1.5 1.5 0 001.5 1.4h4.6a1.5 1.5 0 001.5-1.4l.7-11" />
        </svg>
      </div>
      <div style={{ transform: 'translateX(-86px)', position: 'relative' }}>
        {children}
      </div>
    </div>
  );

  // the standard non-tag rows, reused across states
  const FolderLine = () => (
    <MiniLine icon="folder" label="Folder">
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: INK, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1 }}>
        <span style={{ width: 6, height: 6, borderRadius: 2, background: ACCENT }} />Captures
      </span>
    </MiniLine>
  );
  const CreatedLine = () => (
    <MiniLine icon="created" label="Created"><span style={{ color: INK, fontFamily: SANS, fontSize: 13.5 }}>May 14, 2026</span></MiniLine>
  );
  const ModifiedLine = () => (
    <MiniLine icon="modified" label="Modified"><span style={{ color: INK, fontFamily: SANS, fontSize: 13.5 }}>2h ago<span style={{ color: FAINT }}> · 5:42 PM</span></span></MiniLine>
  );
  const SourceLine = () => (
    <MiniLine icon="source" label="Source">
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
        <span style={{ width: 12, height: 12, borderRadius: 3, background: 'linear-gradient(135deg,#FF6A2E,#C2185B)' }} />
        <span style={{ color: ACCENT, fontFamily: SANS, fontSize: 13.5 }}>every.to<span style={{ color: FAINT }}>/p/strong-ai-products</span></span>
      </span>
    </MiniLine>
  );
  const StatusLine = () => (
    <MiniLine icon="status" label="Status">
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: INK, fontFamily: SANS, fontSize: 13.5 }}>
        <span style={{ width: 7, height: 7, borderRadius: 999, background: '#E6B62A' }} />Drafting
      </span>
    </MiniLine>
  );
  const AuthorLine = () => (
    <MiniLine icon="person" label="Author"><span style={{ color: INK, fontFamily: SANS, fontSize: 13.5 }}>Sahil Lavingia</span></MiniLine>
  );

  // Tags row — static, or in active edit mode (× chips + live input caret)
  const TagsLine = () => {
    if (!editing) {
      return (
        <MiniLine icon="tag" label="Tags">
          <MiniTag>field-guide</MiniTag><MiniTag>ai</MiniTag><MiniTag>writing/draft</MiniTag><MiniTag>2026</MiniTag>
        </MiniLine>
      );
    }
    return (
      <RowHL>
        <MiniLine icon="tag" label="Tags">
          <MiniTag removable>field-guide</MiniTag>
          <MiniTag removable>ai</MiniTag>
          <MiniTag removable>writing/draft</MiniTag>
          <MiniTag removable>2026</MiniTag>
          {/* active input chip — typing a new tag */}
          <span style={{ display: 'inline-flex', alignItems: 'center', color: INK, fontFamily: SANS, fontSize: 12.5 }}>
            produc<Caret />
          </span>
        </MiniLine>
      </RowHL>
    );
  };

  // ─── Type picker — choose a new property's kind (adding state) ──
  const TYPE_OPTS = [
    { icon: 'text', name: 'Text' },
    { icon: 'tag', name: 'Tags' },
    { icon: 'created', name: 'Date & time' },
  ];
  // ─── Type picker — a floating dropdown menu (anchored under the add-property
  //   row), not part of the inline list flow. Liquid-Glass, elevated.
  const TypePicker = () => (
    <div style={{
      position: 'absolute', top: 'calc(100% + 6px)', left: -10, right: -10, zIndex: 50,
      ...cardGlass, background: 'rgba(22,25,31,0.96)', borderRadius: 14, padding: 6,
      boxShadow: '0 20px 50px rgba(0,0,0,0.58), 0 6px 16px rgba(0,0,0,0.42), inset 0 0.5px 0 rgba(255,255,255,0.14)',
      display: 'flex', flexDirection: 'column', gap: 1,
    }}>
      <div style={{ padding: '6px 10px 4px', color: FAINT, fontFamily: SANS, fontSize: 11, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase' }}>
        Property type
      </div>
      {TYPE_OPTS.map((t, i) => (
        <div key={t.name} style={{
          display: 'flex', alignItems: 'center', gap: 10, minHeight: ROW_MIN, padding: '2px 10px', borderRadius: 10, cursor: 'pointer',
          background: i === 0 ? 'rgba(255,122,46,0.14)' : 'transparent',
        }}>
          <PropIcon name={t.icon} color={i === 0 ? ACCENT : MUTED} size={15} />
          <span style={{ flex: 1, color: i === 0 ? HEAD : INK, fontFamily: SANS, fontSize: 14 }}>{t.name}</span>
          {i === 0 && (
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={ACCENT} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 7.5l3.5 3.5L12 3" /></svg>
          )}
        </div>
      ))}
    </div>
  );

  // ─── Add-property row (adding state) — tapped/active; picker open below ──
  const AddPropertyRow = () => (
    <RowHL>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, minHeight: ROW_MIN - 10, padding: '4px 0' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center' }}>
          <PropIcon name="plus" color={ACCENT} size={14} />
        </span>
        <span style={{ color: HEAD, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1 }}>Add property</span>
        <span style={{ flex: 1 }} />
        <span style={{ color: FAINT, fontFamily: SANS, fontSize: 12.5 }}>choose a type</span>
      </div>
    </RowHL>
  );

  // ─── Quiet "+ Add property" row — always present in the minimal list ──
  const QuietAddProperty = () => (
    <button style={{
      display: 'flex', alignItems: 'center', gap: 8, minHeight: ROW_MIN, padding: '2px 0',
      background: 'none', border: 'none', cursor: 'pointer',
    }}>
      <span style={{ display: 'inline-flex', alignItems: 'center' }}>
        <PropIcon name="plus" color={ACCENT} size={14} />
      </span>
      <span style={{ color: MUTED, fontFamily: SANS, fontSize: 13.5, letterSpacing: -0.1 }}>Add property</span>
    </button>
  );

  // ─── Fixed-key-column scroll behavior (shared by editable-key rows) ──
  //   A key field that lets the user edit the key must NOT auto-size to its
  //   content, or the value field reflows mid-typing. Lock the key to a fixed
  //   width and scroll its text horizontally inside that box instead.
  const KEY_COL_W = 120; // ~30% of the inner row width; fixed, never grows
  const notoFieldScroll = {
    whiteSpace: 'nowrap',
    overflowX: 'auto',
    overflowY: 'hidden',
    scrollbarWidth: 'none',  // Firefox: hide scrollbar
    msOverflowStyle: 'none', // legacy Edge
  };
  // Scroll-aware 8px edge fade: fade the LEADING edge when content is hidden to
  // the left (caret scrolled to the end stays crisp on the right), and the
  // TRAILING edge when more text sits to the right — so overflow always
  // dissolves into the gap instead of hard-clipping, signalling more text.
  const applyFieldEdgeFade = (el) => {
    if (!el) return;
    const max = el.scrollWidth - el.clientWidth;
    const left = el.scrollLeft > 1;
    const right = el.scrollLeft < max - 1;
    const L = left ? 'transparent 0, #000 8px' : '#000 0';
    const R = right ? '#000 calc(100% - 8px), transparent 100%' : '#000 100%';
    el.style.webkitMaskImage = 'linear-gradient(to right, ' + L + ', ' + R + ')';
    el.style.maskImage = el.style.webkitMaskImage;
  };
  // ref for an editable key/value field. `toEnd` pins it to the trailing edge so
  // the caret stays in view — mimics a native input typed to the end.
  const fieldRef = (toEnd) => (el) => {
    if (!el) return;
    if (el.__notoBound !== true) {
      el.__notoBound = true;
      el.addEventListener('scroll', () => applyFieldEdgeFade(el), { passive: true });
    }
    const settle = () => { if (toEnd) el.scrollLeft = el.scrollWidth; applyFieldEdgeFade(el); };
    settle();
    requestAnimationFrame(settle);
  };

  // ─── New custom key+value row (addkv state) — two inline fields ──
  //   The KEY lives in a FIXED-WIDTH column (KEY_COL_W) that never grows with
  //   its content. As the user types, the text scrolls horizontally INSIDE the
  //   box (overflow-x:auto, scrollbar hidden) — exactly like a native text input
  //   auto-scrolling to keep the caret in view. A short fade mask on the box
  //   edges lets clipped text dissolve into the gap instead of hard-clipping,
  //   signalling more text exists. Because the key column is a fixed size, the
  //   VALUE field's left edge is anchored (key width + 12px gap) and never moves
  //   as the key is typed. The same scroll+fade rule is applied to the value so
  //   long values don't reflow the row either. The row stays a single line.
  const NewKeyValueRow = () => (
    <RowHL>
      <style>{`.noto-field-scroll::-webkit-scrollbar{display:none;}`}</style>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'nowrap', lineHeight: 1.4, minHeight: ROW_MIN }}>
        <span style={{ flexShrink: 0, alignSelf: 'center', display: 'inline-flex', width: 14, justifyContent: 'center' }}>
          <span style={{ color: FAINT, fontFamily: SANS, fontSize: 11.5, fontWeight: 700, letterSpacing: 0.3 }}>Aa</span>
        </span>
        {/* Key field — FIXED 120px column. Scrolls horizontally; does NOT grow. */}
        <div
          className="noto-field-scroll"
          ref={fieldRef(true)}
          style={{
            ...notoFieldScroll,
            width: KEY_COL_W, flexShrink: 0,
            color: INK, fontFamily: SANS, fontSize: 13.5,
            borderBottom: '1.5px solid ' + ACCENT, padding: '7px 0',
          }}
        >
          <span style={{ display: 'inline-flex', alignItems: 'center' }}>
            Estimated reading time<Caret />
          </span>
        </div>
        {/* Value field — left edge anchored at key width + gap; same scroll rule. */}
        <div
          className="noto-field-scroll"
          ref={fieldRef(false)}
          style={{
            ...notoFieldScroll,
            flex: 1, minWidth: 0,
            color: FAINT, fontFamily: SANS, fontSize: 13.5,
            borderBottom: '1px solid rgba(255,255,255,0.12)', padding: '7px 0',
          }}
        >
          Value
        </div>
      </div>
    </RowHL>
  );

  // ─── The unfolded property list (shared shell for all overlay states) ──
  const PropertyLines = () => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <CollapseHeader />
      <FolderLine />
      <CreatedLine />
      <ModifiedLine />
      <TagsLine />
      <SourceLine />
      {deleting ? <SwipeDeleteRow><StatusLine /></SwipeDeleteRow> : <StatusLine />}
      <AuthorLine />
      {!adding && !addkv && !deleting && <QuietAddProperty />}
      {adding && (
        <div style={{ position: 'relative' }}>
          <AddPropertyRow />
          <TypePicker />
        </div>
      )}
      {addkv && <NewKeyValueRow />}
    </div>
  );

  return (
    <IOSDevice dark={true} background={BG}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS, position: 'relative' }}>
        <style>{`@keyframes notoCaret { 0%,50% { opacity: 1 } 50.01%,100% { opacity: 0 } }`}</style>
        <TopBar />

        <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: '116px 22px 0', position: 'relative' }}>
          {/* PROPERTY SURFACE — sits ABOVE the title (nav → properties → H1 → body).
              In minimal view the expanded block OVERLAYS the article (absolute,
              glass) so the title + body never shift between collapsed and expanded. */}
          <div style={{ marginBottom: 16, position: 'relative' }}>
            {overlayMode ? <CollapsedSummary /> : expanded ? <ExpandedCard /> : <CollapsedSummary />}
            {overlayMode && (
              <div style={{
                position: 'absolute', top: -7, left: -12, right: -12, zIndex: 30,
                padding: '9px 14px 17px', ...overlayGlass,
              }}>
                <PropertyLines />
              </div>
            )}
          </div>

          {/* H1 title — locked at the collapsed baseline */}
          <h1 style={{ margin: 0, color: HEAD, fontFamily: SANS, fontSize: 24, fontWeight: 700, lineHeight: 1.15, letterSpacing: -0.3 }}>
            How to Build Strong AI Products
          </h1>

          {/* lede + long-form body so it reads as a real (long) article */}
          <p style={{ margin: '14px 0 0', fontSize: 16, lineHeight: 1.55, color: INK }}>
            {window.NOTO_LEDE}
          </p>
          <div style={{ marginTop: 16 }}>
            {window.renderNotoDoc({ from: 0 })}
          </div>
        </div>

        {keyboardUp ? (
          <IOSKeyboard dark={true} />
        ) : (
        /* Floating dock — left pair · search · right pair (matches dock direction) */
        <React.Fragment>
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 92, height: 56, background: 'linear-gradient(to bottom, rgba(14,17,22,0), ' + BG + ')', pointerEvents: 'none', zIndex: 5 }} />
        <div style={{ flexShrink: 0, padding: '6px 12px 34px', position: 'relative', zIndex: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
          <DockPair>
            <DockBtn><ArticleIcon name="sidebar" color={HEAD} size={22} /></DockBtn>
            <DockDiv />
            <DockBtn><ArticleIcon name="today" color={HEAD} size={22} /></DockBtn>
          </DockPair>
          <div style={{ flex: 1, height: 52, ...cardGlass, borderRadius: 999, display: 'flex', alignItems: 'center', gap: 9, padding: '0 18px' }}>
            <ArticleIcon name="search" color={FAINT} size={19} />
            <span style={{ color: FAINT, fontFamily: SANS, fontSize: 16 }}>Search</span>
          </div>
          <DockPair>
            {!noTabs && <DockBtn><TabsGlyph /></DockBtn>}
            {!noTabs && <DockDiv />}
            <DockBtn accent><ArticleIcon name="new" color={ACCENT} size={22} /></DockBtn>
          </DockPair>
        </div>
        </React.Fragment>
        )}
      </div>
    </IOSDevice>
  );

  function DockPair({ children }) {
    return <div style={{ height: 52, ...cardGlass, borderRadius: 999, padding: '0 4px', display: 'flex', alignItems: 'center', flexShrink: 0 }}>{children}</div>;
  }
  function DockBtn({ children }) {
    return <div style={{ width: 44, height: 44, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{children}</div>;
  }
  function DockDiv() {
    return <div style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.10)' }} />;
  }
  function TabsGlyph() {
    return (
      <svg width="20" height="20" viewBox="0 0 14 14" fill="none" stroke={HEAD} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="4" width="8" height="7" rx="1.5" />
        <path d="M4 4V3a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1h-1" />
      </svg>
    );
  }
}

Object.assign(window, { ExpArticleProperties });
