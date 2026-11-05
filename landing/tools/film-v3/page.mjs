// DogBar product film v3: the single HTML scene. window.renderAt(t) is a pure function of t.
//
// Object model (not a camera over one screen): the film is built from a few continuous objects that
// keep their identity between shots.
//   planes  two desktops (Desktop 1 / Desktop 2) as 3D planes; flat and clipped to the Mac in "real" shots
//   dock    ONE Dock object. Attached, it sits exactly where DogBar draws it on the Mac; free, it floats
//           large on the stage. It never moves sideways when a desktop changes (DogBar's Dock panel is
//           .canJoinAllSpaces + .stationary): the desktops move behind it and its icons recompose in place.
//   ui      DogBar's real panels in display points (preview, switcher, island, pointer), placed with the Mac
//   morph   a window that grows from a preview card / switcher tile into the real window (and back)
//   paper   the light stage, opened from a real shape (the Dock, the notch) and folded back into one
// Geometry is copied from DogBar's sources (cited inline). Native images (icons, island) come from the
// v2 native renderer (DogBarCore views compiled unchanged). Window content is fictional (../film/content.mjs).
import { WINDOWS, PERSONAL_WINDOWS, APP_NAMES, MENUS, sym } from '../film/content.mjs';
import { T, TYPE, DURATION } from './timeline.mjs';
import { readFileSync } from 'node:fs';

// Window content styling is shared with v2 (same fictional apps): take v2's window stylesheet verbatim.
const V2_WINDOW_CSS = (() => {
  const src = readFileSync(new URL('../film/page.mjs', import.meta.url), 'utf8');
  const a = src.indexOf('/* ---------- windows (macOS 26, dark appearance) ---------- */'), b = src.indexOf('/* ---------- menu bar ---------- */');
  if (a < 0 || b < a) throw Error('v2 window CSS markers not found');
  return src.slice(a, b).replace(/\$\{ACCENT\}/g, '#7a52e6');
})();

export const ACCENT = '#7a52e6';
const DOCKS = {
  work: ['finder', 'safari', 'mail', 'calendar', 'notes', 'terminal', 'cursor', 'settings', '|', 'trash'],
  personal: ['finder', 'safari', 'messages', 'photos', 'maps', 'calendar', 'reminders', '|', 'trash'],
};

