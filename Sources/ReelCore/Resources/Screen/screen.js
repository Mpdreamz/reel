// reel's code screen. Swift drives it through `reelScreen`: each call changes what is shown, and `pump(ms)` moves the
// clock on and lays the frame out. Every animation is a tween read from `screen.now`, never from wall time, so the
// same reel draws the same frames.
//
// The screen is one pane, or two side by side after `split`. Each pane is an editor with its file's header and reel's
// own overlay (caret, marks, callout). Steps act on the active pane: the one last opened, or the one `pane` chose.
(function () {
  const dimmed = 0.32;
  const easings = {
    linear: (t) => t,
    'ease-in': (t) => t * t * t,
    'ease-out': (t) => 1 - Math.pow(1 - t, 3),
    'ease-in-out': (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
    smooth: (t) => (1 - Math.cos(Math.PI * t)) / 2,
    snap: () => 1,
  };
  const ease = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
  const stage = document.getElementById('stage');
  const svg = document.getElementById('links');
  const svgNS = 'http://www.w3.org/2000/svg';

  let options = null;
  let panes = [];
  let active = null;
  /// How far the second pane has come in: 0 one pane, 1 two halves.
  let split = 0;
  let tweens = [];
  let links = [];
  // Something was asked of the page since the last frame.
  let dirty = true;
  let pops = 0;

  const screen = {
    now: 0,
    ready: false,
    error: null,

    /// Loads Monaco and the fonts; `ready` turns true once text can be measured.
    init(o) {
      options = o;
      require.config({ paths: { vs: 'monaco/vs' } });
      require(['vs/editor/editor.main'], () => {
        monaco.editor.defineTheme('reel', {
          base: 'vs-dark',
          inherit: true,
          rules: [
            { token: 'keyword', foreground: 'F2B04C' },
            { token: 'string', foreground: '7FD1C0' },
            { token: 'regexp', foreground: '7FD1C0' },
            { token: 'number', foreground: 'F29E84' },
            { token: 'constant', foreground: 'F29E84' },
            { token: 'comment', foreground: '8397AB', fontStyle: 'italic' },
            { token: 'type', foreground: '86B6F2' },
            { token: 'type.identifier', foreground: '86B6F2' },
            { token: 'tag', foreground: '86B6F2' },
            { token: 'annotation', foreground: 'B9A6F2' },
            { token: 'attribute.name', foreground: 'B9A6F2' },
            { token: 'attribute.value', foreground: '7FD1C0' },
            { token: 'metatag', foreground: 'B9A6F2' },
          ],
          colors: {
            'editor.background': '#111923',
            'editor.foreground': '#E7ECF1',
            'editorLineNumber.foreground': '#4F6275',
            'editorLineNumber.activeForeground': '#9BABBB',
            'editor.selectionBackground': '#2F4A66',
            'editor.inactiveSelectionBackground': '#2F4A66',
            'editorIndentGuide.background1': '#1d2b3a',
            'editorWhitespace.foreground': '#2a3b4e',
          },
        });
        registerReel();
        active = makePane();
        panes = [active];
        document.fonts.load(`${o.fontSize}px 'JetBrains Mono'`).then(() =>
          Promise.all([
            document.fonts.load(`500 ${o.fontSize}px 'JetBrains Mono'`),
            document.fonts.load("500 15px 'Instrument Sans'"),
            document.fonts.load("400 15px 'Instrument Sans'"),
            document.fonts.load("500 13px 'Instrument Sans'"),
          ])
        ).then(() => {
          monaco.editor.remeasureFonts();
          layout();
          screen.ready = true;
        }, (e) => { screen.error = 'fonts: ' + e; });
      }, (e) => { screen.error = 'monaco: ' + e; });
      return true;
    },

    /// Shows a file in the active pane: `text` is what is shown (the whole file, or `lines a-b` of it, numbered from
    /// `firstLine`). With a `transition` (`{ kind, easing, ms }`), the file before moves out as it comes in; without
    /// one, it comes up from the background. Resolves to an error message, or null.
    async open(f, transition) {
      const pane = active;
      const leaving = pane.file && transition && transition.kind !== 'cut' ? snapshot(pane) : null;
      const problem = await show(pane, f);
      if (problem) { if (leaving) leaving.remove(); return problem; }
      if (!transition) {
        // The new file comes up from the background.
        tween('fade', 300, 0, 1, (v) => { pane.content.style.opacity = v; }, null, null, pane);
      } else {
        move(pane, leaving, transition);
      }
      return null;
    },

    /// Turns the active pane's file into `f`: the words both show move from where they were to where they are now,
    /// the rest fade out and in, over `motion` (`{ easing, ms }`). Resolves to an error message, or null.
    async morph(f, motion) {
      const pane = active;
      if (!pane.file) return screen.open(f, null);
      const before = words(pane);
      const problem = await show(pane, f);
      if (problem) return problem;
      // Laid out now, so where every word lands can be measured before anything moves.
      pane.ed.render(true);
      const after = words(pane);
      const layer = el('div', 'morph');
      pane.root.appendChild(layer);
      pane.root.classList.add('morphing');
      const pieces = [];
      const put = (word, at, kind) => {
        const node = el('span', 'word', word.text);
        Object.assign(node.style, { left: at.x + 'px', top: at.y + 'px', color: word.color }, word.font);
        layer.appendChild(node);
        // Its text where the editor's would be: corrected once for how a span sets text against how Monaco does.
        const shown = textBox(node);
        const piece = { node, kind, dx: at.x - shown.x, dy: at.y - shown.y };
        pieces.push(piece);
        return piece;
      };
      for (const [from, to] of match(before, after)) {
        if (from && to) Object.assign(put(to, from, 'move'), { from, to, colour: [from.color, to.color] });
        else if (from) Object.assign(put(from, from, 'out'), { from, to: from });
        else Object.assign(put(to, to, 'in'), { from: to, to });
      }
      // The new file's line numbers come in as its words settle.
      const margin = pane.code.querySelector('.margin');
      tween('morph', motion.ms, 0, 1, (p) => {
        if (margin) margin.style.opacity = String(Math.max(0, 2 * p - 1));
        for (const piece of pieces) {
          const x = piece.from.x + (piece.to.x - piece.from.x) * p;
          const y = piece.from.y + (piece.to.y - piece.from.y) * p;
          piece.node.style.left = x + piece.dx + 'px';
          piece.node.style.top = y + piece.dy + 'px';
          if (piece.kind === 'out') piece.node.style.opacity = String(Math.max(0, 1 - 2 * p));
          if (piece.kind === 'in') piece.node.style.opacity = String(Math.max(0, 2 * p - 1));
          if (piece.colour) piece.node.style.color = p < 0.5 ? piece.colour[0] : piece.colour[1];
        }
      }, () => {
        layer.remove();
        pane.root.classList.remove('morphing');
        if (margin) margin.style.opacity = '';
      }, motion.easing, pane);
      return null;
    },

    /// Opens a second pane beside the first with `f`, and makes it the active one; null closes it again.
    async split(f) {
      if (f === null) {
        if (panes.length < 2) return 'there is no second pane to close';
        const closing = panes[1];
        links = links.filter((l) => {
          const keep = l.from.pane !== closing && l.to.pane !== closing;
          if (!keep) l.group.remove();
          return keep;
        });
        active = panes[0];
        tween('split', 450, split, 0, (v) => { split = v; layout(); }, () => {
          closing.ed.dispose();
          closing.root.remove();
          panes = panes.filter((p) => p !== closing);
          layout();
        }, 'ease-in-out');
        return null;
      }
      if (panes.length > 1) return 'the screen is already split; Split off first';
      const pane = makePane();
      panes.push(pane);
      split = 0;
      layout();
      const problem = await show(pane, f);
      if (problem) {
        pane.ed.dispose();
        pane.root.remove();
        panes.pop();
        layout();
        return problem;
      }
      active = pane;
      tween('split', 450, 0, 1, (v) => { split = v; layout(); }, null, 'ease-in-out');
      return null;
    },

    /// Makes the left (0) or right (1) pane the active one.
    pane(index) {
      if (!panes[index]) return 'there is no right pane: Split a file first';
      active = panes[index];
      return null;
    },

    /// Moves the cursor to `{ line }` (as the file numbers it) or the first `{ text }`, scrolling to show it.
    go(anchor) {
      const pane = active;
      const found = place(pane, anchor);
      if (typeof found === 'string') return found;
      pane.ed.setPosition({ lineNumber: found.line, column: found.column });
      reveal(pane, found.line, found.line, 400);
      return null;
    },

    /// Types `text` at the cursor, over any selection.
    type(text) {
      insert(active, text);
      return null;
    },

    /// One key: an edit, a move, or (with shift) a selection.
    key(name, shift) {
      const pane = active, ed = pane.ed;
      const moves = {
        left: 'cursorLeft', right: 'cursorRight', up: 'cursorUp', down: 'cursorDown',
        home: 'cursorHome', end: 'cursorEnd', pageup: 'cursorPageUp', pagedown: 'cursorPageDown',
      };
      if (moves[name]) {
        ed.trigger('reel', moves[name] + (shift ? 'Select' : ''), null);
        follow(pane);
        return null;
      }
      switch (name) {
        case 'return': case 'enter': {
          const p = ed.getPosition();
          const indent = ed.getModel().getLineContent(p.lineNumber).match(/^\s*/)[0];
          insert(pane, '\n' + indent.slice(0, Math.max(0, p.column - 1)));
          break;
        }
        case 'tab': {
          const column = ed.getPosition().column;
          insert(pane, ' '.repeat(4 - ((column - 1) % 4)));
          break;
        }
        case 'space': insert(pane, ' '); break;
        case 'backspace': case 'delete': ed.trigger('reel', 'deleteLeft', null); follow(pane); break;
        case 'forwarddelete': ed.trigger('reel', 'deleteRight', null); follow(pane); break;
        case 'escape': case 'esc': ed.setPosition(ed.getPosition()); break;
        default: return 'the code screen takes no key ' + name;
      }
      return null;
    },

    /// Brightens lines `a`-`b` (as the file numbers them) and dims the rest; null brightens everything again.
    focus(range) {
      const pane = active, ed = pane.ed;
      const model = ed.getModel();
      const count = model.getLineCount();
      if (range) {
        const a = rowOf(pane.file, model, range[0]);
        const b = rowOf(pane.file, model, range[1]);
        if (a === null || b === null || b < a) return `lines ${range[0]}-${range[1]} are not all in ${pane.file.name}`;
        const outside = [];
        if (a > 1) outside.push(new monaco.Range(1, 1, a - 1, model.getLineMaxColumn(a - 1)));
        if (b < count) outside.push(new monaco.Range(b + 1, 1, count, model.getLineMaxColumn(count)));
        pane.focus = ed.deltaDecorations(pane.focus, outside.map((r) => ({
          range: r, options: { inlineClassName: 'reel-dim', isWholeLine: true },
        })));
        tween('dim', 350, pane.dim, dimmed, (v) => setDim(pane, v), null, null, pane);
        reveal(pane, a, b, 400);
      } else {
        const remove = pane.focus;
        tween('dim', 350, pane.dim, 1, (v) => setDim(pane, v), () => {
          pane.focus = ed.deltaDecorations(remove, []);
        }, null, pane);
      }
      return null;
    },

    /// A box around the first `text`, numbered when `n` is given; null clears every box.
    mark(text, n) {
      const pane = active;
      if (text === null) { clearMarks(pane); return null; }
      const range = find(pane, text);
      if (!range) return `"${text}" is not in ${pane.file.name}`;
      const box = el('div', 'mark');
      if (n !== null) box.appendChild(el('span', 'n', String(n)));
      pane.overlay.appendChild(box);
      pane.marks.push({ range, born: screen.now, el: box });
      tween('pop' + pops++, 180, 0, 1, () => {});
      reveal(pane, range.startLineNumber, range.endLineNumber, 400);
      return null;
    },

    /// A bubble saying `label`, pointing at the first `text`; null takes it away.
    callout(text, label) {
      const pane = active;
      clearCallout(pane);
      if (text === null) return null;
      const range = find(pane, text);
      if (!range) return `"${text}" is not in ${pane.file.name}`;
      const bubble = el('div', 'callout', label);
      const under = el('div', 'under');
      pane.overlay.append(under, bubble);
      pane.callout = { range, born: screen.now, el: bubble, under };
      tween('pop' + pops++, 180, 0, 1, () => {});
      reveal(pane, range.startLineNumber, range.endLineNumber + 3, 400);
      return null;
    },

    /// Opens `f` in a box under the line with the first `text` in the active pane, as an editor peeks a definition;
    /// `text` null closes the box.
    async peek(text, f) {
      const pane = active;
      if (text === null) {
        if (!pane.peek) return 'there is no peek to close';
        closePeek(pane);
        return null;
      }
      const range = find(pane, text);
      if (!range) return `"${text}" is not in ${pane.file.name}`;
      if (pane.peek) closePeek(pane, true);
      const language = languageFor(f.name);
      await monaco.editor.colorize('', language.id, {});
      const lineHeight = pane.ed.getOption(monaco.editor.EditorOption.lineHeight);
      const model = monaco.editor.createModel(f.text, language.id);
      const shown = Math.min(model.getLineCount(), options.peekLines);
      const height = 30 + shown * lineHeight + 14 + 4;
      const node = el('div', 'peek');
      const bar = el('div', 'bar');
      bar.append(el('span', 'name', f.name), el('span', 'path', f.directory));
      const holder = el('div', 'editor');
      node.append(bar, holder);
      const inner = monaco.editor.create(holder, editorOptions({ readOnly: true, padding: { top: 7, bottom: 7 } }));
      inner.setModel(model);
      inner.updateOptions({ lineNumbers: (n) => String(n + f.firstLine - 1) });
      let at = 1;
      if (f.at) {
        const found = placeIn(model, { firstLine: f.firstLine, name: f.name, diff: null }, f.at);
        if (typeof found === 'string') { inner.dispose(); model.dispose(); return found; }
        at = found.line;
        inner.deltaDecorations([], [{
          range: new monaco.Range(at, 1, at, 1), options: { isWholeLine: true, className: 'peek-line' },
        }]);
      }
      forceTokens(model);
      const peek = { node, inner, model, zone: null, id: null };
      pane.ed.changeViewZones((zones) => {
        peek.zone = { afterLineNumber: range.startLineNumber, heightInPx: 0, domNode: node };
        peek.id = zones.addZone(peek.zone);
      });
      pane.peek = peek;
      sizePeek(pane);
      inner.setScrollTop(Math.max(0, inner.getTopForLineNumber(at) - lineHeight));
      tween('peek', 320, 0, height, (v) => {
        peek.zone.heightInPx = v;
        pane.ed.changeViewZones((zones) => zones.layoutZone(peek.id));
      }, null, 'ease-out', pane);
      // Scrolled, as it opens, until the box's bottom shows: the file is not yet as tall as it will be, so this
      // aims past where it can scroll now, and gets there as the box grows.
      const bottom = pane.ed.getTopForLineNumber(range.startLineNumber) + lineHeight + height + lineHeight / 2;
      const view = pane.ed.getLayoutInfo().height;
      if (bottom > targetTop(pane) + view) {
        tween('scroll', 320, pane.ed.getScrollTop(), Math.round(bottom - view), (v) => {
          pane.ed.setScrollTop(Math.round(v));
        }, null, 'ease-out', pane);
      }
      return null;
    },

    /// An arrow from the first `from` to the first `to`, labelled. Split, it goes across the panes: `from` is looked
    /// for on the left first, `to` on the other side. null clears every arrow.
    link(from, to, label) {
      if (from === null) {
        links.forEach((l) => l.group.remove());
        links = [];
        return null;
      }
      const left = panes[0], right = panes[panes.length - 1];
      const start = findIn([left, right], from);
      if (!start) return `"${from}" is not on the screen`;
      const end = findIn(start.pane === left ? [right, left] : [left, right], to, start);
      if (!end) return `"${to}" is not on the screen`;
      const group = document.createElementNS(svgNS, 'g');
      const path = document.createElementNS(svgNS, 'path');
      path.setAttribute('pathLength', '1');
      path.setAttribute('marker-end', 'url(#arrow)');
      path.style.strokeDasharray = '1';
      group.appendChild(path);
      let caption = null;
      if (label) {
        caption = document.createElementNS(svgNS, 'g');
        caption.setAttribute('class', 'label');
        const rect = document.createElementNS(svgNS, 'rect');
        const words = document.createElementNS(svgNS, 'text');
        words.textContent = label;
        caption.append(rect, words);
        group.appendChild(caption);
      }
      svg.appendChild(group);
      links.push({ from: start, to: end, group, path, caption, born: screen.now });
      tween('pop' + pops++, 500, 0, 1, () => {});
      reveal(start.pane, start.range.startLineNumber, start.range.startLineNumber, 400);
      if (end.pane !== start.pane) reveal(end.pane, end.range.startLineNumber, end.range.startLineNumber, 400);
      return null;
    },

    /// Moves the clock on by `ms`, runs what was waiting for a frame, and lays the overlays out. Returns where the
    /// active pane's caret is, in points from the page's top left, or null before a file is open.
    pump(ms) {
      screen.now += ms;
      const changed = dirty || tweens.length > 0;
      dirty = false;
      const due = tweens;
      tweens = [];
      for (const t of due) {
        const p = Math.min(1, (screen.now - t.start) / t.duration);
        t.apply(t.from + (t.to - t.from) * t.curve(p));
        if (p < 1) tweens.push(t); else if (t.done) t.done();
      }
      window.__runFrames(screen.now);
      let at = null;
      for (const pane of panes) {
        const caret = draw(pane);
        if (pane === active) at = caret;
      }
      drawLinks();
      return { changed, x: at ? at.x : null, y: at ? at.y : null };
    },
  };

  // Every step marks the next frame as changed.
  for (const name of ['open', 'morph', 'split', 'pane', 'go', 'type', 'key', 'focus', 'mark', 'callout', 'peek', 'link']) {
    const step = screen[name];
    screen[name] = function () { dirty = true; return step.apply(screen, arguments); };
  }

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function editorOptions(extra) {
    const fontSize = options.fontSize;
    return Object.assign({
      value: '',
      language: 'plaintext',
      theme: 'reel',
      fontFamily: 'JetBrains Mono',
      fontSize,
      lineHeight: Math.round(fontSize * 1.5),
      minimap: { enabled: false },
      automaticLayout: false,
      renderLineHighlight: 'none',
      cursorBlinking: 'solid',
      scrollBeyondLastLine: false,
      smoothScrolling: false,
      scrollbar: { vertical: 'hidden', horizontal: 'hidden', handleMouseWheel: false },
      overviewRulerLanes: 0,
      hideCursorInOverviewRuler: true,
      padding: { top: Math.round(fontSize * 0.8), bottom: Math.round(fontSize * 0.8) },
      autoClosingBrackets: 'never',
      autoClosingQuotes: 'never',
      autoIndent: 'none',
      quickSuggestions: false,
      suggestOnTriggerCharacters: false,
      parameterHints: { enabled: false },
      hover: { enabled: false },
      occurrencesHighlight: 'off',
      selectionHighlight: false,
      matchBrackets: 'never',
      links: false,
      folding: false,
      guides: { indentation: false },
      glyphMargin: false,
      lineDecorationsWidth: 14,
      renderWhitespace: 'none',
      stickyScroll: { enabled: false },
      wordWrap: 'off',
      readOnly: false,
      domReadOnly: true,
      tabSize: 4,
    }, extra || {});
  }

  /// A pane: its header, its editor and its overlay, in a box `layout` places.
  function makePane() {
    const root = el('div', 'pane');
    const content = el('div', 'content');
    const header = el('div', 'header');
    const code = el('div', 'code');
    const overlay = el('div', 'overlay');
    const caret = el('div', 'caret');
    caret.style.display = 'none';
    overlay.appendChild(caret);
    content.append(header, code, overlay);
    root.appendChild(content);
    stage.appendChild(root);
    const ed = monaco.editor.create(code, editorOptions());
    return {
      root, content, header, code, overlay, caret, ed, file: null, marks: [], callout: null, focus: [], dim: 1,
      peek: null,
    };
  }

  /// Where each pane sits: the whole width, or the second coming in from the right to take half.
  function layout() {
    const width = document.body.clientWidth, height = document.body.clientHeight;
    const half = Math.round(width / 2);
    const first = Math.round(width - split * (width - half));
    panes.forEach((pane, index) => {
      const left = index === 0 ? 0 : first;
      const own = index === 0 ? first : half;
      Object.assign(pane.root.style, { left: left + 'px', width: own + 'px' });
      pane.ed.layout({ width: own, height: height - pane.code.offsetTop });
      if (pane.peek) sizePeek(pane);
    });
  }

  function sizePeek(pane) {
    const peek = pane.peek;
    const info = pane.ed.getLayoutInfo();
    const width = Math.max(200, info.width - info.contentLeft - 18);
    const lineHeight = pane.ed.getOption(monaco.editor.EditorOption.lineHeight);
    peek.node.style.width = width + 'px';
    peek.inner.layout({ width, height: Math.min(peek.model.getLineCount(), options.peekLines) * lineHeight + 14 });
  }

  function closePeek(pane, now) {
    const peek = pane.peek;
    pane.peek = null;
    const remove = () => {
      pane.ed.changeViewZones((zones) => zones.removeZone(peek.id));
      peek.inner.dispose();
      peek.model.dispose();
    };
    if (now) {
      tweens = tweens.filter((t) => !(t.kind === 'peek' && t.pane === pane));
      remove();
      return;
    }
    tween('peek', 260, peek.zone.heightInPx, 0, (v) => {
      peek.zone.heightInPx = v;
      pane.ed.changeViewZones((zones) => zones.layoutZone(peek.id));
    }, remove, 'ease-in', pane);
  }

  /// Puts `f` in `pane`: its text, its header, the cursor at its place. Resolves to an error message, or null.
  async function show(pane, f) {
    const language = languageFor(f.name);
    // Tokenizers load on first use; waiting here means the first frame of the file is already coloured.
    await monaco.editor.colorize('', language.id, {});
    if (pane.peek) closePeek(pane, true);
    const old = pane.ed.getModel();
    const model = monaco.editor.createModel(f.text, language.id);
    pane.ed.setModel(model);
    if (old) old.dispose();
    pane.file = { firstLine: f.firstLine, language, name: f.name, diff: f.diff ? diffOf(f.diff) : null };
    if (f.diff) {
      // Numbered as the new file numbers them; a removed line has none.
      pane.ed.updateOptions({ lineNumbers: (n) => (f.diff.numbers[n - 1] === null ? '' : String(f.diff.numbers[n - 1])) });
      pane.ed.deltaDecorations([], diffDecorations(f.diff));
    } else {
      pane.ed.updateOptions({ lineNumbers: (n) => String(n + f.firstLine - 1) });
    }
    pane.focus = [];
    setDim(pane, 1);
    clearMarks(pane);
    clearCallout(pane);
    tweens = tweens.filter((t) => !(t.pane === pane && ['dim', 'scroll', 'peek', 'move', 'fade'].includes(t.kind)));
    Object.assign(pane.content.style, { opacity: '', transform: '', clipPath: '' });
    pane.header.innerHTML = '';
    pane.header.append(el('span', 'dot'), el('span', 'name', f.name), el('span', 'path', f.directory));
    if (f.diff) {
      pane.header.append(
        el('span', 'since', f.diff.label), el('span', 'stat added', '+' + f.diff.added),
        el('span', 'stat removed', '\u2212' + f.diff.removed)
      );
    }
    pane.header.append(el('span', 'lang', language.label));
    let at = { line: 1, column: 1 };
    if (f.at) {
      const found = place(pane, f.at);
      if (typeof found === 'string') return found;
      at = found;
    }
    pane.ed.setPosition({ lineNumber: at.line, column: at.column });
    pane.ed.setScrollTop(f.at ? centredTop(pane, at.line) : 0);
    forceTokens(model);
    return null;
  }

  /// A still copy of what `pane` shows, laid over it, for the file before to move out while the next comes in.
  function snapshot(pane) {
    const leaving = el('div', 'leaving');
    leaving.appendChild(pane.content.cloneNode(true));
    pane.root.appendChild(leaving);
    return leaving;
  }

  /// The file before (`leaving`) moves out of `pane` as the new one comes in, as an intro moves into a demo.
  function move(pane, leaving, transition) {
    const content = pane.content.style;
    const reset = () => {
      Object.assign(content, { opacity: '', transform: '', clipPath: '' });
      if (leaving) leaving.remove();
    };
    if (transition.kind === 'cut' || !leaving) { reset(); return; }
    const out = leaving.style;
    const kind = transition.kind;
    tween('move', transition.ms, 0, 1, (p) => {
      const q = 1 - p;
      switch (kind) {
        case 'crossfade': out.opacity = q; content.opacity = p; break;
        case 'fade': out.opacity = Math.max(0, 1 - 2 * p); content.opacity = Math.max(0, 2 * p - 1); break;
        case 'zoom':
          out.opacity = q; out.transform = `scale(${1 + 0.04 * p})`;
          content.opacity = p; content.transform = `scale(${0.94 + 0.06 * p})`;
          break;
        case 'slide-left': out.transform = `translateX(${-100 * p}%)`; content.transform = `translateX(${100 * q}%)`; break;
        case 'slide-right': out.transform = `translateX(${100 * p}%)`; content.transform = `translateX(${-100 * q}%)`; break;
        case 'slide-up': out.transform = `translateY(${-100 * p}%)`; content.transform = `translateY(${100 * q}%)`; break;
        case 'slide-down': out.transform = `translateY(${100 * p}%)`; content.transform = `translateY(${-100 * q}%)`; break;
        case 'wipe-left': content.clipPath = `inset(0 0 0 ${100 * q}%)`; break;
        case 'wipe-right': content.clipPath = `inset(0 ${100 * q}% 0 0)`; break;
        case 'wipe-up': content.clipPath = `inset(${100 * q}% 0 0 0)`; break;
        case 'wipe-down': content.clipPath = `inset(0 0 ${100 * q}% 0)`; break;
        default: content.opacity = p;
      }
    }, reset, transition.easing, pane);
  }

  /// Every word a pane shows, where it is (points from the pane's top left) and how it is drawn, in reading order.
  function words(pane) {
    const out = [];
    const origin = pane.root.getBoundingClientRect();
    const lines = [...pane.code.querySelectorAll('.view-lines .view-line')]
      .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);
    for (const line of lines) {
      for (const span of line.querySelectorAll('span[class*="mtk"]')) {
        const node = span.firstChild;
        if (!node || node.nodeType !== Node.TEXT_NODE) continue;
        const style = getComputedStyle(span);
        // Each part on its own: the `font` shorthand would turn the font's ligatures back on (`->` as an arrow).
        const font = {
          fontStyle: style.fontStyle, fontWeight: style.fontWeight, fontSize: style.fontSize, fontFamily: style.fontFamily,
        };
        for (const m of node.textContent.matchAll(/\S+/g)) {
          const range = document.createRange();
          range.setStart(node, m.index);
          range.setEnd(node, m.index + m[0].length);
          const box = range.getBoundingClientRect();
          if (!box.width) continue;
          out.push({ text: m[0], x: box.left - origin.left, y: box.top - origin.top, color: style.color, font });
        }
      }
    }
    return out;
  }

  /// Where a span's text is drawn, in the same terms as `words`.
  function textBox(node) {
    const origin = node.parentNode.parentNode.getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(node);
    const box = range.getBoundingClientRect();
    return { x: box.left - origin.left, y: box.top - origin.top };
  }

  /// Pairs the words before with the words after. Lines first: a line that reads the same on both sides moves as one,
  /// in order (the longest such run). Then, among the lines left, words: in order, then any word left with the
  /// nearest of the same text, so a word that moved within an edited line still travels. Unpaired words come back
  /// alone: gone (`[from, null]`) or new (`[null, to]`).
  function match(before, after) {
    const lines = (all) => {
      const out = [];
      for (const word of all) {
        const last = out[out.length - 1];
        if (last && Math.abs(last.y - word.y) < 2) last.words.push(word);
        else out.push({ y: word.y, words: [word] });
      }
      out.forEach((line) => { line.text = line.words.map((w) => w.text).join(' '); });
      return out;
    };
    const pairs = [];
    const [kept, gone, come] = lcs(lines(before), lines(after), (line) => line.text);
    for (const [a, b] of kept) a.words.forEach((word, k) => pairs.push([word, b.words[k]]));
    return pairs.concat(matchWords(gone.flatMap((l) => l.words), come.flatMap((l) => l.words)));
  }

  /// The longest run of `before` and `after` in order whose keys are the same: the pairs, and what is left of each.
  function lcs(before, after, key) {
    const n = before.length, m = after.length;
    const table = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        table[i][j] = key(before[i]) === key(after[j])
          ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
    const pairs = [], gone = [], come = [];
    let i = 0, j = 0;
    while (i < n && j < m) {
      if (key(before[i]) === key(after[j])) pairs.push([before[i++], after[j++]]);
      else if (table[i + 1][j] >= table[i][j + 1]) gone.push(before[i++]);
      else come.push(after[j++]);
    }
    while (i < n) gone.push(before[i++]);
    while (j < m) come.push(after[j++]);
    return [pairs, gone, come];
  }

  function matchWords(before, after) {
    const [pairs, gone, come] = lcs(before, after, (word) => word.text);
    for (const word of gone) {
      let best = -1, distance = Infinity;
      come.forEach((other, k) => {
        if (other.text !== word.text) return;
        const d = Math.hypot(other.x - word.x, other.y - word.y);
        if (d < distance) { distance = d; best = k; }
      });
      pairs.push([word, best >= 0 ? come.splice(best, 1)[0] : null]);
    }
    for (const word of come) pairs.push([null, word]);
    return pairs;
  }

  /// reel's own scripts, `.reel` and `.reelpreset`, coloured as a reader of them would want: what each line does,
  /// what it names, what is quoted, how long, and what is said only for people.
  function registerReel() {
    monaco.languages.register({ id: 'reel', extensions: ['.reel', '.reelpreset'], aliases: ['reel'] });
    monaco.languages.setMonarchTokensProvider('reel', {
      tokenizer: {
        root: [
          [/^\s*#( .*)?$/, 'comment'],
          [/^\s*[A-Z][A-Za-z]*(@[\w,.:-]+)?/, { cases: { '@default': 'keyword' } }],
          { include: '@rest' },
        ],
        rest: [
          [/\s#\s.*$/, 'comment'],
          [/"([^"\\]|\\.)*"/, 'string'],
          [/\bas\s+[A-Za-z][\w-]*\s*$/, 'annotation'],
          [/#[\w.-]+/, 'type'],
          [/\[[^\]]+\]/, 'annotation'],
          [/\b\d+(\.\d+)?(ms|s|m|x|%|MB|KB|GB)?\b/, 'number'],
          [/\/\/[^\s]*/, 'string'],
          // A condition's ? and :, which stand alone; a : in a word (voicebox:Main) is part of it.
          [/\s[?:](?=\s)/, 'keyword'],
          [/\|/, 'keyword'],
          [/[^\s"#\[|]+/, ''],
          [/\s+/, ''],
        ],
      },
    });
  }

  /// The language for a file name, from Monaco's own list of extensions.
  function languageFor(name) {
    const lower = name.toLowerCase();
    const dot = lower.lastIndexOf('.');
    const extension = dot >= 0 ? lower.slice(dot) : '';
    for (const l of monaco.languages.getLanguages()) {
      if ((l.extensions || []).includes(extension) || (l.filenames || []).map((f) => f.toLowerCase()).includes(lower)) {
        return { id: l.id, label: (l.aliases && l.aliases[0]) || l.id };
      }
    }
    return { id: 'plaintext', label: 'text' };
  }

  function find(pane, text) {
    if (!pane.file) return null;
    const matches = pane.ed.getModel().findMatches(text, false, false, true, null, false, 1);
    return matches.length ? matches[0].range : null;
  }

  /// The first of `candidates` that has `text`, and where; never `besides`, the place a link starts from.
  function findIn(candidates, text, besides) {
    for (const pane of candidates) {
      if (!pane.file) continue;
      for (const match of pane.ed.getModel().findMatches(text, false, false, true, null, false, 2)) {
        if (besides && besides.pane === pane && besides.range.equalsRange(match.range)) continue;
        return { pane, range: match.range };
      }
    }
    return null;
  }

  /// A diff's lines by their number in the new file, and where its hunks start (1-based rows).
  function diffOf(diff) {
    const rows = new Map();
    diff.numbers.forEach((n, index) => { if (n !== null) rows.set(n, index + 1); });
    return { rows, hunks: diff.hunks.map((h) => h + 1) };
  }

  /// Added and removed lines, each with its sign in the gutter, and the words that changed in an edited line.
  function diffDecorations(diff) {
    const decorations = [];
    diff.kinds.forEach((kind, index) => {
      if (kind === 'kept') return;
      const line = index + 1;
      decorations.push({
        range: new monaco.Range(line, 1, line, 1),
        options: {
          isWholeLine: true, className: 'diff-' + kind, linesDecorationsClassName: 'diff-sign-' + kind,
          inlineClassName: kind === 'removed' ? 'diff-removed-text' : undefined,
        },
      });
      for (const [start, end] of diff.words[index]) {
        decorations.push({
          range: new monaco.Range(line, start + 1, line, end + 1), options: { inlineClassName: 'diff-word-' + kind },
        });
      }
    });
    return decorations;
  }

  /// The model's row for a line as the file numbers it (a diff's, the new file's); null when it is not shown.
  function rowOf(file, model, n) {
    if (file.diff) return file.diff.rows.get(n) || null;
    const line = n - file.firstLine + 1;
    return line >= 1 && line <= model.getLineCount() ? line : null;
  }

  /// Where `{ line }`, `{ hunk }` or `{ text }` is in a pane's file, or an error message.
  function place(pane, anchor) {
    return placeIn(pane.ed.getModel(), pane.file, anchor);
  }

  function placeIn(model, file, anchor) {
    const count = model.getLineCount();
    const name = file.name;
    let line = null;
    if (anchor.hunk !== undefined) {
      if (!file.diff) return `${name} is not a diff, so it has no hunk ${anchor.hunk}`;
      const hunks = file.diff.hunks;
      if (anchor.hunk > hunks.length) return `${name} has ${hunks.length} hunk${hunks.length === 1 ? '' : 's'}, not ${anchor.hunk}`;
      line = hunks[anchor.hunk - 1];
    } else if (anchor.line !== undefined) {
      line = rowOf(file, model, anchor.line);
      if (line === null) {
        return file.diff ? `line ${anchor.line} is not in the new ${name}`
          : `line ${anchor.line} is not in ${name}, which shows lines ${file.firstLine}-${count + file.firstLine - 1}`;
      }
    }
    if (line !== null) {
      const content = model.getLineContent(line);
      return { line, column: content.length - content.trimStart().length + 1 };
    }
    const matches = model.findMatches(anchor.text, false, false, true, null, false, 1);
    if (!matches.length) return `"${anchor.text}" is not in ${name}`;
    return { line: matches[0].range.startLineNumber, column: matches[0].range.startColumn };
  }

  function tween(kind, duration, from, to, apply, done, easing, pane) {
    tweens = tweens.filter((t) => !(t.kind === kind && t.pane === pane));
    apply(from);
    tweens.push({ kind, pane, start: screen.now, duration, from, to, apply, done, curve: easings[easing] || ease });
  }

  function setDim(pane, v) {
    pane.dim = v;
    pane.root.style.setProperty('--dim', String(v));
  }

  function forceTokens(model) {
    const count = model.getLineCount();
    if (model.tokenization && model.tokenization.forceTokenization) model.tokenization.forceTokenization(count);
    else if (model.forceTokenization) model.forceTokenization(count);
  }

  function centredTop(pane, line) {
    const ed = pane.ed;
    const height = ed.getLayoutInfo().height;
    const top = ed.getTopForLineNumber(line) - height / 2 + ed.getOption(monaco.editor.EditorOption.lineHeight) / 2;
    return clampTop(pane, top);
  }

  function clampTop(pane, top) {
    const max = Math.max(0, pane.ed.getContentHeight() - pane.ed.getLayoutInfo().height);
    return Math.round(Math.max(0, Math.min(max, top)));
  }

  /// Scrolls, easing, so lines `a`-`b` are in view: centred when they were out of it, not moved when they were in.
  function reveal(pane, a, b, duration) {
    const ed = pane.ed;
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const height = ed.getLayoutInfo().height;
    const current = targetTop(pane);
    const top = ed.getTopForLineNumber(a);
    const bottom = ed.getTopForLineNumber(Math.min(b, ed.getModel().getLineCount())) + lineHeight;
    if (top >= current && bottom <= current + height) return;
    const middle = (top + bottom) / 2;
    scrollTo(pane, clampTop(pane, bottom - top > height ? top - lineHeight : middle - height / 2), duration);
  }

  /// Keeps the caret in view as it types or moves: the least scroll that shows it.
  function follow(pane) {
    const ed = pane.ed;
    forceTokens(ed.getModel());
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const height = ed.getLayoutInfo().height;
    const line = ed.getPosition().lineNumber;
    const current = targetTop(pane);
    const top = ed.getTopForLineNumber(line);
    if (top < current) scrollTo(pane, clampTop(pane, top - lineHeight), 150);
    else if (top + lineHeight > current + height) scrollTo(pane, clampTop(pane, top + 2 * lineHeight - height), 150);
  }

  /// Where the view is going to: the end of a scroll under way, else where it is.
  function targetTop(pane) {
    const scrolling = tweens.find((t) => t.kind === 'scroll' && t.pane === pane);
    return scrolling ? scrolling.to : pane.ed.getScrollTop();
  }

  function scrollTo(pane, top, duration) {
    tween('scroll', duration, pane.ed.getScrollTop(), top, (v) => pane.ed.setScrollTop(Math.round(v)), null, null, pane);
  }

  function insert(pane, text) {
    const ed = pane.ed;
    ed.executeEdits('reel', [{ range: ed.getSelection(), text, forceMoveMarkers: true }]);
    ed.setPosition(ed.getSelection().getEndPosition());
    follow(pane);
  }

  function clearMarks(pane) {
    pane.marks.forEach((m) => m.el.remove());
    pane.marks = [];
  }

  function clearCallout(pane) {
    if (pane.callout) { pane.callout.el.remove(); pane.callout.under.remove(); }
    pane.callout = null;
  }

  /// A range's box in its pane's overlay: from its start to its end on its first line; null when out of sight.
  function box(pane, range) {
    const ed = pane.ed;
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const start = ed.getScrolledVisiblePosition({ lineNumber: range.startLineNumber, column: range.startColumn });
    const endColumn = range.endLineNumber === range.startLineNumber
      ? range.endColumn : ed.getModel().getLineMaxColumn(range.startLineNumber);
    const end = ed.getScrolledVisiblePosition({ lineNumber: range.startLineNumber, column: endColumn });
    if (!start || !end) return null;
    if (start.top + lineHeight < 0 || start.top > ed.getLayoutInfo().height) return null;
    return { left: start.left, top: start.top, width: end.left - start.left, height: lineHeight };
  }

  /// Where a pane's overlay starts, in points from the page's top left.
  function origin(pane) {
    return { x: pane.root.offsetLeft, y: pane.root.offsetTop + pane.code.offsetTop };
  }

  function pop(born, node) {
    const p = Math.min(1, (screen.now - born) / 180);
    node.style.opacity = String(p);
    node.style.transform = `scale(${0.92 + 0.08 * ease(p)})`;
  }

  /// Puts a pane's caret, marks and callout where the text they belong to is now; returns where its caret is.
  function draw(pane) {
    const ed = pane.ed;
    if (!ed.getModel() || !pane.file) return null;
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const pos = ed.getScrolledVisiblePosition(ed.getPosition());
    let at = null;
    pane.caret.style.display = pane === active && pos ? '' : 'none';
    if (pos) {
      pane.caret.style.left = pos.left - 1 + 'px';
      pane.caret.style.top = pos.top + 'px';
      pane.caret.style.height = lineHeight + 'px';
      const o = origin(pane);
      at = { x: o.x + pos.left, y: o.y + pos.top + lineHeight / 2 };
    }
    for (const m of pane.marks) {
      const b = box(pane, m.range);
      m.el.style.display = b ? '' : 'none';
      if (!b) continue;
      Object.assign(m.el.style, {
        left: b.left - 3 + 'px', top: b.top + 'px', width: b.width + 6 + 'px', height: b.height + 'px',
      });
      pop(m.born, m.el);
    }
    const callout = pane.callout;
    if (callout) {
      const b = box(pane, callout.range);
      callout.el.style.display = callout.under.style.display = b ? '' : 'none';
      if (b) {
        Object.assign(callout.under.style, {
          left: b.left + 'px', top: b.top + b.height - 3 + 'px', width: b.width + 'px',
        });
        const view = pane.overlay.clientHeight;
        const height = callout.el.offsetHeight;
        const width = callout.el.offsetWidth;
        // Beside the line, past its end, where it covers no code; below it (above, at the bottom) when it does not fit.
        const line = callout.range.startLineNumber;
        const end = ed.getScrolledVisiblePosition({ lineNumber: line, column: ed.getModel().getLineMaxColumn(line) });
        const beside = end && end.left + 28 + width <= pane.overlay.clientWidth - 16;
        const above = !beside && b.top + b.height + 12 + height > view && b.top - 12 - height >= 0;
        callout.el.classList.toggle('beside', !!beside);
        callout.el.classList.toggle('above', above);
        if (beside) {
          callout.el.style.left = end.left + 28 + 'px';
          callout.el.style.top = Math.round(b.top + b.height / 2 - height / 2) + 'px';
        } else {
          const left = Math.max(8, Math.min(pane.overlay.clientWidth - width - 8, b.left - 12));
          callout.el.style.left = left + 'px';
          callout.el.style.top = (above ? b.top - 12 - height : b.top + b.height + 12) + 'px';
        }
        pop(callout.born, callout.el);
        callout.under.style.opacity = callout.el.style.opacity;
      }
    }
    return at;
  }

  /// Draws each arrow from where its start is now to where its end is, growing in as it first appears.
  function drawLinks() {
    for (const link of links) {
      const a = box(link.from.pane, link.from.range), b = box(link.to.pane, link.to.range);
      link.group.style.display = a && b ? '' : 'none';
      if (!a || !b) continue;
      const oa = origin(link.from.pane), ob = origin(link.to.pane);
      const ya = oa.y + a.top + a.height / 2, yb = ob.y + b.top + b.height / 2;
      let d;
      if (link.from.pane !== link.to.pane) {
        // From the end of the one to the start of the other, across the panes.
        const xa = oa.x + a.left + a.width + 8, xb = ob.x + b.left - 10;
        const bend = Math.max(60, Math.abs(xb - xa) * 0.45);
        d = `M ${xa} ${ya} C ${xa + bend} ${ya}, ${xb - bend} ${yb}, ${xb} ${yb}`;
      } else {
        // In one pane: out past the end of both, and back.
        const xa = oa.x + a.left + a.width + 8, xb = ob.x + b.left + b.width + 10;
        const out = Math.max(xa, xb) + 90;
        d = `M ${xa} ${ya} C ${out} ${ya}, ${out} ${yb}, ${xb} ${yb}`;
      }
      link.path.setAttribute('d', d);
      const p = Math.min(1, (screen.now - link.born) / 450);
      link.path.style.strokeDashoffset = String(1 - ease(p));
      if (link.caption) {
        // Where it crosses into the other pane, over its line numbers rather than code; in one pane, its middle,
        // which is out past the end of both lines.
        const words = link.caption.querySelector('text');
        const rect = link.caption.querySelector('rect');
        const width = words.getComputedTextLength() + 20;
        const length = link.path.getTotalLength();
        let point = link.path.getPointAtLength(length / 2);
        if (link.from.pane !== link.to.pane) {
          // Its right edge just before the other pane's code starts.
          const aim = ob.x + link.to.pane.ed.getLayoutInfo().contentLeft - 6 - width / 2;
          for (let i = 0; i <= 48; i++) {
            const at = link.path.getPointAtLength((length * i) / 48);
            if (Math.abs(at.x - aim) < Math.abs(point.x - aim)) point = at;
          }
        }
        words.setAttribute('x', point.x - width / 2 + 10);
        words.setAttribute('y', point.y + 5);
        Object.entries({ x: point.x - width / 2, y: point.y - 14, width, height: 28, rx: 14 })
          .forEach(([k, v]) => rect.setAttribute(k, v));
        link.caption.style.opacity = String(Math.max(0, Math.min(1, (screen.now - link.born - 300) / 200)));
      }
    }
  }

  window.reelScreen = screen;
})();
