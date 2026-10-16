// The big button's colour picker, for making an event (index.html) and its
// settings (host.html): a hue and saturation wheel drawn on a canvas, a
// brightness slider, and a hex code box, so any colour can be reached by eye
// or typed exactly. After uwuColorGuess's Expert wheel (colorguess-game,
// js/wheel.js).
//
// Drag or tap the wheel, or focus it and use the arrow keys: left and right
// turn the hue, up and down change the saturation. The hex box takes six
// digits or three, with or without the #.
//
// **It stands in for an <input type="color">.** The element marked
// data-colour-picker gets a `value` ("#rrggbb", lower case, as the server
// stores it) that can be read and set, and fires one bubbling `input` event
// per change, so the page scripts treat it as the input it replaced.
//
// The wheel, the slider's track and the marker show colours for what they
// are, so like the button itself they are a fixed-meaning exception to the
// theme's tokens.

const KEY_HUE = 5;
const KEY_SAT = 0.05;
const DEFAULT = "#ccffcc";

/* ---- colour maths: hex strings and HSV, h in degrees, s and v 0 to 1 ---- */

// [r, g, b], each 0 to 255.
function hsvToRgb(h, s, v) {
  const f = (k) => {
    const x = (k + h / 60) % 6;
    return Math.round((v - v * s * Math.max(0, Math.min(x, 4 - x, 1))) * 255);
  };
  return [f(5), f(3), f(1)];
}

function hsvToHex(h, s, v) {
  return "#" + hsvToRgb(h, s, v).map((c) => c.toString(16).padStart(2, "0")).join("");
}

function hexToHsv(hex) {
  const n = parseInt(hex.slice(1), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => c / 255);
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  let h = 0;
  if (d) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return { h, s: max ? d / max : 0, v: max };
}

/** "#rrggbb" from what someone typed, or null. Takes 3 or 6 digits, # or not. */
export function parseHex(text) {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(text ?? "").trim());
  if (!m) return null;
  const digits = m[1].length === 3 ? [...m[1]].map((c) => c + c).join("") : m[1];
  return `#${digits.toLowerCase()}`;
}

/* ---- the picker ---- */

let count = 0;

class ColourPicker {
  constructor(root) {
    this.root = root;
    const id = `cp${++count}`;
    const label = root.dataset.label || "Colour";

    root.innerHTML = `
      <div class="wheel-wrap" role="slider" tabindex="0" aria-valuemin="0" aria-valuemax="100"
        aria-label="${label} wheel. Left and right arrows turn the hue, up and down change the saturation.">
        <canvas class="wheel-canvas"></canvas>
        <span class="wheel-dot" aria-hidden="true"></span>
      </div>
      <div class="wheel-side">
        <label class="wheel-label" for="${id}-v">Brightness</label>
        <input class="brightness" id="${id}-v" type="range" min="0" max="100">
        <label class="wheel-label" for="${id}-hex">Hex code</label>
        <input class="input hex-input" id="${id}-hex" type="text" maxlength="7" autocomplete="off"
          autocapitalize="characters" spellcheck="false" aria-describedby="${id}-err">
        <span class="hex-error" id="${id}-err" role="status"></span>
      </div>`;

    this.wrap = root.querySelector(".wheel-wrap");
    this.canvas = root.querySelector(".wheel-canvas");
    this.marker = root.querySelector(".wheel-dot");
    this.slider = root.querySelector(".brightness");
    this.hex = root.querySelector(".hex-input");
    this.error = root.querySelector(".hex-error");
    this.drawnFor = null;

    this.set(parseHex(root.dataset.value) ?? DEFAULT, { quiet: true });
    this.wire();

    // The element itself answers like the input it replaced.
    const picker = this;
    Object.defineProperty(root, "value", {
      get: () => picker.current,
      set: (v) => picker.set(parseHex(v) ?? DEFAULT, { quiet: true }),
    });
  }

  wire() {
    const { wrap, slider, hex } = this;

    wrap.addEventListener("pointerdown", (e) => {
      wrap.setPointerCapture(e.pointerId);
      this.pointAt(e);
      wrap.focus({ preventScroll: true });
      e.preventDefault();
    });
    wrap.addEventListener("pointermove", (e) => {
      if (wrap.hasPointerCapture(e.pointerId)) this.pointAt(e);
    });
    wrap.addEventListener("keydown", (e) => {
      const turn = { ArrowLeft: KEY_HUE, ArrowRight: -KEY_HUE }[e.key];
      const sat = { ArrowUp: KEY_SAT, ArrowDown: -KEY_SAT }[e.key];
      if (turn === undefined && sat === undefined) return;
      e.preventDefault();
      if (turn) this.h = (this.h + turn + 360) % 360;
      if (sat) this.s = Math.max(0, Math.min(1, this.s + sat));
      this.fromHsv();
    });

    // The slider's and the box's own input events stay inside: the picker
    // fires one of its own per change instead.
    slider.addEventListener("input", (e) => {
      e.stopPropagation();
      this.v = Number(slider.value) / 100;
      this.fromHsv();
    });

    hex.addEventListener("input", (e) => {
      e.stopPropagation();
      const parsed = parseHex(hex.value);
      // Three digits are a whole colour too, but somebody typing six passes
      // through three on the way: only a full six applies as they type.
      if (parsed && hex.value.replace("#", "").length === 6) {
        this.showError("");
        this.set(parsed, { keepText: true });
      }
    });
    hex.addEventListener("change", () => this.commitText());
    hex.addEventListener("keydown", (e) => {
      // Enter applies the code rather than submitting the form around it.
      if (e.key !== "Enter") return;
      e.preventDefault();
      this.commitText();
    });

    // Drawn once it has a size: a picker in a closed modal has none.
    new ResizeObserver(() => this.draw()).observe(this.canvas);
  }