export function buildPage({ W = 1920, H = 1080, base, native }) {
  const DATA = { W, H, T, TYPE, DURATION, DOCKS, APP_NAMES, MENUS, native, ACCENT,
    windows: WINDOWS.map(({ html, ...w }) => w), personal: PERSONAL_WINDOWS.map(({ html, ...w }) => w),
    html: Object.fromEntries([...WINDOWS, ...PERSONAL_WINDOWS].map((w) => [w.id, w.html])) };
  const win = (w) => `<div class="win ${w.cls}" data-id="${w.id}" style="left:${w.x}px;top:${w.y}px;width:${w.w}px;height:${w.h}px">${w.html}</div>`;
  const menubar = `<div class="menubar"><div class="left">${sym('applelogo', 15, '#fff', 'vertical-align:-1px')}<b class="mb-app"></b><span class="mb-menus"></span></div>
    <div class="right">${sym('battery.75percent', 24, '#fff')}${sym('wifi', 16, '#fff')}${sym('magnifyingglass', 15, '#fff')}${sym('switch.2', 16, '#fff')}<span>Thu 5 Nov&nbsp;&nbsp;16:12</span></div></div>`;
  const plane = (i, wall, wins) => `<div class="plane" id="pl${i}"><div class="pin"><img class="wall" src="assets/${wall}" alt="">${wins.map(win).join('')}${menubar}<div class="hw-notch"></div>
    <div class="pdock lg"><div class="shadow"></div><div class="mat"></div><div class="dock-icons"></div><div class="rim"></div></div><div class="pdim"></div></div><div class="ring"></div></div>`;
  const words = (s) => s.split(' ').map((w) => `<span class="w">${w}</span>`).join(' ');
  const block = (id, lines, cls = '') => `<div class="tb ${cls}" id="${id}">${lines.map((l, i) => `<div class="ln ${i === lines.length - 1 && lines.length > 1 ? 'ac' : ''}"><span class="lw">${words(l)}</span></div>`).join('')}</div>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><base href="${base}">
<style>
@font-face{font-family:"SFMonoLocal";src:url("sfmono/SF-Mono-Regular.otf")}
@font-face{font-family:"SFMonoLocal";font-weight:600;src:url("sfmono/SF-Mono-Semibold.otf")}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${W}px;height:${H}px;overflow:hidden;background:#07060b;font-family:system-ui,-apple-system;-webkit-font-smoothing:antialiased;color:#fff}
#stage{position:absolute;inset:0;overflow:hidden;background:#07060b}
#bg{position:absolute;inset:-10%;background:radial-gradient(60% 55% at 50% 62%,#2b1a63 0%,#17103a 38%,#0a0814 72%,#07060b 100%)}
#bg:after{content:"";position:absolute;inset:0;background:radial-gradient(30% 22% at 50% 92%,rgba(122,82,230,.28),transparent 70%)}
#floor{position:absolute;left:0;top:0;width:900px;height:150px;border-radius:50%;background:radial-gradient(closest-side,rgba(150,110,255,.38),rgba(122,82,230,.12) 55%,transparent);filter:blur(10px)}
#planes{position:absolute;inset:0;perspective:2400px;perspective-origin:960px 470px}
#bezel{position:absolute;border-radius:18px;box-shadow:0 0 0 1.5px #2a2a30,0 0 0 8px #0b0b0d,0 0 0 9px #2c2c33,0 50px 120px rgba(4,2,12,.6)}
.plane{position:absolute;left:0;top:0;width:1512px;height:982px;transform-origin:756px 491px}
.pin{position:absolute;inset:0;border-radius:18px;overflow:hidden;background:#000}
.plane>.ring{position:absolute;inset:0;border-radius:18px;pointer-events:none;box-shadow:0 0 0 1.5px #2a2a30,0 0 0 8px #0b0b0d,0 0 0 9px #2c2c33,0 40px 110px rgba(4,2,12,.55)}
.pin>.wall{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.pdim{position:absolute;inset:0;background:#07060b;opacity:0;pointer-events:none;z-index:95}
.sym{display:inline-block;-webkit-mask-size:contain;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;vertical-align:-2px;flex:none}
.win{position:absolute;border-radius:22px;overflow:hidden;background:#1d1d1f;color:#f2f2f7;font-size:13px;visibility:hidden;
  box-shadow:0 0 0 .5px rgba(0,0,0,.75),inset 0 0 0 .5px rgba(255,255,255,.2),0 34px 90px rgba(0,0,0,.55),0 6px 18px rgba(0,0,0,.3)}
.win.terminal,.win.cursor{border-radius:16px}
.win.shown{visibility:visible}
.menubar{position:absolute;left:0;right:0;top:0;height:32px;display:flex;align-items:center;font-size:13.5px;color:#fff;text-shadow:0 0 8px rgba(0,0,0,.35);z-index:50}
.menubar .left{display:flex;align-items:center;gap:22px;padding-left:20px}.menubar .left b{font-weight:700}.mb-menus{display:flex;gap:22px}
.menubar .right{margin-left:auto;display:flex;align-items:center;gap:18px;padding-right:18px;font-variant-numeric:tabular-nums}
.hw-notch{position:absolute;left:${756 - 94}px;top:0;width:188px;height:32px;background:#000;border-radius:0 0 12px 12px;z-index:90}
${V2_WINDOW_CSS}
/* ---- glass (DogBar Dock material, approximated) ---- */
.lg{position:absolute;overflow:visible}
.lg>.mat{position:absolute;inset:0;border-radius:inherit;overflow:hidden}
.lg>.rim{position:absolute;inset:0;border-radius:inherit;pointer-events:none;padding:.5px;-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;
  background:linear-gradient(180deg,rgba(255,255,255,.5) 0,rgba(255,255,255,.25) 3px,rgba(255,255,255,.16) 7.5px,rgba(255,255,255,.1) 16px,rgba(255,255,255,.05) 26px,rgba(255,255,255,.05) calc(100% - 26px),rgba(255,255,255,.1) calc(100% - 16px),rgba(255,255,255,.25) calc(100% - 3px),rgba(255,255,255,.5) 100%)}
.lg>.shadow{position:absolute;inset:0;border-radius:inherit;box-shadow:0 3px 10px rgba(0,0,0,.25)}
.pdock{z-index:60}.pdock .mat{backdrop-filter:blur(1.4px) saturate(1.45) brightness(.94);background:rgba(0,0,0,.06)}
#dock{position:absolute;left:0;top:0;transform-origin:0 0;z-index:40}
#dock .bgr{position:absolute;top:0}
#dock .mat{backdrop-filter:blur(1.4px) saturate(1.45) brightness(.94);background:rgba(0,0,0,.06)}
#dock .tint{position:absolute;inset:0;border-radius:inherit;background:linear-gradient(180deg,rgba(150,130,220,.30),rgba(60,40,120,.22) 55%,rgba(30,20,70,.30));box-shadow:inset 0 1px 0 rgba(255,255,255,.28),inset 0 -1px 0 rgba(255,255,255,.12)}
#dock .spec{position:absolute;inset:0;border-radius:inherit;overflow:hidden;pointer-events:none;mix-blend-mode:plus-lighter}
#dock .spec i{position:absolute;top:-20%;bottom:-20%;width:38%;background:linear-gradient(100deg,transparent 0,rgba(255,255,255,.0) 30%,rgba(255,255,255,.34) 50%,rgba(255,255,255,0) 70%,transparent)}
#dock .bshadow{position:absolute;inset:0;border-radius:inherit}
.dicon{position:absolute;width:48px;height:48px}.dicon img{width:100%;height:100%;filter:drop-shadow(0 1px 1.5px rgba(0,0,0,.28))}
.dots{position:absolute;left:0;top:0;overflow:visible;mix-blend-mode:plus-lighter}
.dsep{position:absolute;width:1px;background:rgba(255,255,255,.22)}
.dlabel{position:absolute;height:25px;padding:0 10px;border-radius:7px;background:#2c2c2e;color:#f2f2f7;font-size:13px;line-height:25px;box-shadow:0 0 0 .5px rgba(0,0,0,.6),0 4px 12px rgba(0,0,0,.35);white-space:nowrap;display:none}
#logo{position:absolute;left:0;top:0;width:200px;height:200px;transform-origin:0 0;opacity:0;z-index:41}
#logo img{width:100%;height:100%;filter:drop-shadow(0 18px 40px rgba(0,0,0,.55))}
/* ---- ui (display points) ---- */
#ui,#uitop{position:absolute;left:0;top:0;width:1512px;height:982px;transform-origin:0 0;z-index:30}#uitop{z-index:46;pointer-events:none}
.panel .mat{background:rgba(58,58,64,.94)}
.panel .rim{background:linear-gradient(180deg,rgba(255,255,255,.58),rgba(255,255,255,.08) 30%,rgba(255,255,255,.08) 70%,rgba(255,255,255,.42))}
.panel .shadow{position:absolute;inset:0;border-radius:inherit;box-shadow:0 24px 60px rgba(0,0,0,.45),0 0 0 .5px rgba(0,0,0,.35)}
.preview{border-radius:26px;display:none;z-index:5}
.preview .body{position:absolute;inset:0;perspective:1400px;perspective-origin:50% 60%}
.switcher{border-radius:26px;display:none;z-index:6}
.switcher .mat{backdrop-filter:blur(7px) saturate(1.6) brightness(.64);background:rgba(14,14,18,.22)}
.switcher .body{position:absolute;inset:0;perspective:1600px}
.tile{position:absolute;width:336px;height:264px;transform-origin:0 0;border-radius:16px;padding:8px;background:rgba(255,255,255,.045);box-shadow:inset 0 0 0 1px rgba(255,255,255,.08)}
.selring{position:absolute;border-radius:14.4px;background:#0a7aff;box-shadow:inset 0 0 0 2.25px rgba(255,255,255,.65),0 0 30px rgba(10,122,255,.35)}
.tile .hdr{display:flex;gap:6px;height:40px;align-items:center}
.lights{display:flex;gap:6px;padding:7px;border-radius:15px;background:rgba(120,120,128,.26);box-shadow:inset 0 .5px 0 rgba(255,255,255,.1)}
.lights i{width:12px;height:12px;margin:2px;border-radius:50%;background:rgba(235,235,245,.3)}
.lights.on i:nth-child(1){background:#ff5f57}.lights.on i:nth-child(2){background:#febc2e}.lights.on i:nth-child(3){background:#28c840}
.tpill{flex:1;min-width:0;display:flex;gap:6px;align-items:center;padding:5px 9px;border-radius:10px;background:rgba(120,120,128,.26);box-shadow:inset 0 .5px 0 rgba(255,255,255,.1)}
.tpill img{width:16px;height:16px}.tpill div{min-width:0;display:flex;flex-direction:column;gap:1px}
.tpill b{font-size:12px;font-weight:600;line-height:14px;white-space:nowrap}.tpill span{font-size:11px;line-height:13px;color:rgba(235,235,245,.6);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.thumb{position:relative;width:320px;height:200px;margin-top:8px;border-radius:10px;overflow:hidden;background:rgba(120,120,128,.18)}
.thumb .tw{position:absolute;transform-origin:0 0;pointer-events:none}
.thumb .tw .win,#morph .win{position:relative;left:0!important;top:0!important;box-shadow:none;visibility:visible}
.pv-head{position:absolute;left:16px;top:16px;display:flex;align-items:center;gap:8px;height:22px}.pv-head img{width:22px;height:22px}.pv-head b{font-size:13px;font-weight:600}.pv-head span{font-size:12px;color:rgba(235,235,245,.6)}
.card{position:absolute;width:272px;height:198px;padding:8px;border-radius:16px;background:rgba(255,255,255,.045);box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);transform-origin:50% 100%}
.card.hov{background:rgba(255,255,255,.10);box-shadow:inset 0 0 0 1px rgba(255,255,255,.3)}
.card .thumb{width:256px;height:160px;margin:0}.card .ct{height:16px;margin-top:6px;text-align:center;font-size:12px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card .lights{position:absolute;left:14px;top:14px;opacity:0}.card.hov .lights{opacity:1}
.card.nw{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px}.card.nw .plus{width:54px;height:54px;border-radius:50%;display:grid;place-items:center}.card.nw b{font-size:12px;font-weight:600}
.card .gl{position:absolute;inset:0;border-radius:16px;pointer-events:none;mix-blend-mode:plus-lighter;opacity:0;background:linear-gradient(115deg,transparent 30%,rgba(255,255,255,.22) 48%,transparent 62%)}
#morph{position:absolute;left:0;top:0;transform-origin:0 0;display:none;z-index:8;border-radius:22px}
#morph .win{box-shadow:0 0 0 .5px rgba(0,0,0,.75),inset 0 0 0 .5px rgba(255,255,255,.2),0 34px 90px rgba(0,0,0,.55)}
#mring{position:absolute;display:none;z-index:9;border-radius:22px;box-shadow:0 0 0 3px #0a7aff,0 0 40px rgba(10,122,255,.55)}
.ripple{position:absolute;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:50%;border:2px solid rgba(255,255,255,.9);display:none;z-index:20}
.island{position:absolute;left:0;top:0;width:1512px;height:600px;pointer-events:none;z-index:10;display:none}
.isl-svg{position:absolute;left:0;top:0;overflow:visible}
.isl-clip{position:absolute;inset:0}
.isl-img,.isl-flat{position:absolute;top:0;background-repeat:no-repeat}
.iring{position:absolute;width:20px;height:20px;overflow:visible}
.pointer{position:absolute;left:0;top:0;width:24px;height:34px;z-index:30;transform-origin:2px 2px;filter:drop-shadow(0 1.5px 2px rgba(0,0,0,.35));display:none}
/* ---- light stage ---- */
#paper{position:absolute;left:0;top:0;overflow:hidden;display:none;z-index:50;background:radial-gradient(120% 90% at 30% 35%,#fbfafd 0%,#f3f1f7 55%,#e8e4f0 100%)}
#paper .ink{position:absolute;inset:0;background:#070707}
#iris{position:absolute;left:0;top:0;border-radius:50%;display:none;z-index:51;overflow:hidden}
#iris .bgc{position:absolute;background:radial-gradient(60% 55% at 50% 62%,#2b1a63 0%,#17103a 38%,#0a0814 72%,#07060b 100%)}
/* ---- type ---- */
.tb{position:absolute;display:none;z-index:60}
.tb .ln{overflow:hidden;padding:.06em .04em .14em;margin:-.06em -.04em -.14em;white-space:nowrap}
.tb .lw{display:inline-block}
.tb .w{display:inline-block;will-change:transform}
.big{left:0;right:0;text-align:center;font:720 132px/1.04 system-ui;letter-spacing:-4.6px;color:#15121c}
.big .ac{color:${ACCENT}}
.head{left:0;right:0;text-align:center;font:680 64px/1.06 system-ui;letter-spacing:-1.9px;color:#fff;text-shadow:0 2px 30px rgba(8,4,24,.6)}
.head .ac{color:#c4afff}
.side{left:110px;width:560px;font:700 70px/1.04 system-ui;letter-spacing:-2.2px;color:#fff}
.side .ac{color:#c4afff}
.lab{position:absolute;display:none;z-index:45;font:600 22px/1 system-ui;letter-spacing:-.2px;color:rgba(255,255,255,.88);white-space:nowrap}
.lab i{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:10px;vertical-align:2px;background:rgba(255,255,255,.35)}
.lab.on i{background:#c4afff;box-shadow:0 0 12px #9b7bff}
#count{position:absolute;left:0;top:0;display:none;z-index:45;font:650 40px/1 system-ui;letter-spacing:-.8px;color:#fff;white-space:nowrap;text-align:center}
#count small{display:block;font:500 20px/1.3 system-ui;letter-spacing:0;color:rgba(255,255,255,.6);margin-top:8px}
#tag5{position:absolute;display:none;z-index:60;left:112px;font:650 17px/1 system-ui;letter-spacing:.16em;text-transform:uppercase;color:#c4afff}
#tag5 i{display:inline-block;width:8px;height:8px;border-radius:50%;background:#f7c948;margin-right:12px;vertical-align:2px;box-shadow:0 0 10px rgba(247,201,72,.7)}
#keys{position:absolute;left:0;right:0;top:34px;display:none;justify-content:center;gap:16px;z-index:60}
.kc{min-width:96px;height:78px;padding:0 18px;border-radius:16px;display:flex;flex-direction:column;align-items:center;justify-content:center;font:600 32px/1 system-ui;color:#fff;
  background:linear-gradient(180deg,rgba(255,255,255,.16),rgba(255,255,255,.06));box-shadow:inset 0 1px 0 rgba(255,255,255,.35),inset 0 0 0 1px rgba(255,255,255,.14),0 5px 0 rgba(0,0,0,.35),0 14px 30px rgba(0,0,0,.4)}
.kc small{font:500 14px system-ui;color:rgba(255,255,255,.6);margin-top:6px}
.kc.down{transform:translateY(4px);background:linear-gradient(180deg,rgba(160,130,255,.42),rgba(122,82,230,.28));box-shadow:inset 0 1px 0 rgba(255,255,255,.35),inset 0 0 0 1px rgba(196,175,255,.5),0 1px 0 rgba(0,0,0,.35),0 0 30px rgba(122,82,230,.5)}
#end{position:absolute;inset:0;display:none;z-index:70}
#endline{position:absolute;left:0;right:0;top:640px;text-align:center;font:640 46px/1.15 system-ui;letter-spacing:-1.2px;color:#fff}
#word{position:absolute;left:0;right:0;top:566px;text-align:center;font:760 108px/1 system-ui;letter-spacing:-3.6px;color:#fff}
#url{position:absolute;left:0;right:0;top:700px;text-align:center;font:520 30px/1 system-ui;color:rgba(255,255,255,.86);letter-spacing:-.2px}
#meta{position:absolute;left:0;right:0;top:748px;text-align:center;font:500 20px/1 system-ui;color:rgba(255,255,255,.52)}
#fine{position:absolute;left:0;right:0;bottom:40px;text-align:center;font:500 15px system-ui;color:rgba(255,255,255,.4)}
#demo{position:absolute;right:30px;bottom:20px;font:500 14px system-ui;color:rgba(255,255,255,.4);z-index:80}
#veil{position:absolute;inset:0;background:#000;pointer-events:none;z-index:100}
</style></head><body>
<div id="stage">
 <div id="bg"></div>
 <div id="floor"></div>
 <div id="bezel"></div>
 <div id="planes">${plane(0, 'wallpaper-dusk.jpg', WINDOWS)}${plane(1, 'wallpaper-morning.jpg', PERSONAL_WINDOWS)}</div>
 <div class="lab" id="lab0"><i></i>Desktop 1</div><div class="lab" id="lab1"><i></i>Desktop 2</div>
 <div id="ui">
  <div class="preview lg panel"><div class="shadow"></div><div class="mat"></div><div class="body"></div><div class="rim"></div></div>
  <div class="switcher lg panel"><div class="shadow"></div><div class="mat"></div><div class="body"></div><div class="rim"></div></div>
  <div id="morph"></div><div id="mring"></div>
  <div class="island"><svg class="isl-svg" width="1512" height="600"><defs><filter id="isl-shadow" x="-50%" y="-50%" width="200%" height="200%"><feDropShadow dx="0" dy="8" stdDeviation="9" flood-color="#000" flood-opacity=".38"/></filter></defs><path class="isl-shell" fill="#070707"/></svg>
   <div class="isl-clip"><div class="isl-img isl-a"></div><div class="isl-img isl-b"></div></div><div class="isl-flat"></div><div class="isl-flat isl-flat2"></div>
   <svg class="iring" viewBox="0 0 20 20"><circle cx="10" cy="10" r="11" fill="#070707"/><circle cx="10" cy="10" r="8.7" fill="none" stroke="rgba(255,255,255,.16)" stroke-width="2.6"/><circle class="iring-arc" cx="10" cy="10" r="8.7" fill="none" stroke="#FF8A3D" stroke-width="2.6" stroke-linecap="round"/></svg></div>
 </div>
 <div id="dock"><div class="bgr lg"><div class="bshadow"></div><div class="mat"></div><div class="tint"></div><div class="rim"></div></div><div class="dock-icons"></div><div class="bgr spec"><i></i></div></div>
 <div id="uitop"><div class="dlabel"></div><div class="ripple"></div><svg class="pointer" viewBox="0 0 24 34"><path d="M3 2 L3 26 L8.6 20.8 L12.4 29.6 L16.2 28 L12.5 19.4 L20 19.4 Z" fill="#000" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg></div>
 <div id="logo"><img src="native/dogbar-logo.png" alt=""></div>
 <div id="count">3 windows<small>One dot per window</small></div>
 <div id="paper"><div class="ink"></div></div>
 <div id="iris"><div class="bgc"></div></div>
 ${block('t1', TYPE.t1, 'big')}${block('t2', TYPE.t2, 'big')}
 ${block('t3a', [TYPE.t3[0]], 'head')}${block('t3b', [TYPE.t3[1]], 'head')}
 ${block('t5', TYPE.t5, 'side')}<div id="tag5"><i></i>Agent Activity · beta</div>
 <div id="keys"><span class="kc" data-k="opt">⌥<small>option</small></span><span class="kc" data-k="tab">⇥<small>tab</small></span></div>
 <div id="end"><div id="endline">${words(TYPE.end)}</div><div id="word">DogBar</div><div id="url">dogbar.hristijan.dev</div><div id="meta">For Mac · Apple Silicon · macOS 26 or later</div>
  <div id="fine">Agent Activity is an optional beta for Claude Code and Codex. Illustrative demo with fictional content.</div></div>
 <div id="demo">Illustrative demo · fictional content</div>
 <div id="veil"></div>
 <span style="position:absolute;left:-99px;top:0;font:13px SFMonoLocal;opacity:0">x<b style="font-weight:600">x</b></span>
</div>
<script>window.FILM=${JSON.stringify(DATA)};</script>
<script>${RUNTIME}</script>
</body></html>`;
}

