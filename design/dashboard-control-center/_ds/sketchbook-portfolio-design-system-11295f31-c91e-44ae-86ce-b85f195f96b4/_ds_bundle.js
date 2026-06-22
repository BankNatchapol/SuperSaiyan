/* @ds-bundle: {"format":3,"namespace":"SketchbookPortfolioDesignSystem_11295f","components":[{"name":"Button","sourcePath":"components/buttons/Button.jsx"},{"name":"IconButton","sourcePath":"components/buttons/IconButton.jsx"},{"name":"Avatar","sourcePath":"components/display/Avatar.jsx"},{"name":"Badge","sourcePath":"components/display/Badge.jsx"},{"name":"Card","sourcePath":"components/display/Card.jsx"},{"name":"Divider","sourcePath":"components/display/Divider.jsx"},{"name":"Tag","sourcePath":"components/display/Tag.jsx"},{"name":"Checkbox","sourcePath":"components/forms/Checkbox.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Textarea","sourcePath":"components/forms/Textarea.jsx"},{"name":"Tabs","sourcePath":"components/navigation/Tabs.jsx"}],"sourceHashes":{"components/buttons/Button.jsx":"1fd541c42740","components/buttons/IconButton.jsx":"a2e09c90bb6e","components/display/Avatar.jsx":"7e94a4e33ed8","components/display/Badge.jsx":"c2e10083dba3","components/display/Card.jsx":"6cacc35e6a01","components/display/Divider.jsx":"14df4615e5b0","components/display/Tag.jsx":"4fa5395e636b","components/forms/Checkbox.jsx":"cdbfff950f46","components/forms/Input.jsx":"880a1b8e4cf2","components/forms/Textarea.jsx":"0d8f0d171c6c","components/navigation/Tabs.jsx":"cf75c2bb4b72","ui_kits/portfolio/Contact.jsx":"c0aa8a992c25","ui_kits/portfolio/Experience.jsx":"815604421dea","ui_kits/portfolio/Hero.jsx":"57720dddde34","ui_kits/portfolio/Nav.jsx":"994e5b19f6a4","ui_kits/portfolio/Projects.jsx":"ab714e92cd8e","ui_kits/portfolio/Publications.jsx":"b2f0a2cb5e1e","ui_kits/portfolio/Research.jsx":"31934f65d14e","ui_kits/portfolio/kit.jsx":"3c75645e7abf"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.SketchbookPortfolioDesignSystem_11295f = window.SketchbookPortfolioDesignSystem_11295f || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/buttons/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Injects the component's hover/active/focus CSS once per document.
   Inline styles can't express pseudo-states, so the static look lives inline
   and the interactive bits live in this tiny stylesheet. */
let injected = false;
function useSketchButtonCSS() {
  React.useEffect(() => {
    if (injected || typeof document === 'undefined') return;
    injected = true;
    const el = document.createElement('style');
    el.id = 'sk-button-css';
    el.textContent = `
      .sk-btn { transition: transform var(--dur-quick) var(--ease-hand),
                            box-shadow var(--dur-quick) var(--ease-hand),
                            background-color var(--dur-quick) ease; }
      .sk-btn:hover:not(:disabled) { transform: translate(-1px,-1px) rotate(-0.6deg); }
      .sk-btn:active:not(:disabled){ transform: translate(1px,2px) rotate(0.3deg); box-shadow: var(--shadow-sketch-sm) !important; }
      .sk-btn:focus-visible { outline: 2px dashed var(--focus-ring); outline-offset: 3px; }
      .sk-btn--primary:hover:not(:disabled)  { background-color: var(--blue-700); }
      .sk-btn--secondary:hover:not(:disabled){ background-color: var(--paper-2); }
      .sk-btn--ghost:hover:not(:disabled)    { background-color: var(--blue-100); }
    `;
    document.head.appendChild(el);
  }, []);
}
const SIZES = {
  sm: {
    fontSize: '13px',
    padding: '6px 14px'
  },
  md: {
    fontSize: '15px',
    padding: '10px 20px'
  },
  lg: {
    fontSize: '17px',
    padding: '14px 28px'
  }
};
const RADII = ['var(--sketch-radius-1)', 'var(--sketch-radius-2)', 'var(--sketch-radius-3)'];

/**
 * Button — a hand-drawn action with a wobbly ink border and a doodle shadow.
 * Hover lifts & tilts the paper; press pushes it down.
 */
function Button({
  children,
  variant = 'primary',
  size = 'md',
  icon = null,
  iconRight = null,
  disabled = false,
  wobble = 0,
  // 0–2: pick a border-radius preset so repeats vary
  style = {},
  ...rest
}) {
  useSketchButtonCSS();
  const base = {
    fontFamily: 'var(--font-label)',
    letterSpacing: '0.04em',
    lineHeight: 1.1,
    display: 'inline-flex',
    alignItems: 'center',
    gap: '8px',
    whiteSpace: 'nowrap',
    cursor: disabled ? 'not-allowed' : 'pointer',
    border: 'var(--stroke) solid var(--ink-line)',
    borderRadius: RADII[wobble % RADII.length],
    boxShadow: 'var(--shadow-sketch)',
    textDecoration: 'none',
    opacity: disabled ? 0.45 : 1,
    ...SIZES[size]
  };
  const variants = {
    primary: {
      background: 'var(--blue-500)',
      color: 'var(--paper-0)'
    },
    secondary: {
      background: 'var(--surface-card)',
      color: 'var(--ink-900)'
    },
    ghost: {
      background: 'transparent',
      color: 'var(--blue-700)',
      boxShadow: 'none',
      borderStyle: 'dashed'
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    className: `sk-btn sk-btn--${variant}`,
    disabled: disabled,
    style: {
      ...base,
      ...variants[variant],
      ...style
    }
  }, rest), icon, children, iconRight);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/buttons/Button.jsx", error: String((e && e.message) || e) }); }

// components/buttons/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useIconButtonCSS() {
  React.useEffect(() => {
    if (injected || typeof document === 'undefined') return;
    injected = true;
    const el = document.createElement('style');
    el.id = 'sk-iconbutton-css';
    el.textContent = `
      .sk-iconbtn { transition: transform var(--dur-quick) var(--ease-hand), background-color var(--dur-quick) ease; }
      .sk-iconbtn:hover:not(:disabled)  { transform: rotate(-4deg) scale(1.06); background-color: var(--blue-100); }
      .sk-iconbtn:active:not(:disabled) { transform: rotate(2deg) scale(0.94); }
      .sk-iconbtn:focus-visible { outline: 2px dashed var(--focus-ring); outline-offset: 3px; }
    `;
    document.head.appendChild(el);
  }, []);
}
const SIZES = {
  sm: 32,
  md: 40,
  lg: 48
};

