// DogBar landing: interactive hero demo and scroll reveals. No dependencies.
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
  // A fictional weekend trip: Safari holds a Lisbon day plan and a hotel booking, next
  // to a Slack chat with friends and a Notes packing list. Desktop 2 is a quiet Sunday.
  // All content is made up.
  const mac = document.querySelector("[data-demo]");
  if (!mac) return;

  const $ = (sel) => document.querySelector(sel);
  const desk = $("[data-desk]");
  const dock = $("[data-dock]");
  const dockWrap = dock.parentElement;
  const switcher = $("[data-switcher]");
  const tilesEl = $("[data-tiles]");
  const preview = $("[data-preview]");
  const caption = $("[data-caption]");
  const frontApp = $("[data-front-app]");
  const menus = $("[data-menus]");
  const swipeHud = $("[data-swipe]");
  const stage = $("#demo");

  const APPS = {
    finder: { name: "Finder", img: "assets/apps/finder.png" },
    dockwindow: { name: "DogBar", img: "assets/dog-96.png" },
    safari: { name: "Safari", img: "assets/apps/safari.png" },
    slack: { name: "Slack", img: "assets/apps/slack.png" },
    notes: { name: "Notes", img: "assets/apps/notes.png" },
    music: { name: "Music", img: "assets/apps/music.png" },
  };
  const PINS = ["finder", "dockwindow"];
  const INTRO_APP = "safari";
  const INTRO_PICK = "s2";
  const INTRO_TEXT = "Safari has two windows open. Click “Hotel booking” to bring up just that one.";

  // Only the front window is shown on the desk, so every change reads at a glance;
  // the others wait behind it. `view` picks the window's content.
  const initialWindows = () => ({
    1: [
      { id: "s1", app: "safari", view: "trip", title: "Lisbon day plan", url: "wanderly.travel" },
      { id: "s2", app: "safari", view: "booking", title: "Hotel booking", url: "casaluz-stays.travel" },
      { id: "k1", app: "slack", view: "slack", title: "#lisbon-trip" },
      { id: "n1", app: "notes", view: "notes", title: "Packing list" },
    ],
    2: [
      { id: "s3", app: "safari", view: "hike", title: "Sunday hike", url: "trailmap.travel" },
      { id: "m1", app: "music", view: "music", title: "Up Next" },
    ],
  });
  // The front app's menus, as macOS shows them.
  const MENUS = {
    finder: ["File", "Edit", "View", "Go", "Window", "Help"],
    safari: ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"],
    slack: ["File", "Edit", "View", "Go", "Window", "Help"],
    notes: ["File", "Edit", "Format", "View", "Window", "Help"],
    music: ["File", "Edit", "Song", "View", "Controls", "Window", "Help"],
  };
  // Front-to-back window order per desktop.
  const initialOrder = () => ({ 1: ["s1", "s2", "k1", "n1"], 2: ["m1", "s3"] });

  const state = {
    desk: 1,
    windows: initialWindows(),
    order: initialOrder(),
    mode: "idle", // idle | switcher | preview
    sel: 0,
    previewApp: null,
    intro: false, // the opening Safari preview, shown until the first interaction
  };

  const windowsHere = () => state.windows[state.desk];
  const byId = (id) => windowsHere().find((w) => w.id === id);
  const mru = () => state.order[state.desk].map(byId).filter(Boolean);
  const say = (text) => { caption.textContent = text; };
  const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

  const iconMarkup = (appKey, cls = "ic") =>
    `<img class="${cls}" src="${APPS[appKey].img}" width="96" height="96" alt="" draggable="false">`;

  // Window content, all spans so it is also valid inside preview and tile buttons.
  const VIEWS = {
    trip: `<span class="trip">
      <span class="trip-img"></span>
      <span class="trip-h">A weekend in Lisbon</span>
      <span class="trip-ln">Day 1: Alfama and the 28 tram</span>
      <span class="trip-ln">Day 2: Belém and pastéis de nata</span>
    </span>`,
    booking: `<span class="site">
      <span class="site-logo">Casa Luz</span>
      <span class="site-steps"><i class="on"></i><i class="on"></i></span>
      <span class="site-h">Confirm your stay</span>
      <span class="site-input">14–16 Nov · 3 guests</span>
      <span class="site-btn">Book 2 nights</span>
    </span>`,
    slack: `<span class="slack">
      <span class="sl-side"><b>Friends</b><span># general</span><span class="on"># lisbon-trip</span><span># photos</span></span>
      <span class="sl-main"><span class="sl-head"># lisbon-trip</span>
        <span class="msg"><i class="av" style="--av:#e8912d">M</i><span><b>Maya</b>Found a hotel near Alfama. Can someone book it tonight?</span></span>
        <span class="msg"><i class="av" style="--av:#2bac76">L</i><span><b>Leo</b>Love the day plan. Tram on Saturday!</span></span>
      </span>
    </span>`,
    notes: `<span class="note">
      <span class="note-h">Packing list</span>
      <span class="check done"><i></i>Passport</span>
      <span class="check done"><i></i>Comfy shoes</span>
      <span class="check"><i></i>Sunscreen</span>
      <span class="check"><i></i>Phone charger</span>
    </span>`,
    hike: `<span class="trip">
      <span class="trip-img"></span>
      <span class="trip-h">Sunday hike: Pine Ridge loop</span>
      <span class="trip-ln">6 km · about 2 hours</span>
      <span class="trip-ln">Picnic spot at the lookout</span>
    </span>`,
    music: `<span class="music">
      <span class="mu-h">Up Next</span>
      <span class="mu-row"><i class="album-art" style="--art:#ff6b8b"></i><span><b>Slow Orbit</b>Juniper Lane</span></span>
      <span class="mu-row"><i class="album-art" style="--art:#6e24e6"></i><span><b>Paper Boats</b>Hollow Pines</span></span>
      <span class="mu-row"><i class="album-art" style="--art:#ffb020"></i><span><b>Afterglow</b>Mira Vale</span></span>
    </span>`,
  };

  // Title bar: Safari shows its address field, other apps their window title.
  const barMarkup = (w) => w.url
    ? `<span class="win-bar is-safari"><span class="lights"><i></i><i></i><i></i></span>
        <span class="tb tb-side"></span><span class="tb-nav">‹ ›</span>
        <span class="addr">${w.url}</span><span class="tb tb-share"></span><span class="tb tb-plus">+</span></span>`
    : `<span class="win-bar"><span class="lights"><i></i><i></i><i></i></span><span class="t">${w.title}</span></span>`;
  const windowInner = (w) => `${barMarkup(w)}<span class="win-body">${VIEWS[w.view]}</span>`;
  const miniMarkup = (w) => `<span class="mini" data-app="${w.app}">${windowInner(w)}</span>`;

  // ----- Desk -----
  function renderDesk({ swap = 0 } = {}) {
    // Desktop switches slide like macOS Spaces: a copy of the old desktop slides out
    // while the new one, with its own wallpaper, slides in. The Dock stays put.
    if (swap && !reduceMotion.matches) {
      desk.parentElement.querySelectorAll(".desk-ghost").forEach((g) => g.remove());
      const ghost = desk.cloneNode(true);
      ghost.removeAttribute("data-desk");
      ghost.classList.remove("slide-in");
      ghost.classList.add("desk-ghost");
      ghost.querySelectorAll("[data-win]").forEach((el) => el.removeAttribute("data-win"));
      ghost.style.setProperty("--dir", swap);
      desk.before(ghost);
      setTimeout(() => ghost.remove(), 700);
    }
    const order = state.order[state.desk];
    desk.dataset.wall = String(state.desk);
    desk.innerHTML = windowsHere().map((w) => {
      const z = order.length - order.indexOf(w.id);
      return `<div class="win${order[0] === w.id ? " is-front" : ""}" data-win="${w.id}" data-app="${w.app}"
        style="z-index:${z}">${windowInner(w)}</div>`;
    }).join("");
    const front = mru()[0];
    const app = front ? front.app : "finder";
    frontApp.textContent = APPS[app].name;
    menus.innerHTML = MENUS[app].map((m) => `<span>${m}</span>`).join("");
    if (swap && !reduceMotion.matches) {
      desk.style.setProperty("--dir", swap);
      desk.classList.remove("slide-in");
      void desk.offsetWidth;
      desk.classList.add("slide-in");
    }
  }

  // A macOS-style HUD for desktop changes: a three-finger trackpad swipe, then which
  // desktop you are on.
  let swipeTimer = 0;
  function showSwipe(n, dir) {
    clearTimeout(swipeTimer);
    swipeHud.querySelector("[data-swipe-label]").textContent = `Desktop ${n}`;
    swipeHud.querySelectorAll("[data-swipe-dot]").forEach((d) => d.classList.toggle("on", Number(d.dataset.swipeDot) === n));
    swipeHud.style.setProperty("--dir", dir);
    swipeHud.hidden = false;
    swipeHud.classList.remove("go");
    void swipeHud.offsetWidth;
    swipeHud.classList.add("go");
    swipeTimer = setTimeout(() => { swipeHud.hidden = true; }, 1700);
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
        aria-label="${label}" aria-expanded="false" aria-controls="demo-preview">
        ${iconMarkup(key)}<span class="dots" aria-hidden="true">${"<i></i>".repeat(count)}</span></button></li>`;
    };
    dock.innerHTML = pins.map(button).join("") +
      (running.length ? `<li class="dock-sep" aria-hidden="true"></li>` : "") +
      running.map(button).join("");
  }

  // ----- Focus a window -----
  function focusWindow(id) {
    const w = byId(id);
    if (!w) return;
    const order = state.order[state.desk];
    order.splice(order.indexOf(id), 1);
    order.unshift(id);
    closeAll();
    renderDesk();
    const el = desk.querySelector(`[data-win="${id}"]`);
    if (el && !reduceMotion.matches) el.classList.add("flash");
    const name = APPS[w.app].name;
    const others = windowsHere().filter((x) => x.app === w.app && x.id !== id).length;
    const rest = others === 0 ? "" : others === 1
      ? ` Your other ${name} window stays where it was.`
      : ` Your other ${others} ${name} windows stay where they were.`;
    say(`“${w.title}” is now in front.${rest}`);
  }

  // ----- Switcher -----
  function openSwitcher(direction = 1) {
    closePreview();
    const list = mru();
    if (!list.length) { say("No windows on this desktop to switch to."); return; }
    state.mode = "switcher";
    state.sel = list.length > 1 ? (direction < 0 ? list.length - 1 : 1) : 0;
    switcher.hidden = false;
    renderTiles();
  }

  function renderTiles() {
    const list = mru();
    tilesEl.innerHTML = list.map((w, i) =>
      `<li><button type="button" class="tile" data-tile="${w.id}" aria-current="${i === state.sel}"
        aria-label="${APPS[w.app].name}: ${w.title}">${miniMarkup(w)}${iconMarkup(w.app)}<span class="name">${w.title}</span></button></li>`
    ).join("");
    const w = list[state.sel];
    say(`Every window gets its own tile. “${w.title}” (${APPS[w.app].name}) is selected.`);
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
  }

  // ----- Previews -----
  let hoverTimer = 0;
  let leaveTimer = 0;

  function openPreview(appKey, { announce = true, intro = false } = {}) {
    closeSwitcher();
    const btn = dock.querySelector(`[data-app="${appKey}"]`);
    if (!btn) return;
    state.mode = "preview";
    state.previewApp = appKey;
    state.intro = intro;
    dock.querySelectorAll(".dock-btn").forEach((b) => b.setAttribute("aria-expanded", String(b === btn)));
    const wins = windowsHere().filter((w) => w.app === appKey);
    const name = APPS[appKey].name;
    preview.setAttribute("role", "group");
    preview.setAttribute("aria-label", `${name} window previews`);
    preview.classList.toggle("is-intro", intro);
    preview.innerHTML = (intro ? `<p class="pv-hint" aria-hidden="true">${plural(wins.length, `${name} window`)}. Pick one.</p>` : "") +
      (wins.length
        ? wins.map((w) => `<div class="pv${intro && w.id === INTRO_PICK ? " is-pick" : ""}">
          <span class="pv-lights"><button type="button" data-close="${w.id}" aria-label="Close ${name} window “${w.title}”"></button><i></i><i></i></span>
          <button type="button" class="pv-shot" data-focus="${w.id}" aria-label="Focus ${name} window “${w.title}”">${miniMarkup(w)}</button>
          <span class="pv-name">${w.title}</span></div>`).join("")
        : `<p class="pv-empty">No open windows on this desktop</p>`);
    preview.hidden = false;
    placePreview(btn);
    if (intro) say(INTRO_TEXT);
    else if (announce) {
      say(wins.length
        ? `${name} has ${plural(wins.length, "window")} here. Click one to bring up just that window.`
        : `No ${name} windows on this desktop.`);
    }
  }

  // Centre over the icon, keep inside the screen, sit just above the Dock. Uses
  // layout offsets, so the hero's entrance transform cannot skew the position.
  function placePreview(btn) {
    const width = preview.offsetWidth;
    const half = width / 2;
    const room = mac.clientWidth;
    const center = dockWrap.offsetLeft + btn.offsetLeft + btn.offsetWidth / 2;
    const left = Math.min(Math.max(center, half + 8), Math.max(half + 8, room - half - 8));
    const tail = Math.min(Math.max(center - left + half, 22), Math.max(22, width - 22));
    preview.style.left = `${left}px`;
    preview.style.bottom = `${Math.max(mac.clientHeight - dockWrap.offsetTop - dock.offsetTop + 14, 0)}px`;
    preview.style.setProperty("--tail", `${tail}px`);
  }

  function replacePreview() {
    if (state.mode !== "preview") return;
    const b = dock.querySelector(`[data-app="${state.previewApp}"]`);
    if (b) placePreview(b);
  }

  function closePreview() {
    clearTimeout(hoverTimer);
    clearTimeout(leaveTimer);
    peek(null);
    if (state.mode !== "preview") return;
    state.mode = "idle";
    state.previewApp = null;
    state.intro = false;
    preview.hidden = true;
    preview.innerHTML = "";
    preview.classList.remove("is-intro");
    dock.querySelectorAll(".dock-btn").forEach((b) => b.setAttribute("aria-expanded", "false"));
  }

  // Outlines the desk window a preview stands for, so the mapping is visible.
  function peek(id) {
    desk.querySelectorAll(".peek").forEach((el) => el.classList.remove("peek"));
    if (id) desk.querySelector(`[data-win="${id}"]`)?.classList.add("peek");
  }

  function closeWindow(id) {
    const w = byId(id);
    if (!w) return;
    const app = w.app;
    state.windows[state.desk] = windowsHere().filter((x) => x.id !== id);
    state.order[state.desk] = state.order[state.desk].filter((x) => x !== id);
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
    say(left
      ? `Closed “${w.title}”. ${APPS[app].name} now shows ${plural(left, "dot")}, one per window.`
      : `Closed “${w.title}”. ${APPS[app].name} has no windows left here, so it leaves this Dock.`);
  }

  function closeAll() { closeSwitcher(); closePreview(); }

  // ----- Desktops -----
  function setDesk(n, { hud = true } = {}) {
    if (n === state.desk) return;
    closeAll();
    const dir = n > state.desk ? 1 : -1;
    if (hud) showSwipe(n, dir);
    state.desk = n;
    renderDesk({ swap: dir });
    renderDock({ animate: true });
    const { running } = dockApps();
    const names = running.map((a) => APPS[a].name);
    const list = names.length > 1 ? `${names.slice(0, -1).join(", ")} and ${names.at(-1)}` : names[0];
    say(`Desktop ${n} has its own Dock: ${list ? `just ${list}` : "only your pinned apps"}. Finder and DogBar stay on every Dock.`);
  }

  function showIntro() {
    if (state.desk === 1 && byId(INTRO_PICK)) openPreview(INTRO_APP, { intro: true });
  }

  // Restores the opening scenario. Never moves focus.
  function reset() {
    closeAll();
    state.windows = initialWindows();
    state.order = initialOrder();
    state.desk = 1;
    renderDesk();
    renderDock();
    showIntro();
  }

  // Letting go of Option brings the selected window forward.
  function releaseSwitcher({ focus = true } = {}) {
    const w = mru()[state.sel];
    if (w) focusWindow(w.id);
    if (focus) stage.focus({ preventScroll: true });
  }

  // ----- Events -----
  tilesEl.addEventListener("click", (e) => {
    const t = e.target.closest("[data-tile]");
    if (t) { focusWindow(t.dataset.tile); stage.focus({ preventScroll: true }); }
  });

  desk.addEventListener("click", (e) => {
    const w = e.target.closest("[data-win]");
    if (w) focusWindow(w.dataset.win);
  });

  dock.addEventListener("click", (e) => {
    const b = e.target.closest(".dock-btn");
    if (!b) return;
    const key = b.dataset.app;
    if (state.mode === "preview" && state.previewApp === key && !state.intro) { closePreview(); return; }
    openPreview(key);
    if (e.detail === 0) preview.querySelector("button")?.focus();
  });

  // Hover previews for mouse pointers only; touch and keyboard use click.
  dock.addEventListener("pointerover", (e) => {
    if (e.pointerType !== "mouse" || tour.playing) return;
    const b = e.target.closest(".dock-btn");
    if (!b) return;
    clearTimeout(leaveTimer);
    clearTimeout(hoverTimer);
    if (!windowsHere().some((w) => w.app === b.dataset.app)) { closePreview(); return; }
    if (state.mode === "switcher") return;
    hoverTimer = setTimeout(() => {
      if (state.previewApp !== b.dataset.app) openPreview(b.dataset.app);
    }, 140);
  });
  const scheduleLeave = (e) => {
    if (e.pointerType !== "mouse") return;
    clearTimeout(hoverTimer);
    if (state.mode !== "preview" || state.intro || tour.playing) return;
    const to = e.relatedTarget;
    if (to && (dock.contains(to) || preview.contains(to))) return;
    leaveTimer = setTimeout(() => {
      if (!preview.contains(document.activeElement)) closePreview();
    }, 320);
  };
  dock.addEventListener("pointerout", scheduleLeave);
  preview.addEventListener("pointerout", scheduleLeave);
  preview.addEventListener("pointerover", () => clearTimeout(leaveTimer));

  const peekFrom = (e) => peek(e.target.closest("[data-focus]")?.dataset.focus || null);
  preview.addEventListener("pointerover", peekFrom);
  preview.addEventListener("focusin", peekFrom);
  preview.addEventListener("pointerleave", () => peek(null));
  preview.addEventListener("focusout", () => peek(null));

  preview.addEventListener("click", (e) => {
    const close = e.target.closest("[data-close]");
    if (close) { closeWindow(close.dataset.close); return; }
    const focus = e.target.closest("[data-focus]");
    if (focus) {
      const appKey = state.previewApp;
      focusWindow(focus.dataset.focus);
      dock.querySelector(`[data-app="${appKey}"]`)?.focus();
    }
  });

  // Keys are handled only while focus is inside the demo, never globally. Like the
  // real thing: hold Option and tap Tab (Shift goes back), let go of Option to switch.
  stage.addEventListener("keydown", (e) => {
    if (e.key === "Tab" && e.altKey) {
      if (state.mode === "switcher") stepSwitcher(e.shiftKey ? -1 : 1);
      else openSwitcher(e.shiftKey ? -1 : 1);
      e.preventDefault();
    } else if (e.key === "Escape" && state.mode !== "idle") {
      const appKey = state.previewApp;
      const wasSwitcher = state.mode === "switcher";
      closeAll();
      say(wasSwitcher ? "Closed the switcher. Nothing changed." : "Closed the preview.");
      if (wasSwitcher) stage.focus({ preventScroll: true });
      else dock.querySelector(`[data-app="${appKey}"]`)?.focus();
      e.preventDefault();
    } else if (state.mode === "switcher" && (e.key === "ArrowRight" || e.key === "ArrowLeft")) {
      stepSwitcher(e.key === "ArrowRight" ? 1 : -1);
      e.preventDefault();
    } else if (state.mode === "switcher" && e.key === "Enter") {
      releaseSwitcher();
      e.preventDefault();
    }
  });
  stage.addEventListener("keyup", (e) => {
    if (e.key === "Alt" && state.mode === "switcher") releaseSwitcher();
  });

  // Click outside the demo dismisses overlays, except the opening example.
  document.addEventListener("pointerdown", (e) => {
    if (state.mode !== "idle" && !state.intro && !stage.contains(e.target)) closeAll();
  });

  window.addEventListener("resize", replacePreview);
  if ("ResizeObserver" in window) {
    const ro = new ResizeObserver(replacePreview);
    ro.observe(mac);
    ro.observe(dock);
  }

  renderDesk();
  renderDock();
  showIntro();

  // ---------- Guided tour ----------
  // Plays the three ideas with a pointer, a swipe HUD and a camera that zooms in. It uses
  // the same functions as the hands-on demo, never moves focus, and stops for good as
  // soon as someone uses the demo. It starts only while the demo is on screen and never
  // on its own under reduced motion.
  const cam = $("[data-cam]");
  const pointer = $("[data-cursor]");
  const keys = $("[data-keys]");
  const tourBtn = $("[data-tour-toggle]");
  const tourSteps = [...document.querySelectorAll("[data-tour-step]")];
  const tour = { run: 0, scene: 0, playing: false, userTook: false };
  const STOP = Symbol("tour stopped");

  // Centre of an element in the camera's own (unzoomed) coordinates. Layout offsets
  // ignore transforms, so the preview's translateX(-50%) is corrected by hand.
  function spot(el, { bottom = false } = {}) {
    let x = el.offsetWidth / 2;
    let y = bottom ? el.offsetHeight : el.offsetHeight / 2;
    for (let n = el; n && n !== cam; n = n.offsetParent) { x += n.offsetLeft; y += n.offsetTop; }
    if (preview.contains(el)) x -= preview.offsetWidth / 2;
    return { x, y };
  }
  function zoom(scale, el, opts) {
    if (scale === 1 || !el) { cam.style.transform = ""; return; }
    const p = spot(el, opts);
    cam.style.transformOrigin = `${p.x}px ${p.y}px`;
    cam.style.transform = `scale(${scale})`;
  }
  // Zoom as far as asked, but never so far that the element spills off a narrow screen.
  const fit = (scale, el) => (el.offsetWidth ? Math.max(1, Math.min(scale, (cam.clientWidth * 0.94) / el.offsetWidth)) : scale);
  const point = (el) => {
    const p = spot(el);
    pointer.style.transform = `translate(${p.x}px, ${p.y}px)`;
  };
  function press() {
    pointer.classList.remove("press");
    void pointer.offsetWidth;
    pointer.classList.add("press");
  }

  const SCENES = [
    // One window on screen: the Lisbon day plan. Its sibling, the hotel booking, is
    // one hover away in Safari's Dock previews.
    { ms: 7600, run: async (wait) => {
      reset();
      closeAll();
      say("Safari has two windows open, but you can only see one. Hover Safari in the Dock to see both.");
      point(desk);
      pointer.classList.add("is-on");
      await wait(1100);
      point(dock.querySelector('[data-app="safari"]'));
      await wait(1000);
      zoom(fit(1.55, dock), dock, { bottom: true });
      openPreview("safari");
      await wait(1500);
      const shot = preview.querySelector('[data-focus="s2"]');
      if (shot) { point(shot); peek("s2"); }
      await wait(1300);
      press();
      focusWindow("s2");
      zoom(1);
      await wait(2700);
    } },
    // Option+Tab over a single window: step to the Slack chat, let go, and it replaces
    // the hotel booking on screen.
    { ms: 5600, run: async (wait) => {
      closeAll();
      if (state.desk !== 1) setDesk(1, { hud: false });
      pointer.classList.remove("is-on");
      keys.hidden = false;
      openSwitcher();
      zoom(1.2, switcher);
      await wait(1500);
      stepSwitcher(1);
      await wait(2400);
      keys.hidden = true;
      releaseSwitcher({ focus: false });
      zoom(1);
      await wait(1700);
    } },
    // A three-finger swipe to Desktop 2, then a close look at its Dock, and back.
    { ms: 9200, run: async (wait) => {
      closeAll();
      if (state.desk !== 1) setDesk(1, { hud: false });
      pointer.classList.remove("is-on");
      say("Swipe to another desktop and the Dock changes to match.");
      await wait(400);
      showSwipe(2, 1);
      await wait(700);
      setDesk(2, { hud: false });
      await wait(700);
      zoom(fit(1.8, dock), dock, { bottom: true });
      await wait(2600);
      zoom(1);
      await wait(900);
      showSwipe(1, -1);
      await wait(700);
      setDesk(1, { hud: false });
      await wait(700);
      zoom(fit(1.8, dock), dock, { bottom: true });
      await wait(2000);
      zoom(1);
      await wait(500);
    } },
  ];

  function markStep(i) {
    tourSteps.forEach((b, n) => {
      b.classList.remove("is-active");
      void b.offsetWidth; // restart the progress fill
      b.classList.toggle("is-active", n === i);
      b.classList.toggle("is-done", n < i);
      b.style.setProperty("--dur", `${SCENES[n].ms}ms`);
      if (n === i) b.setAttribute("aria-current", "step");
      else b.removeAttribute("aria-current");
    });
  }

  function setTouring(on) {
    tour.playing = on;
    stage.dataset.tour = on ? "playing" : "stopped";
    caption.setAttribute("aria-live", on ? "off" : "polite"); // no running commentary for screen readers
    tourBtn.setAttribute("aria-label", on ? "Pause the demo" : "Play the demo");
    if (!on) {
      zoom(1);
      pointer.classList.remove("is-on", "press");
      keys.hidden = true;
      swipeHud.hidden = true;
      peek(null);
    }
  }

  async function playTour(from = tour.scene) {
    const id = ++tour.run;
    const wait = (ms) => new Promise((resolve, reject) =>
      setTimeout(() => (id === tour.run ? resolve() : reject(STOP)), ms));
    setTouring(true);
    try {
      for (let i = from; ; i = (i + 1) % SCENES.length) {
        tour.scene = i;
        markStep(i);
        await SCENES[i].run(wait);
      }
    } catch (err) {
      if (err !== STOP) throw err;
    }
  }

  function stopTour({ byUser = false } = {}) {
    if (byUser) tour.userTook = true;
    if (!tour.playing) return;
    tour.run++;
    setTouring(false);
  }

  tourBtn.addEventListener("click", () => {
    if (tour.playing) stopTour({ byUser: true });
    else { tour.userTook = false; playTour(); }
  });
  tourSteps.forEach((b) => b.addEventListener("click", () => {
    tour.userTook = false;
    playTour(Number(b.dataset.tourStep));
  }));
  // "Watch the demo" links scroll to the demo and play it from the start.
  document.querySelectorAll("[data-demo-start]").forEach((a) => a.addEventListener("click", () => {
    tour.userTook = false;
    playTour(0);
  }));

  // Any hands-on use of the demo ends the tour; the tour's own buttons do not.
  const takeOver = (e) => {
    if (!e.target.closest(".tour")) stopTour({ byUser: true });
  };
  stage.addEventListener("pointerdown", takeOver, true);
  stage.addEventListener("keydown", takeOver, true);
  stage.addEventListener("focusin", takeOver);

  // Autoplay waits a moment after the demo comes into view, and pauses when it leaves.
  if ("IntersectionObserver" in window) {
    let inView = false;
    new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting;
      if (!inView) { if (tour.playing) stopTour(); return; }
      setTimeout(() => {
        if (inView && !tour.playing && !tour.userTook && !reduceMotion.matches) playTour();
      }, 700);
    }, { threshold: 0.5 }).observe(stage);
  }
  setTouring(false);
})();