const RUNTIME = String.raw`
(()=>{
const F=window.FILM,T=F.T,W=F.W,H=F.H,SW=1512,SH=982;
const $=s=>document.querySelector(s);
const clamp=(x,a=0,b=1)=>Math.min(b,Math.max(a,x));
const lerp=(a,b,p)=>a+(b-a)*p;
const easeOut=p=>1-Math.pow(1-clamp(p),3);
const easeIn=p=>Math.pow(clamp(p),3);
const easeIO=p=>{p=clamp(p);return p<.5?4*p*p*p:1-Math.pow(-2*p+2,3)/2};
const expoIO=p=>{p=clamp(p);return p===0?0:p===1?1:p<.5?Math.pow(2,20*p-10)/2:(2-Math.pow(2,-20*p+10))/2};
const expoOut=p=>{p=clamp(p);return p===1?1:1-Math.pow(2,-10*p)};
const minJerk=p=>{p=clamp(p);return p*p*p*(10-15*p+6*p*p)};
// SwiftUI .spring(duration:d, bounce:b) step response.
function spring(t,d,b=0){if(t<=0)return 0;const w=2*Math.PI/d,z=1-b;
 if(z>=1)return 1-(1+w*t)*Math.exp(-w*t);const wd=w*Math.sqrt(1-z*z);
 return 1-Math.exp(-z*w*t)*(Math.cos(wd*t)+z/Math.sqrt(1-z*z)*Math.sin(wd*t));}
// Camera-style ease that lands exactly (critically damped tail).
function camEase(p){p=clamp(p);const w=6.5,f=x=>1-(1+w*x)*Math.exp(-w*x);const v=p*p*(3-2*p)*.45+p*.55;return f(v)/f(1);}
const seg=(t,a,b,e=camEase)=>e((t-a)/(b-a));
const byId={};[...F.windows,...F.personal].forEach(w=>byId[w.id]=w);

// ---------- Dock geometry (DockLayout.swift / DockIconLayer.swift) ----------
const ICON=48,INSET=Math.max(4,ICON*.17),THICK=ICON+2*INSET,CORNER=THICK*.28,SEPW=ICON*.43,GAP=4,SGAP=4;
const DIA=Math.min(4,ICON/14),DOFF=INSET*.38,STRIDE=DIA+3;
function layout(items){const widths=items.map(k=>k==='|'?SEPW:ICON);const total=widths.reduce((a,b)=>a+b,0)+GAP*(items.length-1);
 let x=-total/2;const pos={};items.forEach((k,i)=>{pos[k]=x+widths[i]/2;x+=widths[i]+GAP});return {pos,w:total+2*INSET};}
const LAY={work:layout(F.DOCKS.work),personal:layout(F.DOCKS.personal)};
const DOCK_CY=SH-SGAP-THICK/2; // dock centre in display points
const counts={work:{},personal:{}};F.windows.forEach(w=>counts.work[w.app]=(counts.work[w.app]||0)+1);F.personal.forEach(w=>counts.personal[w.app]=(counts.personal[w.app]||0)+1);
function dotsSVG(n){if(!n)return '';const cy=ICON+DOFF,cap=DIA*.5;let c='',h='';
 for(let i=0;i<n;i++){const cx=ICON/2+(i-(n-1)/2)*STRIDE;c+='<circle cx="'+cx.toFixed(4)+'" cy="'+cy.toFixed(4)+'" r="'+(DIA/2).toFixed(4)+'"/>';
  h+='<ellipse cx="'+cx.toFixed(4)+'" cy="'+(cy-.42*DIA+.6*cap).toFixed(4)+'" rx="'+(cap/2).toFixed(4)+'" ry="'+(cap*.4).toFixed(4)+'"/>';}
 return '<svg class="dots" width="48" height="60" viewBox="0 0 48 60"><g fill="rgba(255,255,255,.5)">'+c+'</g><g fill="rgba(255,255,255,.4)">'+h+'</g><g class="glow"></g></svg>';}

// ---------- device (the Mac) ----------
// D maps display point (ax,ay) to screen (sx,sy) at scale k.
const CEN={ax:756,ay:491};
const DS={
 a0:{...CEN,sx:960,sy:560,k:.70},a1:{...CEN,sx:960,sy:560,k:.80},
 full:{...CEN,sx:960,sy:596,k:.84},
 d3:{ax:756,ay:DOCK_CY,sx:960,sy:700,k:1.9},
 sw:{ax:756,ay:507,sx:960,sy:662,k:.95},
 notch:{ax:756,ay:0,sx:960,sy:150,k:1.5},
 end:{...CEN,sx:960,sy:560,k:.74},
};
const sIdx=F.DOCKS.work.indexOf('safari');
DS.dots={ax:756+LAY.work.pos.safari,ay:SH-SGAP-INSET-6,sx:860,sy:560,k:3.3};
// Preview panel (PreviewController): thumbnail 160 high, 1.6× wide; card = w+16; panel = n(w+16)+(n−1)10+38 × h+96+22.
const PVW=256,PVH=160,PV_IDS=['checkout','docs','pr'];
const PG=(()=>{const n=PV_IDS.length+1,w=n*(PVW+16)+(n-1)*10+38,h=PVH+96+22,icx=756+LAY.work.pos.safari,top=SH-SGAP-INSET-ICON;let x=clamp(icx-w/2,0,SW-w);return {x,y:top-10-h,w,h};})();
DS.prev={ax:PG.x+PG.w/2,ay:PG.y+PG.h/2+64,sx:960,sy:548,k:1.42};
const mixD=(a,b,p)=>({ax:lerp(a.ax,b.ax,p),ay:lerp(a.ay,b.ay,p),sx:lerp(a.sx,b.sx,p),sy:lerp(a.sy,b.sy,p),k:Math.exp(lerp(Math.log(a.k),Math.log(b.k),p))});
const DSEG=[
 [0,T.settle[1],DS.a1],
 [T.iris1[0]-.001,T.iris1[0],DS.d3,()=>1],
 [T.dotsZoom[0]+.1,T.dotsZoom[1],DS.dots],
 [T.toPreviewFrame[0],T.toPreviewFrame[1]+.2,DS.prev],
 [T.grow[0],T.grow[1],DS.full],
 [T.optDown,T.open+.45,DS.sw],
 [T.ringGrow[0],T.ringGrow[1]+.15,DS.full],
 [T.toNotch[0],T.toNotch[0]+.001,DS.notch,()=>1],
 [T.pullBack[0],T.pullBack[1],DS.end],
];
// Before the stage acts DS.a* apply; the proof uses DS.full.
function deviceAt(t){let d=DS.a0;
 if(t>=T.toFlat[0]&&t<T.iris1[0])return DS.full;
 for(const [a,b,s,e] of DSEG){if(t<a)break;const p=e?e(clamp((t-a)/(b-a))):camEase((t-a)/(b-a));const nd=mixD(d,s,p);d=t>=b?s:nd;if(t<b)break;}
 return d;}
const map=(D,x,y)=>({x:D.sx+(x-D.ax)*D.k,y:D.sy+(y-D.ay)*D.k});
const devRect=D=>{const p=map(D,0,0);return {x:p.x,y:p.y,w:SW*D.k,h:SH*D.k};};

// ---------- which desktop / dock set ----------
// stage slides use a slower spring; the real swipe uses the system-like 0.62 s spring.
function slideAt(t){let s=0;
 const st=(t0,from,to,d)=>{const p=spring(t-t0,d,0);return lerp(from,to,clamp(p,0,1.02));};
 if(t>=T.slide1)s=st(T.slide1,0,1,.95);if(t>=T.slide2)s=st(T.slide2,1,0,.95);if(t>=T.slide3)s=st(T.slide3,0,1,.8);
 if(t>=T.swipeReal)s=st(T.swipeReal,1,0,.62);return s;}
const SWAPS=[[T.slide1+.42,'personal',1],[T.slide2+.42,'work',1],[T.slide3+.36,'personal',1],[T.swipeReal+.4,'work',0]];
function dockSetAt(t){let set='work',prev=null,at=-9,stage=1;for(const [x,s,st] of SWAPS)if(t>=x){prev=set;set=s;at=x;stage=st;}return {set,prev,at,stage};}

// ---------- the Dock object ----------
const dockEl=$('#dock'),dockBg=dockEl.querySelector('.bgr.lg'),dockSpec=dockEl.querySelector('.spec'),dockIcons=dockEl.querySelector('.dock-icons');
const ALL=[...new Set([...F.DOCKS.work,...F.DOCKS.personal])];
const iconEls={};
ALL.forEach(k=>{const e=document.createElement('div');if(k==='|'){e.className='dsep';e.style.height=(ICON*.7)+'px';}
 else{e.className='dicon';e.innerHTML='<img src="native/icon-'+k+'.png" alt=""><span class="dw"></span>';}dockIcons.appendChild(e);iconEls[k]=e;});
function setDots(k,n){const e=iconEls[k];if(!e||k==='|')return;if(+e.dataset.n!==n){e.dataset.n=n;e.querySelector('.dw').innerHTML=dotsSVG(n);}}
// returns per-icon {x,o,s} in dock-local points and the background width
function dockShape(t){const ds=dockSetAt(t);const cur=LAY[ds.set];
 if(!ds.prev||ds.prev===ds.set)return {w:cur.w,icons:Object.fromEntries(Object.entries(cur.pos).map(([k,x])=>[k,{x,o:1,s:1}])),set:ds.set};
 const old=LAY[ds.prev],age=t-ds.at;const out={};
 if(!ds.stage){ // real: DogBar recomposes in place; icons cross-fade quickly, the material resizes with them
  const p=easeOut(age/.16);for(const k of new Set([...Object.keys(old.pos),...Object.keys(cur.pos)])){const a=k in old.pos,b=k in cur.pos;
   out[k]={x:b?cur.pos[k]:old.pos[k],o:a&&b?1:b?p:1-p,s:1};if(a&&b)out[k].x=lerp(old.pos[k],cur.pos[k],p);}
  return {w:lerp(old.w,cur.w,p),icons:out,set:ds.set};}
 const p=spring(age,.42,.12);
 for(const k of new Set([...Object.keys(old.pos),...Object.keys(cur.pos)])){const a=k in old.pos,b=k in cur.pos;
  if(a&&b)out[k]={x:lerp(old.pos[k],cur.pos[k],p),o:1,s:1};
  else if(a){const q=easeOut(age/.2);out[k]={x:old.pos[k]*lerp(1,cur.w/old.w,p),o:1-q,s:1-.4*q};}
  else{const q=spring(age-.07,.36,.28);out[k]={x:cur.pos[k],o:clamp(q*1.4),s:.55+.45*q};}}
 return {w:lerp(old.w,cur.w,p),icons:out,set:ds.set};}
// attach: 1 = drawn where DogBar draws it on the Mac; 0 = the free stage pose.
function attachAt(t){if(t<T.detach[0])return 1;if(t<T.toFlat[0])return 1-seg(t,T.detach[0],T.detach[1],easeIO);
 if(t<T.lift2[0])return seg(t,T.toFlat[0],T.toFlat[1],easeIO);return 1-seg(t,T.lift2[0],T.lift2[1],easeIO);}
function freeAt(t){if(t<T.toFlat[1])return {x:960,y:742,s:1.9};return {x:960,y:540,s:2.3};}
function lookAt(t){ // stage glass tint
 if(t<T.toFlat[1])return 1-attachAt(t);if(t<T.paper1[0])return 0;if(t<T.dotsZoom[0])return 1;if(t<T.dotsZoom[1])return 1-seg(t,T.dotsZoom[0],T.dotsZoom[1]);
 if(t<T.lift2[0])return 0;return 1-attachAt(t);}
function dockPose(t){const D=deviceAt(t),a=attachAt(t),fr=freeAt(t);const at=map(D,756,DOCK_CY);
 let x=lerp(fr.x,at.x,a),y=lerp(fr.y,at.y,a),s=Math.exp(lerp(Math.log(fr.s),Math.log(D.k),a));
 // lift arcs: a small rise and overshoot while detaching / landing
 for(const [t0,t1,dir] of [[T.detach[0],T.detach[1],1],[T.toFlat[0],T.toFlat[1],-1],[T.lift2[0],T.lift2[1],1]]){if(t>t0&&t<t1){const p=(t-t0)/(t1-t0);y-=Math.sin(Math.PI*p)*60;s*=1+.07*Math.sin(Math.PI*p);}}
 return {x,y,s};}
function foldAt(t){return seg(t,T.fold[0],T.fold[1],expoIO);}
function renderDock(t){const pose=dockPose(t),sh=dockShape(t),look=lookAt(t),fold=foldAt(t);
 const vis=dockVisible(t);dockEl.style.display=vis>0?'block':'none';if(vis<=0)return {pose,sh};
 dockEl.style.opacity=vis;
 // fold: width contracts to a square tile, icons converge and fade
 const w=lerp(sh.w,THICK,fold),r=lerp(CORNER,THICK*.2237,fold);
 Object.assign(dockBg.style,{left:(-w/2)+'px',width:w+'px',height:THICK+'px',top:(-THICK/2)+'px',borderRadius:r+'px'});
 Object.assign(dockSpec.style,{left:(-w/2)+'px',width:w+'px',height:THICK+'px',top:(-THICK/2)+'px',borderRadius:r+'px'});
 dockBg.querySelector('.tint').style.opacity=look;dockBg.querySelector('.bshadow').style.boxShadow='0 '+(3+16*look)+'px '+(10+36*look)+'px rgba(0,0,0,'+(.25+.3*look)+')';
 dockEl.style.transform='translate('+pose.x.toFixed(3)+'px,'+pose.y.toFixed(3)+'px) scale('+pose.s.toFixed(5)+')';
 const set=sh.set;const cnt=counts[set];
 for(const k of ALL){const e=iconEls[k],st=sh.icons[k];if(!st||st.o<=.002){e.style.display='none';continue;}e.style.display='block';
  setDots(k,Math.min(5,(k in LAY[set].pos?cnt[k]:counts[set==='work'?'personal':'work'][k])||0));
  if(k==='safari'){const g=e.querySelector('.glow');if(g){const n=+e.dataset.n,cy=ICON+DOFF;let h='';for(let i=0;i<n;i++){const a=(T.dotsCount[i]!==undefined?clamp((t-T.dotsCount[i])/.1):0)*(1-clamp((t-T.toPreviewFrame[0])/.4));if(a>0)h+='<circle cx="'+(ICON/2+(i-(n-1)/2)*STRIDE)+'" cy="'+cy+'" r="'+(DIA*.5+.9*(1-easeOut((t-T.dotsCount[i])/.3)))+'" fill="rgba(214,196,255,'+a+')"/><circle cx="'+(ICON/2+(i-(n-1)/2)*STRIDE)+'" cy="'+cy+'" r="'+(DIA*1.6)+'" fill="rgba(160,120,255,'+(a*.35)+')"/>';}g.innerHTML=h;}}
  const conv=fold>0?Math.pow(clamp(fold*1.25-Math.abs(st.x)/(sh.w/2)*.25),1):0;
  const x=st.x*(1-conv),o=st.o*(1-easeOut(conv*1.3)),sc=st.s*(1-.5*conv);
  if(k==='|'){Object.assign(e.style,{left:(x-.5)+'px',top:(-ICON*.35)+'px',opacity:o});continue;}
  Object.assign(e.style,{left:(x-ICON/2)+'px',top:(-ICON/2)+'px',opacity:o,transform:'scale('+sc+')'});}
 // specular sweep across the glass at key moments
 const sweeps=[T.detach[1]-.35,T.slide1+.5,T.slide2+.5,T.slide3+.45,T.iris1[0]+.2,T.lift2[1]-.25,T.fold[1]-.35];let sp=-1;for(const s0 of sweeps){const p=(t-s0)/.75;if(p>=0&&p<=1)sp=p;}
 const si=dockSpec.querySelector('i');si.style.left=(lerp(-45,110,easeIO(sp)))+'%';dockSpec.style.opacity=sp<0?0:Math.sin(Math.PI*sp)*(.5+.5*look);
 return {pose,sh};}
function dockVisible(t){if(t<T.detach[0])return 0;                        // the plane's own Dock draws it while the Mac is tilted
 if(t>=T.paper1[0]&&t<T.paper1[0]+.22)return 1-(t-T.paper1[0])/.22;      // the paper grows out of its shape
 if(t>=T.paper1[0]&&t<T.iris1[0]-.55)return 0;                            // under paper
 if(t>=T.iris1[0]-.55&&t<T.iris1[0])return easeOut((t-T.iris1[0]+.55)/.45);
 if(t>=T.fold[1]+.25)return 0;if(t>=T.fold[1]-.1)return 1-clamp((t-T.fold[1]+.1)/.35);return 1;}

// ---------- planes ----------
const PL=[$('#pl0'),$('#pl1')];
const planeWins=PL.map(p=>{const o={};p.querySelectorAll('.win').forEach(e=>o[e.dataset.id]=e);return o;});
// front window on Desktop 1 over time
function front0(t){if(t<T.grow[1]-.02)return 'checkout';if(t<T.ringGrow[1]-.02)return 'pr';return 'cursor';}
// Stage pose for plane i at slide s: a row, the active plane forward.
function stagePose(i,s){const k=.46,gap=90,off=i-s;return {x:960+off*(SW*k+gap),y:420,z:-Math.min(1,Math.abs(off))*240,k,ry:-off*9,rx:0,dim:.12+.5*Math.min(1,Math.abs(off))};}
function flatPose(i,s,D){const c=map(D,756+(i-s)*(SW+60),491);return {x:c.x,y:c.y,z:0,k:D.k,ry:0,rx:0,dim:0};}
const mixP=(a,b,p)=>({x:lerp(a.x,b.x,p),y:lerp(a.y,b.y,p),z:lerp(a.z,b.z,p),k:Math.exp(lerp(Math.log(a.k),Math.log(b.k),p)),ry:lerp(a.ry,b.ry,p),rx:lerp(a.rx,b.rx,p),dim:lerp(a.dim,b.dim,p)});
// stage-ness: 0 flat (clipped to the Mac), 1 free planes
function stageAt(t){if(t<T.detach[0])return 0;if(t<T.toFlat[0])return seg(t,T.detach[0],T.detach[1]+.2,easeIO);if(t<T.toFlat[1])return 1-seg(t,T.toFlat[0],T.toFlat[1],easeIO);return 0;}
function openingTilt(t){const p=seg(t,T.settle[0],T.settle[1]);return {rx:lerp(13,0,p),ry:lerp(-17,0,p)};}
function planePoses(t){const D=deviceAt(t),s=slideAt(t),st=stageAt(t);const tilt=openingTilt(t);
 return [0,1].map(i=>{let f=flatPose(i,s,D);if(t<T.detach[0]){f.rx=tilt.rx;f.ry=tilt.ry;}
  let p=st>0?mixP(f,stagePose(i,s),st):f;
  if(i===1){const a=t<T.detach[0]?0:t<T.toFlat[0]?easeOut((t-T.plane2In[0])/(T.plane2In[1]-T.plane2In[0])):1;p.op=a;p.x+=(1-a)*220;p.z-=(1-a)*300;}else p.op=1;
  return p;});}
// focus dim of the Mac (depth of field when the UI is isolated)
function macDim(t){let d=0;
 if(t>=T.iris1[0]&&t<T.grow[1])d=Math.max(d,lerp(.9,.66,seg(t,T.toPreviewFrame[0],T.toPreviewFrame[1]))*(1-seg(t,T.grow[0],T.grow[1])));       // act 3: dim behind the Dock/preview
 d=Math.max(d,.82*clamp((t-T.lift[0])/.4)*(1-clamp((t-T.land[0])/.4)));
 if(t>=T.open&&t<T.release+.3)d=Math.max(d,.35*easeOut((t-T.open)/.3)*(1-clamp((t-T.release)/.3)));
 if(t>=T.toNotch[1]-.2&&t<T.pullBack[1])d=Math.max(d,.55*clamp((t-T.toNotch[1]+.2)/.5)*(1-seg(t,T.pullBack[0],T.pullBack[1])));
 if(t>=T.lift2[0])d=Math.max(d,.85*seg(t,T.lift2[0],T.fold[0]+.3));
 return d;}
function macBlur(t){let b=0;if(t>=T.iris1[0]&&t<T.grow[1])b=7*(1-seg(t,T.grow[0],T.grow[1]))+3*clamp((t-T.lift[0])/.4)*(1-clamp((t-T.land[0])/.4));
 if(t>=T.lift2[0])b=10*seg(t,T.lift2[0],T.fold[0]+.3);return b;}
function macVisible(t){if(t>=T.paper1[1]&&t<T.iris1[0])return 0;if(t>=T.paper2[1]&&t<T.toNotch[0])return 0;
 if(t>=T.toNotch[0]&&t<T.toNotch[1])return easeOut((t-T.toNotch[0]-.15)/.5);if(t>=T.fold[1])return 1-clamp((t-T.fold[1])/.4);return 1;}
function setMenu(pl,app){const b=pl.querySelector('.mb-app');if(b.textContent!==F.APP_NAMES[app]){b.textContent=F.APP_NAMES[app];pl.querySelector('.mb-menus').innerHTML=(F.MENUS[app]||[]).map(m=>'<span>'+m+'</span>').join('');}}
// plane 0's own Dock (only while the Mac is tilted, before the Dock lifts out)
(function(){const pd=PL[0].querySelector('.pdock'),L=LAY.work;Object.assign(pd.style,{left:(756-L.w/2)+'px',top:(SH-SGAP-THICK)+'px',width:L.w+'px',height:THICK+'px',borderRadius:CORNER+'px'});
 pd.querySelector('.dock-icons').innerHTML=F.DOCKS.work.map(k=>k==='|'?'<div class="dsep" style="left:'+(L.w/2+L.pos[k]-.5)+'px;top:'+(INSET+ICON*.15)+'px;height:'+(ICON*.7)+'px"></div>'
  :'<div class="dicon" style="left:'+(L.w/2+L.pos[k]-ICON/2)+'px;top:'+INSET+'px"><img src="native/icon-'+k+'.png" alt="">'+dotsSVG(Math.min(5,counts.work[k]||0))+'</div>').join('');})();
function renderPlanes(t){const P=planePoses(t),st=stageAt(t),D=deviceAt(t),vis=macVisible(t),dim=macDim(t),bl=macBlur(t);
 const fr=front0(t);
 for(const [id,e] of Object.entries(planeWins[0])){e.classList.toggle('shown',id===fr);}
 for(const e of Object.values(planeWins[1]))e.classList.add('shown');
 setMenu(PL[0],byId[fr].app);setMenu(PL[1],'messages');
 PL.forEach((pl,i)=>{const p=P[i];const o=p.op*vis;pl.style.display=o>.002?'block':'none';pl.style.opacity=o;
  pl.style.transform='translate3d('+(p.x-756).toFixed(3)+'px,'+(p.y-491).toFixed(3)+'px,'+p.z.toFixed(2)+'px) rotateY('+p.ry.toFixed(3)+'deg) rotateX('+p.rx.toFixed(3)+'deg) scale('+p.k.toFixed(5)+')';
  pl.querySelector('.pdim').style.opacity=Math.max(p.dim*st,dim);
  pl.querySelector('.ring').style.opacity=t<T.toFlat[0]?1:st;
  pl.querySelector('.pin').style.filter=bl>.05?'blur('+(bl/p.k).toFixed(2)+'px)':'';
  pl.querySelector('.pdock').style.display=(i===0&&t<T.detach[0])?'block':'none';});
 // clip to the Mac while flat; open while on the stage
 const R=devRect(D),big={x:-400,y:-400,w:W+800,h:H+800};const c=t<T.detach[0]?big:{x:lerp(R.x,big.x,st),y:lerp(R.y,big.y,st),w:lerp(R.w,big.w,st),h:lerp(R.h,big.h,st)};
 const rr=lerp(18*D.k,0,st);$('#planes').style.clipPath=(t<T.detach[0]||st>.999)?'none':'inset('+c.y.toFixed(2)+'px '+(W-c.x-c.w).toFixed(2)+'px '+(H-c.y-c.h).toFixed(2)+'px '+c.x.toFixed(2)+'px round '+rr.toFixed(2)+'px)';
 const bz=$('#bezel');const bo=(t<T.toFlat[0]?0:1-st)*vis;bz.style.display=bo>.01?'block':'none';Object.assign(bz.style,{left:R.x+'px',top:R.y+'px',width:R.w+'px',height:R.h+'px',borderRadius:(18*D.k)+'px',opacity:bo});
 // desktop labels on the stage
 [0,1].forEach(i=>{const l=$('#lab'+i),p=P[i];const a=clamp((t-T.labelsIn)/.4)*st*p.op*(1-clamp((t-T.toFlat[0])/.3));l.style.display=a>.01?'block':'none';if(a<=.01)return;
  const s=slideAt(t);l.classList.toggle('on',Math.abs(i-s)<.5);l.style.opacity=a*(Math.abs(i-s)<.5?1:.6);const sc=1/(1-p.z/2400);
  const x=960+(p.x-960)*sc,y=470+(p.y-SH*p.k/2-36-470)*sc;l.style.transform='translate('+(x-l.offsetWidth/2).toFixed(2)+'px,'+y.toFixed(2)+'px)';});
 return P;}

// ---------- UI layer (display points) ----------
const ui=$('#ui');
function placeUI(D){$('#uitop').style.transform=ui.style.transform='translate('+(D.sx-D.ax*D.k).toFixed(3)+'px,'+(D.sy-D.ay*D.k).toFixed(3)+'px) scale('+D.k.toFixed(5)+')';}
function winHTML(id,bw,bh){const w=byId[id],s=Math.min(bw/w.w,bh/w.h),ox=(bw-w.w*s)/2,oy=(bh-w.h*s)/2;
 return {s,ox,oy,html:'<div class="tw" style="left:'+ox+'px;top:'+oy+'px;width:'+w.w+'px;height:'+w.h+'px;transform:scale('+s+')"><div class="win '+w.cls+'" style="width:'+w.w+'px;height:'+w.h+'px">'+F.html[id]+'</div></div>'};}
const shortTitle=w=>w.title.replace(/ – (Acme Store \(dev\)|Acme API Docs)$/,'');
// preview
const pv=$('.preview');const cardRect=i=>({x:PG.x+19+i*(PVW+26),y:PG.y+51,w:272,h:198});
Object.assign(pv.style,{left:PG.x+'px',top:PG.y+'px',width:PG.w+'px',height:PG.h+'px'});
pv.querySelector('.body').innerHTML='<div class="pv-head"><img src="native/icon-safari.png" alt=""><b>Safari</b><span>'+PV_IDS.length+' windows</span></div>'+
 PV_IDS.map((id,i)=>'<div class="card" data-i="'+i+'" style="left:'+(19+i*(PVW+26))+'px;top:51px"><div class="thumb">'+winHTML(id,PVW,PVH).html+'</div><div class="ct">'+shortTitle(byId[id])+'</div><div class="lights on"><i></i><i></i><i></i></div><div class="gl"></div></div>').join('')+
 '<div class="card nw" data-i="3" style="left:'+(19+PV_IDS.length*(PVW+26))+'px;top:51px"><div class="plus"><i class="sym" style="width:28px;height:28px;background:#fff;-webkit-mask-image:url(native/sym-plus.png)"></i></div><b>New Window</b><div class="gl"></div></div>';
const cards=[...pv.querySelectorAll('.card')];
function renderPreview(t,cur){const on=T.preview,off=T.click+.02;if(!(t>=on&&t<off+.1)){pv.style.display='none';return null;}
 pv.style.display='block';const a=t<off?easeOut((t-on)/.14):1-clamp((t-off)/.08);pv.style.opacity=a;
 const lift=t<T.land[0]?seg(t,T.lift[0],T.lift[1],t=>spring(t*1.33,.9,.18)):1-seg(t,T.land[0],T.land[1],t=>spring(t*1.33,.8,.1));
 const L=clamp(lift,0,1.2);pv.style.transform='translateY('+(4*(1-easeOut((t-on)/.14)))+'px)';
 pv.querySelector('.mat').style.opacity=1-.75*clamp(L);pv.querySelector('.shadow').style.opacity=1-.8*clamp(L);pv.querySelector('.rim').style.opacity=1-clamp(L);pv.querySelector('.pv-head').style.opacity=1-clamp(L);
 cards.forEach((e,i)=>{const r=cardRect(i);const hov=cur&&cur.vis&&cur.x>=r.x&&cur.x<=r.x+r.w&&cur.y>=r.y&&cur.y<=r.y+r.h;e.classList.toggle('hov',!!hov&&L<.05);
  const c=i-1.5;e.style.transform=L>.001?'translate3d('+(c*34*L).toFixed(2)+'px,'+(-70*L-Math.abs(c)*-14*L).toFixed(2)+'px,'+(180*L-Math.abs(c)*40*L).toFixed(2)+'px) rotateY('+(-c*7*L).toFixed(2)+'deg) rotateX('+(9*L).toFixed(2)+'deg)':'';
  e.style.boxShadow=L>.01?'inset 0 0 0 1px rgba(255,255,255,'+(.08+.2*clamp(L))+'),0 '+(30*L)+'px '+(60*L)+'px rgba(0,0,0,'+(.5*clamp(L))+')':'';
  e.style.background=L>.01?'rgba(60,58,72,'+(.94*clamp(L))+')':'';
  const g=e.querySelector('.gl');const gp=(t-T.lift[0]-.25-i*.08)/.8;g.style.opacity=gp>0&&gp<1?Math.sin(Math.PI*gp)*.9:0;g.style.backgroundPosition=(lerp(-300,300,gp))+'px 0';g.style.backgroundSize='200% 100%';});
 return {open:a>.5};}
// switcher (SwitcherTileMetrics: 320×200 thumbs, tile 336×264 ×0.9, spacing 12, padding 20, ≤4 per row; MRU order)
const TS=.9,TW=336*TS,TH=264*TS,TSP=12,TPAD=20;
const MRU=['pr','checkout','docs','claude','cursor','mail','notes','finder'];
const swEl=$('.switcher');const SWG=(()=>{const n=MRU.length,cols=4,rows=2,w=cols*TW+(cols-1)*TSP+2*TPAD,h=rows*TH+(rows-1)*TSP+2*TPAD;return {x:(SW-w)/2,y:32+(SH-32-h)/2,w,h,cols};})();
Object.assign(swEl.style,{left:SWG.x+'px',top:SWG.y+'px',width:SWG.w+'px',height:SWG.h+'px'});
const tileXY=i=>({x:TPAD+(i%4)*(TW+TSP),y:TPAD+Math.floor(i/4)*(TH+TSP)});
swEl.querySelector('.body').innerHTML='<div class="selring"></div>'+MRU.map((id,i)=>{const p=tileXY(i),wn=byId[id];
 return '<div class="tile" data-i="'+i+'" style="left:'+p.x+'px;top:'+p.y+'px"><div class="hdr"><div class="lights"><i></i><i></i><i></i></div><div class="tpill"><img src="native/icon-'+wn.app+'.png" alt=""><div><b>'+wn.appName+'</b><span>'+wn.title+'</span></div></div></div><div class="thumb">'+winHTML(id,320,200).html+'</div></div>'}).join('');
const tiles=[...swEl.querySelectorAll('.tile')],selRing=swEl.querySelector('.selring');
// thumbnail rect of tile i, in display points
const tileThumb=i=>{const p=tileXY(i),m=winHTML(MRU[i],320,200);return {x:SWG.x+p.x+TS*(8+m.ox),y:SWG.y+p.y+TS*(56+m.oy),s:TS*m.s};};
function selAt(t){let s=0;T.tabs.forEach((x,i)=>{if(t>=x)s=i+1});return Math.max(1,s);}
function renderSwitcher(t){if(!(t>=T.open-.001&&t<T.release+.1)){swEl.style.display='none';return null;}
 swEl.style.display='block';const a=t<T.release?easeOut((t-T.open)/.12):1-clamp((t-T.release)/.08);
 swEl.style.opacity=a;swEl.style.transform='scale('+(0.98+0.02*a)+')';swEl.style.transformOrigin='50% 50%';
 const sel=selAt(t);
 tiles.forEach((e,i)=>{let tr='';if(i>0){const p=spring(t-T.open-.04-i*.035,.5,.16);const q=clamp(p,0,1.1);tr='translate3d(0,'+((1-q)*40).toFixed(2)+'px,'+((1-q)*-420).toFixed(2)+'px)';e.style.opacity=clamp(p*1.6);}
  else{e.style.opacity=t<T.open+.42?0:1;}
  const focus=t>=T.tabs[T.tabs.length-1]+.2?seg(t,T.tabs[T.tabs.length-1]+.2,T.tabs[T.tabs.length-1]+.7):0;
  if(i!==sel&&focus>0){e.style.filter='blur('+(1.6*focus).toFixed(2)+'px)';e.style.opacity=(+e.style.opacity)*(1-.35*focus);}else e.style.filter='';
  e.style.transform=tr+' scale('+TS+')';});
 // the selection ring travels between tiles (fast spring), it is the anchor of the next transition
 let px=tileXY(1),cx=px.x,cy=px.y;for(let k=1;k<T.tabs.length;k++){const t0=T.tabs[k];if(t>=t0){const from=tileXY(k),to=tileXY(k+1),p=spring(t-t0,.2,0);cx=lerp(from.x,to.x,p);cy=lerp(from.y,to.y,p);}}
 Object.assign(selRing.style,{left:cx+'px',top:cy+'px',width:TW+'px',height:TH+'px',opacity:clamp((t-T.open-.12)/.1)});
 return {sel:MRU[sel]};}
// morph: card → window, window → tile, tile → window
const morph=$('#morph'),mring=$('#mring');const FR={x:10,y:40,w:1492,h:862};
function setMorph(id){if(morph.dataset.id!==id){morph.dataset.id=id;const w=byId[id];morph.innerHTML='<div class="win '+w.cls+'" style="width:'+w.w+'px;height:'+w.h+'px">'+F.html[id]+'</div>';}}
function renderMorph(t){morph.style.display='none';mring.style.display='none';
 const cardT=(()=>{const i=2,r=cardRect(i),m=winHTML(PV_IDS[i],PVW,PVH);return {x:r.x+8+m.ox,y:r.y+8+m.oy,s:m.s};})();
 const full={x:FR.x,y:FR.y,s:1};
 const show=(id,a,b,p,rad)=>{setMorph(id);const x=lerp(a.x,b.x,p),y=lerp(a.y,b.y,p),s=Math.exp(lerp(Math.log(a.s),Math.log(b.s),clamp(p,-.2,1.2)));
  Object.assign(morph.style,{display:'block',transform:'translate('+x.toFixed(3)+'px,'+y.toFixed(3)+'px) scale('+s.toFixed(5)+')'});return {x,y,s};};
 if(t>=T.grow[0]&&t<T.grow[1]){const p=spring(t-T.grow[0],.62,.1);show('pr',cardT,full,clamp(p,0,1.04));return 'pr';}
 if(t>=T.open&&t<T.open+.42){const p=seg(t,T.open,T.open+.42,expoIO);show('pr',full,tileThumb(0),p);return 'pr→tile';}
 if(t>=T.ringGrow[0]&&t<T.ringGrow[1]){const sel=selAt(t),from=tileThumb(sel),p=spring(t-T.ringGrow[0],.6,.08);const r=show(MRU[sel],from,full,clamp(p,0,1.04));
  const q=clamp(p);Object.assign(mring.style,{display:'block',left:(r.x-3)+'px',top:(r.y-3)+'px',width:(FR.w*r.s+6)+'px',height:(FR.h*r.s+6)+'px',borderRadius:(14+8*q)+'px',opacity:1-easeIn(q)});return 'tile→'+MRU[sel];}
 return null;}
// click ripple
const ripple=$('.ripple');
function renderRipple(t,cur){const c=[T.click,T.clickClaude].find(c=>t>=c&&t<c+.45);if(c===undefined){ripple.style.display='none';return;}
 const p=(t-c)/.45;Object.assign(ripple.style,{display:'block',left:cur.x+'px',top:cur.y+'px',transform:'scale('+(.3+1.1*easeOut(p))+')',opacity:(1-p)*.9});}
// hover label (DogBar draws the app name above the hovered icon until its preview opens)
function renderLabel(t,cur){const lab=$('.dlabel');if(!(t>=T.hover&&t<T.preview)){lab.style.display='none';return;}
 lab.style.display='block';lab.textContent='Safari';const cx=756+LAY.work.pos.safari;Object.assign(lab.style,{left:(cx-lab.offsetWidth/2)+'px',top:(SH-SGAP-THICK-8-25)+'px'});}
// island (AgentIslandGeometry / IslandMotion; images are the real AgentIslandView rendered natively)
const N=F.native,G=N.geometry,BAR=G.barHeight,PX=G.panel[0],PWD=G.panel[2],PHT=G.panel[3],ICX=G.centerX,COL=G.collapsedTwoDogs,EXPW=G.expandedWidth;
const shapeOf=n=>N.shapes[n]||[EXPW,300];
const isl=$('.island');
function islandPath(w,h,shoulder,r){const x0=ICX-w/2,x1=ICX+w/2,s=Math.min(shoulder,w/4);r=Math.min(r,(w-2*s)/2,h/2);
 return 'M'+x0+' 0Q'+(x0+s)+' 0 '+(x0+s)+' '+s+'L'+(x0+s)+' '+(h-r)+'Q'+(x0+s)+' '+h+' '+(x0+s+r)+' '+h+'L'+(x1-s-r)+' '+h+'Q'+(x1-s)+' '+h+' '+(x1-s)+' '+(h-r)+'L'+(x1-s)+' '+s+'Q'+(x1-s)+' 0 '+x1+' 0Z';}
const expImg=t=>t<T.clickClaude?'island-list.png':'island-claude-finished.png';
const colImg=t=>t<T.finished?'island-collapsed-working.png':'island-collapsed-finished.png';
function renderIsland(t){if(!(t>=T.toNotch[1]-.12&&t<T.fold[1])){isl.style.display='none';return null;}isl.style.display='block';
 const q=c=>isl.querySelector(c);const shell=q('.isl-shell'),clip=q('.isl-clip'),A=q('.isl-a'),Bi=q('.isl-b'),flat=q('.isl-flat'),flat2=q('.isl-flat2'),ring=q('.iring');
 const bg=(el,img,a)=>{if(!img||a<=.001){el.style.display='none';return;}el.style.display='block';Object.assign(el.style,{left:PX+'px',width:PWD+'px',height:PHT+'px',backgroundImage:'url(native/'+img+')',backgroundSize:PWD+'px '+PHT+'px',opacity:a});};
 let e=0;if(t>=T.expand&&t<T.collapse)e=spring(t-T.expand,.34,.08);else if(t>=T.collapse)e=1-spring(t-T.collapse,.26,0);
 const img=expImg(t);let h=shapeOf(img)[1];if(t>=T.clickClaude&&t<T.collapse)h=lerp(shapeOf('island-list.png')[1],h,spring(t-T.clickClaude,.30,0));
 const ci=colImg(t),cf=t>=T.finished?easeOut((t-T.finished)/.1):0;
 if(e<=.001){shell.style.display='none';clip.style.display='none';bg(flat,'island-collapsed-working.png',1-cf);bg(flat2,cf>0?'island-collapsed-finished.png':null,cf);}
 else{bg(flat,null,0);bg(flat2,null,0);shell.style.display='block';clip.style.display='block';
  const w=lerp(COL[0],EXPW,e),hh=lerp(BAR,h,e),r=lerp(Math.min(12,BAR*.42),26,e),sh=lerp(6,10,e);const path=islandPath(w,hh,sh,r);
  shell.setAttribute('d',path);shell.setAttribute('filter',e>.02?'url(#isl-shadow)':'');clip.style.clipPath='path("'+path+'")';
  const opening=t<T.collapse;const ca=opening?easeOut((t-T.expand-.05)/.12):1-easeOut((t-T.collapse)/.08);
  const mix=t>=T.clickClaude?easeOut((t-T.clickClaude)/.1):1;
  bg(A,img,ca*mix);bg(Bi,t>=T.clickClaude&&mix<1?'island-list.png':null,ca*(1-mix));if(ca<1)bg(flat,ci,1-ca);}
 // working ring turns once per 1.5 s (IslandMotion.ringPeriod) on the collapsed island and the session list
 const working=t<T.finished||(e>.5&&t<T.clickClaude);
 if(working){const ex=e>.5?1:0;const cx=lerp(ICX+COL[0]/2-12-10,ICX+EXPW/2-18-10,ex);ring.style.display='block';Object.assign(ring.style,{left:(cx-10)+'px',top:'6px'});
  const C=2*Math.PI*8.7,arc=q('.iring-arc');arc.setAttribute('stroke-dasharray',(C*.28)+' '+C);arc.setAttribute('transform','rotate('+(-90+((t%1.5)/1.5)*360)+' 10 10)');}
 else ring.style.display='none';
 return {e,img:e>.5?img:ci};}
// pointer (display points)
const ic={x:756+LAY.work.pos.safari,y:SH-SGAP-INSET-ICON/2};const cardMid=i=>{const r=cardRect(i);return {x:r.x+r.w*.5,y:r.y+r.h*.42};};
const CUR=[
 {t:T.cursorIn[0],x:ic.x+330,y:ic.y-330},{t:T.cursorIn[1],x:ic.x-6,y:ic.y-12},
 {t:T.cardMoves[0]-.45,x:ic.x-6,y:ic.y-12},{t:T.cardMoves[0],x:cardMid(0).x,y:cardMid(0).y},{t:T.cardMoves[1],x:cardMid(1).x,y:cardMid(1).y},{t:T.cardMoves[2],x:cardMid(2).x,y:cardMid(2).y},
 {t:T.grow[1]+.4,x:cardMid(2).x,y:cardMid(2).y},
 {t:T.cursorToIsland[0]-.6,x:ICX+260,y:380},{t:T.cursorToIsland[1],x:ICX+40,y:18},{t:T.clickClaude-.6,x:ICX+40,y:18},{t:T.clickClaude-.05,x:PX+112,y:117},
 {t:T.leave-.05,x:PX+112,y:117},{t:T.leave+.6,x:ICX+330,y:560},{t:99,x:ICX+330,y:560}];
function cursorAt(t){let i=0;while(i<CUR.length-2&&t>=CUR[i+1].t)i++;const a=CUR[i],b=CUR[i+1];
 const p=minJerk((t-a.t)/Math.max(1e-6,b.t-a.t));const dx=b.x-a.x,dy=b.y-a.y,d=Math.hypot(dx,dy);
 const arc=Math.sin(Math.PI*p)*Math.min(40,d*.08);
 const vis=(t>=T.cursorIn[0]&&t<T.grow[1]+.35)||(t>=T.cursorToIsland[0]-.6&&t<T.leave+.6);
 const op=t<T.cursorIn[0]+.15?clamp((t-T.cursorIn[0])/.15):t>=T.grow[1]&&t<T.grow[1]+.35?1-(t-T.grow[1])/.35:t>=T.leave+.3&&t<T.leave+.6?1-(t-T.leave-.3)/.3:t>=T.cursorToIsland[0]-.6&&t<T.cursorToIsland[0]-.45?(t-T.cursorToIsland[0]+.6)/.15:1;
 return {x:a.x+dx*p-dy/(d||1)*arc,y:a.y+dy*p+dx/(d||1)*arc,vis,op};}
const press=t=>[T.click,T.clickClaude].some(c=>t>=c-.04&&t<c+.09);

// ---------- paper, iris ----------
const paper=$('#paper'),ink=paper.querySelector('.ink'),iris=$('#iris');
function rectCss(el,r,rad){Object.assign(el.style,{left:r.x+'px',top:r.y+'px',width:r.w+'px',height:r.h+'px',borderRadius:rad});}
const FULL={x:0,y:0,w:W,h:H};const mixR=(a,b,p)=>({x:lerp(a.x,b.x,p),y:lerp(a.y,b.y,p),w:lerp(a.w,b.w,p),h:lerp(a.h,b.h,p)});
function dockScreenRect(t){const p=dockPose(t),sh=dockShape(t);return {x:p.x-sh.w*p.s/2,y:p.y-THICK*p.s/2,w:sh.w*p.s,h:THICK*p.s,r:CORNER*p.s};}
function renderPaper(t){paper.style.display='none';
 if(t>=T.paper1[0]&&t<T.iris1[1]){const a=dockScreenRect(T.paper1[0]);const p=seg(t,T.paper1[0],T.paper1[1],expoIO);const r=mixR(a,FULL,p);
  paper.style.display='block';rectCss(paper,r,lerp(a.r,0,p)+'px');paper.style.opacity=clamp((t-T.paper1[0])/.12);ink.style.opacity=0;return 'paper1';}
 if(t>=T.paper2[0]&&t<T.toNotch[1]){const D=deviceAt(T.paper2[0]);const n0=map(D,756-94,0),nr={x:n0.x,y:n0.y,w:188*D.k,h:32*D.k};
  const Dn=DS.notch,i0=map(Dn,ICX-COL[0]/2,0),ir={x:i0.x,y:i0.y,w:COL[0]*Dn.k,h:BAR*Dn.k};paper.style.display='block';paper.style.opacity=1;
  if(t<T.toNotch[0]){const p=seg(t,T.paper2[0],T.paper2[1],expoIO);const rr=mixR(nr,FULL,p);rectCss(paper,rr,'0 0 '+lerp(12*D.k,0,p)+'px '+lerp(12*D.k,0,p)+'px');ink.style.opacity=1-clamp((rr.h-nr.h)/(H*.35));return 'paper2';}
  const p=seg(t,T.toNotch[0],T.toNotch[1],expoIO);rectCss(paper,mixR(FULL,ir,p),'0 0 '+lerp(0,12*Dn.k,p)+'px '+lerp(0,12*Dn.k,p)+'px');ink.style.opacity=clamp((p-.45)/.4);
  paper.style.opacity=t>T.toNotch[1]-.1?1-(t-T.toNotch[1]+.1)/.1:1;return 'toNotch';}
 return null;}
function renderIris(t){if(!(t>=T.iris1[0]&&t<T.iris1[1])){iris.style.display='none';if(t>=T.iris1[1]&&t<T.iris1[1]+.05){}return;}
 const D=deviceAt(t),c=map(D,756,DOCK_CY);const p=seg(t,T.iris1[0],T.iris1[1],expoIO);const R=Math.hypot(W,H)*1.05*p+40;
 iris.style.display='block';rectCss(iris,{x:c.x-R,y:c.y-R,w:2*R,h:2*R},'50%');const bgc=iris.querySelector('.bgc');Object.assign(bgc.style,{left:(-c.x+R-W*.1)+'px',top:(-c.y+R-H*.1)+'px',width:W*1.2+'px',height:H*1.2+'px'});}
// while the iris opens, the dark stage and the Mac must sit above the paper: the paper is hidden after the iris completes.

// ---------- type ----------
function typeIn(el,tIn,tOut,opts={}){const st=opts.stagger??.06,dur=opts.dur??.62;
 if(t_<tIn-.01||t_>tOut+.7){el.style.display='none';return false;}el.style.display='block';
 el.querySelectorAll('.w').forEach((w,i)=>{const p=expoOut((t_-tIn-i*st)/dur);const o=clamp((t_-tOut-i*.03)/.42);const q=easeIn(o);
  w.style.transform='translateY('+((1-p)*108-q*108).toFixed(2)+'%)';w.style.opacity=t_<tIn+i*st?0:1;});return true;}
let t_=0;
function renderType(t){
 const t1=$('#t1');if(typeIn(t1,T.type1a,T.iris1[0]-.55)){t1.style.top='378px';const l=t1.querySelectorAll('.ln');l[1].querySelectorAll('.w').forEach((w,i)=>{const p=expoOut((t-T.type1b-i*.06)/.62);const o=easeIn(clamp((t-T.iris1[0]+.55-i*.03)/.42));w.style.transform='translateY('+((1-p)*108-o*108)+'%)';w.style.opacity=t<T.type1b?0:1;});}
 const t2=$('#t2');if(typeIn(t2,T.type2a,T.toNotch[0]-.45)){t2.style.top='378px';t2.querySelectorAll('.ln')[1].querySelectorAll('.w').forEach((w,i)=>{const p=expoOut((t-T.type2b-i*.06)/.62);const o=easeIn(clamp((t-T.toNotch[0]+.45-i*.03)/.42));w.style.transform='translateY('+((1-p)*108-o*108)+'%)';w.style.opacity=t<T.type2b?0:1;});}
 const a=$('#t3a');if(typeIn(a,T.type3a,T.grow[0]-.1)){a.style.top='70px';}
 const b=$('#t3b');if(typeIn(b,T.type3b,T.optDown-.35)){b.style.top='70px';}
 const t5=$('#t5');if(typeIn(t5,T.type5,T.leave+.1)){t5.style.top='400px';}
 const tg=$('#tag5');const ta=clamp((t-T.type5+.1)/.4)*(1-clamp((t-T.leave-.1)/.4));tg.style.display=ta>.01?'block':'none';tg.style.top='350px';tg.style.opacity=ta;tg.style.transform='translateY('+(1-easeOut(ta))*10+'px)';
 // keycaps (Option-Tab)
 const ks=$('#keys');const ka=clamp((t-T.optDown+.25)/.25)*(1-clamp((t-T.release-.15)/.3));ks.style.display=ka>.01?'flex':'none';ks.style.opacity=ka;ks.style.transform='translateY('+(1-easeOut(ka))*-14+'px)';
 ks.querySelector('[data-k="opt"]').classList.toggle('down',t>=T.optDown&&t<T.release);ks.querySelector('[data-k="tab"]').classList.toggle('down',T.tabs.some(x=>t>=x&&t<x+.13));
 // window-count callout beside the Safari dots
 const cn=$('#count');const ca=clamp((t-T.dotsCount[0])/.3)*(1-clamp((t-T.toPreviewFrame[0]+.1)/.3));cn.style.display=ca>.01?'block':'none';
 if(ca>.01){const D=deviceAt(t),p=map(D,756+LAY.work.pos.safari,SH-SGAP);cn.style.opacity=ca;cn.style.transform='translate('+(p.x-cn.offsetWidth/2).toFixed(1)+'px,'+(p.y+30+(1-easeOut(ca))*16).toFixed(1)+'px)';}
 // end
 const end=$('#end');const ea=t>=T.endline-.05;end.style.display=ea?'block':'none';
 if(ea){const el=$('#endline');el.querySelectorAll('.w').forEach((w,i)=>{const p=expoOut((t-T.endline-.1-i*.045)/.6);const o=clamp((t-T.lockup+.5)/.4);w.style.opacity=p*(1-o);w.style.transform='translateY('+((1-p)*28-o*16)+'px)';w.style.filter='blur('+((1-p)*6+o*5)+'px)';w.style.display='inline-block';});
  const lp=(d)=>expoOut((t-T.lockup-d)/.7);$('#word').style.opacity=lp(.1);$('#word').style.transform='translateY('+(1-lp(.1))*24+'px)';
  $('#url').style.opacity=lp(.35)*.95;$('#url').style.transform='translateY('+(1-lp(.35))*14+'px)';$('#meta').style.opacity=lp(.5);$('#meta').style.transform='translateY('+(1-lp(.5))*12+'px)';$('#fine').style.opacity=easeOut((t-T.lockup-1)/.8)*.9;}
}
// the app icon that the Dock folds into, then the lockup position
const logo=$('#logo');
function renderLogo(t){if(t<T.fold[0]+.25){logo.style.opacity=0;logo.style.display='none';return null;}logo.style.display='block';
 const pose=dockPose(T.fold[1]);const tile=THICK*pose.s;const a=easeOut((t-T.fold[0]-.55)/.4);
 // after the fold, the icon rises to the lockup
 const up=seg(t,T.lockup-.2,T.lockup+.7,expoIO),settle=seg(t,T.fold[1],T.endline+.8);
 const size=lerp(lerp(tile,230,settle),200,up),cx=960,cy=lerp(lerp(pose.y,470,settle),420,up);
 Object.assign(logo.style,{opacity:a,transform:'translate('+(cx-size/2).toFixed(2)+'px,'+(cy-size/2).toFixed(2)+'px) scale('+(size/200).toFixed(5)+')'});return {size,cy};}

// ---------- floor glow ----------
function renderFloor(t,pose){const f=$('#floor');const a=lookAt(t)*(t<T.toFlat[1]||t>T.lift2[0]?1:.4)*(dockVisible(t));f.style.opacity=a*.9;
 f.style.transform='translate('+(pose.x-450)+'px,'+(pose.y+THICK*pose.s*.15-75)+'px) scale('+(pose.s/1.9).toFixed(4)+',1)';}

// ---------- frame ----------
window.renderAt=function(t){t_=t;
 const D=deviceAt(t);placeUI(D);
 const P=renderPlanes(t);
 const cur=cursorAt(t);const ptr=$('.pointer');ptr.style.display=cur.vis?'block':'none';ptr.style.opacity=cur.op;ptr.style.transform='translate('+(cur.x-3)+'px,'+(cur.y-2)+'px) scale('+(press(t)?.88:1)+')';
 const pvs=renderPreview(t,cur);const sw=renderSwitcher(t);const mo=renderMorph(t);renderRipple(t,cur);renderLabel(t,cur);const il=renderIsland(t);
 const d=renderDock(t);renderFloor(t,d.pose);
 // the Dock sits above the paper while the iris opens
 dockEl.style.zIndex=(t>=T.iris1[0]-.6&&t<T.iris1[1])?'53':'40';
 const pp=renderPaper(t);renderIris(t);
 // during the iris, the Mac and Dock layers must show inside the circle: the paper hides once the iris covers it,
 // and the planes/UI render above the paper via z-index while the iris is open
 const irisOn=t>=T.iris1[0]&&t<T.iris1[1];$('#planes').style.zIndex=irisOn?'52':'';$('#bezel').style.zIndex=irisOn?'52':'';ui.style.zIndex=irisOn?'52':'30';
 if(irisOn){const p=seg(t,T.iris1[0],T.iris1[1],expoIO);const c=map(D,756,DOCK_CY);const R=Math.hypot(W,H)*1.05*p+40;const cp='circle('+R.toFixed(1)+'px at '+c.x.toFixed(1)+'px '+c.y.toFixed(1)+'px)';$('#planes').style.clipPath=cp;$('#bezel').style.clipPath=cp;}
 else{$('#bezel').style.clipPath='';}
 renderType(t);renderLogo(t);
 // the demo note: on the dark Mac shots only
 $('#demo').style.opacity=(t>1&&!(t>=T.paper1[0]&&t<T.iris1[1])&&!(t>=T.paper2[0]&&t<T.toNotch[1])&&t<T.lift2[0])?1:0;
 const v=$('#veil');const fi=1-clamp((t-T.fadeIn[0])/(T.fadeIn[1]-T.fadeIn[0]));const fo=clamp((t-T.fadeOut[0])/(T.fadeOut[1]-T.fadeOut[0]));v.style.opacity=Math.max(fi,fo);
 return {D,cur,dock:{set:d.sh.set,x:d.pose.x,y:d.pose.y,s:d.pose.s,w:d.sh.w},front:front0(t),slide:slideAt(t),stage:stageAt(t),attach:attachAt(t),pv:pvs,sw,morph:mo,island:il,paper:pp};};

// motion probes for the 180° shutter: largest per-frame displacement (px) of moving objects, measured in the DOM
const PROBE=()=>['#pl0','#pl1','#dock','#morph','#paper','#iris','#logo','#mring','.preview','.switcher .selring','#ui',...[0,1,2,3].map(i=>'.card[data-i="'+i+'"]'),...[1,2,3,4,5,6,7].map(i=>'.tile[data-i="'+i+'"]')].map(s=>document.querySelector(s));
function measureAll(){return PROBE().map(e=>{if(!e)return null;let n=e;while(n&&n!==document.body){if(getComputedStyle(n).display==='none')return null;n=n.parentElement;}const r=e.getBoundingClientRect();if(!r.width)return null;
 // clip to a generous frame so huge off-screen layers do not dominate
 return [clamp(r.left,-200,W+200),clamp(r.top,-200,H+200),clamp(r.right,-200,W+200),clamp(r.bottom,-200,H+200)];});}
window.motionAt=function(t){const dt=1/60;window.renderAt(t-dt/2);const a=measureAll();window.renderAt(t+dt/2);const b=measureAll();let v=0;
 for(let i=0;i<a.length;i++){if(!a[i]||!b[i])continue;for(let k=0;k<4;k+=2)v=Math.max(v,Math.hypot(b[i][k]-a[i][k],b[i][k+1]-a[i][k+1]));}
 return v;};
window.metricsAt=function(t){return window.renderAt(t);};
})();`;