/**
 * IconButton — a circular-ish hand-drawn button for a single glyph/icon.
 */
function IconButton({
  children,
  label,
  size = 'md',
  variant = 'outline',
  disabled = false,
  style = {},
  ...rest
}) {
  useIconButtonCSS();
  const d = SIZES[size] || SIZES.md;
  const variants = {
    outline: {
      background: 'var(--surface-card)',
      border: 'var(--stroke) solid var(--ink-line)',
      color: 'var(--ink-900)'
    },
    solid: {
      background: 'var(--blue-500)',
      border: 'var(--stroke) solid var(--ink-line)',
      color: 'var(--paper-0)'
    },
    plain: {
      background: 'transparent',
      border: '0',
      color: 'var(--ink-700)'
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    className: "sk-iconbtn",
    "aria-label": label,
    title: label,
    disabled: disabled,
    style: {
      width: d,
      height: d,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 'var(--sketch-radius-blob)',
      cursor: disabled ? 'not-allowed' : 'pointer',
      opacity: disabled ? 0.45 : 1,
      boxShadow: variant === 'plain' ? 'none' : 'var(--shadow-sketch-sm)',
      ...variants[variant],
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/buttons/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/display/Avatar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Avatar — a portrait framed in a hand-drawn blob border. Falls back to
 * initials on a paper tint when no image is given.
 */
function Avatar({
  src,
  alt = '',
  initials = '',
  size = 64,
  tone = 'blue',
  style = {},
  ...rest
}) {
  const tints = {
    blue: {
      bg: 'var(--blue-100)',
      fg: 'var(--blue-700)'
    },
    terra: {
      bg: 'var(--terra-100)',
      fg: 'var(--terra-500)'
    },
    sage: {
      bg: 'var(--sage-100)',
      fg: 'var(--sage-500)'
    }
  };
  const t = tints[tone] || tints.blue;
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      width: size,
      height: size,
      flex: 'none',
      borderRadius: 'var(--sketch-radius-blob)',
      border: 'var(--stroke) solid var(--ink-line)',
      boxShadow: 'var(--shadow-sketch-sm)',
      overflow: 'hidden',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: t.bg,
      color: t.fg,
      fontFamily: 'var(--font-display)',
      fontSize: size * 0.42,
      lineHeight: 1,
      ...style
    }
  }, rest), src ? /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: alt,
    style: {
      width: '100%',
      height: '100%',
      objectFit: 'cover'
    }
  }) : /*#__PURE__*/React.createElement("span", {
    "aria-label": alt
  }, initials));
}
Object.assign(__ds_scope, { Avatar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Avatar.jsx", error: String((e && e.message) || e) }); }

// components/display/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Badge — a small stamped label. Use `tone` to colour-code (status, year,
 * category). Reads like a rubber-stamp in Special Elite.
 */
function Badge({
  children,
  tone = 'ink',
  style = {},
  ...rest
}) {
  const tones = {
    ink: {
      bg: 'var(--paper-2)',
      fg: 'var(--ink-900)',
      bd: 'var(--ink-line)'
    },
    blue: {
      bg: 'var(--blue-100)',
      fg: 'var(--blue-700)',
      bd: 'var(--blue-500)'
    },
    terra: {
      bg: 'var(--terra-100)',
      fg: 'var(--terra-500)',
      bd: 'var(--terra-500)'
    },
    sage: {
      bg: 'var(--sage-100)',
      fg: 'var(--sage-500)',
      bd: 'var(--sage-500)'
    },
    amber: {
      bg: 'var(--amber-100)',
      fg: 'var(--pencil-500)',
      bd: 'var(--amber-500)'
    }
  };
  const t = tones[tone] || tones.ink;
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '5px',
      fontFamily: 'var(--font-label)',
      fontSize: '11px',
      letterSpacing: '0.1em',
      textTransform: 'uppercase',
      lineHeight: 1,
      padding: '4px 9px',
      color: t.fg,
      background: t.bg,
      border: `var(--stroke-fine) solid ${t.bd}`,
      borderRadius: 'var(--sketch-radius-2)',
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Badge.jsx", error: String((e && e.message) || e) }); }

// components/display/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const RADII = ['var(--sketch-radius-1)', 'var(--sketch-radius-2)', 'var(--sketch-radius-3)'];

/**
 * Card — a sheet of paper with a drawn ink border and a doodle shadow.
 * Optional `tilt` gives it that pinned-to-a-corkboard lean.
 */
function Card({
  children,
  wobble = 0,
  tilt = 0,
  shadow = 'sketch',
  // 'sketch' | 'lift' | 'none'
  grain = true,
  interactive = false,
  style = {},
  ...rest
}) {
  const shadows = {
    sketch: 'var(--shadow-sketch)',
    lift: 'var(--shadow-lift)',
    none: 'none'
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      background: 'var(--surface-card)',
      backgroundImage: grain ? 'var(--paper-grain)' : 'none',
      border: 'var(--stroke) solid var(--ink-line)',
      borderRadius: RADII[wobble % RADII.length],
      boxShadow: shadows[shadow] || shadows.sketch,
      padding: 'var(--space-5)',
      transform: tilt ? `rotate(${tilt}deg)` : undefined,
      transition: interactive ? 'transform var(--dur) var(--ease-hand), box-shadow var(--dur) var(--ease-hand)' : undefined,
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Card.jsx", error: String((e && e.message) || e) }); }

// components/display/Divider.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Divider — a hand-drawn rule. `variant` picks the stroke: a wavy ink line,
 * a dashed pencil line, or a row of sketchy dots.
 */
function Divider({
  variant = 'wave',
  color = 'var(--ink-line)',
  style = {},
  ...rest
}) {
  if (variant === 'dashed') {
    return /*#__PURE__*/React.createElement("hr", _extends({
      style: {
        border: 'none',
        borderTop: `2px dashed ${color}`,
        opacity: 0.5,
        margin: 'var(--space-5) 0',
        ...style
      }
    }, rest));
  }
  if (variant === 'dots') {
    return /*#__PURE__*/React.createElement("div", _extends({
      role: "separator",
      style: {
        height: '8px',
        backgroundImage: `radial-gradient(${color} 1.4px, transparent 1.6px)`,
        backgroundSize: '14px 8px',
        opacity: 0.55,
        margin: 'var(--space-5) 0',
        ...style
      }
    }, rest));
  }
  // wave — a drawn squiggle. The SVG is a black mask; the visible colour is
  // the element's background, so any CSS colour/var works.
  const wave = "data:image/svg+xml," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='10' viewBox='0 0 80 10'>" + "<path d='M0 5 Q 10 0 20 5 T 40 5 T 60 5 T 80 5' fill='none' stroke='#000' stroke-width='1.6'/></svg>");
  return /*#__PURE__*/React.createElement("div", _extends({
    role: "separator",
    style: {
      height: '10px',
      background: color,
      WebkitMaskImage: `url("${wave}")`,
      maskImage: `url("${wave}")`,
      WebkitMaskRepeat: 'repeat-x',
      maskRepeat: 'repeat-x',
      WebkitMaskPosition: 'center',
      maskPosition: 'center',
      margin: 'var(--space-5) 0',
      ...style
    }
  }, rest));
}
Object.assign(__ds_scope, { Divider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Divider.jsx", error: String((e && e.message) || e) }); }

// components/display/Tag.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Tag — a hand-drawn chip for research keywords / skills. Lighter than Badge;
 * meant to sit in rows. Renders as a button when `onClick` is supplied.
 */
function Tag({
  children,
  active = false,
  onClick,
  style = {},
  ...rest
}) {
  const Comp = onClick ? 'button' : 'span';
  return /*#__PURE__*/React.createElement(Comp, _extends({
    onClick: onClick,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '6px',
      fontFamily: 'var(--font-body)',
      fontSize: '14px',
      lineHeight: 1.2,
      padding: '5px 12px',
      color: active ? 'var(--paper-0)' : 'var(--ink-700)',
      background: active ? 'var(--blue-500)' : 'transparent',
      border: 'var(--stroke-fine) solid var(--ink-line)',
      borderRadius: 'var(--sketch-radius-1)',
      cursor: onClick ? 'pointer' : 'default',
      font: 'inherit',
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Tag });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Tag.jsx", error: String((e && e.message) || e) }); }

// components/forms/Checkbox.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Checkbox — a hand-drawn tick-box. The check is a drawn SVG stroke that
 * "inks in" when toggled. Controlled via `checked` / `onChange`.
 */
function Checkbox({
  label,
  checked = false,
  onChange,
  disabled = false,
  id,
  style = {},
  ...rest
}) {
  const fid = id || `sk-${Math.random().toString(36).slice(2, 8)}`;
  return /*#__PURE__*/React.createElement("label", {
    htmlFor: fid,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '10px',
      fontFamily: 'var(--font-body)',
      fontSize: '15px',
      color: 'var(--ink-900)',
      cursor: disabled ? 'not-allowed' : 'pointer',
      opacity: disabled ? 0.5 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("input", _extends({
    id: fid,
    type: "checkbox",
    checked: checked,
    disabled: disabled,
    onChange: onChange,
    style: {
      position: 'absolute',
      opacity: 0,
      width: 0,
      height: 0
    }
  }, rest)), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      width: 24,
      height: 24,
      flex: 'none',
      position: 'relative',
      border: 'var(--stroke) solid var(--ink-line)',
      borderRadius: 'var(--sketch-radius-2)',
      background: checked ? 'var(--blue-100)' : 'var(--paper-0)',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'background var(--dur-quick) ease'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "16",
    height: "16",
    viewBox: "0 0 16 16",
    fill: "none",
    style: {
      opacity: checked ? 1 : 0,
      transition: 'opacity var(--dur-quick) var(--ease-ink)'
    }
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2 8.5 Q 5 13 6.5 13 Q 9 13 14 2.5",
    stroke: "var(--blue-700)",
    strokeWidth: "2.4",
    strokeLinecap: "round",
    fill: "none"
  }))), label);
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useFieldCSS() {
  React.useEffect(() => {
    if (injected || typeof document === 'undefined') return;
    injected = true;
    const el = document.createElement('style');
    el.id = 'sk-field-css';
    el.textContent = `
      .sk-input { transition: border-color var(--dur-quick) ease, box-shadow var(--dur-quick) ease; }
      .sk-input::placeholder { color: var(--pencil-300); font-style: italic; }
      .sk-input:focus { outline: none; border-color: var(--blue-500);
        box-shadow: 2px 3px 0 var(--blue-100); }
      .sk-input:disabled { opacity: .5; cursor: not-allowed; }
    `;
    document.head.appendChild(el);
  }, []);
}

/**
 * Input — a single-line field that looks ruled into the page, with a wobbly
 * ink underline-and-box. Supports an optional label and hint.
 */
function Input({
  label,
  hint,
  id,
  invalid = false,
  style = {},
  wrapStyle = {},
  ...rest
}) {
  useFieldCSS();
  const fid = id || `sk-${Math.random().toString(36).slice(2, 8)}`;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '6px',
      ...wrapStyle
    }
  }, label && /*#__PURE__*/React.createElement("label", {
    htmlFor: fid,
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '11px',
      letterSpacing: '0.12em',
      textTransform: 'uppercase',
      color: 'var(--ink-700)'
    }
  }, label), /*#__PURE__*/React.createElement("input", _extends({
    id: fid,
    className: "sk-input",
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: '16px',
      color: 'var(--ink-900)',
      padding: '10px 14px',
      background: 'var(--paper-0)',
      border: `var(--stroke) solid ${invalid ? 'var(--terra-500)' : 'var(--ink-line)'}`,
      borderRadius: 'var(--sketch-radius-1)',
      ...style
    }
  }, rest)), hint && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: '13px',
      color: invalid ? 'var(--terra-500)' : 'var(--text-faint)'
    }
  }, hint));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Textarea.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Ensures the shared .sk-input focus/placeholder CSS exists even when Input
   isn't on the page. Guarded by element id so it's only added once. */
