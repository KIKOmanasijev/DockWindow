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
  const spaces = document.querySelectorAll("[data-space]");
  const tabBtn = $("[data-tab]");
  const releaseBtn = $("[data-release]");
  const resetBtn = $("[data-reset]");
  const deskBtns = document.querySelectorAll("[data-desk-btn]");
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
  const INTRO_TEXT = "Planning a trip: Safari has two windows open. Pick “Hotel booking” to bring just that one forward.";

  // Positions are percentages of the desk. `view` picks the window's content.
  const initialWindows = () => ({
    1: [
      { id: "s1", app: "safari", view: "trip", title: "Lisbon day plan", url: "wanderly.travel", x: 7, y: 27, w: 47, h: 56 },
      { id: "s2", app: "safari", view: "booking", title: "Hotel booking", url: "casaluz-stays.travel", x: 40, y: 6, w: 37, h: 56 },
      { id: "k1", app: "slack", view: "slack", title: "#lisbon-trip", x: 2, y: 4, w: 40, h: 44 },
      { id: "n1", app: "notes", view: "notes", title: "Packing list", x: 73, y: 17, w: 25, h: 56 },
    ],
    2: [
      { id: "s3", app: "safari", view: "hike", title: "Sunday hike", url: "trailmap.travel", x: 4, y: 8, w: 52, h: 64 },
      { id: "m1", app: "music", view: "music", title: "Up Next", x: 48, y: 19, w: 46, h: 56 },
    ],
  });
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
  const barMarkup = (w) =>
    `<span class="win-bar"><span class="lights"><i></i><i></i><i></i></span>${
      w.url ? `<span class="addr">${w.url}</span>` : `<span class="t">${w.title}</span>`}</span>`;
  const windowInner = (w) => `${barMarkup(w)}<span class="win-body">${VIEWS[w.view]}</span>`;
  const miniMarkup = (w) => `<span class="mini" data-app="${w.app}">${windowInner(w)}</span>`;

  // ----- Desk -----
  function renderDesk({ swap = 0 } = {}) {
    const order = state.order[state.desk];
    desk.innerHTML = windowsHere().map((w) => {
      const z = order.length - order.indexOf(w.id);
      return `<div class="win${order[0] === w.id ? " is-front" : ""}" data-win="${w.id}" data-app="${w.app}"
        style="left:${w.x}%;top:${w.y}%;width:${w.w}%;height:${w.h}%;z-index:${z}">${windowInner(w)}</div>`;
    }).join("");
    const front = mru()[0];
    frontApp.textContent = front ? APPS[front.app].name : "Finder";
    spaces.forEach((el) => el.classList.toggle("on", Number(el.dataset.space) === state.desk));
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
        aria-label="${label}" aria-expanded="false" aria-controls="demo-preview">
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
    const name = APPS[w.app].name;
    const others = windowsHere().filter((x) => x.app === w.app && x.id !== id).length;
    const rest = others === 0 ? "" : others === 1
      ? ` The other ${name} window stayed where it was.`
      : ` The other ${others} ${name} windows stayed where they were.`;
    say(`${how}: ${name}, “${w.title}”, is in front.${rest}`);
  }

  // ----- Switcher -----
  function openSwitcher() {
    closePreview();
    const list = mru();
    if (!list.length) { say("No windows on this desktop to switch to."); return; }
    state.mode = "switcher";
    state.sel = list.length > 1 ? 1 : 0;
    switcher.hidden = false;
    tabBtn.innerHTML = '<kbd aria-hidden="true">⇥</kbd> Tab again';
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
    tabBtn.innerHTML = '<kbd aria-hidden="true">⌥</kbd> Option+Tab';
    releaseBtn.hidden = true;
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
        ? `${name} previews: ${plural(wins.length, "window")}. Pick one to bring exactly that window forward.`
        : `${name} is pinned here with no windows on this desktop.`);
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
    const list = running.map((a) => `${APPS[a].name} (${plural(windowsHere().filter((w) => w.app === a).length, "dot")})`);
    say(`Desktop ${n} has its own Dock: ${list.join(", ") || "only pins"}. Finder and DogBar stay pinned.`);
  }

  function showIntro() {
    if (state.desk === 1 && byId(INTRO_PICK)) openPreview(INTRO_APP, { intro: true });
  }

  // Restores the opening scenario. Only a person pressing Reset gets focus moved.
  function reset({ focus = true } = {}) {
    closeAll();
    state.windows = initialWindows();
    state.order = initialOrder();
    resetBtn.hidden = true;
    if (state.desk !== 1) {
      state.desk = 1;
      deskBtns.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.deskBtn === "1")));
    }
    renderDesk();
    renderDock();
    showIntro();
    if (focus) tabBtn.focus();
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
  resetBtn.addEventListener("click", () => reset());

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

  // "Try the demo" links land focus on the first demo control.
  document.querySelectorAll("[data-demo-start]").forEach((a) => a.addEventListener("click", () => {
    setTimeout(() => tabBtn.focus({ preventScroll: true }), reduceMotion.matches ? 0 : 450);
  }));

  renderDesk();
  renderDock();
  showIntro();

  // ---------- Guided tour ----------
  // Plays the three ideas with a pointer and a camera that zooms into the Dock. It uses
  // the same functions as the hands-on demo, never moves focus, and stops for good as
  // soon as someone uses the demo. It starts only while the demo is on screen and never
  // on its own under reduced motion.
  const cam = $("[data-cam]");
  const pointer = $("[data-cursor]");
  const keys = $("[data-keys]");
  const tourBtn = $("[data-tour-toggle]");
  const tourLabel = $("[data-tour-label]");
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
    { ms: 7600, run: async (wait) => {
      reset({ focus: false });
      closeAll();
      say("Safari has two windows open: a day plan and a hotel booking. Watch the Dock.");
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
      focusWindow("s2", "Picked from the preview");
      zoom(1);
      await wait(2700);
    } },
    { ms: 5600, run: async (wait) => {
      closeAll();
      if (state.desk !== 1) setDesk(1);
      pointer.classList.remove("is-on");
      keys.hidden = false;
      openSwitcher();
      zoom(1.2, switcher);
      await wait(1500);
      stepSwitcher(1);
      await wait(1300);
      stepSwitcher(-1);
      await wait(1100);
      const w = mru()[state.sel];
      keys.hidden = true;
      if (w) focusWindow(w.id, "Released Option");
      zoom(1);
      await wait(1700);
    } },
    { ms: 8200, run: async (wait) => {
      closeAll();
      if (state.desk !== 1) setDesk(1);
      point(desk);
      pointer.classList.add("is-on");
      say("Each desktop keeps its own Dock. Switching to Desktop 2.");
      await wait(500);
      point($('[data-space="2"]'));
      await wait(1100);
      press();
      setDesk(2);
      zoom(fit(1.8, dock), dock, { bottom: true });
      await wait(3000);
      setDesk(1);
      await wait(2600);
      zoom(1);
      await wait(1000);
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
    tourLabel.textContent = on ? "Pause tour" : "Play tour";
    if (!on) {
      zoom(1);
      pointer.classList.remove("is-on", "press");
      keys.hidden = true;
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
