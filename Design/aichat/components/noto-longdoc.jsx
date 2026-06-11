// noto-longdoc.jsx
// ─────────────────────────────────────────────────────────────
// One long-form test document, shared by every screen that shows the editor
// (dock reading/scrolled/editing, find-in-note, and the property surface's
// article body). Lets us see how a genuinely long note renders + clips.
// Exposes on window: NOTO_LEDE, NOTO_DOC, renderNotoDoc, makeCompoundHL,
// countCompound.

(function () {
  const INK    = '#ECECEE';
  const HEAD   = '#FFFFFF';
  const ACCENT = '#FF6A2E';
  const SANS   = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif';
  const HL     = 'rgba(230,182,42,0.32)';

  const NOTO_LEDE = 'A field guide for founders shipping AI features in 2026 — what separates the products that compound from the ones that flame out after a launch week.';

  // Body blocks (after the lede). t: 'p' | 'h2' | 'ol' | 'quote'.
  const NOTO_DOC = [
    { t: 'p', s: 'The defining question for AI products in 2026 is no longer can we build it? — model capability has caught up to ambition. The harder question is what does this become once people use it every day?' },
    { t: 'p', s: 'As Sahil Lavingia recently argued, durable products are the ones whose value compounds with the user’s data, not the ones whose value depends on a model swap. The distinction sounds academic until you watch two products launch the same week and diverge six months later.' },
    { t: 'h2', s: 'The compounding loop' },
    { t: 'p', s: 'Every product has a loop. For social apps it’s the post-and-react loop; for marketplaces it’s the list-and-buy loop. For AI products the loop that matters is the one where the system gets measurably better at helping you specifically — not better in the aggregate, better for you.' },
    { t: 'p', s: 'When that loop is tight, each session deposits something the next session can draw on. When it’s loose, every session starts from zero and the novelty wears off within a week. The products that compound make the loop impossible to leave; the ones that flame out never close it.' },
    { t: 'h2', s: 'The three deposits' },
    { t: 'p', s: 'Each interaction should leave behind a deposit: a memory, a preference, a sliver of taste. Over weeks these deposits compound into a product that feels like yours and like no one else’s.' },
    { t: 'ol', items: [
      'Memory — what the system remembers about you and your work',
      'Preference — the things you asked it to do differently, encoded so you never repeat yourself',
      'Taste — the rough shape of what you’d call “good,” learned from what you keep and what you discard',
    ] },
    { t: 'p', s: 'None of these require a frontier model. They require a product that treats every edit, correction, and discarded draft as signal rather than exhaust.' },
    { t: 'quote', s: 'The model layer is interchangeable. The data you’ve accumulated, and the trust that came with it, is not.' },
    { t: 'h2', s: 'Why the model layer is interchangeable' },
    { t: 'p', s: 'Two years from now you’ll still have a usable product even if you swap the underlying weights — provided the deposits survive the swap. That’s the test: if a better model shipped tomorrow, would your moat get wider or vanish? If it vanishes, you were renting capability, not building a product.' },
    { t: 'p', s: 'This is why the teams that obsess over prompt-level cleverness tend to plateau. Cleverness at the model layer is the most copyable thing in software. Accumulated context is the least, and it is where value quietly compounds.' },
    { t: 'h2', s: 'What this means for builders' },
    { t: 'p', s: 'Stop optimizing the demo. Optimize the tenth session. The demo sells the first download; the tenth session is where compounding either kicks in or doesn’t, and it’s the only session your retention curve actually remembers.' },
    { t: 'p', s: 'Concretely: instrument the loop, make memory visible, let people correct the system cheaply, and never throw away a signal you could have kept. Do that and the model layer becomes a detail. Skip it and no amount of model capability will save the launch.' },
    { t: 'p', s: 'The products that compound in 2026 won’t be the ones with the best model on launch day. They’ll be the ones still getting better on day three hundred, quietly, because they were built to.' },
  ];

  // A highlighter with an internal match counter so only the FIRST "compound…"
  // match across the whole document is the active (solid) hit.
  function makeCompoundHL() {
    let idx = 0;
    return (text) => {
      const parts = text.split(/(compound[a-z]*)/gi);
      return parts.map((p, i) => {
        if (/^compound/i.test(p)) {
          idx++;
          const active = idx === 1;
          return (
            <span key={i} style={{ background: active ? '#E6B62A' : HL, color: active ? '#1a1100' : HEAD, borderRadius: 3, padding: '0 2px', fontWeight: active ? 600 : 400 }}>{p}</span>
          );
        }
        return <React.Fragment key={i}>{p}</React.Fragment>;
      });
    };
  }

  function countCompound() {
    let n = 0;
    const scan = (s) => { const m = s.match(/compound[a-z]*/gi); if (m) n += m.length; };
    scan(NOTO_LEDE);
    NOTO_DOC.forEach((b) => { if (b.s) scan(b.s); if (b.items) b.items.forEach(scan); });
    return n;
  }

  // Render the body blocks (from `from` onward). `hl` is an optional highlighter.
  function renderNotoDoc({ from = 0, hl = null } = {}) {
    const r = (s) => (hl ? hl(s) : s);
    return NOTO_DOC.slice(from).map((b, i) => {
      if (b.t === 'h2') {
        return <h2 key={i} style={{ margin: '24px 0 10px', color: HEAD, fontFamily: SANS, fontSize: 18, fontWeight: 700, letterSpacing: -0.2 }}>{b.s}</h2>;
      }
      if (b.t === 'ol') {
        return <ol key={i} style={{ margin: '0 0 14px', paddingLeft: 22, color: INK, fontFamily: SANS, fontSize: 16, lineHeight: 1.55 }}>{b.items.map((it, j) => <li key={j} style={{ marginBottom: 6 }}>{r(it)}</li>)}</ol>;
      }
      if (b.t === 'quote') {
        return <blockquote key={i} style={{ margin: '0 0 16px', padding: '2px 0 2px 14px', borderLeft: '2px solid ' + ACCENT, color: INK, fontFamily: SANS, fontStyle: 'italic', fontSize: 16, lineHeight: 1.5 }}>{r(b.s)}</blockquote>;
      }
      return <p key={i} style={{ margin: '0 0 14px', color: INK, fontFamily: SANS, fontSize: 16, lineHeight: 1.55 }}>{r(b.s)}</p>;
    });
  }

  Object.assign(window, { NOTO_LEDE, NOTO_DOC, renderNotoDoc, makeCompoundHL, countCompound });
})();