function useSharedFieldCSS() {
  React.useEffect(() => {
    if (typeof document === 'undefined' || document.getElementById('sk-field-css')) return;
    const el = document.createElement('style');
    el.id = 'sk-field-css';
    el.textContent = `
      .sk-input { transition: border-color var(--dur-quick) ease, box-shadow var(--dur-quick) ease; }
      .sk-input::placeholder { color: var(--pencil-300); font-style: italic; }
      .sk-input:focus { outline: none; border-color: var(--blue-500); box-shadow: 2px 3px 0 var(--blue-100); }
      .sk-input:disabled { opacity: .5; cursor: not-allowed; }
    `;
    document.head.appendChild(el);
  }, []);
}

/**
 * Textarea — multi-line sibling of Input. Same drawn box, with faint ruled
 * lines so it reads like notebook paper.
 */
function Textarea({
  label,
  hint,
  id,
  rows = 4,
  ruled = true,
  invalid = false,
  style = {},
  wrapStyle = {},
  ...rest
}) {
  useSharedFieldCSS();
  const fid = id || `sk-${Math.random().toString(36).slice(2, 8)}`;
  const ruledBg = ruled ? 'repeating-linear-gradient(var(--paper-0) 0 27px, var(--paper-edge) 27px 28px)' : 'var(--paper-0)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '6px',
      ...wrapStyle
    }
  }, label && /*#__PURE__*/React.createElement("label", {
    htmlFor: fid,
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '11px',
      letterSpacing: '0.12em',
      textTransform: 'uppercase',
      color: 'var(--ink-700)'
    }
  }, label), /*#__PURE__*/React.createElement("textarea", _extends({
    id: fid,
    rows: rows,
    className: "sk-input",
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: '16px',
      lineHeight: '28px',
      color: 'var(--ink-900)',
      padding: '8px 14px',
      resize: 'vertical',
      background: ruledBg,
      backgroundAttachment: 'local',
      border: `var(--stroke) solid ${invalid ? 'var(--terra-500)' : 'var(--ink-line)'}`,
      borderRadius: 'var(--sketch-radius-2)',
      ...style
    }
  }, rest)), hint && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: '13px',
      color: invalid ? 'var(--terra-500)' : 'var(--text-faint)'
    }
  }, hint));
}
Object.assign(__ds_scope, { Textarea });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Textarea.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Tabs.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Tabs — a row of hand-drawn tab labels with a wavy ink underline that slides
 * to the active one. Controlled via `value` / `onChange`, or uncontrolled with
 * `defaultValue`.
 *
 * items: [{ value, label }]
 */
