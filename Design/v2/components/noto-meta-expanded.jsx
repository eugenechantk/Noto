// Noto — Expanded Metadata Frontmatter accordion + baseline reference screens.
//
// The collapsed accordion lives in noto-shared.jsx as <NMetaAccordion />. This
// file adds the EXPANDED state: the full table of frontmatter key/value rows,
// a trailing "key | value | +" empty row for inserting a new pair, and three
// reference screens (iPhone, iPad mini, macOS) that wrap each platform's
// existing realistic editor chrome around the expanded accordion so the rest
// of the design system has a concrete reference for the expanded layout.
//
// Depends on: NOTO, NIcon, NHeading, NRichBody, NImagePlaceholder, NBlockquote,
// NBody, NComment, NCompactNoteRow, NTrafficLights — all on window.
// Plus PhoneTop/PhoneIsland/PhoneEditorChrome/PhoneBottomCapsule/
// PhoneHomeIndicator and IpadStatusBar/IpadEditorChrome/IpadHomeIndicator.

// ─────────────────────────────────────────────────────────────
// Visual tokens — local to the metadata table.
// ─────────────────────────────────────────────────────────────
const META_MONO = '"SF Mono", "JetBrains Mono", ui-monospace, "Menlo", monospace';
const META_KEY_FG    = 'rgba(255,255,255,0.46)';   // muted key column
const META_VAL_FG    = 'rgba(255,255,255,0.92)';   // value text
const META_FAINT_FG  = 'rgba(255,255,255,0.32)';   // placeholders, X glyph
const META_URL_FG    = '#5DA8FF';                   // url value link color
const META_ROW_RULE  = 'rgba(255,255,255,0.05)';   // hairline between rows

// Caret-down chevron — matches stroke style of NIcon "caret-right".
function MetaCaretDown({ size = 14, color = NOTO.metaFg }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
         stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

// X glyph — close/remove row.
function MetaX({ size = 13, color = META_FAINT_FG }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none"
         stroke={color} strokeWidth="1.6" strokeLinecap="round">
      <path d="M3 3l8 8M11 3l-8 8" />
    </svg>
  );
}

// Pencil glyph — edit URL value affordance.
function MetaPencil({ size = 13, color = META_FAINT_FG }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none"
         stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 12l2-0.5L11 4.5 9.5 3 2.5 10 2 12z" />
      <path d="M10 4l1.5-1.5 0.8 0.8L10.8 4.8" />
    </svg>
  );
}

