// reel's terminal screen. Swift sizes it (`size`, `layout`), feeds it what the shell printed (`feed`) and points
// things out (`mark`, `callout`); `pump(ms)` moves the clock on and lays the frame out. Every animation is a tween
// read from `now`, never from wall time, so the same take draws the same frames.
(function () {
  const ease = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
  const overlay = document.getElementById('overlay');
  const holder = document.getElementById('term');
  const root = document.documentElement.style;

  let term = null;
  let options = null;
  let tweens = [];
  let marks = []; // { line, column, length, el }
  let callout = null; // { line, column, length, el, under }
  let dirty = true;
  let pops = 0;
  let redactions = [];
  let masks = [];

  const screen = {
    now: 0,
    ready: false,
    error: null,

    /// `{ columns, rows, fontSize, theme, title }`; `ready` turns true once the terminal can be measured.
    init(o) {
      options = o;
      redactions = (o.redactions || []).map((p) => new RegExp(p, 'g'));
      const theme = o.theme || {};
      if (theme.background) root.setProperty('--bg', theme.background);
      if (theme.foreground) root.setProperty('--fg', theme.foreground);
      root.setProperty('--bar', mix(theme.background || '#111923', theme.foreground || '#E7ECF1', 0.07));
      root.setProperty('--line', mix(theme.background || '#111923', theme.foreground || '#E7ECF1', 0.16));
      root.setProperty('--mut', mix(theme.background || '#111923', theme.foreground || '#E7ECF1', 0.62));
      document.querySelector('#bar .title').textContent = o.title || '';
      Promise.all([
        document.fonts.load(`400 ${o.fontSize}px 'JetBrains Mono'`),
        document.fonts.load(`500 ${o.fontSize}px 'JetBrains Mono'`),
        document.fonts.load("500 14px 'Instrument Sans'"),
        document.fonts.load("500 16px 'Instrument Sans'"),
      ]).then(() => {
        term = new Terminal({
          cols: o.columns,
          rows: o.rows,
          fontFamily: "'JetBrains Mono', monospace",
          fontSize: o.fontSize,
          lineHeight: 1.2,
          fontWeightBold: '500',
          theme,
          cursorBlink: false,
          cursorStyle: 'block',
          cursorInactiveStyle: 'block',
          scrollback: 5000,
          allowProposedApi: true,
          drawBoldTextInBrightColors: false,
        });
        term.open(holder);
        // xterm draws its cursor once it has been focused or typed into, which a page nobody sees never is.
        term._core._showCursor();
        screen.ready = true;
      }, (e) => { screen.error = 'fonts: ' + e; });
      return true;
    },

    /// The page's size in points: the window's bar, the padding, and the terminal's columns and rows.
    size() {
      const cell = cellSize();
      const pad = 18, title = 40;
      return {
        width: Math.ceil(options.columns * cell.width + 2 * pad),
        height: Math.ceil(options.rows * cell.height + 2 * pad + title),
      };
    },

    /// Fits the terminal to the page, once the page has the size `size` asked for.
    layout() {
      const cell = cellSize();
      holder.style.width = Math.ceil(options.columns * cell.width) + 'px';
      holder.style.height = Math.ceil(options.rows * cell.height) + 'px';
      dirty = true;
      return null;
    },

    /// Prints `text`; resolves once the terminal has taken all of it in, and anything `Set Redact` matches on screen
    /// is dots.
    async feed(text) {
      dirty = true;
      await write(text);
    },

    /// A box around the last `text` on screen, numbered when `n` is given; null clears every box.
    mark(text, n) {
      dirty = true;
      if (text === null) { clearMarks(); return null; }
      const found = find(text);
      if (!found) return `"${text}" is not on the terminal's screen`;
      const box = el('div', 'mark');
      if (n !== null) box.appendChild(el('span', 'n', String(n)));
      overlay.appendChild(box);
      marks.push({ ...found, el: box, born: screen.now });
      tween('pop' + pops++, 180, 0, 1, () => {});
      return null;
    },

    /// A bubble saying `label`, pointing at the last `text` on screen; null takes it away.
    callout(text, label) {
      dirty = true;
      clearCallout();
      if (text === null) return null;
      const found = find(text);
      if (!found) return `"${text}" is not on the terminal's screen`;
      const bubble = el('div', 'callout', label);
      const under = el('div', 'under');
      overlay.append(under, bubble);
      callout = { ...found, el: bubble, under, born: screen.now };
      tween('pop' + pops++, 180, 0, 1, () => {});
      return null;
    },

    /// Moves the clock on by `ms`, runs what was waiting for a frame, and lays the overlays out. Returns whether
    /// anything may have changed, and where the cursor is in points from the page's top left.
    pump(ms) {
      screen.now += ms;
      const changed = dirty || tweens.length > 0;
      dirty = false;
      const due = tweens;
      tweens = [];
      for (const t of due) {
        const p = Math.min(1, (screen.now - t.start) / t.duration);
        t.apply(t.from + (t.to - t.from) * ease(p));
        if (p < 1) tweens.push(t);
      }
      window.__runFrames(screen.now);
      const at = draw();
      return { changed, x: at ? at.x : null, y: at ? at.y : null };
    },
  };

  function write(text) {
    return new Promise((done) => term.write(text, done));
  }

  /// Covers what a `Set Redact` pattern matches on screen with dots, wherever it came from: a command's output, or
  /// what was typed, which the shell echoes a character at a time. The terminal keeps the real text, so a match grows
  /// as more of it is typed; only the picture is covered.
  function redact() {
    masks.forEach((m) => m.remove());
    masks = [];
    if (!redactions.length) return;
    const cell = cellSize();
    const buffer = term.buffer.active;
    for (let row = 0; row < term.rows; row++) {
      const line = buffer.getLine(buffer.viewportY + row);
      if (!line) continue;
      const text = line.translateToString(true);
      for (const pattern of redactions) {
        pattern.lastIndex = 0;
        for (const match of text.matchAll(pattern)) {
          if (!match[0].length) continue;
          const mask = el('div', 'redact', '•'.repeat(match[0].length));
          Object.assign(mask.style, {
            left: holder.offsetLeft + match.index * cell.width + 'px',
            top: holder.offsetTop + row * cell.height + 'px',
            width: match[0].length * cell.width + 'px',
            height: cell.height + 'px',
            lineHeight: cell.height + 'px',
            fontSize: options.fontSize + 'px',
            letterSpacing: cell.width - measure('•') + 'px',
          });
          overlay.prepend(mask);
          masks.push(mask);
        }
      }
    }
  }

  let widths = {};
  /// How wide a character is in the terminal's font, without the cell's spacing.
  function measure(character) {
    if (widths[character] === undefined) {
      const context = document.createElement('canvas').getContext('2d');
      context.font = `${options.fontSize}px 'JetBrains Mono'`;
      widths[character] = context.measureText(character).width;
    }
    return widths[character];
  }

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  /// `a` moved towards `b` by `share`, as #rrggbb.
  function mix(a, b, share) {
    const n = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
    const [x, y] = [n(a), n(b)];
    return '#' + x.map((v, i) => Math.round(v + (y[i] - v) * share).toString(16).padStart(2, '0')).join('');
  }

  /// A character cell's size in points, as the terminal lays them out.
  function cellSize() {
    const dimensions = term._core._renderService.dimensions.css.cell;
    return { width: dimensions.width, height: dimensions.height };
  }

  function tween(kind, duration, from, to, apply) {
    tweens = tweens.filter((t) => t.kind !== kind);
    apply(from);
    tweens.push({ kind, start: screen.now, duration, from, to, apply });
  }

  /// The last place `text` shows on screen, newest output first: its line in the buffer and its column.
  function find(text) {
    const buffer = term.buffer.active;
    for (let row = term.rows - 1; row >= 0; row--) {
      const line = buffer.getLine(buffer.viewportY + row);
      if (!line) continue;
      const column = line.translateToString(true).lastIndexOf(text);
      if (column >= 0) return { line: buffer.viewportY + row, column, length: text.length };
    }
    return null;
  }

  function clearMarks() {
    marks.forEach((m) => m.el.remove());
    marks = [];
  }

  function clearCallout() {
    if (callout) { callout.el.remove(); callout.under.remove(); }
    callout = null;
  }

  /// Where a found text is now, in points from the page's top left; null once it has scrolled off.
  function box(found) {
    const cell = cellSize();
    const row = found.line - term.buffer.active.viewportY;
    if (row < 0 || row >= term.rows) return null;
    return {
      left: holder.offsetLeft + found.column * cell.width,
      top: holder.offsetTop + row * cell.height,
      width: found.length * cell.width,
      height: cell.height,
      row,
    };
  }

  function pop(born, node) {
    const p = Math.min(1, (screen.now - born) / 180);
    node.style.opacity = String(p);
    node.style.transform = `scale(${0.92 + 0.08 * ease(p)})`;
  }

  /// Puts the masks, the marks and the callout on the text they belong to, and says where the cursor is.
  function draw() {
    if (!term) return null;
    redact();
    const cell = cellSize();
    const buffer = term.buffer.active;
    for (const m of marks) {
      const b = box(m);
      m.el.style.display = b ? '' : 'none';
      if (!b) continue;
      Object.assign(m.el.style, {
        left: b.left - 3 + 'px', top: b.top + 'px', width: b.width + 6 + 'px', height: b.height + 'px',
      });
      pop(m.born, m.el);
    }
    if (callout) {
      const b = box(callout);
      callout.el.style.display = callout.under.style.display = b ? '' : 'none';
      if (b) {
        Object.assign(callout.under.style, { left: b.left + 'px', top: b.top + b.height - 2 + 'px', width: b.width + 'px' });
        const width = callout.el.offsetWidth, height = callout.el.offsetHeight;
        const end = holder.offsetLeft + buffer.getLine(callout.line).translateToString(true).length * cell.width;
        const beside = end + 28 + width <= document.body.clientWidth - 16;
        const above = !beside && b.top + b.height + 12 + height > document.body.clientHeight;
        callout.el.classList.toggle('beside', beside);
        callout.el.classList.toggle('above', above);
        if (beside) {
          callout.el.style.left = end + 28 + 'px';
          callout.el.style.top = Math.round(b.top + b.height / 2 - height / 2) + 'px';
        } else {
          callout.el.style.left = Math.max(8, Math.min(document.body.clientWidth - width - 8, b.left - 12)) + 'px';
          callout.el.style.top = (above ? b.top - 12 - height : b.top + b.height + 12) + 'px';
        }
        pop(callout.born, callout.el);
        callout.under.style.opacity = callout.el.style.opacity;
      }
    }
    return {
      x: holder.offsetLeft + (buffer.cursorX + 0.5) * cell.width,
      y: holder.offsetTop + (buffer.cursorY + 0.5) * cell.height,
    };
  }

  window.reelScreen = screen;
})();
