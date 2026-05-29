// --- CLAUDE RTL PATCH START ---
/*
 *  Claude Desktop - RTL Engine (shared: Windows + macOS)
 *  =====================================================================
 *  Original, STRICTLY-ASCII renderer payload. Contains NO non-ASCII bytes and
 *  NO regex Unicode ranges - RTL detection uses numeric charCodeAt comparisons
 *  (0x.... hex), so no installer text-encoding can ever corrupt it. Prepended
 *  into Claude's bundled renderer JS by the platform installer.
 *
 *  Why this is better than prior art (shraga100 / toboly / soguy):
 *   - They flip a block to RTL if it contains ANY rtl char ("rtl-dominant"),
 *     which wrongly flips English paragraphs that contain one Arabic word.
 *     We use the browser's NATIVE first-strong algorithm via dir="auto" +
 *     unicode-bidi:plaintext, which is correct for mixed AR/EN content.
 *   - CSS does the heavy lifting (re-render resilient); JS only stamps
 *     dir="auto" on streamed nodes + the composer, and isolates code as LTR.
 *   - Adds a real ON/OFF toggle (Ctrl+Alt+R) with persistence + a console API.
 *   - CSP-resilient style injection (adoptedStyleSheets, dir attribute).
 *
 *  (c) 2026 - MIT. Works for any RTL script (Arabic, Hebrew, ...) AND English.
 */