function Tabs({
  items = [],
  value,
  defaultValue,
  onChange,
  style = {},
  ...rest
}) {
  const [internal, setInternal] = React.useState(defaultValue ?? items[0]?.value);
  const active = value !== undefined ? value : internal;
  const select = v => {
    if (value === undefined) setInternal(v);
    onChange && onChange(v);
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    role: "tablist",
    style: {
      display: 'flex',
      gap: '4px',
      alignItems: 'flex-end',
      borderBottom: '2px solid var(--paper-edge)',
      ...style
    }
  }, rest), items.map(it => {
    const on = it.value === active;
    return /*#__PURE__*/React.createElement("button", {
      key: it.value,
      role: "tab",
      "aria-selected": on,
      onClick: () => select(it.value),
      style: {
        position: 'relative',
        fontFamily: 'var(--font-label)',
        fontSize: '13px',
        letterSpacing: '0.06em',
        textTransform: 'uppercase',
        color: on ? 'var(--ink-900)' : 'var(--text-faint)',
        background: 'transparent',
        border: 'none',
        cursor: 'pointer',
        padding: '8px 14px 12px',
        marginBottom: '-2px',
        transition: 'color var(--dur-quick) ease'
      }
    }, it.label, /*#__PURE__*/React.createElement("span", {
      "aria-hidden": "true",
      style: {
        position: 'absolute',
        left: 8,
        right: 8,
        bottom: 0,
        height: '3px',
        background: 'var(--blue-500)',
        borderRadius: 'var(--radius-pill)',
        transform: on ? 'scaleX(1)' : 'scaleX(0)',
        transformOrigin: 'left',
        transition: 'transform var(--dur) var(--ease-hand)'
      }
    }));
  }));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Tabs.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Contact.jsx
try { (() => {
/* Contact — a note-card with a working-looking form (fake submit) plus direct
   links. On submit it stamps a handwritten thank-you over the card. */
function Contact() {
  const [sent, setSent] = React.useState(false);
  const [name, setName] = React.useState('');
  const submit = e => {
    e.preventDefault();
    if (name.trim()) setSent(true);
  };
  const links = [['mail', 'natchapol@qubit.dev', 'mailto:natchapol@qubit.dev'], ['github', 'github.com/npatama', 'https://github.com'], ['graduation-cap', 'Google Scholar', '#'], ['map-pin', 'Waterloo, ON', '#']];
  return /*#__PURE__*/React.createElement(window.Section, {
    id: "contact",
    num: "05",
    eyebrow: "Contact",
    title: "Get in touch",
    note: "I reply, eventually \u2726",
    bg: "var(--paper-0)"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1.1fr 0.9fr',
      gap: 'var(--space-8)',
      alignItems: 'start'
    },
    className: "contact-grid"
  }, /*#__PURE__*/React.createElement(window.Reveal, null, /*#__PURE__*/React.createElement(NS.Card, {
    wobble: 1,
    tilt: -0.8,
    style: {
      position: 'relative'
    }
  }, !sent ? /*#__PURE__*/React.createElement("form", {
    onSubmit: submit,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement(NS.Input, {
    label: "Your name",
    placeholder: "who's writing?",
    value: name,
    onChange: e => setName(e.target.value)
  }), /*#__PURE__*/React.createElement(NS.Input, {
    label: "Email",
    type: "email",
    placeholder: "you@somewhere"
  }), /*#__PURE__*/React.createElement(NS.Textarea, {
    label: "Message",
    rows: 4,
    placeholder: "say hello, ask a question, send a paper\u2026"
  }), /*#__PURE__*/React.createElement(NS.Button, {
    variant: "primary",
    type: "submit",
    iconRight: /*#__PURE__*/React.createElement(window.Icon, {
      name: "send",
      size: 16
    })
  }, "Send it")) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 'var(--space-6) var(--space-3)',
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: '44px',
      color: 'var(--blue-500)',
      lineHeight: 1,
      transform: 'rotate(-3deg)'
    }
  }, "Thanks, ", name.split(' ')[0], "!"), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-base)',
      color: 'var(--ink-700)',
      marginTop: 'var(--space-4)'
    }
  }, "Your note is on its way. I'll get back to you soon."), /*#__PURE__*/React.createElement(NS.Button, {
    variant: "ghost",
    onClick: () => setSent(false),
    style: {
      marginTop: 'var(--space-3)'
    }
  }, "\u2190 write another")))), /*#__PURE__*/React.createElement(window.Reveal, {
    delay: 120
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-2)'
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-md)',
      lineHeight: 1.7,
      color: 'var(--ink-700)',
      margin: '0 0 var(--space-4)'
    }
  }, "Always happy to talk error correction, control software, or the long road to a useful quantum computer. The fastest way to reach me:"), links.map(([icon, label, href]) => /*#__PURE__*/React.createElement("a", {
    key: label,
    href: href,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '14px',
      padding: 'var(--space-3) var(--space-4)',
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-base)',
      color: 'var(--ink-900)',
      textDecoration: 'none',
      border: '2px solid var(--ink-line)',
      borderRadius: 'var(--sketch-radius-1)',
      background: 'var(--surface-card)',
      boxShadow: 'var(--shadow-sketch-sm)'
    },
    className: "contact-link"
  }, /*#__PURE__*/React.createElement(window.Icon, {
    name: icon,
    size: 20,
    color: "var(--blue-700)"
  }), label))))));
}
window.Contact = Contact;