  // What was typed, applied when the box is left or Enter is pressed.
  commitText() {
    const parsed = parseHex(this.hex.value);
    if (!parsed) {
      this.showError("A hex code is 6 digits and letters A to F, like CCFFCC.");
      return;
    }
    this.showError("");
    this.set(parsed);
  }

  showError(text) {
    this.error.textContent = text;
    this.hex.setAttribute("aria-invalid", String(Boolean(text)));
  }

  pointAt(e) {
    const rect = this.wrap.getBoundingClientRect();
    const r = rect.width / 2;
    const x = (e.clientX - rect.left - r) / r;
    const y = (rect.top + r - e.clientY) / r;
    this.h = ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
    this.s = Math.min(1, Math.hypot(x, y));
    // Picking on the wheel at no brightness would change nothing visible.
    if (this.v < 0.05) this.v = 1;
    this.fromHsv();
  }

  fromHsv() {
    this.current = hsvToHex(this.h, this.s, this.v);
    this.showError("");
    this.render();
    this.emit();
  }

  /** A whole colour from outside, or from the hex box. */
  set(hex, { quiet = false, keepText = false } = {}) {
    this.current = hex;
    const { h, s, v } = hexToHsv(hex);
    // A grey has no hue of its own: keep the one the wheel was on.
    if (s > 0) this.h = h;
    else this.h ??= 0;
    this.s = s;
    this.v = v;
    this.render({ keepText });
    if (!quiet) this.emit();
  }

  emit() {
    this.root.dispatchEvent(new Event("input", { bubbles: true }));
  }

  render({ keepText = false } = {}) {
    const { slider, marker, wrap, hex } = this;
    slider.value = String(Math.round(this.v * 100));
    slider.style.setProperty("--wheel-top", hsvToHex(this.h, this.s, 1));
    const a = (this.h * Math.PI) / 180;
    marker.style.left = `${50 + 50 * this.s * Math.cos(a)}%`;
    marker.style.top = `${50 - 50 * this.s * Math.sin(a)}%`;
    marker.style.background = this.current;
    if (!keepText) hex.value = this.current.toUpperCase();
    wrap.setAttribute("aria-valuenow", String(Math.round(this.s * 100)));
    wrap.setAttribute(
      "aria-valuetext",
      `${this.current.toUpperCase()}: hue ${Math.round(this.h)} degrees, saturation ${Math.round(this.s * 100)} percent, brightness ${Math.round(this.v * 100)} percent`
    );
    this.draw();
  }

  // Redrawn only when the brightness or the size changes.
  draw() {
    const { canvas } = this;
    const size = Math.round(canvas.clientWidth * (window.devicePixelRatio || 1));
    if (!size) return;
    const key = `${size}|${this.v.toFixed(2)}`;
    if (this.drawnFor === key) return;
    this.drawnFor = key;
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext("2d");
    const img = ctx.createImageData(size, size);
    const r = size / 2;
    for (let py = 0; py < size; py++) {
      for (let px = 0; px < size; px++) {
        const x = (px + 0.5 - r) / r;
        const y = (r - py - 0.5) / r;
        const d = Math.hypot(x, y);
        // A pixel's worth of soft edge, so the rim is not jagged.
        const alpha = Math.max(0, Math.min(1, (1 - d) * r));
        if (!alpha) continue;
        const [red, green, blue] = hsvToRgb(((Math.atan2(y, x) * 180) / Math.PI + 360) % 360, Math.min(1, d), this.v);
        const i = (py * size + px) * 4;
        img.data[i] = red;
        img.data[i + 1] = green;
        img.data[i + 2] = blue;
        img.data[i + 3] = Math.round(alpha * 255);
      }
    }
    ctx.putImageData(img, 0, 0);
  }
}

/** Every [data-colour-picker] on the page. Called by bootShell. */
export function initColourPickers(root = document) {
  root.querySelectorAll("[data-colour-picker]").forEach((el) => {
    if (!el.dataset.ready) {
      el.dataset.ready = "1";
      new ColourPicker(el);
    }
  });
}
