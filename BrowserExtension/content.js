(() => {
  const extensionAPI = globalThis.browser ?? chrome;
  if (globalThis.__textwarden) { globalThis.__textwarden(); return; }
  globalThis.__textwarden = () => { requestPolicy(); void checkConnection(true); };
  // Extension updates replace the isolated world but can leave its old DOM behind.
  document.querySelectorAll("textwarden-overlay").forEach(overlay => overlay.remove());
  let port, pausedSession;
  const policySession = crypto.randomUUID();
  let policyURL = location.origin + location.pathname;
  let applyingReplacement = false, hoverSuppressed = false, rewriting = false;
  const host = document.createElement("textwarden-overlay");
  host.style.cssText = "position:fixed;inset:0;z-index:2147483647;pointer-events:none";
  const shadow = host.attachShadow({ mode: "closed" });
  let enabled = false, pageUnderlines = true, pendingTool, lastPageState, reconnectNeeded = false;
  let field, session, revision = 0, checkedText = "", issues = [], timer, composing = false, frame, editFailure;
  let showUnderlines = true, underlineThickness = 2, checkingEnabled = true;
  let presentation = { width: 36, sectionHeight: 36, cornerRadius: 12, hoverEnabled: true, hoverDelay: 0, styleEnabled: true, alwaysShow: true, grammarColor: "orange" };
  let hoverTimer, hoveredIssue, drag, position, suppressClick = false, wordTargets = [];
  const style = document.createElement("style");
  style.textContent = `:host {color-scheme:light dark;--bg:rgba(250,250,252,.96);--text:#242426;--muted:#6d6d72;--line:#0002;--hover:#0000000c;font:13px -apple-system,BlinkMacSystemFont,system-ui,sans-serif}
    @media(prefers-color-scheme:dark){:host{--bg:rgba(40,40,42,.96);--text:#f5f5f7;--muted:#aaaab0;--line:#fff3;--hover:#ffffff12}}
    :host([data-theme=Light]){color-scheme:light;--bg:rgba(250,250,252,.96);--text:#242426;--muted:#6d6d72;--line:#0002;--hover:#0000000c}
    :host([data-theme=Dark]){color-scheme:dark;--bg:rgba(40,40,42,.96);--text:#f5f5f7;--muted:#aaaab0;--line:#fff3;--hover:#ffffff12}
    *{box-sizing:border-box}button{font:inherit;cursor:pointer;color:inherit}button:disabled{opacity:.4;cursor:default}button:focus-visible{outline:3px solid #0a84ff;outline-offset:2px}button:hover:enabled{background:var(--hover)}[hidden]{display:none!important}
    .mark{position:fixed;border:0;border-bottom:2px solid #ff9500;background:transparent;padding:0;pointer-events:auto;cursor:pointer}
    .word-highlight{position:fixed;pointer-events:none}
    .toolbar,.menu{position:fixed;background:var(--bg);color:var(--text);border:1px solid var(--line);box-shadow:0 3px 12px #0003,inset 0 1px 0 #ffffff18;backdrop-filter:blur(18px);pointer-events:auto}
    /* Native pill geometry; browser-only color preview pending approval. */
    .toolbar{--pill-base:#ebeff5;--pill-highlight:#f9fbfe;--pill-border:#00000026;--pill-divider:#0000001a;--pill-hover:8%;--pill-shadow:#00000026;--red:#b82432;--orange:#925300;--green:#18743c;--blue:#0061c9;--purple:#8739c5;--grammar:var(--orange);width:var(--pill-width,36px);height:calc(var(--pill-section,36px)*3);border:2px solid transparent;border-radius:calc(var(--pill-radius,12px) + 2px);background:linear-gradient(to bottom,var(--pill-highlight),var(--pill-base));background-clip:padding-box;box-shadow:inset 0 0 0 1px var(--pill-border),0 2px 3px var(--pill-shadow);backdrop-filter:none;overflow:hidden;padding:0;touch-action:none;user-select:none;transition:width .2s ease,height .2s ease,transform .15s ease}
    @media(prefers-color-scheme:dark){.toolbar{--pill-base:#1e1f21;--pill-highlight:#2f3133;--pill-border:#ffffff2b;--pill-divider:#ffffff1f;--pill-hover:8%;--pill-shadow:#00000059;--red:#ff787b;--orange:#ffad33;--green:#42ce75;--blue:#52acff;--purple:#c68bff}}
    :host([data-theme=Light]) .toolbar{--pill-base:#ebeff5;--pill-highlight:#f9fbfe;--pill-border:#00000026;--pill-divider:#0000001a;--pill-hover:8%;--pill-shadow:#00000026;--red:#b82432;--orange:#925300;--green:#18743c;--blue:#0061c9;--purple:#8739c5}
    :host([data-theme=Dark]) .toolbar{--pill-base:#1e1f21;--pill-highlight:#2f3133;--pill-border:#ffffff2b;--pill-divider:#ffffff1f;--pill-hover:8%;--pill-shadow:#00000059;--red:#ff787b;--orange:#ffad33;--green:#42ce75;--blue:#52acff;--purple:#c68bff}
    .toolbar.horizontal{width:calc(var(--pill-section,36px)*3);height:var(--pill-width,36px)}.toolbar.dragging{transform:scale(1.14);cursor:grabbing;opacity:.85}.toolbar.single{border-radius:50%;width:var(--pill-width,36px);height:var(--pill-width,36px);box-shadow:inset 0 0 0 2.5px var(--grammar),0 2px 3px var(--pill-shadow)}.toolbar.single:hover{box-shadow:inset 0 0 0 3px var(--grammar),0 2px 3px var(--pill-shadow)}.toolbar.snapping{transition:left .18s ease-out,top .18s ease-out,width .2s ease,height .2s ease,transform .15s ease}
    .toolbar button{position:absolute;top:-2px;left:0;display:flex;align-items:center;justify-content:center;width:calc(var(--pill-width,36px) - 4px);height:var(--pill-section,36px);border:0;border-radius:0;background:none;padding:0;transition:transform .2s ease}
    .toolbar button:hover{background:color-mix(in srgb,currentColor var(--pill-hover),transparent)}.toolbar button:focus-visible{outline-offset:-4px}.toolbar .grammar:disabled{opacity:1}
    .toolbar button:nth-child(2){transform:translateY(var(--pill-section,36px))}.toolbar button:nth-child(3){transform:translateY(calc(var(--pill-section,36px)*2))}
    .toolbar.horizontal button{top:0;left:-2px;width:var(--pill-section,36px);height:calc(var(--pill-width,36px) - 4px)}
    .toolbar.horizontal button:nth-child(2){transform:translateX(var(--pill-section,36px))}.toolbar.horizontal button:nth-child(3){transform:translateX(calc(var(--pill-section,36px)*2))}
    .toolbar button+button:before{content:"";position:absolute;left:6px;right:6px;top:0;border-top:.5px solid var(--pill-divider)}.toolbar.horizontal button+button:before{left:0;right:auto;top:6px;bottom:6px;border-top:0;border-left:.5px solid var(--pill-divider)}
    /* Matches BorderGuideWindow's inward-fading 100pt placement band. */
    .placement-guide{position:fixed;inset:0;border-radius:12px;pointer-events:none;--guide:#b8bbc285;background:linear-gradient(to right,var(--guide),transparent 100px),linear-gradient(to left,var(--guide),transparent 100px),linear-gradient(to bottom,var(--guide),transparent 100px),linear-gradient(to top,var(--guide),transparent 100px)}
    @media(prefers-color-scheme:dark){.placement-guide{--guide:#73716f99}}
    :host([data-theme=Light]) .placement-guide{--guide:#b8bbc285}:host([data-theme=Dark]) .placement-guide{--guide:#73716f99}
    @media(prefers-reduced-motion:reduce){.toolbar,.toolbar button,.toolbar.snapping{transition:none}.spinner{animation:none}}
    .toolbar .grammar{font-size:12px;font-weight:700;color:var(--grammar)}.toolbar .grammar.many{font-size:10px}.style{color:var(--purple)}.compose{color:var(--blue)}
    .toolbar .style{font-size:12px;font-weight:700}.toolbar .style.success{color:var(--green)}.toolbar .style:hover{background:color-mix(in srgb,var(--purple) var(--pill-hover),transparent)}
    .spinner{width:14px;height:14px;border:2px solid color-mix(in srgb,var(--purple) 20%,transparent);border-top-color:var(--purple);border-radius:50%;animation:working 1s linear infinite}@keyframes working{to{transform:rotate(360deg)}}
    svg{width:14px;height:14px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
    .menu{width:252px;max-width:calc(100vw - 16px);padding:6px;border-radius:12px;max-height:calc(100vh - 16px);overflow:auto}.menu header{font-weight:600;padding:7px 8px 3px}.status{font-size:12px;color:var(--muted);line-height:1.45;padding:0 8px 8px;overflow-wrap:anywhere}
    @media(prefers-reduced-transparency:reduce){.toolbar,.menu{backdrop-filter:none;background:Canvas}}
    @media(prefers-contrast:more){:host{--line:GrayText}.toolbar,.menu{border-width:2px}}`;
  const marks = document.createElement("div");
  const guide = document.createElement("div"); guide.className = "placement-guide"; guide.hidden = true; guide.setAttribute("aria-hidden", "true");
  const toolbar = document.createElement("div"), menu = document.createElement("div"), status = document.createElement("div");
  toolbar.className = "toolbar"; toolbar.hidden = true;
  toolbar.setAttribute("role", "group"); toolbar.setAttribute("aria-label", "TextWarden writing tools");
  menu.className = "menu"; menu.hidden = true; menu.setAttribute("aria-label", "TextWarden page options");
  const heading = document.createElement("header"); heading.textContent = "TextWarden";
  status.className = "status"; status.setAttribute("role", "status");
  menu.append(heading, status);
  const icons = {
    compose: 'M12 5H5v14h14v-7M12 12l1-4 7-7 3 3-7 7-4 1ZM18 3l3 3',
    rewrite: 'm12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5ZM20 2v4M18 4h4',
  };
  function createIcon(path) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("aria-hidden", "true");
    const shape = document.createElementNS(svg.namespaceURI, "path"); shape.setAttribute("d", path);
    svg.append(shape); return svg;
  }
  const spinner = document.createElement("span"); spinner.className = "spinner"; spinner.setAttribute("aria-hidden", "true");
  function button(parent, title, action, icon, className = "") {
    const element = document.createElement("button"); element.type = "button";
    element.className = className; element.title = title; element.setAttribute("aria-label", title);
    if (icon) element.append(createIcon(icon));
    else element.textContent = title;
    element.addEventListener("mousedown", (event) => event.preventDefault());
    element.addEventListener("click", action); parent.append(element); return element;
  }
  function grammar() { if (issues.length) send("show", { errorID: issues[0].id, action: "indicator" }); }
  const suggestions = button(toolbar, "Suggestions", grammar, null, "grammar");
  const toolButtons = [];
  for (const [title, kind] of [["Style & Clarity", "style"], ["AI Compose", "compose"]]) {
    toolButtons.push([button(toolbar, title, () => kind === "style" ? send("show", { action: "style" }) : requestTool(kind), icons[kind === "style" ? "rewrite" : kind], kind), kind]);
  }
  toolbar.title = "Drag to reposition · Right-click for TextWarden options";
  toolbar.addEventListener("click", (event) => {
    if (suppressClick) { suppressClick = false; event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  toolbar.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    // Keep Safari’s editor focus while pressing or dragging any part of the pill.
    event.preventDefault();
    if (field && eligible(field) === field) field.focus({ preventScroll: true });
    const rect = toolbar.getBoundingClientRect();
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY, left: rect.left, top: rect.top, moved: false };
    suppressClick = false; toolbar.classList.remove("snapping");
  });
  window.addEventListener("pointermove", (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
    if (!drag.moved && Math.hypot(dx, dy) < 4) return;
    drag.moved = true; guide.hidden = false;
    const x = event.clientX / innerWidth, y = event.clientY / innerHeight;
    toolbar.classList.toggle("horizontal", x >= .15 && x <= .85 && (y < .12 || y > .88));
    clearTimeout(hoverTimer); send("hoverEnd"); menu.hidden = true;
    toolbar.setPointerCapture(event.pointerId); toolbar.classList.add("dragging");
    toolbar.style.left = `${Math.max(0, Math.min(innerWidth - toolbar.offsetWidth, drag.left + dx))}px`;
    toolbar.style.top = `${Math.max(0, Math.min(innerHeight - toolbar.offsetHeight, drag.top + dy))}px`;
  });
  function finishDrag(event) {
    if (!drag || event.pointerId !== drag.id) return;
    if (drag.moved) {
      const rect = toolbar.getBoundingClientRect();
      const x = rect.left + rect.width / 2, y = rect.top + rect.height / 2;
      const edge = Object.entries({ left: x, right: innerWidth - x, top: y, bottom: innerHeight - y }).sort((a,b) => a[1] - b[1])[0][0];
      position = { edge, fraction: ["top", "bottom"].includes(edge) ? x / innerWidth : y / innerHeight };
      suppressClick = true;
      // Safari can omit the post-drag click; never swallow the next real click.
      setTimeout(() => { suppressClick = false; }, 0);
    }
    if (toolbar.hasPointerCapture(event.pointerId)) toolbar.releasePointerCapture(event.pointerId);
    drag = null; guide.hidden = true; toolbar.classList.remove("dragging"); toolbar.classList.add("snapping"); scheduleRender();
  }
  window.addEventListener("pointerup", finishDrag); window.addEventListener("pointercancel", finishDrag);
  shadow.append(style, guide, marks, toolbar, menu);
  document.documentElement.append(host);

  async function openMenu() {
    clearTimeout(hoverTimer); send("hoverEnd"); menu.hidden = true;
    try {
      const result = await extensionAPI.runtime.sendMessage({ target: "textwarden-background", action: "menu" });
      if (result?.error) throw new Error(result.error);
    } catch { status.textContent = "Reload this page, then open TextWarden from your browser’s toolbar."; menu.hidden = false; scheduleRender(); }
  }
  function startHover(issue, fromIndicator = false) {
    if (!presentation.hoverEnabled || drag?.moved || hoverSuppressed) return;
    const target = `${fromIndicator === "style" ? "style" : fromIndicator ? "indicator" : "underline"}:${issue.id}`;
    if (hoveredIssue === target) { send("hoverKeep"); return; }
    clearTimeout(hoverTimer); hoveredIssue = target;
    highlightWord(fromIndicator ? null : issue.id);
    const expectedSession = session, expectedRevision = revision;
    hoverTimer = setTimeout(() => {
      if (session === expectedSession && revision === expectedRevision && hoveredIssue === target && !drag?.moved) send("show", fromIndicator === "style" ? { action: "styleHover" } : { errorID: issue.id, action: fromIndicator ? "indicatorHover" : "hover" });
    }, presentation.hoverDelay);
  }
  function endHover() { clearTimeout(hoverTimer); hoveredIssue = null; highlightWord(null); send("hoverEnd"); }
  suggestions.addEventListener("pointerenter", () => { if (issues[0]) startHover(issues[0], true); });
  suggestions.addEventListener("pointermove", () => { if (issues[0]) startHover(issues[0], true); });
  suggestions.addEventListener("pointerleave", endHover);
  const styleButton = toolButtons.find(([, kind]) => kind === "style")[0];
  styleButton.addEventListener("pointerenter", () => startHover({ id: "style" }, "style"));
  styleButton.addEventListener("pointermove", () => startHover({ id: "style" }, "style"));
  styleButton.addEventListener("pointerleave", endHover);
  function updateUI() {
    toolbar.hidden = !enabled || !field || reconnectNeeded || (!issues.length && !presentation.alwaysShow && !presentation.styleEnabled);
    suggestions.disabled = !issues.length; suggestions.textContent = !checkingEnabled ? "Ⅱ" : issues.length ? (issues.length > 9 ? "9+" : String(issues.length)) : "✓";
    suggestions.title = status.textContent || "Suggestions";
    suggestions.setAttribute("aria-label", issues.length ? `${issues.length} grammar ${issues.length === 1 ? "suggestion" : "suggestions"}` : checkingEnabled ? "No grammar suggestions" : "Checking is paused");
    for (const [item] of toolButtons) item.disabled = !field || !checkingEnabled;
    for (const [item, kind] of toolButtons) { item.hidden = !presentation.styleEnabled; item.classList.toggle("working", kind === "style" && presentation.styleLoading); }
    const count = presentation.styleCount;
    styleButton.replaceChildren(presentation.styleLoading ? spinner : count == null ? createIcon(icons.rewrite) : count === 0 ? "✓" : count > 9 ? "9+" : String(count));
    styleButton.classList.toggle("success", count === 0);
    styleButton.title = presentation.styleLoading ? "Checking Style & Clarity…" : count == null ? "Style & Clarity" : count === 0 ? "No style suggestions" : `${count} style ${count === 1 ? "suggestion" : "suggestions"}`;
    styleButton.setAttribute("aria-label", styleButton.title);
    toolbar.classList.toggle("single", !presentation.styleEnabled);
    host.style.setProperty("--pill-width", `${presentation.width}px`);
    host.style.setProperty("--pill-section", `${presentation.sectionHeight}px`);
    host.style.setProperty("--pill-radius", `${presentation.cornerRadius}px`);
    suggestions.classList.toggle("many", issues.length > 9);
    toolbar.style.setProperty("--grammar", ({ red: "var(--red)", orange: "var(--orange)", green: "var(--green)", blue: "var(--blue)" })[presentation.grammarColor] || "var(--orange)");
    const state = pageState();
    if (JSON.stringify(state) !== JSON.stringify(lastPageState)) {
      const enabledChanged = state.enabled !== lastPageState?.enabled;
      lastPageState = state;
      try { extensionAPI.runtime.sendMessage({ target: "textwarden-popup", page: state, enabledChanged }).catch(() => {}); }
      catch { status.textContent = "TextWarden was updated. Reload this page to reconnect."; }
    }
  }
  function requestPolicy() {
    const current = location.origin + location.pathname;
    if (policyURL !== current) { release(); pauseOwnership("release"); pausedSession = null; policyURL = current; host.hidden = true; }
    try {
      if (!port) connect();
      port.postMessage({ version: 1, kind: "pageStatus", session: policySession, revision: 0 });
    } catch { host.hidden = true; }
  }
  function highlightWord(id) {
    for (const target of wordTargets) target.highlight.hidden = target.issue.id !== id;
  }
  function hoverWord(event) {
    if (event.composedPath().includes(host)) return;
    // Observe the word's bounds without covering text with a click/selection interceptor.
    const target = enabled && checkingEnabled && showUnderlines && pageUnderlines && !frame
      && !event.buttons && field && eligible(field) === field && event.composedPath().includes(field)
      ? wordTargets.filter(({ issue, rect }) => issues.includes(issue)
        && event.clientX >= rect.left && event.clientX <= rect.right
        && event.clientY >= rect.top && event.clientY <= rect.bottom)
        .sort((a, b) => (a.issue.end - a.issue.start) - (b.issue.end - b.issue.start))[0] : null;
    if (target) startHover(target.issue);
    else if (hoveredIssue?.startsWith("underline:")) endHover();
  }
  window.addEventListener("pointermove", (event) => {
    if (event.isTrusted && (event.movementX || event.movementY)) hoverSuppressed = false;
    hoverWord(event);
  }, { passive: true, capture: true });
  function pageState() {
    const selection = selectionRange();
    return { enabled, pageUnderlines, hasEditor: Boolean(field?.isConnected), hasSelection: Boolean(selection && selection.end > selection.start), issueCount: issues.length, status: status.textContent };
  }
  function pauseOwnership(kind = "pausePage") {
    if (!pausedSession) return;
    try {
      if (!port) connect();
      port.postMessage({ version: 1, kind, session: pausedSession, revision: 0 });
    } catch {}
  }
  function setEnabled(value) {
    enabled = value; pendingTool = null; composing = false;
    if (enabled) {
      pauseOwnership("release"); pausedSession = null;
      host.hidden = false; if (!port) connect(); focus(document.activeElement);
    } else {
      release(); pausedSession ??= crypto.randomUUID(); pauseOwnership();
      host.hidden = true; menu.hidden = true;
    }
    updateUI(); scheduleRender();
  }
  function runPendingTool() {
    if (!pendingTool) return;
    const action = pendingTool; pendingTool = null;
    // Safari may keep document focus false after closing its toolbar popup.
    // This explicit action still passes editor and native foreground checks.
    if (!enabled || document.hidden) return;
    menu.hidden = true;
    if (action === "grammar") grammar(); else requestTool(action);
  }
  extensionAPI.runtime.onMessage.addListener((message, sender, respond) => {
    if (sender.id !== extensionAPI.runtime.id || sender.tab || message.target !== "textwarden-page") return;
    switch (message.action) {
      case "underlines": if (typeof message.value === "boolean") { pageUnderlines = message.value; updateUI(); scheduleRender(); } break;
      case "tool":
        if (!enabled || !field?.isConnected || !["grammar", "compose", "rewrite", "readability"].includes(message.tool)) { respond({ queued: false }); return; }
        pendingTool = message.tool; respond({ queued: true }); runPendingTool(); return;
      case "status": break;
      default: return;
    }
    respond(pageState());
  });
  const observer = new MutationObserver(() => { if (!applyingReplacement) changed(); });
  const resizeObserver = new ResizeObserver(() => scheduleRender());
  const sensitiveFields = new WeakSet(document.querySelectorAll('input[type="password"]'));
  function rememberPasswords(records) {
    for (const record of records) {
      if (record.attributeName === "type" && (record.oldValue?.toLowerCase() === "password" || record.target.type === "password")) sensitiveFields.add(record.target);
    }
  }
  const privacyObserver = new MutationObserver(records => {
    rememberPasswords(records);
    if (field && eligible(field) !== field) release();
  });
  privacyObserver.observe(document.documentElement, { subtree: true, attributes: true, attributeOldValue: true,
    attributeFilter: ["type", "autocomplete", "name", "id", "aria-label", "placeholder", "inputmode", "spellcheck", "data-private", "data-sensitive", "aria-labelledby"] });

  function sensitive(element) {
    rememberPasswords(privacyObserver.takeRecords());
    if (sensitiveFields.has(element)) return true;
    if (element.closest('[data-private],[data-sensitive],[spellcheck="false"]')) return true;
    const autocomplete = (element.getAttribute("autocomplete") || "").toLowerCase().split(/\s+/);
    if (autocomplete.some(token => /^(current-password|new-password|one-time-code|webauthn|cc-.+)$/.test(token))) return true;
    const labels = [...["name", "id", "aria-label", "placeholder"].map(name => element.getAttribute(name) || ""),
      ...Array.from(element.labels || [], label => label.textContent),
      ...(element.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean).map(id => document.getElementById(id)?.textContent || "")].join(" ")
      .replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase();
    if (/(?:^|[^a-z])(?:password|passwd|passphrase|passcode|otp|totp|2fa|mfa|pin|code|token|cvv|cvc|secret|ssn|iban)(?:$|[^a-z])|(?:verification|one[\s_-]*time|security|authentication|auth|backup|recovery)[\s_-]*code|(?:api|private)[\s_-]*key|(?:access|auth|bearer|refresh)[\s_-]*token|(?:seed|recovery)[\s_-]*phrase|(?:credit|debit)[\s_-]*card|card[\s_-]*number|social[\s_-]*security/.test(labels)) return true;
    if (element instanceof HTMLInputElement && ["numeric", "decimal"].includes(element.inputMode)) return true;
    // Login and verification forms are not writing surfaces, including revealed passwords.
    return Boolean(element.closest("form")?.querySelector('input[type="password"],input[autocomplete="current-password"],input[autocomplete="new-password"],input[autocomplete="one-time-code"]'));
  }

  function eligible(element) {
    if (!(element instanceof HTMLElement) || element.closest("[readonly],[disabled],[contenteditable=false]")) return null;
    if (sensitive(element)) return null;
    if (element instanceof HTMLTextAreaElement) return element;
    if (element instanceof HTMLInputElement) return element.type === "text" && element.spellcheck ? element : null;
    if (!element.isContentEditable) return null;
    let root = element;
    while (root.parentElement?.isContentEditable) root = root.parentElement;
    // These editors own their document state; add validated adapters before writing to them.
    if (root.closest(".ProseMirror,.ql-editor,.cm-content,[data-lexical-editor],[data-slate-editor],.public-DraftEditor-content,.ck-editor__editable")) return null;
    // Reject the entire rich editor rather than extracting around a protected subtree.
    if (sensitive(root) || Array.from(root.querySelectorAll("input,textarea,[autocomplete],[data-private],[data-sensitive],[spellcheck='false']")).some(child => sensitive(child) || child.type === "password")) return null;
    return root;
  }

  function extract(element = field) {
    if (!element || eligible(element) !== element) return { text: "", nodes: [] };
    if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) return { text: element.value, nodes: [] };
    const nodes = [];
    let text = "";
    function walk(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        nodes.push({ node, start: text.length, end: text.length + node.data.length });
        // Chrome preserves boundary spacing with NBSP during rich-text edits; offsets stay UTF-16 aligned.
        text += node.data.replace(/\u00a0/g, " ");
      } else if (node instanceof HTMLElement) {
        if (node !== element && (node.contentEditable === "false" || node.hidden)) return;
        if (node.tagName === "BR") { text += "\n"; return; }
        const block = node !== element && ["block", "list-item"].includes(getComputedStyle(node).display);
        if (block && text && !text.endsWith("\n")) text += "\n";
        node.childNodes.forEach(walk);
        if (block && text && !text.endsWith("\n")) text += "\n";
      }
    }
    walk(element);
    if (!nodes.length && text === "\n") text = ""; // A lone BR is Chrome's empty-editor placeholder.
    return { text, nodes };
  }

  function indicatorGeometry() {
    if (toolbar.hidden || !innerWidth || !innerHeight) return;
    const rect = toolbar.getBoundingClientRect();
    return { x: rect.left / innerWidth, y: rect.top / innerHeight, width: rect.width / innerWidth,
      height: rect.height / innerHeight, edge: position?.edge ?? "right" };
  }

  function send(kind, extra = {}) {
    if (!session) return;
    if (field && eligible(field) !== field && !["release", "hoverEnd"].includes(kind)) return;
    if (!port && kind === "release") return;
    try {
      if (!port) connect();
      const indicator = ["compose", "readability"].includes(kind) || kind === "show" && ["indicator", "indicatorHover", "style", "styleHover"].includes(extra.action) ? indicatorGeometry() : undefined;
      port.postMessage({ version: 1, kind, session, revision, ...extra, ...(indicator ? { indicator } : {}) });
    } catch { status.textContent = "TextWarden was updated. Reload this page to reconnect."; }
  }

  function connectionLost(detail) {
    reconnectNeeded = true; checkingEnabled = false; issues = []; pendingTool = null; rewriting = false;
    clearTimeout(hoverTimer); hoveredIssue = null;
    presentation.styleLoading = false; presentation.styleCount = null;
    marks.replaceChildren(); status.textContent = detail; updateUI();
  }
  let healthPending = false;
  async function checkConnection(userInitiated = false) {
    // Native popovers take focus while this editor stays visible. Keep their reply channel alive.
    if (healthPending || document.hidden || (!userInitiated && (!enabled || !field || eligible(field) !== field))) return;
    healthPending = true;
    const connection = port;
    let deadline;
    try {
      const health = await Promise.race([
        extensionAPI.runtime.sendMessage({ target: "textwarden-background", action: "health", session: policySession }),
        new Promise((_, reject) => { deadline = setTimeout(() => reject(new Error()), 4000); }),
      ]);
      if (port !== connection || document.hidden || (!userInitiated && (!enabled || !field || eligible(field) !== field))) return;
      if (!health || typeof health.known !== "boolean") throw new Error();
      if (!health.known) {
        // Safari can unload its event page without disconnecting the content port.
        const old = port; port = null; old?.disconnect();
        connectionLost("Reconnecting to TextWarden…");
        requestPolicy();
      } else if (!health.ready) connectionLost("TextWarden is not responding. Open the app to reconnect.");
      else if (reconnectNeeded) requestPolicy();
    } catch {
      if (port === connection) connectionLost("TextWarden disconnected. Reload this page to reconnect.");
    }
    finally { clearTimeout(deadline); healthPending = false; }
  }
  function connect() {
    const connection = extensionAPI.runtime.connect({ name: "textwarden-editor" });
    port = connection;
    connection.onMessage.addListener(receive);
    connection.onDisconnect.addListener(() => {
      void extensionAPI.runtime.lastError;
      if (port !== connection) return;
      port = null;
      connectionLost("TextWarden disconnected. Click another editor or type to reconnect.");
    });
  }

  function release() {
    endHover(); send("release"); field = null; session = null; checkedText = ""; pendingTool = null; issues = []; suggestions.disabled = true;
    observer.disconnect(); resizeObserver.disconnect();
    clearTimeout(timer); marks.replaceChildren();
    status.textContent = "Click a supported text field."; menu.hidden = true; updateUI();
  }

  function focus(element) {
    const next = eligible(element);
    if (!enabled) return;
    if (next === field) { if (next && reconnectNeeded) changed(); return; }
    release();
    if (!next) return;
    field = next; session = crypto.randomUUID(); revision = 0;
    if (field.isContentEditable) observer.observe(field, { subtree: true, childList: true, characterData: true });
    resizeObserver.observe(field);
    changed(); updateUI(); scheduleRender();
  }

  function changed() {
    if (!field) return;
    if (eligible(field) !== field) { release(); return; }
    editFailure = null; endHover();
    revision++; issues = []; suggestions.disabled = true; marks.replaceChildren();
    send("invalidate"); clearTimeout(timer);
    if (composing) return;
    timer = setTimeout(() => {
      if (!field?.isConnected || document.hidden) return;
      if (eligible(field) !== field) { release(); return; }
      const { text } = extract();
      if (text.length > 20000) { status.textContent = "This editor is too large for the browser preview."; return; }
      checkedText = text;
      status.textContent = "Checking locally…"; updateUI();
      send("snapshot", { text });
    }, 600);
  }

  function rangeFor(nodes, start, end) {
    const a = nodes.find((entry) => start >= entry.start && start < entry.end);
    const b = nodes.find((entry) => end > entry.start && end <= entry.end);
    if (!a || !b) return null;
    const range = document.createRange();
    range.setStart(a.node, start - a.start); range.setEnd(b.node, end - b.start);
    return range;
  }

  function selectionRange() {
    if (!field || eligible(field) !== field) return null;
    if (field instanceof HTMLTextAreaElement || field instanceof HTMLInputElement) return { start: field.selectionStart, end: field.selectionEnd };
    const selection = getSelection();
    if (!selection.rangeCount) return null;
    const selected = selection.getRangeAt(0);
    if (!field.contains(selected.commonAncestorContainer)) return null;
    const { nodes, text } = extract();
    if (!nodes.length && text) return null;
    function offset(container, position) {
      const entry = nodes.find((item) => item.node === container);
      if (entry) return entry.start + position;
      const boundary = document.createRange();
      boundary.setStart(container, position); boundary.collapse(true);
      const following = nodes.find((item) => boundary.comparePoint(item.node, 0) >= 0);
      return following?.start ?? nodes.at(-1)?.end ?? 0;
    }
    return { start: offset(selected.startContainer, selected.startOffset), end: offset(selected.endContainer, selected.endOffset) };
  }

  function requestTool(kind) {
    if (!field?.isConnected || eligible(field) !== field || document.hidden) {
      status.textContent = "Click a supported text field first."; return;
    }
    const selection = selectionRange(), { text } = extract();
    if (!selection || text.length > 20000) { status.textContent = "Select text in a supported editor of up to 20,000 characters."; return; }
    if (text !== checkedText) changed();
    clearTimeout(timer); checkedText = text;
    send(kind, { text, ...selection });
  }

  function measure() {
    if (!field || eligible(field) !== field) return { text: "", nodes: [], cleanup() {} };
    if (!(field instanceof HTMLTextAreaElement || field instanceof HTMLInputElement)) return { ...extract(), cleanup() {} };
    // Same browser-mirror technique used by Harper; never modify the editor's own DOM.
    const mirror = document.createElement("div"), css = getComputedStyle(field), box = field.getBoundingClientRect();
    for (const property of ["font", "letter-spacing", "line-height", "text-align", "text-indent", "text-transform", "direction", "tab-size", "padding", "border", "box-sizing", "word-spacing", "overflow-wrap", "word-break"]) mirror.style.setProperty(property, css.getPropertyValue(property));
    Object.assign(mirror.style, { position: "fixed", left: `${box.left}px`, top: `${box.top}px`, width: `${box.width}px`, height: `${box.height}px`, whiteSpace: field instanceof HTMLTextAreaElement ? "pre-wrap" : "pre", overflow: "hidden", visibility: "hidden", pointerEvents: "none" });
    const text = field.value, node = document.createTextNode(text);
    mirror.append(node); shadow.append(mirror);
    mirror.scrollTop = field.scrollTop; mirror.scrollLeft = field.scrollLeft;
    return { text, nodes: [{ node, start: 0, end: text.length }], cleanup() { mirror.remove(); } };
  }

  function render() {
    frame = null; marks.replaceChildren(); wordTargets = [];
    if (!enabled || reconnectNeeded || !field?.isConnected || document.hidden) { toolbar.hidden = true; menu.hidden = true; return; }
    if (eligible(field) !== field) { release(); return; }
    let clip = field.getBoundingClientRect();
    clip = { left: Math.max(0, clip.left), top: Math.max(0, clip.top), right: Math.min(innerWidth, clip.right), bottom: Math.min(innerHeight, clip.bottom) };
    for (let parent = field.parentElement; parent; parent = parent.parentElement) {
      const css = getComputedStyle(parent), rect = parent.getBoundingClientRect();
      if (/(auto|scroll|hidden|clip)/.test(css.overflowX)) { clip.left = Math.max(clip.left, rect.left); clip.right = Math.min(clip.right, rect.right); }
      if (/(auto|scroll|hidden|clip)/.test(css.overflowY)) { clip.top = Math.max(clip.top, rect.top); clip.bottom = Math.min(clip.bottom, rect.bottom); }
    }
    toolbar.hidden = clip.bottom <= clip.top || clip.right <= clip.left || (!issues.length && !presentation.alwaysShow && !presentation.styleEnabled);
    if (toolbar.hidden) { menu.hidden = true; return; }
    if (!drag?.moved) toolbar.classList.toggle("horizontal", Boolean(position && ["top", "bottom"].includes(position.edge)));
    let left = Math.max(8, Math.min(innerWidth - toolbar.offsetWidth - 8, clip.right + 8));
    let top = Math.max(8, Math.min(innerHeight - toolbar.offsetHeight - 8, clip.top));
    if (position) {
      const horizontal = ["top", "bottom"].includes(position.edge);
      left = horizontal ? position.fraction * innerWidth - toolbar.offsetWidth / 2 : position.edge === "left" ? 8 : innerWidth - toolbar.offsetWidth - 8;
      top = horizontal ? position.edge === "top" ? 8 : innerHeight - toolbar.offsetHeight - 8 : position.fraction * innerHeight - toolbar.offsetHeight / 2;
      left = Math.max(8, Math.min(innerWidth - toolbar.offsetWidth - 8, left)); top = Math.max(8, Math.min(innerHeight - toolbar.offsetHeight - 8, top));
    }
    if (!drag?.moved) Object.assign(toolbar.style, { left: `${left}px`, top: `${top}px` });
    if (!menu.hidden) Object.assign(menu.style, {
      left: `${Math.max(8, Math.min(innerWidth - menu.offsetWidth - 8, left - menu.offsetWidth - 8))}px`,
      top: `${Math.max(8, Math.min(innerHeight - menu.offsetHeight - 8, top))}px`,
    });
    if (!showUnderlines || !pageUnderlines) return;
    const measured = measure();
    try {
      if (measured.text !== checkedText) { changed(); return; }
      for (const issue of issues.slice(0, 50)) {
        const range = rangeFor(measured.nodes, issue.start, issue.end);
        if (!range) continue;
        for (const rect of range.getClientRects()) {
          const left = Math.max(rect.left, clip.left), right = Math.min(rect.right, clip.right);
          if (right <= left || rect.bottom > clip.bottom || rect.bottom < clip.top) continue;
          const wordRect = { left, right, top: Math.max(rect.top, clip.top), bottom: rect.bottom };
          const highlight = document.createElement("div"); highlight.className = "word-highlight";
          highlight.hidden = hoveredIssue !== `underline:${issue.id}`;
          Object.assign(highlight.style, { left: `${left}px`, top: `${wordRect.top}px`, width: `${right - left}px`, height: `${wordRect.bottom - wordRect.top}px`, backgroundColor: issue.highlightColor || "transparent" });
          wordTargets.push({ issue, rect: wordRect, highlight }); marks.append(highlight);
          const mark = document.createElement("button");
          mark.className = "mark"; mark.type = "button";
          mark.style.borderBottomWidth = `${underlineThickness}px`;
          mark.style.borderBottomColor = issue.underlineColor || "#ff9500";
          mark.setAttribute("aria-label", issue.message);
          Object.assign(mark.style, { left: `${left}px`, top: `${rect.bottom - 5}px`, width: `${right - left}px`, height: "6px" });
          mark.addEventListener("pointerenter", () => startHover(issue));
          mark.addEventListener("pointermove", () => startHover(issue));
          mark.addEventListener("pointerleave", endHover);
          mark.addEventListener("mousedown", (event) => event.preventDefault());
          mark.addEventListener("click", (event) => { event.stopPropagation(); send("show", { errorID: issue.id }); });
          marks.append(mark);
        }
      }
    } finally { measured.cleanup(); }
  }

  function scheduleRender() { if (!frame) frame = requestAnimationFrame(render); }

  function receive(message) {
    if (message.version !== 1) return;
    if (message.kind === "connection") {
      if (message.status !== "connected") {
        connectionLost(message.detail);
      }
      return;
    }
    if (message.kind === "configuration" && message.session === policySession) {
      if (message.pageURL === location.origin + location.pathname) setEnabled(message.pageEnabled !== false);
      return;
    }
    if (message.kind === "request" && message.action === "refresh") {
      if (message.session === policySession) { requestPolicy(); return; }
      if (pausedSession) pauseOwnership();
      else if (enabled && field?.isConnected && !document.hidden) changed();
      return;
    }
    if (message.session !== session) return;
    if (field && eligible(field) !== field) { release(); return; }
    if (message.kind === "request" && message.action === "grammar") {
      if (issues.length) grammar();
      else status.textContent = "No suggestions are available yet.";
      return;
    }
    if (message.kind === "request" && message.action === "style") { send("show", { action: "style" }); return; }
    if (message.kind === "request" && ["compose", "rewrite", "readability"].includes(message.action)) { requestTool(message.action); return; }
    if (message.kind === "status") {
      if (message.action === "editFailed") editFailure = message.status;
      status.textContent = message.status; rewriting = message.status === "Rewriting locally…";
      if (message.action === "disconnected") {
        reconnectNeeded = true; checkingEnabled = false; issues = []; marks.replaceChildren();
      } else if (!rewriting && !message.status?.startsWith("Readability:") && field && document.hasFocus()) { menu.hidden = false; scheduleRender(); }
      updateUI(); return;
    }
    if (message.revision !== revision || !field?.isConnected) return;
    if (message.kind === "result") {
      if (extract().text !== checkedText) return;
      issues = message.errors ?? []; rewriting = false;
      if (!editFailure) menu.hidden = true;
      checkingEnabled = message.checkingEnabled !== false; reconnectNeeded = false;
      if (!checkingEnabled) { setEnabled(false); return; }
      suggestions.disabled = !issues.length;
      showUnderlines = message.showUnderlines !== false;
      underlineThickness = Number.isFinite(message.underlineThickness) ? Math.min(5, Math.max(1, message.underlineThickness)) : 2;
      status.textContent = editFailure ?? message.status ?? (issues.length ? `${issues.length} ${issues.length === 1 ? "suggestion" : "suggestions"}` : "No grammar issues found");
      if (message.presentation) presentation = message.presentation;
      if (message.theme) host.dataset.theme = message.theme;
      updateUI(); scheduleRender();
    } else if (message.kind === "replace") {
      const before = extract();
      if (policyURL !== location.origin + location.pathname || document.hidden || before.text !== message.text || before.text !== checkedText || eligible(field) !== field) return;
      if (!Number.isInteger(message.start) || !Number.isInteger(message.end) || message.start < 0 || message.end < message.start || message.end > before.text.length || typeof message.replacement !== "string") return;
      if (message.selectionRequired) {
        const selection = selectionRange();
        if (selection?.start !== message.start || selection?.end !== message.end) return;
      }
      field.focus({ preventScroll: true });
      if (field instanceof HTMLTextAreaElement || field instanceof HTMLInputElement) field.setSelectionRange(message.start, message.end);
      else {
        let range = rangeFor(before.nodes, message.start, message.end);
        if (!range && message.start === message.end) {
          const entry = before.nodes.find((item) => message.start >= item.start && message.start <= item.end);
          range = document.createRange();
          if (entry) range.setStart(entry.node, message.start - entry.start);
          else if (!before.text) range.selectNodeContents(field);
          else return;
          range.collapse(true);
        }
        if (!range) return;
        const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
      }
      const expected = before.text.slice(0, message.start) + message.replacement + before.text.slice(message.end);
      const target = field;
      // execCommand does not deliver Chrome's normal cancellable beforeinput event.
      // Let the editor refuse the insertion or update its state before touching its text.
      applyingReplacement = true; hoverSuppressed = true; endHover();
      const allowed = target.dispatchEvent(new InputEvent("beforeinput", {
        inputType: "insertText", data: message.replacement, bubbles: true, cancelable: true, composed: true,
      }));
      if (field !== target || !target.isConnected) { applyingReplacement = false; return; }
      const selection = selectionRange();
      const unchanged = extract().text === before.text && eligible(target) === target
        && selection?.start === message.start && selection?.end === message.end;
      // The editing command preserves native Undo. Report failure rather than force a DOM edit.
      let applied = false;
      try {
        if (allowed && unchanged) document.execCommand("insertText", false, message.replacement);
        applied = allowed && unchanged && extract().text === expected;
      } catch { /* Some editors reject the command; recover through the normal failure path. */ }
      finally { observer.takeRecords(); applyingReplacement = false; }
      if (applied) {
        revision++; checkedText = expected; issues = []; clearTimeout(timer); marks.replaceChildren();
        send("applied", { status: "ok", text: expected });
        updateUI();
      } else { send("applied", { status: "failed" }); changed(); }
      if (!applied) { editFailure = "This editor could not apply the correction safely."; status.textContent = editFailure; menu.hidden = false; updateUI(); scheduleRender(); }
    }
  }

  document.addEventListener("focusin", (event) => { if (event.target !== host) focus(event.target); }, true);
  document.addEventListener("selectionchange", () => {
    const selection = selectionRange();
    if (selection) send("selection", selection);
    updateUI();
  });
  document.addEventListener("input", () => { if (!applyingReplacement && field && document.activeElement === field) changed(); }, true);
  document.addEventListener("compositionstart", () => { composing = true; changed(); }, true);
  document.addEventListener("compositionend", () => { composing = false; changed(); }, true);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) { release(); pauseOwnership("release"); }
    else if (pausedSession) pauseOwnership(); else focus(document.activeElement);
  });
  window.addEventListener("pagehide", () => { release(); pauseOwnership("release"); port?.disconnect(); port = null; });
  window.addEventListener("pageshow", (event) => { if (event.persisted) requestPolicy(); });
  window.addEventListener("blur", () => { menu.hidden = true; send("blur"); pauseOwnership("blur"); });
  window.addEventListener("focus", () => { if (pausedSession) { pauseOwnership(); return; } if (field) { if (reconnectNeeded) changed(); else send("focus"); } else focus(document.activeElement); requestAnimationFrame(runPendingTool); });
  document.addEventListener("pointerdown", (event) => { if (event.target !== host) { menu.hidden = true; } }, true);
  shadow.addEventListener("keydown", (event) => { if (event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")) { event.preventDefault(); openMenu(); } if (event.key === "Escape") { menu.hidden = true; suggestions.focus(); } });
  toolbar.addEventListener("contextmenu", (event) => { event.preventDefault(); endHover(); openMenu(); });
  window.addEventListener("scroll", scheduleRender, { capture: true, passive: true });
  window.addEventListener("resize", scheduleRender, { passive: true });
  host.hidden = true;
  requestPolicy();
  if (extensionAPI.runtime.getURL("").startsWith("safari-web-extension:")) setInterval(checkConnection, 5000);
})();