/* Footer — a torn strip with a handwritten sign-off. */
function Footer() {
  return /*#__PURE__*/React.createElement("footer", {
    style: {
      borderTop: '2px solid var(--ink-line)',
      padding: 'var(--space-7) var(--gutter)',
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-hand)',
      fontSize: '26px',
      color: 'var(--ink-700)'
    }
  }, "drawn & written by Natchapol, ", new Date().getFullYear()), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '11px',
      letterSpacing: '0.12em',
      textTransform: 'uppercase',
      color: 'var(--pencil-300)',
      marginTop: '8px'
    }
  }, "made on paper \xB7 no qubits were harmed"));
}
window.Footer = Footer;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Contact.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Experience.jsx
try { (() => {
/* Experience — a CV timeline drawn as a dashed ink line with sketched nodes. */
function Experience() {
  const items = [{
    when: '2021 — now',
    role: 'PhD Candidate, Quantum Information',
    org: 'Institute for Quantum Computing',
    tone: 'blue',
    detail: 'Real-time surface-code decoding and control software for superconducting devices.'
  }, {
    when: 'Summer 2023',
    role: 'Visiting Researcher',
    org: 'Industrial Quantum Lab',
    tone: 'terra',
    detail: 'Crosstalk-aware calibration across a 50-qubit lattice.'
  }, {
    when: '2021',
    role: 'MSc Physics',
    org: 'ETH Zürich',
    tone: 'sage',
    detail: 'Thesis on leakage characterisation in transmon qubits.'
  }, {
    when: '2019',
    role: 'BSc Physics (First Class)',
    org: 'Chulalongkorn University',
    tone: 'amber',
    detail: 'Foundations in condensed matter and computation.'
  }];
  return /*#__PURE__*/React.createElement(window.Section, {
    id: "experience",
    num: "04",
    eyebrow: "Experience",
    title: "The short CV",
    note: "pinned to the board"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: '720px',
      position: 'relative',
      paddingLeft: '34px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    "aria-hidden": "true",
    style: {
      position: 'absolute',
      left: '9px',
      top: '6px',
      bottom: '6px',
      width: '2px',
      backgroundImage: 'repeating-linear-gradient(var(--ink-line) 0 6px, transparent 6px 12px)'
    }
  }), items.map((it, i) => /*#__PURE__*/React.createElement(window.Reveal, {
    key: it.role,
    delay: i * 90
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      paddingBottom: i === items.length - 1 ? 0 : 'var(--space-7)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      position: 'absolute',
      left: '-34px',
      top: '4px',
      width: '20px',
      height: '20px',
      background: `var(--${it.tone}-300)`,
      border: '2px solid var(--ink-line)',
      borderRadius: 'var(--sketch-radius-blob)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '12px',
      letterSpacing: '0.1em',
      textTransform: 'uppercase',
      color: 'var(--pencil-500)'
    }
  }, it.when), /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-body)',
      fontWeight: 700,
      fontSize: 'var(--text-lg)',
      margin: '4px 0 2px',
      color: 'var(--ink-900)'
    }
  }, it.role), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-hand)',
      fontSize: '22px',
      color: `var(--${it.tone}-500)`,
      lineHeight: 1.1
    }
  }, it.org), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-base)',
      lineHeight: 1.7,
      color: 'var(--ink-700)',
      margin: '8px 0 0',
      maxWidth: '54ch'
    }
  }, it.detail))))));
}
window.Experience = Experience;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Experience.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Hero.jsx
try { (() => {
/* Hero — name, title, short bio, CTAs, social row. The handwritten name is
   the anchor; a margin note and a drawn arrow add the sketchbook feel. */
function Hero() {
  const socials = [['github', 'GitHub', 'https://github.com'], ['graduation-cap', 'Google Scholar', '#'], ['file-text', 'arXiv', '#'], ['twitter', 'X', '#']];
  const go = id => e => {
    e.preventDefault();
    const el = document.getElementById(id);
    if (el) window.scrollTo({
      top: el.offsetTop - 20,
      behavior: 'smooth'
    });
  };
  return /*#__PURE__*/React.createElement("section", {
    id: "top",
    style: {
      padding: 'clamp(56px, 12vh, 120px) var(--gutter) var(--section-gap)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--content-wide)',
      margin: '0 auto',
      display: 'grid',
      gridTemplateColumns: 'minmax(0,1fr) auto',
      gap: 'var(--space-8)',
      alignItems: 'center'
    },
    className: "hero-grid"
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(window.Reveal, null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '14px',
      letterSpacing: '0.18em',
      textTransform: 'uppercase',
      color: 'var(--blue-700)'
    }
  }, "Quantum Computing Researcher")), /*#__PURE__*/React.createElement(window.Reveal, {
    delay: 80
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: 'clamp(64px, 11vw, 128px)',
      lineHeight: 0.92,
      margin: '10px 0 0',
      color: 'var(--ink-900)',
      textWrap: 'balance'
    }
  }, "Natchapol", /*#__PURE__*/React.createElement("br", null), /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--blue-500)'
    }
  }, "Patamawisut"))), /*#__PURE__*/React.createElement(window.Reveal, {
    delay: 160
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-md)',
      lineHeight: 1.75,
      color: 'var(--ink-700)',
      maxWidth: '52ch',
      margin: 'var(--space-5) 0 0'
    }
  }, "I build the error-correction software that keeps fragile qubits honest \u2014 real-time decoders, pulse-level calibration, and the unglamorous plumbing between a dilution fridge and a laptop. PhD candidate at the Institute for Quantum Computing.")), /*#__PURE__*/React.createElement(window.Reveal, {
    delay: 240
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-3)',
      flexWrap: 'wrap',
      marginTop: 'var(--space-6)'
    }
  }, /*#__PURE__*/React.createElement(NS.Button, {
    variant: "primary",
    onClick: go('publications'),
    iconRight: /*#__PURE__*/React.createElement(window.Icon, {
      name: "arrow-right",
      size: 16
    })
  }, "Read my work"), /*#__PURE__*/React.createElement(NS.Button, {
    variant: "secondary",
    wobble: 1,
    icon: /*#__PURE__*/React.createElement(window.Icon, {
      name: "download",
      size: 16
    })
  }, "Download CV"))), /*#__PURE__*/React.createElement(window.Reveal, {
    delay: 320
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-3)',
      marginTop: 'var(--space-6)',
      alignItems: 'center'
    }
  }, socials.map(([icon, label, href]) => /*#__PURE__*/React.createElement(NS.IconButton, {
    key: label,
    label: label,
    variant: "outline",
    onClick: () => window.open(href, '_blank')
  }, /*#__PURE__*/React.createElement(window.Icon, {
    name: icon,
    size: 18
  })))))), /*#__PURE__*/React.createElement(window.Reveal, {
    delay: 200,
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "hero-portrait"
  }, /*#__PURE__*/React.createElement(NS.Avatar, {
    initials: "NP",
    tone: "blue",
    size: 210
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      bottom: -18,
      right: -26,
      fontFamily: 'var(--font-hand)',
      fontSize: '22px',
      color: 'var(--terra-500)',
      transform: 'rotate(-6deg)'
    }
  }, "that's me \u2196")))));
}
window.Hero = Hero;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Hero.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Nav.jsx
try { (() => {
/* Sticky top navigation — name mark + section links + theme of paper. */
function Nav() {
  const [open, setOpen] = React.useState(false);
  const links = [['research', 'Research'], ['projects', 'Projects'], ['publications', 'Publications'], ['experience', 'Experience'], ['contact', 'Contact']];
  const go = id => e => {
    e.preventDefault();
    const el = document.getElementById(id);
    if (el) window.scrollTo({
      top: el.offsetTop - 20,
      behavior: 'smooth'
    });
    setOpen(false);
  };
  return /*#__PURE__*/React.createElement("header", {
    style: {
      position: 'sticky',
      top: 0,
      zIndex: 100,
      background: 'color-mix(in srgb, var(--paper-1) 88%, transparent)',
      backdropFilter: 'blur(4px)',
      borderBottom: '2px solid var(--ink-line)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--content-wide)',
      margin: '0 auto',
      padding: '14px var(--gutter)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between'
    }
  }, /*#__PURE__*/React.createElement("a", {
    href: "#top",
    onClick: go('top'),
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: '30px',
      color: 'var(--ink-900)',
      textDecoration: 'none',
      lineHeight: 1
    }
  }, "N", /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--blue-500)'
    }
  }, "."), "Patamawisut"), /*#__PURE__*/React.createElement("nav", {
    style: {
      display: 'flex',
      gap: '4px',
      alignItems: 'center'
    },
    className: "nav-links"
  }, links.map(([id, label]) => /*#__PURE__*/React.createElement("a", {
    key: id,
    href: `#${id}`,
    onClick: go(id),
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '12px',
      letterSpacing: '0.1em',
      textTransform: 'uppercase',
      color: 'var(--ink-700)',
      textDecoration: 'none',
      padding: '8px 12px'
    },
    className: "nav-link"
  }, label)), /*#__PURE__*/React.createElement(NS.Button, {
    size: "sm",
    variant: "primary",
    onClick: go('contact'),
    style: {
      marginLeft: '8px'
    }
  }, "Say hello"))));
}
window.Nav = Nav;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Nav.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Projects.jsx
try { (() => {
/* Projects — selected builds, split into a Quantum group and an AI group.
   Each project is a tilted paper card with a status badge, blurb, tags, and a
   repo link. The two groups are labelled with handwritten sub-headers. */
function Projects() {
  const groups = [{
    key: 'quantum',
    label: 'Quantum',
    tone: 'blue',
    note: 'fridge-tested ❄',
    projects: [{
      name: 'surfsim',
      status: 'maintained',
      blurb: 'A GPU surface-code simulator that runs a distance-21 patch in real time.',
      tags: ['CUDA', 'QEC']
    }, {
      name: 'decoderd',
      status: 'research',
      blurb: 'Low-latency decoder daemon that talks to the control stack over shared memory.',
      tags: ['Rust', 'decoding']
    }, {
      name: 'calibkit',
      status: 'open source',
      blurb: 'Autocalibration routines for fixed-frequency transmons — set it and forget it.',
      tags: ['Python', 'calibration']
    }]
  }, {
    key: 'ai',
    label: 'AI',
    tone: 'terra',
    note: 'learned, not hand-tuned ✦',
    projects: [{
      name: 'ml-decoder',
      status: 'research',
      blurb: 'A neural decoder for the surface code that beats MWPM at high noise.',
      tags: ['PyTorch', 'GNN']
    }, {
      name: 'noise2vec',
      status: 'experimental',
      blurb: 'Learned embeddings of qubit noise that predict gate fidelity drift.',
      tags: ['representation', 'time-series']
    }, {
      name: 'scholar-rag',
      status: 'side project',
      blurb: 'A retrieval-augmented assistant over the full quant-ph arXiv corpus.',
      tags: ['LLM', 'RAG']
    }]
  }];
  const statusTone = {
    'maintained': 'sage',
    'open source': 'sage',
    'research': 'blue',
    'experimental': 'amber',
    'side project': 'terra'
  };
  return /*#__PURE__*/React.createElement(window.Section, {
    id: "projects",
    num: "02",
    eyebrow: "Projects",
    title: "Things I've built",
    note: "quantum & AI \u2193"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-9)'
    }
  }, groups.map(g => /*#__PURE__*/React.createElement("div", {
    key: g.key
  }, /*#__PURE__*/React.createElement(window.Reveal, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: '16px',
      marginBottom: 'var(--space-5)'
    }
  }, /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: '40px',
      lineHeight: 1,
      margin: 0,
      color: `var(--${g.tone}-500)`
    }
  }, g.label), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      height: '10px',
      background: `var(--${g.tone}-300)`,
      WebkitMaskImage: "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='10' viewBox='0 0 80 10'%3E%3Cpath d='M0 5 Q 10 0 20 5 T 40 5 T 60 5 T 80 5' fill='none' stroke='%23000' stroke-width='1.6'/%3E%3C/svg%3E\")",
      maskImage: "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='10' viewBox='0 0 80 10'%3E%3Cpath d='M0 5 Q 10 0 20 5 T 40 5 T 60 5 T 80 5' fill='none' stroke='%23000' stroke-width='1.6'/%3E%3C/svg%3E\")",
      WebkitMaskRepeat: 'repeat-x',
      maskRepeat: 'repeat-x'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-hand)',
      fontSize: '20px',
      color: `var(--${g.tone}-500)`,
      transform: 'rotate(-2deg)',
      whiteSpace: 'nowrap'
    }
  }, g.note))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
      gap: 'var(--space-5)'
    }
  }, g.projects.map((p, i) => /*#__PURE__*/React.createElement(window.Reveal, {
    key: p.name,
    delay: i * 80
  }, /*#__PURE__*/React.createElement(NS.Card, {
    wobble: i % 3,
    tilt: i % 2 ? 1 : -1,
    style: {
      height: '100%',
      display: 'flex',
      flexDirection: 'column'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: '10px'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontWeight: 700,
      fontSize: '20px',
      color: 'var(--ink-900)'
    }
  }, p.name), /*#__PURE__*/React.createElement(NS.Badge, {
    tone: statusTone[p.status] || 'ink'
  }, p.status)), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-base)',
      lineHeight: 1.65,
      color: 'var(--ink-700)',
      margin: 'var(--space-3) 0 var(--space-4)',
      flex: 1
    }
  }, p.blurb), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: '8px',
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '6px',
      flexWrap: 'wrap'
    }
  }, p.tags.map(t => /*#__PURE__*/React.createElement(NS.Tag, {
    key: t
  }, t))), /*#__PURE__*/React.createElement("a", {
    href: "#",
    onClick: e => e.preventDefault(),
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '11px',
      letterSpacing: '0.08em',
      textTransform: 'uppercase',
      color: 'var(--blue-700)',
      textDecoration: 'none',
      display: 'inline-flex',
      alignItems: 'center',
      gap: '5px',
      whiteSpace: 'nowrap'
    }
  }, "Repo ", /*#__PURE__*/React.createElement(window.Icon, {
    name: "arrow-up-right",
    size: 13,
    color: "var(--blue-700)"
  })))))))))));
}
window.Projects = Projects;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Projects.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Publications.jsx
try { (() => {
/* Publications — filterable list. Tabs switch the year; each entry is a ruled
   paper row with venue badge, title, authors, and links. */
function Publications() {
  const papers = [{
    year: '2024',
    venue: 'Nature Physics',
    tone: 'blue',
    title: 'Real-time decoding of the surface code on a 100-qubit processor',
    authors: 'N. Patamawisut, R. Okafor, L. Demir, et al.',
    tags: ['error correction', 'decoders']
  }, {
    year: '2024',
    venue: 'PRX Quantum',
    tone: 'sage',
    title: 'Crosstalk-robust calibration for fixed-frequency transmons',
    authors: 'N. Patamawisut, J. Vyas, M. Sørensen',
    tags: ['calibration', 'crosstalk']
  }, {
    year: '2023',
    venue: 'Quantum',
    tone: 'terra',
    title: 'Benchmarking logical error rates under realistic noise',
    authors: 'L. Demir, N. Patamawisut, A. Bianchi',
    tags: ['benchmarking']
  }, {
    year: '2023',
    venue: 'npj Quantum Information',
    tone: 'blue',
    title: 'A pulse-level compiler for variational algorithms',
    authors: 'N. Patamawisut, K. Adeyemi',
    tags: ['compilers', 'control']
  }, {
    year: '2022',
    venue: 'Phys. Rev. A',
    tone: 'amber',
    title: 'Characterising leakage in superconducting qubits',
    authors: 'A. Bianchi, N. Patamawisut, R. Okafor',
    tags: ['leakage', 'tomography']
  }];
  const years = ['all', '2024', '2023', '2022'];
  const tabs = years.map(y => ({
    value: y,
    label: y === 'all' ? 'All' : y
  }));
  const [year, setYear] = React.useState('all');
  const shown = papers.filter(p => year === 'all' || p.year === year);
  return /*#__PURE__*/React.createElement(window.Section, {
    id: "publications",
    num: "03",
    eyebrow: "Publications",
    title: "Selected papers",
    note: "newest first",
    bg: "var(--paper-0)"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: '780px'
    }
  }, /*#__PURE__*/React.createElement(NS.Tabs, {
    items: tabs,
    value: year,
    onChange: setYear
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--space-6)',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-2)'
    }
  }, shown.map((p, i) => /*#__PURE__*/React.createElement(window.Reveal, {
    key: p.title,
    delay: i * 60
  }, /*#__PURE__*/React.createElement("article", {
    style: {
      display: 'grid',
      gridTemplateColumns: '88px 1fr',
      gap: 'var(--space-5)',
      alignItems: 'start',
      padding: 'var(--space-5) 0',
      borderBottom: '1px dashed var(--paper-edge)'
    },
    className: "pub-row"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '8px',
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: '34px',
      lineHeight: 1,
      color: 'var(--ink-900)'
    }
  }, p.year), /*#__PURE__*/React.createElement(NS.Badge, {
    tone: p.tone
  }, p.venue)), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-body)',
      fontWeight: 700,
      fontSize: 'var(--text-lg)',
      lineHeight: 1.4,
      margin: 0,
      color: 'var(--ink-900)'
    }
  }, p.title), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-sm)',
      color: 'var(--ink-500)',
      margin: '6px 0 12px'
    }
  }, p.authors), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '8px',
      flexWrap: 'wrap',
      alignItems: 'center'
    }
  }, p.tags.map(t => /*#__PURE__*/React.createElement(NS.Tag, {
    key: t
  }, t)), /*#__PURE__*/React.createElement("a", {
    href: "#",
    onClick: e => e.preventDefault(),
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '11px',
      letterSpacing: '0.08em',
      textTransform: 'uppercase',
      color: 'var(--blue-700)',
      textDecoration: 'none',
      display: 'inline-flex',
      alignItems: 'center',
      gap: '5px',
      marginLeft: '4px'
    }
  }, "PDF ", /*#__PURE__*/React.createElement(window.Icon, {
    name: "external-link",
    size: 13,
    color: "var(--blue-700)"
  }))))))))));
}
window.Publications = Publications;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Publications.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/Research.jsx
try { (() => {
/* Research — four interest areas as tilted paper cards with keyword tags. */
function Research() {
  const areas = [{
    icon: 'shield-check',
    tone: 'blue',
    tilt: -1.4,
    title: 'Quantum Error Correction',
    body: 'Surface codes and the real-time decoders that have to keep up with them. How low can we push the logical error rate before the wiring gives out?',
    tags: ['surface codes', 'real-time decoding', 'logical qubits']
  }, {
    icon: 'activity',
    tone: 'terra',
    tilt: 1.2,
    title: 'Superconducting Control',
    body: 'Pulse-level calibration for fixed-frequency transmons, and chasing down the crosstalk that ruins an otherwise good gate.',
    tags: ['transmons', 'pulse calibration', 'crosstalk']
  }, {
    icon: 'ruler',
    tone: 'sage',
    tilt: -0.8,
    title: 'Noise & Benchmarking',
    body: 'Honest numbers for noisy machines: randomized benchmarking, gate-set tomography, and leakage characterisation under realistic conditions.',
    tags: ['benchmarking', 'tomography', 'leakage']
  }, {
    icon: 'code',
    tone: 'amber',
    tilt: 1.6,
    title: 'Open Quantum Software',
    body: 'Most of my work ships as code. I contribute to open-source control stacks so the next person spends less time fighting the fridge.',
    tags: ['open source', 'compilers', 'control stacks']
  }];
  return /*#__PURE__*/React.createElement(window.Section, {
    id: "research",
    num: "01",
    eyebrow: "Research",
    title: "What I work on",
    note: "follow the qubits \u2193"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
      gap: 'var(--space-6)'
    }
  }, areas.map((a, i) => /*#__PURE__*/React.createElement(window.Reveal, {
    key: a.title,
    delay: i * 90
  }, /*#__PURE__*/React.createElement(NS.Card, {
    wobble: i % 3,
    tilt: a.tilt,
    style: {
      height: '100%'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 44,
      height: 44,
      flex: 'none',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      border: '2px solid var(--ink-line)',
      borderRadius: 'var(--sketch-radius-blob)',
      background: `var(--${a.tone}-100)`,
      color: `var(--${a.tone}-500)`
    }
  }, /*#__PURE__*/React.createElement(window.Icon, {
    name: a.icon,
    size: 22,
    color: `var(--${a.tone}-500)`
  })), /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: '28px',
      margin: 0,
      color: 'var(--ink-900)',
      lineHeight: 1
    }
  }, a.title)), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--text-base)',
      lineHeight: 1.7,
      color: 'var(--ink-700)',
      margin: 'var(--space-4) 0 var(--space-5)'
    }
  }, a.body), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '8px',
      flexWrap: 'wrap'
    }
  }, a.tags.map(t => /*#__PURE__*/React.createElement(NS.Tag, {
    key: t
  }, t))))))));
}
window.Research = Research;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/Research.jsx", error: String((e && e.message) || e) }); }

