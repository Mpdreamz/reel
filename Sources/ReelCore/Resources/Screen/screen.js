// reel's code screen. Swift drives it through `screen`: each call changes what is shown, and `screen.pump(ms)` moves
// the clock on and lays the frame out. Every animation is a tween read from `screen.now`, never from wall time, so
// the same reel draws the same frames.
(function () {
  const dimmed = 0.32;
  const ease = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
  const overlay = document.getElementById('overlay');
  const header = document.getElementById('header');
  const code = document.getElementById('code');

  let ed = null;
  let file = null; // { firstLine, language }
  let tweens = [];
  let marks = []; // { range, n, born, el }
  let callout = null; // { range, label, born, el, under }
  let focusDecorations = [];
  let dim = 1;
  // Something was asked of the page since the last frame.
  let dirty = true;
  let pops = 0;
  const caret = document.createElement('div');
  caret.className = 'caret';
  caret.style.display = 'none';
  overlay.appendChild(caret);

  const screen = {
    now: 0,
    ready: false,
    error: null,

    /// Loads Monaco and the fonts; `ready` turns true once text can be measured.
    init(options) {
      const fontSize = options.fontSize;
      const lineHeight = Math.round(fontSize * 1.5);
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
        ed = monaco.editor.create(code, {
          value: '',
          language: 'plaintext',
          theme: 'reel',
          fontFamily: 'JetBrains Mono',
          fontSize,
          lineHeight,
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
        });
        document.fonts.load(`${fontSize}px 'JetBrains Mono'`).then(() =>
          Promise.all([
            document.fonts.load(`500 ${fontSize}px 'JetBrains Mono'`),
            document.fonts.load("500 15px 'Instrument Sans'"),
            document.fonts.load("400 15px 'Instrument Sans'"),
          ])
        ).then(() => {
          monaco.editor.remeasureFonts();
          layout();
          screen.ready = true;
        }, (e) => { screen.error = 'fonts: ' + e; });
      }, (e) => { screen.error = 'monaco: ' + e; });
      return true;
    },

    /// Shows a file: `text` is what is shown (the whole file, or `lines a-b` of it, numbered from `firstLine`).
    /// Resolves to an error message, or null.
    async open(f) {
      const language = languageFor(f.name);
      // Tokenizers load on first use; waiting here means the first frame of the file is already coloured.
      await monaco.editor.colorize('', language.id, {});
      const old = ed.getModel();
      const model = monaco.editor.createModel(f.text, language.id);
      ed.setModel(model);
      if (old) old.dispose();
      file = { firstLine: f.firstLine, language };
      ed.updateOptions({ lineNumbers: (n) => String(n + f.firstLine - 1) });
      focusDecorations = [];
      dim = 1;
      document.documentElement.style.setProperty('--dim', '1');
      clearMarks();
      clearCallout();
      tweens = tweens.filter((t) => t.kind !== 'scroll' && t.kind !== 'dim');
      header.innerHTML = '';
      const dot = el('span', 'dot');
      const name = el('span', 'name', f.name);
      const path = el('span', 'path', f.directory);
      const lang = el('span', 'lang', language.label);
      header.append(dot, name, path, lang);
      let at = { line: 1, column: 1 };
      if (f.at) {
        const found = place(f.at);
        if (typeof found === 'string') return found;
        at = found;
      }
      ed.setPosition({ lineNumber: at.line, column: at.column });
      ed.setScrollTop(f.at ? centredTop(at.line) : 0);
      forceTokens();
      caret.style.display = '';
      // The new file comes up from the background.
      tween('fade', 300, 0, 1, (v) => { code.style.opacity = v; overlay.style.opacity = v; });
      return null;
    },

    /// Moves the cursor to `{ line }` (as the file numbers it) or the first `{ text }`, scrolling to show it.
    go(anchor) {
      const found = place(anchor);
      if (typeof found === 'string') return found;
      ed.setPosition({ lineNumber: found.line, column: found.column });
      reveal(found.line, found.line, 400);
      return null;
    },

    /// Types `text` at the cursor, over any selection.
    type(text) {
      insert(text);
      return null;
    },

    /// One key: an edit, a move, or (with shift) a selection.
    key(name, shift) {
      const moves = {
        left: 'cursorLeft', right: 'cursorRight', up: 'cursorUp', down: 'cursorDown',
        home: 'cursorHome', end: 'cursorEnd', pageup: 'cursorPageUp', pagedown: 'cursorPageDown',
      };
      if (moves[name]) {
        ed.trigger('reel', moves[name] + (shift ? 'Select' : ''), null);
        follow();
        return null;
      }
      switch (name) {
        case 'return': case 'enter': {
          const p = ed.getPosition();
          const indent = ed.getModel().getLineContent(p.lineNumber).match(/^\s*/)[0];
          insert('\n' + indent.slice(0, Math.max(0, p.column - 1)));
          break;
        }
        case 'tab': {
          const column = ed.getPosition().column;
          insert(' '.repeat(4 - ((column - 1) % 4)));
          break;
        }
        case 'space': insert(' '); break;
        case 'backspace': case 'delete': edit('deleteLeft'); break;
        case 'forwarddelete': edit('deleteRight'); break;
        case 'escape': case 'esc': ed.setPosition(ed.getPosition()); break;
        default: return 'the code screen takes no key ' + name;
      }
      return null;
    },

    /// Brightens lines `a`-`b` (as the file numbers them) and dims the rest; null brightens everything again.
    focus(range) {
      const model = ed.getModel();
      const count = model.getLineCount();
      if (range) {
        const a = range[0] - file.firstLine + 1;
        const b = range[1] - file.firstLine + 1;
        if (a < 1 || b > count) return `lines ${range[0]}-${range[1]} are not all in ${describe()}`;
        const outside = [];
        if (a > 1) outside.push(new monaco.Range(1, 1, a - 1, model.getLineMaxColumn(a - 1)));
        if (b < count) outside.push(new monaco.Range(b + 1, 1, count, model.getLineMaxColumn(count)));
        focusDecorations = ed.deltaDecorations(focusDecorations, outside.map((r) => ({
          range: r, options: { inlineClassName: 'reel-dim', isWholeLine: true },
        })));
        tween('dim', 350, dim, dimmed, setDim);
        reveal(a, b, 400);
      } else {
        const remove = focusDecorations;
        tween('dim', 350, dim, 1, setDim, () => { focusDecorations = ed.deltaDecorations(remove, []); });
      }
      return null;
    },

    /// A box around the first `text`, numbered when `n` is given; null clears every box.
    mark(text, n) {
      if (text === null) { clearMarks(); return null; }
      const range = find(text);
      if (!range) return `"${text}" is not in ${describe()}`;
      const box = el('div', 'mark');
      if (n !== null) box.appendChild(el('span', 'n', String(n)));
      overlay.appendChild(box);
      marks.push({ range, born: screen.now, el: box });
      tween('pop' + pops++, 180, 0, 1, () => {});
      reveal(range.startLineNumber, range.endLineNumber, 400);
      return null;
    },

    /// A bubble saying `label`, pointing at the first `text`; null takes it away.
    callout(text, label) {
      clearCallout();
      if (text === null) return null;
      const range = find(text);
      if (!range) return `"${text}" is not in ${describe()}`;
      const bubble = el('div', 'callout', label);
      const under = el('div', 'under');
      overlay.append(under, bubble);
      callout = { range, born: screen.now, el: bubble, under };
      tween('pop' + pops++, 180, 0, 1, () => {});
      reveal(range.startLineNumber, range.endLineNumber + 3, 400);
      return null;
    },

    /// Moves the clock on by `ms`, runs what was waiting for a frame, and lays the overlays out. Returns where the
    /// caret is, in points from the page's top left, or null before a file is open.
    pump(ms) {
      screen.now += ms;
      const changed = dirty || tweens.length > 0;
      dirty = false;
      const due = tweens;
      tweens = [];
      for (const t of due) {
        const p = Math.min(1, (screen.now - t.start) / t.duration);
        t.apply(t.from + (t.to - t.from) * ease(p));
        if (p < 1) tweens.push(t); else if (t.done) t.done();
      }
      window.__runFrames(screen.now);
      const at = draw();
      return { changed, x: at ? at.x : null, y: at ? at.y : null };
    },
  };

  // Every step marks the next frame as changed.
  for (const name of ['open', 'go', 'type', 'key', 'focus', 'mark', 'callout']) {
    const step = screen[name];
    screen[name] = function () { dirty = true; return step.apply(screen, arguments); };
  }

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function layout() {
    ed.layout({ width: code.clientWidth, height: code.clientHeight });
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

  function describe() {
    return header.querySelector('.name') ? header.querySelector('.name').textContent : 'the code';
  }

  function find(text) {
    const matches = ed.getModel().findMatches(text, false, false, true, null, false, 1);
    return matches.length ? matches[0].range : null;
  }

  /// Where `{ line }` or `{ text }` is in the model, or an error message.
  function place(anchor) {
    const count = ed.getModel().getLineCount();
    if (anchor.line !== undefined) {
      const line = anchor.line - file.firstLine + 1;
      if (line < 1 || line > count) {
        const last = count + file.firstLine - 1;
        return `line ${anchor.line} is not in ${describe()}, which shows lines ${file.firstLine}-${last}`;
      }
      const content = ed.getModel().getLineContent(line);
      return { line, column: content.length - content.trimStart().length + 1 };
    }
    const range = find(anchor.text);
    if (!range) return `"${anchor.text}" is not in ${describe()}`;
    return { line: range.startLineNumber, column: range.startColumn };
  }

  function tween(kind, duration, from, to, apply, done) {
    tweens = tweens.filter((t) => t.kind !== kind);
    apply(from);
    tweens.push({ kind, start: screen.now, duration, from, to, apply, done });
  }

  function setDim(v) {
    dim = v;
    document.documentElement.style.setProperty('--dim', String(v));
  }

  function forceTokens() {
    const model = ed.getModel();
    const count = model.getLineCount();
    if (model.tokenization && model.tokenization.forceTokenization) model.tokenization.forceTokenization(count);
    else if (model.forceTokenization) model.forceTokenization(count);
  }

  function centredTop(line) {
    const height = ed.getLayoutInfo().height;
    const top = ed.getTopForLineNumber(line) - height / 2 + ed.getOption(monaco.editor.EditorOption.lineHeight) / 2;
    return clampTop(top);
  }

  function clampTop(top) {
    const max = Math.max(0, ed.getContentHeight() - ed.getLayoutInfo().height);
    return Math.round(Math.max(0, Math.min(max, top)));
  }

  /// Scrolls, easing, so lines `a`-`b` are in view: centred when they were out of it, not moved when they were in.
  function reveal(a, b, duration) {
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const height = ed.getLayoutInfo().height;
    const current = targetTop();
    const top = ed.getTopForLineNumber(a);
    const bottom = ed.getTopForLineNumber(Math.min(b, ed.getModel().getLineCount())) + lineHeight;
    if (top >= current && bottom <= current + height) return;
    const middle = (top + bottom) / 2;
    scrollTo(clampTop(bottom - top > height ? top - lineHeight : middle - height / 2), duration);
  }

  /// Keeps the caret in view as it types or moves: the least scroll that shows it.
  function follow() {
    forceTokens();
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const height = ed.getLayoutInfo().height;
    const line = ed.getPosition().lineNumber;
    const current = targetTop();
    const top = ed.getTopForLineNumber(line);
    if (top < current) scrollTo(clampTop(top - lineHeight), 150);
    else if (top + lineHeight > current + height) scrollTo(clampTop(top + 2 * lineHeight - height), 150);
  }

  /// Where the view is going to: the end of a scroll under way, else where it is.
  function targetTop() {
    const scrolling = tweens.find((t) => t.kind === 'scroll');
    return scrolling ? scrolling.to : ed.getScrollTop();
  }

  function scrollTo(top, duration) {
    tween('scroll', duration, ed.getScrollTop(), top, (v) => ed.setScrollTop(Math.round(v)));
  }

  function insert(text) {
    const selection = ed.getSelection();
    ed.executeEdits('reel', [{ range: selection, text, forceMoveMarkers: true }]);
    const end = ed.getSelection().getEndPosition();
    ed.setPosition(end);
    follow();
  }

  function edit(command) {
    ed.trigger('reel', command, null);
    follow();
  }

  function clearMarks() {
    marks.forEach((m) => m.el.remove());
    marks = [];
  }

  function clearCallout() {
    if (callout) { callout.el.remove(); callout.under.remove(); }
    callout = null;
  }

  /// A range's box in the overlay: from its start to its end on its first line.
  function box(range) {
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const start = ed.getScrolledVisiblePosition({ lineNumber: range.startLineNumber, column: range.startColumn });
    const endColumn = range.endLineNumber === range.startLineNumber
      ? range.endColumn : ed.getModel().getLineMaxColumn(range.startLineNumber);
    const end = ed.getScrolledVisiblePosition({ lineNumber: range.startLineNumber, column: endColumn });
    if (!start || !end) return null;
    return { left: start.left, top: start.top, width: end.left - start.left, height: lineHeight };
  }

  function pop(born, node, base) {
    const p = Math.min(1, (screen.now - born) / 180);
    node.style.opacity = String(p);
    node.style.transform = `${base || ''} scale(${0.92 + 0.08 * ease(p)})`;
  }

  /// Puts the caret, the marks and the callout where the text they belong to is now.
  function draw() {
    if (!ed || !ed.getModel() || !file) return null;
    const lineHeight = ed.getOption(monaco.editor.EditorOption.lineHeight);
    const pos = ed.getScrolledVisiblePosition(ed.getPosition());
    let at = null;
    if (pos) {
      caret.style.left = pos.left - 1 + 'px';
      caret.style.top = pos.top + 'px';
      caret.style.height = lineHeight + 'px';
      at = { x: pos.left, y: pos.top + lineHeight / 2 + code.offsetTop };
    }
    const pad = 3;
    for (const m of marks) {
      const b = box(m.range);
      if (!b) continue;
      Object.assign(m.el.style, {
        left: b.left - pad + 'px', top: b.top + 'px', width: b.width + 2 * pad + 'px', height: b.height + 'px',
      });
      pop(m.born, m.el);
    }
    if (callout) {
      const b = box(callout.range);
      if (b) {
        Object.assign(callout.under.style, {
          left: b.left + 'px', top: b.top + b.height - 3 + 'px', width: b.width + 'px',
        });
        const view = overlay.clientHeight;
        const height = callout.el.offsetHeight;
        const width = callout.el.offsetWidth;
        // Beside the line, past its end, where it covers no code; below it (above, at the bottom) when it does not fit.
        const line = callout.range.startLineNumber;
        const end = ed.getScrolledVisiblePosition({ lineNumber: line, column: ed.getModel().getLineMaxColumn(line) });
        const beside = end && end.left + 28 + width <= overlay.clientWidth - 16;
        const above = !beside && b.top + b.height + 12 + height > view && b.top - 12 - height >= 0;
        callout.el.classList.toggle('beside', !!beside);
        callout.el.classList.toggle('above', above);
        if (beside) {
          callout.el.style.left = end.left + 28 + 'px';
          callout.el.style.top = Math.round(b.top + b.height / 2 - height / 2) + 'px';
        } else {
          const left = Math.max(8, Math.min(overlay.clientWidth - width - 8, b.left - 12));
          callout.el.style.left = left + 'px';
          callout.el.style.top = (above ? b.top - 12 - height : b.top + b.height + 12) + 'px';
        }
        pop(callout.born, callout.el);
        callout.under.style.opacity = callout.el.style.opacity;
      }
    }
    return at;
  }

  window.reelScreen = screen;
})();