// Plus glyph — append empty row affordance.
function MetaPlus({ size = 13, color = META_FAINT_FG }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none"
         stroke={color} strokeWidth="1.6" strokeLinecap="round">
      <path d="M7 2v10M2 7h10" />
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// MetaRow — one frontmatter row inside the expanded accordion.
//   row: { key, value, kind?: 'text'|'url'|'multiline', valueJSX? }
//   keyColW: fixed pixel width of the left key column
//   density: 'compact' | 'comfortable' — controls row vertical padding
// ─────────────────────────────────────────────────────────────
function NMetaRow({ row, keyColW = 110, density = 'compact', isLast = false, fontSize = 12 }) {
  const padY = density === 'comfortable' ? 11 : 9;
  const isUrl = row.kind === 'url';
  const isMulti = row.kind === 'multiline';

  // Value rendering — string with optional special handling.
  let valueNode;
  if (row.valueJSX !== undefined) {
    valueNode = row.valueJSX;
  } else if (isMulti) {
    // Multi-line value (e.g. yaml tag list). Render each line on its own
    // row, preserving the leading "- " bullet that the screenshots show.
    const lines = String(row.value).split('\n');
    valueNode = (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        {lines.map((ln, i) => (
          <span key={i} style={{
            color: META_VAL_FG, fontFamily: META_MONO, fontSize,
            whiteSpace: 'pre', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{ln}</span>
        ))}
      </div>
    );
  } else {
    valueNode = (
      <span style={{
        color: isUrl ? META_URL_FG : META_VAL_FG,
        fontFamily: META_MONO, fontSize,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        textDecoration: isUrl ? 'underline' : 'none',
        textDecorationColor: 'rgba(93,168,255,0.55)',
        textUnderlineOffset: 2,
        display: 'block',
      }}>{row.value}</span>
    );
  }

  return (
    <div style={{
      display: 'flex', alignItems: isMulti ? 'flex-start' : 'center', gap: 12,
      padding: `${padY}px 14px ${padY}px 16px`,
      borderTop: `0.5px solid ${META_ROW_RULE}`,
    }}>
      {/* key column */}
      <div style={{
        width: keyColW, flexShrink: 0,
        color: META_KEY_FG, fontFamily: META_MONO, fontSize,
        letterSpacing: 0,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{row.key}</div>

      {/* value column */}
      <div style={{ flex: 1, minWidth: 0, overflow: 'hidden' }}>{valueNode}</div>

      {/* trailing affordances: pencil for URLs, then X */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
        {isUrl && <MetaPencil />}
        <MetaX />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// NMetaAccordionExpanded — header (caret-down + "Metadata" + count)
// followed by a vertical stack of MetaRows and a trailing empty
// "key  value  +" insert row.
// ─────────────────────────────────────────────────────────────
function NMetaAccordionExpanded({
  rows = [],
  count,            // displayed count; defaults to rows.length
  keyColW = 110,
  density = 'compact',
  fontSize = 12,
  radius = 10,
}) {
  const n = count ?? rows.length;
  return (
    <div style={{
      background: NOTO.metaBg, borderRadius: radius,
      overflow: 'hidden',
    }}>
      {/* header */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '12px 16px',
      }}>
        <MetaCaretDown size={14} color={NOTO.metaFg} />
        <div style={{
          color: NOTO.metaFg, fontSize: 14, fontWeight: 500,
          letterSpacing: -0.1, flex: 1,
        }}>Metadata</div>
        <div style={{
          color: NOTO.fgFaint, fontSize: 13, fontVariantNumeric: 'tabular-nums',
        }}>{n}</div>
      </div>

      {/* rows */}
      {rows.map((r, i) => (
        <NMetaRow key={i} row={r} keyColW={keyColW} density={density}
          isLast={i === rows.length - 1} fontSize={fontSize} />
      ))}

      {/* trailing empty "key | value | +" insert row */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: `${density === 'comfortable' ? 11 : 9}px 14px ${density === 'comfortable' ? 11 : 9}px 16px`,
        borderTop: `0.5px solid ${META_ROW_RULE}`,
      }}>
        <div style={{
          width: keyColW, flexShrink: 0,
          color: META_FAINT_FG, fontFamily: META_MONO, fontSize,
        }}>key</div>
        <div style={{
          flex: 1, color: META_FAINT_FG, fontFamily: META_MONO, fontSize,
        }}>value</div>
        <MetaPlus />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Canonical sample rows — the realistic "How to Build Strong AI
// Products" frontmatter, used on iPhone + iPad references.
// ─────────────────────────────────────────────────────────────
const META_ROWS_ARTICLE_11 = [
  { key: 'id',              value: 'A1B2C3D4-E5F6-4789-ABCD-EF0123456789' },
  { key: 'created',         value: '2026-05-12T09:15:00Z' },
  { key: 'updated',         value: '2026-05-14T11:40:29Z' },
  { key: 'type',            value: 'source' },
  { key: 'source_kind',     value: '"article"' },
  { key: 'capture_status',  value: 'full' },
  { key: 'source_title',    value: '"How to Build Strong AI Products"' },
  { key: 'source_url',      value: '"https://www.lennysnewsletter.com/p/how-to-build-strong-ai-products"', kind: 'url' },
  { key: 'author',          value: '"Lenny Rachitsky"' },
  { key: 'tags',            value: '- imported/readwise\n  - imported/reader\n  - product/strategy', kind: 'multiline' },
  { key: 'readwise_source', value: '"reader"' },
];

// macOS sample — 17 fields, the "Step 2: Account Warmup Protocol" capture.
const META_ROWS_WARMUP_17 = [
  { key: 'id',                  value: '422C5772-4F5B-46A3-A3C7-B3CD7D67567D' },
  { key: 'created',             value: '2026-04-30T03:50:29Z' },
  { key: 'updated',             value: '2026-05-12T04:33:05Z' },
  { key: 'type',                value: 'source' },
  { key: 'source_kind',         value: '"article"' },
  { key: 'capture_status',      value: 'full' },
  { key: 'canonical_key',       value: '"reader:01kqe7cs7xy02krycc4b76vp29"' },
  { key: 'source_title',        value: '"Step 2: Account Warmup Protocol"' },
  { key: 'reader_document_id',  value: '"01kqe7cs7xy02krycc4b76vp29"' },
  { key: 'source_url',          value: '"https://www.post-bridge.com/growth-guide/account-warmup-protocol"', kind: 'url' },
  { key: 'reader_url',          value: '"https://read.readwise.io/read/01kqe7cs7xy02krycc4b76vp29"',           kind: 'url' },
  { key: 'reader_location',     value: '"new"' },
  { key: 'author',              value: '"post-bridge.com"' },
  { key: 'site_name',           value: '"post bridge"' },
  { key: 'published',           value: '"2025-08-21"' },
  { key: 'word_count',          value: '442' },
  { key: 'tags',                value: '- imported/reader\n  - "marketing"', kind: 'multiline' },
];

// ═════════════════════════════════════════════════════════════
// iPhone — Editor with EXPANDED metadata accordion.
// Same chrome + same realistic note as ScreenPhoneEditorRealistic,
// just with the accordion open. Body collapses below the fold.
// ═════════════════════════════════════════════════════════════
function ScreenPhoneEditorMetaExpanded() {
  const W = 402, H = 874;
  return (
    <div style={{
      width: W, height: H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <PhoneTop />
      <PhoneIsland />
      <PhoneEditorChrome />

      <div style={{ padding: '14px 18px 0' }}>
        <NMetaAccordionExpanded
          rows={META_ROWS_ARTICLE_11}
          count={11}
          keyColW={108}
          fontSize={12}
        />

        {/* Body continues below the (now tall) accordion — the
            screenshot crops here, with the floating capsule sitting
            atop the body content. */}
        <NRichBody marginTop={22} fontSize={15} parts={[
          'The defining question for AI products in 2026 is no longer ',
          { italic: 'can we build it?' },
          ' \u2014 model capability has caught up to ambition. The ',
          { link: '@harder' },
          ' question is ',
          { italic: 'what does this become once people use it every day?' },
          ' As ',
          { link: 'Sahil Lavingia recently argued' },
          ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap. That distinction is doing a lot ',
        ]} />
      </div>

      <PhoneBottomCapsule />
      <PhoneHomeIndicator />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// iPad mini — Editor with EXPANDED metadata accordion.
// Wider key column, more comfortable row padding, and a 16px
// monospace size that matches the iPad's body type rhythm.
// ═════════════════════════════════════════════════════════════
function ScreenIpadEditorMetaExpanded() {
  return (
    <div style={{
      width: IPAD_W, height: IPAD_H, background: NOTO.bg, position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg, overflow: 'hidden',
    }}>
      <IpadStatusBar />
      <IpadEditorChrome />
      <div style={{ padding: '16px 60px 0' }}>
        <NMetaAccordionExpanded
          rows={META_ROWS_ARTICLE_11}
          count={11}
          keyColW={150}
          fontSize={13}
          density="comfortable"
          radius={12}
        />

        {/* Body continues — image + opening paragraph, matching the
            iPad realistic editor's rhythm. */}
        <NImagePlaceholder marginTop={20} height={260} label="1200 × 500" />

        <NRichBody marginTop={24} fontSize={16} parts={[
          'The defining question for AI products in 2026 is no longer ',
          { italic: 'can we build it?' },
          ' \u2014 model capability has caught up to ambition. The harder question is ',
          { italic: 'what does this become once people use it every day?' },
          ' As ',
          { link: 'Sahil Lavingia recently argued' },
          ', durable products are the ones whose value compounds with the user\u2019s data, not the ones whose value depends on a model swap. That distinction is doing a lot of work in the market right now.',
        ]} />

        <NHeading level={2} marginTop={32}>The compounding loop</NHeading>

        <NRichBody marginTop={22} fontSize={16} parts={[
          'A compounding product feels different when you open it on day 30 versus day 1. It remembers what you cared about. It surfaces what you forgot. It connects the dots you didn\u2019t have time to. According to ',
          { link: 'Patrick Collison\u2019s essay on agency' },
          ', the products people stick with are the ones that "make you feel slightly smarter every time you return@ @\n." That feeling is rarely the model \u2014 it\u2019s the accumulated context.',
        ]} />

        <NBlockquote marginTop={24} fontSize={16}>
          The only moat AI startups have left is the one their users are quietly building for them every day, without realizing it.
        </NBlockquote>
      </div>
      <IpadHomeIndicator />
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// macOS — Window with EXPANDED metadata accordion in editor pane.
// Same window chrome + list pane as ScreenMacWindow. Editor body
// uses the 17-field "Account Warmup Protocol" frontmatter so a
// wider key column and more rows are exercised.
// ═════════════════════════════════════════════════════════════
function ScreenMacWindowMetaExpanded() {
  const W = 1280, H = 880;
  const LIST_W = 320;

  const items = [
    { name: '\uD83E\uDD80 Crabbox Docs',                   time: '2 seconds ago' },
    { name: 'The blueprint for becoming an emotionall\u2026', time: '2 days ago' },
    { name: 'Looking for Alice',                            time: '2 days ago' },
    { name: 'Dostoevsky as lover',                          time: '2 days ago' },
    { name: 'Why Vertical LLM Agents Are The New $1\u2026',  time: '2 days ago' },
    { name: 'Sometimes the reason you can\u2019t find peo\u2026', time: '2 days ago' },
    { name: 'Relationships are coevolutionary loops',       time: '2 days ago' },
    { name: 'This is it',                                   time: '2 days ago' },
    { name: 'A Primer On The Agentic AI Economy',           time: '2 days ago' },
    { name: '$10M/yr app idea',                             time: '4 days ago' },
    { name: 'how to consistently get high views on Tik\u2026', time: '4 days ago' },
    { name: 'This app makes $1M/mo helping people ki\u2026',  time: '4 days ago' },
    { name: 'This is how I try to target a US audience.\u2026', time: '4 days ago' },
    { name: 'Step 2 Account Warmup Protocol',               time: '4 days ago', selected: true },
    { name: 'I speedran a new app from 0 to $2m/year\u2026',  time: '4 days ago' },
    { name: 'Someone\u2019s going to make a lot of money\u2026', time: '4 days ago' },
    { name: 'The Wu Tapes',                                 time: '4 days ago' },
    { name: 'Using Claude Code The Unreasonable Eff\u2026',  time: '6 days ago' },
    { name: 'Fuck dropshipping, Fuck claude code, Fu\u2026',  time: '1 week ago' },
    { name: 'the internet where 85% of the money is (\u2026', time: '1 week ago' },
  ];

  return (
    <div style={{
      width: W, height: H,
      background: '#1A1B1F',
      borderRadius: 12, overflow: 'hidden', position: 'relative',
      fontFamily: NOTO.font, color: NOTO.fg,
      boxShadow: '0 30px 80px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)',
      display: 'flex',
    }}>
      {/* LEFT pane — list */}
      <div style={{
        width: LIST_W, height: '100%', display: 'flex', flexDirection: 'column',
        background: '#101115',
        borderRight: '0.5px solid rgba(255,255,255,0.07)',
      }}>
        <div style={{ height: 46, display: 'flex', alignItems: 'center', padding: '0 16px' }}>
          <NTrafficLights />
        </div>
        <div style={{
          height: 40, display: 'flex', alignItems: 'center',
          padding: '0 14px', gap: 10,
        }}>
          <NIcon name="chevron-left" size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <div style={{ flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 700, letterSpacing: -0.1 }}>Captures</div>
          <NIcon name="search" size={17} color={NOTO.fgMuted} strokeWidth={1.7} />
        </div>
        <div style={{ height: 0.5, background: 'rgba(255,255,255,0.06)' }} />
        <div style={{ flex: 1, overflow: 'hidden', padding: '6px 6px 8px' }}>
          {items.map((it, i) => (
            <NCompactNoteRow key={i} name={it.name} time={it.time} selected={it.selected} />
          ))}
        </div>
      </div>

      {/* RIGHT pane — editor */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        <div style={{
          height: 46, display: 'flex', alignItems: 'center', gap: 14,
          padding: '0 18px 0 18px',
        }}>
          <NIcon name="sidebar"      size={19} color={NOTO.fgMuted} strokeWidth={1.7} />
          <NIcon name="arrow-back"   size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <NIcon name="arrow-fwd"    size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <NIcon name="calendar"     size={18} color={NOTO.fgMuted} strokeWidth={1.7} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginLeft: 16 }}>
            <span style={{ color: NOTO.fgMuted, fontSize: 14 }}>Noto</span>
            <NIcon name="caret-right" size={12} color={NOTO.fgMuted} />
            <span style={{ color: NOTO.fg,   fontSize: 14, fontWeight: 600 }}>Captures</span>
          </div>
          <div style={{ flex: 1 }} />
          <div style={{
            display: 'flex', alignItems: 'center', gap: 4,
            padding: '4px 6px 4px 10px',
            background: 'rgba(255,255,255,0.06)',
            borderRadius: 14,
          }}>
            <NIcon name="ellipsis" size={18} color={NOTO.fg} />
            <NIcon name="caret-down" size={14} color={NOTO.fgMuted} />
          </div>
        </div>
        <div style={{ height: 0.5, background: 'rgba(255,255,255,0.06)' }} />

        {/* editor body */}
        <div style={{ flex: 1, overflow: 'hidden', padding: '20px 44px 0' }}>
          <NMetaAccordionExpanded
            rows={META_ROWS_WARMUP_17}
            count={17}
            keyColW={190}
            fontSize={14}
            density="comfortable"
            radius={12}
          />

          <NBody marginTop={28} fontSize={15}>
            Skipping this step also often flags your account as a bot, and you will get
            0–100 max views on your first posts. A new user doesnt create an account
            and instantly post, they watch content and engage with it, only a small % post,
            so new accounts spamming out bots are flagged as spam.
          </NBody>

          <NBody marginTop={22} fontSize={15}>
            7 days seems to be the safest amount of time to warmup a new account. You
            can do just 3 days of warmup, but I would recommend 7 days to be safe.
            Everytime i do 3 days of warmup it sometimes is enough, but sometimes i
            need to stop posting again and resume warmup for another few days. Just be
            patient and keep warmup going for 7 days. Then you can post and get views.
          </NBody>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  NMetaAccordionExpanded, NMetaRow,
  META_ROWS_ARTICLE_11, META_ROWS_WARMUP_17,
  ScreenPhoneEditorMetaExpanded,
  ScreenIpadEditorMetaExpanded,
  ScreenMacWindowMetaExpanded,
});
