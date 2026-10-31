// DogBar landing: the hero demo (a looping, video-like walkthrough) and scroll reveals.
// No dependencies.
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
  // A short walkthrough that plays like a video: no clicks or keys inside the screen,
  // just chapters and play/pause underneath. The scenario is a fictional weekend trip:
  // Safari holds a Lisbon day plan and a hotel booking, next to a Slack chat with
  // friends and a Notes packing list. Desktop 2 is a quiet Sunday. All content is made up.
  const mac = document.querySelector("[data-demo]");
  if (!mac) return;

  const $ = (sel) => document.querySelector(sel);
  const cam = $("[data-cam]");
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
  const pointer = $("[data-cursor]");
  const keys = $("[data-keys]");
  const stage = $("#demo");
  const playBtn = $("[data-tour-toggle]");
  const chapters = [...document.querySelectorAll("[data-tour-step]")];

  const APPS = {
    finder: { name: "Finder", img: "assets/apps/finder.png" },
    dockwindow: { name: "DogBar", img: "assets/dog-96.png" },
    safari: { name: "Safari", img: "assets/apps/safari.png" },
    slack: { name: "Slack", img: "assets/apps/slack.png" },
    notes: { name: "Notes", img: "assets/apps/notes.png" },
    music: { name: "Music", img: "assets/apps/music.png" },
  };
  const PINS = ["finder", "dockwindow"];
  const INTRO_TEXT = "Safari has two windows open, but you can only see one. DogBar’s Dock preview shows both.";

  // Only the front window is shown on the desk, so every change reads at a glance.
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
  // Front-to-back window order per desktop.
  const initialOrder = () => ({ 1: ["s1", "s2", "k1", "n1"], 2: ["m1", "s3"] });
  // The front app's menus, as macOS shows them.
  const MENUS = {
    finder: ["File", "Edit", "View", "Go", "Window", "Help"],
    safari: ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"],
    slack: ["File", "Edit", "View", "Go", "Window", "Help"],
    notes: ["File", "Edit", "Format", "View", "Window", "Help"],
    music: ["File", "Edit", "Song", "View", "Controls", "Window", "Help"],
  };

  const state = { desk: 1, windows: initialWindows(), order: initialOrder(), mode: "idle", sel: 0, previewApp: null };

  const windowsHere = () => state.windows[state.desk];
  const byId = (id) => windowsHere().find((w) => w.id === id);
  const mru = () => state.order[state.desk].map(byId).filter(Boolean);
  const say = (text) => { caption.textContent = text; };
  const iconMarkup = (appKey, cls = "ic") =>
    `<img class="${cls}" src="${APPS[appKey].img}" width="96" height="96" alt="" draggable="false">`;

  // Window content. The same markup renders on the desk, in previews and in tiles.
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

  // Title bar: Safari shows its toolbar and address field, other apps their window title.
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
      cam.querySelectorAll(".desk-ghost").forEach((g) => g.remove());
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
    desk.innerHTML = windowsHere().map((w) =>
      `<div class="win${order[0] === w.id ? " is-front" : ""}" data-win="${w.id}" data-app="${w.app}"
        style="z-index:${order.length - order.indexOf(w.id)}">${windowInner(w)}</div>`).join("");
    const app = mru()[0]?.app || "finder";
    frontApp.textContent = APPS[app].name;
    menus.innerHTML = MENUS[app].map((m) => `<span>${m}</span>`).join("");
    if (swap && !reduceMotion.matches) {
      desk.style.setProperty("--dir", swap);
      desk.classList.remove("slide-in");
      void desk.offsetWidth;
      desk.classList.add("slide-in");
    }
  }

  // A macOS-style HUD for desktop changes: which way you swiped, and where you are.
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

  // ----- Dock: pinned apps, a divider, then apps with windows here; one dot each -----
  function dockApps() {
    const running = [];
    for (const w of windowsHere()) if (!running.includes(w.app) && !PINS.includes(w.app)) running.push(w.app);
    return running;
  }
  function renderDock({ animate = false } = {}) {
    const running = dockApps();
    const item = (key) => {
      const count = windowsHere().filter((w) => w.app === key).length;
      return `<li><span class="dock-btn${animate && !PINS.includes(key) ? " enter" : ""}" data-app="${key}">
        ${iconMarkup(key)}<span class="dots">${"<i></i>".repeat(count)}</span></span></li>`;
    };
    dock.innerHTML = PINS.map(item).join("") +
      (running.length ? `<li class="dock-sep"></li>` : "") + running.map(item).join("");
  }

  // ----- Bring one window to the front -----
  function focusWindow(id) {
    const w = byId(id);
    if (!w) return;
    const order = state.order[state.desk];
    order.splice(order.indexOf(id), 1);
    order.unshift(id);
    closeAll();
    renderDesk();
    if (!reduceMotion.matches) desk.querySelector(`[data-win="${id}"]`)?.classList.add("flash");
    const others = windowsHere().filter((x) => x.app === w.app && x.id !== id).length;
    say(`“${w.title}” is now in front.${others ? ` Your other ${APPS[w.app].name} window stays where it was.` : ""}`);
  }

  // ----- Switcher: one tile per window -----
  function openSwitcher() {
    closePreview();
    state.mode = "switcher";
    state.sel = mru().length > 1 ? 1 : 0;
    switcher.hidden = false;
    renderTiles();
  }
  function renderTiles() {
    const list = mru();
    tilesEl.innerHTML = list.map((w, i) =>
      `<li><span class="tile${i === state.sel ? " is-sel" : ""}" data-tile="${w.id}">${miniMarkup(w)}${iconMarkup(w.app)}<span class="name">${w.title}</span></span></li>`
    ).join("");
    const w = list[state.sel];
    say(`Every window gets its own tile. “${w.title}” (${APPS[w.app].name}) is selected.`);
  }
  function stepSwitcher(delta) {
    const n = mru().length;
    state.sel = (state.sel + delta + n) % n;
    renderTiles();
  }
  function releaseSwitcher() {
    const w = mru()[state.sel];
    if (w) focusWindow(w.id);
  }
  function closeSwitcher() {
    if (state.mode !== "switcher") return;
    state.mode = "idle";
    switcher.hidden = true;
    tilesEl.innerHTML = "";
  }

  // ----- Dock previews -----
  function openPreview(appKey, { hint = false } = {}) {
    closeSwitcher();
    const icon = dock.querySelector(`[data-app="${appKey}"]`);
    if (!icon) return;
    state.mode = "preview";
    state.previewApp = appKey;
    dock.querySelectorAll(".dock-btn").forEach((b) => b.classList.toggle("is-open", b === icon));
    const wins = windowsHere().filter((w) => w.app === appKey);
    const name = APPS[appKey].name;
    preview.innerHTML = (hint ? `<p class="pv-hint">${wins.length} ${name} windows</p>` : "") +
      wins.map((w) => `<div class="pv">
        <span class="pv-lights"><i></i><i></i><i></i></span>
        <span class="pv-shot" data-focus="${w.id}">${miniMarkup(w)}</span>
        <span class="pv-name">${w.title}</span></div>`).join("");
    preview.hidden = false;
    mac.classList.add("is-focus");
    placePreview(icon);
    say(`${name} has ${wins.length} windows here. Pick the one you want.`);
  }
  // The pointer resting on a preview: highlight it, but nothing changes on screen yet.
  function hoverPreview(id) {
    preview.querySelectorAll(".pv").forEach((pv) => pv.classList.toggle("is-hover", pv.querySelector(`[data-focus="${id}"]`) !== null));
  }
  // Centre over the icon, keep inside the screen, sit just above the Dock. Uses layout
  // offsets, so entrance transforms cannot skew the position.
  function placePreview(icon) {
    const width = preview.offsetWidth;
    const half = width / 2;
    const room = mac.clientWidth;
    const center = dockWrap.offsetLeft + icon.offsetLeft + icon.offsetWidth / 2;
    const left = Math.min(Math.max(center, half + 8), Math.max(half + 8, room - half - 8));
    const tail = Math.min(Math.max(center - left + half, 22), Math.max(22, width - 22));
    preview.style.left = `${left}px`;
    preview.style.bottom = `${Math.max(mac.clientHeight - dockWrap.offsetTop - dock.offsetTop + 14, 0)}px`;
    preview.style.setProperty("--tail", `${tail}px`);
  }
  function closePreview() {
    if (state.mode !== "preview") return;
    state.mode = "idle";
    state.previewApp = null;
    preview.hidden = true;
    preview.innerHTML = "";
    mac.classList.remove("is-focus");
    dock.querySelectorAll(".dock-btn").forEach((b) => b.classList.remove("is-open"));
  }
  function closeAll() { closeSwitcher(); closePreview(); }

  // ----- Desktops -----
  function setDesk(n) {
    if (n === state.desk) return;
    closeAll();
    const dir = n > state.desk ? 1 : -1;
    state.desk = n;
    renderDesk({ swap: dir });
    renderDock({ animate: true });
    const names = dockApps().map((a) => APPS[a].name);
    const list = names.length > 1 ? `${names.slice(0, -1).join(", ")} and ${names.at(-1)}` : names[0];
    say(`Desktop ${n} has its own Dock: ${list ? `just ${list}` : "only your pinned apps"}. Finder and DogBar stay on every Dock.`);
  }

  // The opening frame, also the still image under reduced motion: one window, and
  // Safari's previews showing the second one.
  function reset() {
    closeAll();
    state.windows = initialWindows();
    state.order = initialOrder();
    state.desk = 1;
    renderDesk();
    renderDock();
  }
  function openingFrame() {
    reset();
    openPreview("safari", { hint: true });
    say(INTRO_TEXT);
  }

  window.addEventListener("resize", () => {
    if (state.mode === "preview") placePreview(dock.querySelector(`[data-app="${state.previewApp}"]`));
  });

  // ---------- Playback ----------
  // Scenes are scripts of steps separated by `wait`s on a play clock, so Pause freezes
  // the walkthrough mid-scene and Play resumes from the same moment.
  const point = (el) => {
    if (!el) return;
    let x = el.offsetWidth / 2;
    let y = el.offsetHeight / 2;
    for (let n = el; n && n !== cam; n = n.offsetParent) { x += n.offsetLeft; y += n.offsetTop; }
    if (preview.contains(el)) x -= preview.offsetWidth / 2; // offsets ignore its translateX(-50%)
    pointer.style.transform = `translate(${x}px, ${y}px)`;
  };
  function press() {
    pointer.classList.remove("press");
    void pointer.offsetWidth;
    pointer.classList.add("press");
  }

  const SCENES = [
    // Only the day plan is on screen. Hover Safari, the previews show both windows,
    // the pointer settles on "Hotel booking", and only the click brings it forward.
    { ms: 7800, run: async (wait) => {
      reset();
      say("Safari has two windows open, but you can only see one.");
      point(desk);
      pointer.classList.add("is-on");
      await wait(1200);
      point(dock.querySelector('[data-app="safari"]'));
      await wait(900);
      openPreview("safari");
      await wait(1400);
      point(preview.querySelector('[data-focus="s2"]'));
      await wait(800);
      hoverPreview("s2");
      await wait(900);
      press();
      await wait(200);
      focusWindow("s2");
      await wait(2400);
    } },
    // Option+Tab over the hotel booking: step to the Slack chat, let go, Slack is in front.
    { ms: 5600, run: async (wait) => {
      closeAll();
      if (state.desk !== 1) setDesk(1);
      pointer.classList.remove("is-on");
      keys.hidden = false;
      openSwitcher();
      await wait(1500);
      stepSwitcher(1);
      await wait(2400);
      keys.hidden = true;
      releaseSwitcher();
      await wait(1700);
    } },
    // A swipe to Desktop 2 and back. The Dock visibly changes with the desktop.
    { ms: 7000, run: async (wait) => {
      closeAll();
      if (state.desk !== 1) setDesk(1);
      pointer.classList.remove("is-on");
      say("Swipe to another desktop and the Dock changes to match.");
      await wait(400);
      showSwipe(2, 1);
      await wait(700);
      setDesk(2);
      await wait(2900);
      showSwipe(1, -1);
      await wait(700);
      setDesk(1);
      await wait(2300);
    } },
  ];

  const STOP = Symbol("stopped");
  const player = { run: 0, scene: 0, playing: false, pausedByUser: false, timer: null };

  // Waits `ms` of playing time. Pausing banks the time left; playing spends the rest.
  function clockWait(id, ms) {
    return new Promise((resolve, reject) => {
      if (id !== player.run) { reject(STOP); return; } // a newer run has taken over
      let left = ms;
      let since = 0;
      let handle = 0;
      const start = () => { since = performance.now(); handle = setTimeout(() => { player.timer = null; resolve(); }, left); };
      player.timer = {
        pause() { clearTimeout(handle); left = Math.max(0, left - (performance.now() - since)); },
        resume: start,
        cancel() { clearTimeout(handle); reject(STOP); },
      };
      if (player.playing) start();
    });
  }

  function markChapter(i) {
    chapters.forEach((b, n) => {
      b.classList.remove("is-active");
      void b.offsetWidth; // restart the progress fill
      b.classList.toggle("is-active", n === i);
      b.classList.toggle("is-done", n < i);
      b.style.setProperty("--dur", `${SCENES[n].ms}ms`);
      if (n === i) b.setAttribute("aria-current", "step");
      else b.removeAttribute("aria-current");
    });
  }

  function setPlaying(on) {
    player.playing = on;
    stage.dataset.tour = on ? "playing" : "paused";
    playBtn.setAttribute("aria-label", on ? "Pause the demo" : "Play the demo");
  }

  // Starts the loop at a chapter, cancelling whatever was running.
  async function playFrom(i) {
    player.timer?.cancel();
    const id = ++player.run;
    setPlaying(true);
    try {
      for (let n = i; ; n = (n + 1) % SCENES.length) {
        player.scene = n;
        markChapter(n);
        await SCENES[n].run((ms) => clockWait(id, ms));
      }
    } catch (err) {
      if (err !== STOP) throw err;
    }
  }
  function pause() {
    if (!player.playing) return;
    setPlaying(false);
    player.timer?.pause();
  }
  function resume() {
    if (player.playing) return;
    if (!player.timer && !player.run) { playFrom(0); return; }
    setPlaying(true);
    player.timer?.resume();
  }

  playBtn.addEventListener("click", () => {
    if (player.playing) { player.pausedByUser = true; pause(); }
    else { player.pausedByUser = false; resume(); }
  });
  chapters.forEach((b) => b.addEventListener("click", () => {
    player.pausedByUser = false;
    playFrom(Number(b.dataset.tourStep));
  }));
  // "Watch the demo" links scroll here and start from the beginning.
  document.querySelectorAll("[data-demo-start]").forEach((a) => a.addEventListener("click", () => {
    player.pausedByUser = false;
    playFrom(0);
  }));

  // Plays while the demo is on screen and pauses when it scrolls away. Under reduced
  // motion it never starts by itself; the opening frame stays as a still.
  openingFrame();
  stage.dataset.tour = "idle"; // not "paused": the opening frame's own animations still run
  playBtn.setAttribute("aria-label", "Play the demo");
  if ("IntersectionObserver" in window) {
    let inView = false;
    new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting;
      if (!inView) { pause(); return; }
      setTimeout(() => {
        if (inView && !player.pausedByUser && !reduceMotion.matches) resume();
      }, 700);
    }, { threshold: 0.5 }).observe(stage);
  }
})();