(function () {
  'use strict';
  if (typeof document === 'undefined') return;        // skip non-DOM (preload) contexts
  if (window.__claudeRtlLoaded) return;               // idempotent
  window.__claudeRtlLoaded = true;

  var KEY  = 'claude-rtl-enabled';
  var MARK = 'data-claude-rtl';

  // Text blocks whose direction should follow their own content.
  var BLOCKS = 'p,li,ul,ol,h1,h2,h3,h4,h5,h6,blockquote,td,th,dd,dt,summary,figcaption,caption';
  // Elements that must always stay left-to-right (code only - NOT data tables).
  var LTR = 'pre,code,kbd,samp,.katex,.katex-display,[class*="code-block"],[class*="codeBlock"]';

  // RTL detection via numeric code points (ASCII source only). Covers Hebrew,
  // Arabic, Syriac, Arabic Supplement, Thaana, NKo, Arabic Extended-A, and the
  // Arabic Presentation Forms-A/-B. Used only for the composer hint.
  function hasRTL(s) {
    if (!s) return false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if ((c >= 0x0590 && c <= 0x05FF) || (c >= 0x0600 && c <= 0x06FF) ||
          (c >= 0x0700 && c <= 0x074F) || (c >= 0x0750 && c <= 0x077F) ||
          (c >= 0x0780 && c <= 0x07BF) || (c >= 0x07C0 && c <= 0x07FF) ||
          (c >= 0x08A0 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) ||
          (c >= 0xFE70 && c <= 0xFEFF)) return true;
    }
    return false;
  }

  var CSS =
    '/* Each block resolves its own direction from its first strong char. */\n' +
    '[' + MARK + '="auto"]{unicode-bidi:plaintext;text-align:start}\n' +
    '/* Code / tables / math stay LTR and isolated. */\n' +
    LTR + '{unicode-bidi:isolate !important;direction:ltr !important;text-align:left}\n' +
    '/* Mirror list bullets / padding for RTL blocks. */\n' +
    '[dir="rtl"]{text-align:start}\n' +
    '[dir="rtl"] ul,[dir="rtl"] ol{padding-right:1.5em;padding-left:0}\n' +
    '/* Cleaner Arabic typography. */\n' +
    '[dir="rtl"]{font-family:"IBM Plex Sans Arabic","Noto Naskh Arabic","Segoe UI",system-ui,sans-serif;line-height:1.9}\n';

  var sheet = null, styleEl = null, observer = null;

  function addStyles() {
    try {                                             // CSP-safe: constructable stylesheet
      sheet = new CSSStyleSheet();
      sheet.replaceSync(CSS);
      document.adoptedStyleSheets = document.adoptedStyleSheets.concat(sheet);
      return;
    } catch (e) { /* fall back */ }
    styleEl = document.createElement('style');
    styleEl.textContent = CSS;
    (document.head || document.documentElement).appendChild(styleEl);
  }
  function removeStyles() {
    if (sheet) { document.adoptedStyleSheets = document.adoptedStyleSheets.filter(function (s) { return s !== sheet; }); sheet = null; }
    if (styleEl) { styleEl.remove(); styleEl = null; }
  }

  // Stamp one text block so the browser auto-resolves its direction.
  function tag(el) {
    if (!el || el.nodeType !== 1 || el.hasAttribute(MARK)) return;
    if (el.closest && el.closest(LTR)) return;        // never touch code
    el.setAttribute(MARK, 'auto');
    el.setAttribute('dir', 'auto');                   // native first-strong; CSP-safe attribute
  }
  // Stamp a TABLE: dir="auto" makes RTL content reverse the COLUMN order
  // (the first column moves to the right) - not just the text inside cells.
  function tagTable(el) {
    if (!el || el.nodeType !== 1 || el.hasAttribute(MARK)) return;
    el.setAttribute(MARK, 'table');
    el.setAttribute('dir', 'auto');
  }
  function tagTree(root) {
    if (!root || root.nodeType !== 1) return;
    if (root.matches) {
      if (root.matches(BLOCKS)) tag(root);
      if (root.matches('table')) tagTable(root);
    }
    if (root.querySelectorAll) {
      var b = root.querySelectorAll(BLOCKS), i;
      for (i = 0; i < b.length; i++) tag(b[i]);
      var t = root.querySelectorAll('table'), j;
      for (j = 0; j < t.length; j++) tagTable(t[j]);
    }
  }

  // The composer (textarea or contenteditable) also follows its content.
  function tagComposer() {
    var c = document.querySelectorAll('textarea,[contenteditable="true"],[data-testid="chat-input"]'), i;
    for (i = 0; i < c.length; i++) if (!c[i].hasAttribute('dir')) c[i].setAttribute('dir', 'auto');
  }

  var scheduled = false, queue = [];
  function flush() {
    scheduled = false;
    var batch = queue; queue = [];
    if (batch.length > 40) { tagTree(document.body); tagComposer(); return; }  // bulk fallback
    for (var i = 0; i < batch.length; i++) tagTree(batch[i]);
    tagComposer();
  }
  function onMutations(muts) {
    for (var i = 0; i < muts.length; i++) {
      var m = muts[i], j;
      for (j = 0; j < m.addedNodes.length; j++) if (m.addedNodes[j].nodeType === 1) queue.push(m.addedNodes[j]);
      if (m.type === 'characterData' && m.target.parentElement) queue.push(m.target.parentElement);
    }
    if (!scheduled && queue.length) { scheduled = true; setTimeout(flush, 50); } // throttle for streaming
  }

  function enable() {
    if (observer) return;
    addStyles();
    observer = new MutationObserver(onMutations);
    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    tagTree(document.body);
    tagComposer();
    console.log('[Claude RTL] on');
  }
  function disable() {
    if (observer) { observer.disconnect(); observer = null; }
    removeStyles();
    var n = document.querySelectorAll('[' + MARK + ']'), i;
    for (i = 0; i < n.length; i++) { n[i].removeAttribute(MARK); n[i].removeAttribute('dir'); }
    console.log('[Claude RTL] off');
  }
  function toggle() {
    var on = !!observer;
    try { localStorage.setItem(KEY, on ? 'false' : 'true'); } catch (e) {}
    if (on) disable(); else enable();
  }

  // Console API + keyboard toggle (Ctrl+Alt+R).
  window.__claudeRTL = { enable: enable, disable: disable, toggle: toggle, hasRTL: hasRTL,
    get on() { return !!observer; } };
  window.addEventListener('keydown', function (e) {
    if (e.ctrlKey && e.altKey && (e.key === 'r' || e.key === 'R')) { e.preventDefault(); toggle(); }
  }, true);

  function start() {
    var pref = null;
    try { pref = localStorage.getItem(KEY); } catch (e) {}
    if (pref !== 'false') enable();                   // default ON
  }
  if (document.body) start();
  else window.addEventListener('DOMContentLoaded', start, { once: true });
})();
// --- CLAUDE RTL PATCH END ---