// ui_kits/portfolio/kit.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Shared helpers for the portfolio kit — attached to window so each section
   script can use them. Loaded before the section files. */
const NS = window.SketchbookPortfolioDesignSystem_11295f;

/* ── Icon ────────────────────────────────────────────────────────────────
   Lucide line icons (CDN), roughened by an SVG displacement filter for the
   hand-drawn feel. <Icon name="github" /> renders an <i data-lucide> that
   Lucide swaps for an <svg> after mount. */
function Icon({
  name,
  size = 20,
  stroke = 2,
  color = 'currentColor',
  style = {}
}) {
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (window.lucide && ref.current) {
      ref.current.innerHTML = '';
      const i = document.createElement('i');
      i.setAttribute('data-lucide', name);
      ref.current.appendChild(i);
      window.lucide.createIcons({
        attrs: {
          width: size,
          height: size,
          'stroke-width': stroke,
          stroke: color
        },
        nameAttr: 'data-lucide'
      });
    }
  }, [name, size, stroke, color]);
  return /*#__PURE__*/React.createElement("span", {
    ref: ref,
    className: "rough",
    style: {
      display: 'inline-flex',
      lineHeight: 0,
      ...style
    }
  });
}

/* ── Reveal ──────────────────────────────────────────────────────────────
   Plays a one-shot "sketch in" CSS animation on mount that ALWAYS ends
   visible — so content can never get stuck at opacity:0 if an observer or the
   preview viewport misbehaves. Honours reduced-motion. */
