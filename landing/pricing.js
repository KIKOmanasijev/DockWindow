// DogBar landing: pay what you want, from $5, with Paddle checkout.
// The slider picks a whole-dollar amount. Checkout sells that many units of a $1 Paddle
// price, so the price needs a minimum quantity of 5 and a maximum of at least 50 in
// Paddle. Both values below are public by design (Paddle calls client-side tokens safe
// to publish). Until they are filled in, the button stays disabled and says so.
(() => {
  "use strict";

  const PADDLE = {
    token: "",   // client-side token: live_… (or test_… for the sandbox)
    priceId: "", // the $1 one-time price: pri_…
  };
  const MIN = 5;
  const MAX = 50;
  const SCRIPT = "https://cdn.paddle.com/paddle/v2/paddle.js";

  const root = document.querySelector("[data-pwyw]");
  if (!root) return;
  const range = root.querySelector("[data-pwyw-range]");
  const value = root.querySelector("[data-pwyw-value]");
  const total = root.querySelector("[data-pwyw-total]");
  const cta = root.querySelector("[data-pwyw-cta]");
  const pay = root.querySelector("[data-pwyw-pay]");
  const status = root.querySelector("[data-pwyw-status]");

  const amount = () => Math.min(MAX, Math.max(MIN, Math.round(Number(range.value) || MIN)));
  const dollars = (n) => `$${n}`;

  // One amount drives the readout, the total, the button and the slider's spoken value.
  function render() {
    const n = amount();
    range.value = String(n);
    range.setAttribute("aria-valuetext", dollars(n));
    value.textContent = dollars(n);
    total.textContent = dollars(n);
    cta.textContent = dollars(n);
  }
  range.addEventListener("input", render);
  render();

  const configured = /^(live|test)_[A-Za-z0-9]+$/.test(PADDLE.token) && /^pri_[a-z0-9]+$/.test(PADDLE.priceId);
  if (!configured) return; // stays disabled: "Payments aren't open yet."

  pay.disabled = false;
  status.textContent = "Secure checkout by Paddle. You can review the total, including any tax, before paying.";

  let ready = null;
  function loadPaddle() {
    if (ready) return ready;
    ready = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = SCRIPT;
      s.async = true;
      s.onload = () => {
        const P = window.Paddle;
        if (!P) { reject(new Error("Paddle.js missing")); return; }
        if (PADDLE.token.startsWith("test_")) P.Environment.set("sandbox");
        P.Initialize({ token: PADDLE.token });
        resolve(P);
      };
      s.onerror = () => reject(new Error("Paddle.js failed to load"));
      document.head.append(s);
    });
    ready.catch(() => { ready = null; });
    return ready;
  }

  pay.addEventListener("click", async () => {
    const n = amount();
    pay.disabled = true;
    try {
      const P = await loadPaddle();
      P.Checkout.open({
        items: [{ priceId: PADDLE.priceId, quantity: n }],
        settings: { displayMode: "overlay", theme: "light" },
      });
      window.dogbarTrack?.("checkout_opened", { amount: n });
    } catch {
      status.textContent = "Checkout couldn’t load. Please try again in a moment.";
    } finally {
      pay.disabled = false;
    }
  });
})();
