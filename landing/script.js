// DockWindow landing: interactive demo and scroll reveals. No dependencies.
(() => {
  "use strict";
  document.documentElement.classList.add("js");

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // ---------- Scroll reveals ----------
  const reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !reduceMotion.matches) {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) { entry.target.classList.add("in"); io.unobserve(entry.target); }
      }
    }, { rootMargin: "0px 0px -12% 0px", threshold: 0.15 });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add("in"));
  }

  // ---------- Demo ----------
  const mac = document.querySelector("[data-demo]");
  if (!mac) return;

  const $ = (sel) => document.querySelector(sel);
  const desk = $("[data-desk]");
  const dock = $("[data-dock]");
  const switcher = $("[data-switcher]");
  const tilesEl = $("[data-tiles]");
  const preview = $("[data-preview]");
  const caption = $("[data-caption]");
  const frontApp = $("[data-front-app]");
  const deskChip = $("[data-desk-chip]");
  const tabBtn = $("[data-tab]");
  const releaseBtn = $("[data-release]");
  const resetBtn = $("[data-reset]");
  const deskBtns = document.querySelectorAll("[data-desk-btn]");
  const stage = $("#demo");

  const APPS = {
    finder: { name: "Finder", icon: "i-finder", pinned: true },
    dockwindow: { name: "DockWindow", img: "assets/dog-96.png", pinned: true },
    safari: { name: "Safari", icon: "i-safari" },
    notes: { name: "Notes", icon: "i-notes" },
    terminal: { name: "Terminal", icon: "i-terminal" },
    music: { name: "Music", icon: "i-music" },
  };
  const PINS = ["finder", "dockwindow"];

  const initialWindows = () => ({
    1: [
      { id: "s1", app: "safari", title: "Docs", x: 5, y: 8, w: 54, h: 52 },
      { id: "s2", app: "safari", title: "Recipes", x: 24, y: 20, w: 52, h: 50 },
      { id: "n1", app: "notes", title: "Groceries", x: 58, y: 5, w: 37, h: 46 },
    ],
    2: [
      { id: "t1", app: "terminal", title: "zsh", x: 6, y: 10, w: 54, h: 48 },
      { id: "m1", app: "music", title: "Up Next", x: 40, y: 20, w: 52, h: 52 },
    ],
  });

  const state = {
    desk: 1,
    windows: initialWindows(),
    // Front-to-back order of window ids per desktop.
    order: { 1: ["s2", "n1", "s1"], 2: ["m1", "t1"] },
    mode: "idle", // idle | switcher | preview
    sel: 0,
    previewApp: null,
    dirty: false,
  };

  const windowsHere = () => state.windows[state.desk];
  const byId = (id) => windowsHere().find((w) => w.id === id);
  const mru = () => state.order[state.desk].map(byId).filter(Boolean);
  const say = (text) => { caption.textContent = text; };
  const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

  function iconMarkup(appKey, cls = "ic") {
    const app = APPS[appKey];
    if (app.img) return `<img class="${cls}" src="${app.img}" width="96" height="96" alt="">`;
    return `<svg class="${cls}" aria-hidden="true" focusable="false"><use href="#${app.icon}"/></svg>`;
  }

  function bodyMarkup(app) {
    switch (app) {
      case "safari":
        return `<span class="url"></span><span class="ln dark"></span><span class="pic"></span><span class="ln"></span><span class="ln" style="width:70%"></span>`;
      case "notes":
        return `<span class="notes"><span class="side"></span><span class="main"><span class="ln dark"></span><span class="ln"></span><span class="ln" style="width:80%"></span><span class="ln" style="width:60%"></span></span></span>`;
      case "terminal":
        return `<span>~/app $ swift build</span><span style="color:#cfc9e8">Build complete!</span><span>~/app $ ▍</span>`;
      case "music":
        return `<span class="albums"><i></i><i></i><i></i><i></i><i></i><i></i></span>`;
      default:
        return "";
    }
  }

  const miniMarkup = (w) =>
    `<span class="mini" data-app="${w.app}"><span class="win-bar"><span class="lights"><i></i><i></i><i></i></span></span><span class="win-body">${bodyMarkup(w.app)}</span></span>`;

  // ----- Desk -----
  function renderDesk({ swap = 0 } = {}) {
    const order = state.order[state.desk];
    desk.innerHTML = windowsHere().map((w) => {
      const z = order.length - order.indexOf(w.id);
      return `<div class="win${order[0] === w.id ? " is-front" : ""}" data-win="${w.id}" data-app="${w.app}"
        style="left:${w.x}%;top:${w.y}%;width:${w.w}%;height:${w.h}%;z-index:${z}">
        <div class="win-bar"><span class="lights"><i></i><i></i><i></i></span><span class="t">${w.title}</span></div>
        <div class="win-body">${bodyMarkup(w.app)}</div></div>`;
    }).join("");
    const front = mru()[0];
    frontApp.textContent = front ? APPS[front.app].name : "Finder";
    deskChip.textContent = `Desktop ${state.desk}`;
    if (swap && !reduceMotion.matches) {
      desk.style.setProperty("--swap-from", `${swap * 40}px`);
      desk.classList.remove("swap");
      void desk.offsetWidth;
      desk.classList.add("swap");
    }
  }

  // ----- Dock -----
  function dockApps() {
    const running = [];
    for (const w of windowsHere()) if (!running.includes(w.app)) running.push(w.app);
    return { pins: PINS, running: running.filter((a) => !PINS.includes(a)) };
  }

  function renderDock({ animate = false } = {}) {
    const { pins, running } = dockApps();
    const button = (key) => {
      const count = windowsHere().filter((w) => w.app === key).length;
      const label = `${APPS[key].name}, ${count ? plural(count, "window") : "no windows"} on this desktop`;
      return `<li><button type="button" class="dock-btn${animate && !pins.includes(key) ? " enter" : ""}" data-app="${key}"
        aria-label="${label}" aria-expanded="false" aria-haspopup="true">
        ${iconMarkup(key)}<span class="dots" aria-hidden="true">${"<i></i>".repeat(count)}</span></button></li>`;
    };
    dock.innerHTML = pins.map(button).join("") +
      (running.length ? `<li class="dock-sep" aria-hidden="true"></li>` : "") +
      running.map(button).join("");
  }

  // ----- Focus a window -----
  function focusWindow(id, how) {
    const w = byId(id);
    if (!w) return;
    const order = state.order[state.desk];
    order.splice(order.indexOf(id), 1);
    order.unshift(id);
    closeAll();
    renderDesk();
    const el = desk.querySelector(`[data-win="${id}"]`);
    if (el && !reduceMotion.matches) el.classList.add("flash");
    say(`${how}: focused ${APPS[w.app].name}, “${w.title}”. Just that window.`);
  }

  // ----- Switcher -----
  function openSwitcher() {
    closePreview();
    const list = mru();
    if (!list.length) { say("No windows on this desktop to switch to."); return; }
    state.mode = "switcher";
    state.sel = list.length > 1 ? 1 : 0;
    switcher.hidden = false;
    tabBtn.innerHTML = "<kbd>⇥</kbd> Tab again";
    releaseBtn.hidden = false;
    renderTiles();
  }

  function renderTiles() {
    const list = mru();
    tilesEl.innerHTML = list.map((w, i) =>
      `<li><button type="button" class="tile" data-tile="${w.id}" aria-current="${i === state.sel}"
        aria-label="${APPS[w.app].name}: ${w.title}">${miniMarkup(w)}${iconMarkup(w.app)}<span class="name">${w.title}</span></button></li>`
    ).join("");
    const w = list[state.sel];
    say(`Switcher: ${plural(list.length, "tile")}, one per window. Selected ${APPS[w.app].name}, “${w.title}”.`);
  }

  function stepSwitcher(delta) {
    const n = mru().length;
    state.sel = (state.sel + delta + n) % n;
    renderTiles();
  }

  function closeSwitcher() {
    if (state.mode !== "switcher") return;
    state.mode = "idle";
    switcher.hidden = true;
    tilesEl.innerHTML = "";
    tabBtn.innerHTML = "<kbd>⌥</kbd> Option+Tab";
    releaseBtn.hidden = true;
  }

  // ----- Previews -----
  let hoverTimer = 0;
  let leaveTimer = 0;

  function openPreview(appKey, { announce = true } = {}) {
    closeSwitcher();
    const btn = dock.querySelector(`[data-app="${appKey}"]`);
    if (!btn) return;
    state.mode = "preview";
    state.previewApp = appKey;
    dock.querySelectorAll(".dock-btn").forEach((b) => b.setAttribute("aria-expanded", String(b === btn)));
    const wins = windowsHere().filter((w) => w.app === appKey);
    const name = APPS[appKey].name;
    preview.setAttribute("role", "group");
    preview.setAttribute("aria-label", `${name} window previews`);
    preview.innerHTML = wins.length
      ? wins.map((w) => `<div class="pv">
          <span class="pv-lights"><button type="button" data-close="${w.id}" aria-label="Close ${name} window “${w.title}”"></button><i></i><i></i></span>
          <button type="button" class="pv-shot" data-focus="${w.id}" aria-label="Focus ${name} window “${w.title}”">${miniMarkup(w)}</button>
          <span class="pv-name">${w.title}</span></div>`).join("")
      : `<p class="pv-empty">No open windows on this desktop</p>`;
    preview.hidden = false;
    placePreview(btn);
    if (announce) {
      say(wins.length
        ? `${name} previews: ${plural(wins.length, "window")}. Pick one to focus exactly that window.`
        : `${name} is pinned here with no windows on this desktop.`);
    }
  }

  function placePreview(btn) {
    const m = mac.getBoundingClientRect();
    const b = btn.getBoundingClientRect();
    const half = preview.offsetWidth / 2;
    const center = b.left + b.width / 2 - m.left;
    const left = Math.min(Math.max(center, half + 8), m.width - half - 8);
    preview.style.left = `${left}px`;
    preview.style.setProperty("--tail", `${center - left + half}px`);
  }

  function closePreview() {
    clearTimeout(hoverTimer);
    clearTimeout(leaveTimer);
    if (state.mode !== "preview") return;
    state.mode = "idle";
    state.previewApp = null;
    preview.hidden = true;
    preview.innerHTML = "";
    dock.querySelectorAll(".dock-btn").forEach((b) => b.setAttribute("aria-expanded", "false"));
  }

  function closeWindow(id) {
    const w = byId(id);
    if (!w) return;
    const app = w.app;
    state.windows[state.desk] = windowsHere().filter((x) => x.id !== id);
    state.order[state.desk] = state.order[state.desk].filter((x) => x !== id);
    state.dirty = true;
    resetBtn.hidden = false;
    renderDesk();
    renderDock();
    const left = windowsHere().filter((x) => x.app === app).length;
    if (left) {
      openPreview(app, { announce: false });
      preview.querySelector("[data-focus]")?.focus();
    } else {
      closePreview();
      dock.querySelector(".dock-btn")?.focus();
    }
    say(`Closed “${w.title}”. ${APPS[app].name} now has ${plural(left, "dot")}${left ? "" : " and leaves this desktop’s Dock"}.`);
  }

  function closeAll() { closeSwitcher(); closePreview(); }

  // ----- Desktops -----
  function setDesk(n) {
    if (n === state.desk) return;
    closeAll();
    const dir = n > state.desk ? 1 : -1;
    state.desk = n;
    deskBtns.forEach((b) => b.setAttribute("aria-pressed", String(Number(b.dataset.deskBtn) === n)));
    renderDesk({ swap: dir });
    renderDock({ animate: true });
    const { running } = dockApps();
    say(`Desktop ${n}: the Dock shows ${running.map((a) => APPS[a].name).join(" and ") || "only pins"}. Finder and DockWindow stay pinned.`);
  }

  function reset() {
    closeAll();
    state.windows = initialWindows();
    state.order = { 1: ["s2", "n1", "s1"], 2: ["m1", "t1"] };
    state.dirty = false;
    resetBtn.hidden = true;
    renderDesk();
    renderDock();
    say("Demo reset. Click a Dock icon for previews, or press Option+Tab.");
    tabBtn.focus();
  }

  // ----- Events -----
  deskBtns.forEach((b) => b.addEventListener("click", () => setDesk(Number(b.dataset.deskBtn))));

  tabBtn.addEventListener("click", () => {
    if (state.mode === "switcher") stepSwitcher(1);
    else openSwitcher();
  });
  releaseBtn.addEventListener("click", () => {
    const w = mru()[state.sel];
    if (w) focusWindow(w.id, "Released Option");
    tabBtn.focus();
  });
  resetBtn.addEventListener("click", reset);

  tilesEl.addEventListener("click", (e) => {
    const t = e.target.closest("[data-tile]");
    if (t) { focusWindow(t.dataset.tile, "Switcher"); tabBtn.focus(); }
  });

  desk.addEventListener("click", (e) => {
    const w = e.target.closest("[data-win]");
    if (w) focusWindow(w.dataset.win, "Clicked");
  });

  dock.addEventListener("click", (e) => {
    const b = e.target.closest(".dock-btn");
    if (!b) return;
    const key = b.dataset.app;
    if (state.mode === "preview" && state.previewApp === key) closePreview();
    else openPreview(key);
  });

  // Hover previews for mouse pointers only; touch and keyboard use click.
  dock.addEventListener("pointerover", (e) => {
    if (e.pointerType !== "mouse") return;
    const b = e.target.closest(".dock-btn");
    if (!b) return;
    clearTimeout(leaveTimer);
    clearTimeout(hoverTimer);
    if (state.mode === "switcher") return;
    hoverTimer = setTimeout(() => {
      if (state.previewApp !== b.dataset.app) openPreview(b.dataset.app);
    }, 140);
  });
  const scheduleLeave = (e) => {
    if (e.pointerType !== "mouse") return;
    clearTimeout(hoverTimer);
    if (state.mode !== "preview") return;
    const to = e.relatedTarget;
    if (to && (dock.contains(to) || preview.contains(to))) return;
    leaveTimer = setTimeout(() => {
      if (!preview.contains(document.activeElement)) closePreview();
    }, 320);
  };
  dock.addEventListener("pointerout", scheduleLeave);
  preview.addEventListener("pointerout", scheduleLeave);
  preview.addEventListener("pointerover", () => clearTimeout(leaveTimer));

  preview.addEventListener("click", (e) => {
    const close = e.target.closest("[data-close]");
    if (close) { closeWindow(close.dataset.close); return; }
    const focus = e.target.closest("[data-focus]");
    if (focus) {
      const appKey = state.previewApp;
      focusWindow(focus.dataset.focus, "Preview");
      dock.querySelector(`[data-app="${appKey}"]`)?.focus();
    }
  });

  // Keys are handled only while focus is inside the demo, never globally.
  stage.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && state.mode !== "idle") {
      const appKey = state.previewApp;
      const wasSwitcher = state.mode === "switcher";
      closeAll();
      say(wasSwitcher ? "Switcher cancelled. Nothing changed." : "Preview closed.");
      (wasSwitcher ? tabBtn : dock.querySelector(`[data-app="${appKey}"]`))?.focus();
      e.preventDefault();
    } else if (state.mode === "switcher" && (e.key === "ArrowRight" || e.key === "ArrowLeft")) {
      stepSwitcher(e.key === "ArrowRight" ? 1 : -1);
      e.preventDefault();
    }
  });

  // Click outside the demo dismisses overlays.
  document.addEventListener("pointerdown", (e) => {
    if (state.mode !== "idle" && !stage.contains(e.target)) closeAll();
  });

  window.addEventListener("resize", () => {
    if (state.mode === "preview") {
      const b = dock.querySelector(`[data-app="${state.previewApp}"]`);
      if (b) placePreview(b);
    }
  });

  // "Try the demo" links land focus on the first demo control.
  document.querySelectorAll("[data-demo-start]").forEach((a) => a.addEventListener("click", () => {
    setTimeout(() => tabBtn.focus({ preventScroll: true }), reduceMotion.matches ? 0 : 450);
  }));

  renderDesk();
  renderDock();
})();