function ensureRevealCSS() {
  if (typeof document === 'undefined' || document.getElementById('sk-reveal-css')) return;
  const el = document.createElement('style');
  el.id = 'sk-reveal-css';
  el.textContent = `
    @keyframes sk-reveal { from { transform: translateY(18px) rotate(-0.4deg); }
                           to   { transform: none; } }
    .sk-reveal { opacity: 1; animation: sk-reveal 0.6s var(--ease-hand) both; }
    @media (prefers-reduced-motion: reduce) { .sk-reveal { animation: none; } }
  `;
  document.head.appendChild(el);
}
function Reveal({
  children,
  delay = 0,
  as = 'div',
  style = {},
  ...rest
}) {
  React.useEffect(ensureRevealCSS, []);
  const Comp = as;
  return /*#__PURE__*/React.createElement(Comp, _extends({
    className: "sk-reveal",
    style: {
      animationDelay: `${delay}ms`,
      ...style
    }
  }, rest), children);
}

/* ── Section ─────────────────────────────────────────────────────────────
   Standard section frame: numbered eyebrow + handwritten heading + body. */
function Section({
  id,
  num,
  eyebrow,
  title,
  note,
  children,
  bg
}) {
  return /*#__PURE__*/React.createElement("section", {
    id: id,
    "data-screen-label": eyebrow,
    style: {
      background: bg || 'transparent',
      padding: 'var(--section-gap) var(--gutter)',
      borderTop: '2px solid var(--paper-edge)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--content)',
      margin: '0 auto'
    }
  }, /*#__PURE__*/React.createElement(Reveal, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: '14px',
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-label)',
      fontSize: '13px',
      letterSpacing: '0.16em',
      textTransform: 'uppercase',
      color: 'var(--pencil-500)'
    }
  }, num, " \u2014 ", eyebrow), note && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-hand)',
      fontSize: '20px',
      color: 'var(--blue-500)',
      transform: 'rotate(-2deg)'
    }
  }, note)), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: 'clamp(40px, 6vw, 60px)',
      lineHeight: 1,
      margin: '8px 0 0',
      color: 'var(--ink-900)'
    }
  }, title)), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--space-7)'
    }
  }, children)));
}
Object.assign(window, {
  NS,
  Icon,
  Reveal,
  Section
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/portfolio/kit.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Avatar = __ds_scope.Avatar;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Divider = __ds_scope.Divider;

__ds_ns.Tag = __ds_scope.Tag;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Textarea = __ds_scope.Textarea;

__ds_ns.Tabs = __ds_scope.Tabs;

})();
