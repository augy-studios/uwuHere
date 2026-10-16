// The channel to the Android app (android/), when the site is open in it:
// what the app can do for the page that a web page can't do for itself. The
// app is Capacitor: the site runs in its own WebView, which injects
// window.Capacitor before the page's scripts, and calls go straight to its
// plugin (android/native/app/src/main/java/org/uwuapps/here/HerePlugin.java).
//
// In a browser or the PWA there's no window.Capacitor, and the page carries on
// as a website with everything it already has.
//
//   AppBridge.native                    true in the app
//   AppBridge.has("keepawake")          whether the app says it can
//   AppBridge.ready(ms)                 resolves true once the app has answered, false after ms
//   AppBridge.call(plugin, method, {})  a plugin's answer
//   AppBridge.version()                 the app's version, such as "1.0.0"
//
// Also, in the app: the status bar's icons follow the page's light or dark
// mode, not the phone's.

const cap = window.Capacitor;
const native = Boolean(cap && typeof cap.nativePromise === "function" && cap.getPlatform?.() === "android");

let info = null;
const waiting = [];

function call(plugin, method, options = {}) {
  return native ? cap.nativePromise(plugin, method, options) : Promise.reject(new Error("Not in the app."));
}

function heard(answer) {
  info = answer;
  waiting.splice(0).forEach((resolve) => resolve(true));
}

function ready(ms = 1500) {
  if (info) return Promise.resolve(true);
  if (!native) return Promise.resolve(false);
  return new Promise((resolve) => {
    waiting.push(resolve);
    setTimeout(() => resolve(false), ms);
  });
}

// The site picks light or dark itself (js/theme.js), whatever the phone is
// set to, so the status bar's icons are told which: dark icons on the light
// page, light on the dark.
function syncBars() {
  const style = document.documentElement.getAttribute("data-mode") === "dark" ? "DARK" : "LIGHT";
  call("SystemBars", "setStyle", { style }).catch(() => {});
}

if (native) {
  document.documentElement.setAttribute("data-app", "android");
  call("Here", "info")
    .then(heard)
    .catch(() => heard({ features: [] }));

  syncBars();
  new MutationObserver(syncBars).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mode"] });
}

export const AppBridge = {
  native,
  has: (feature) => Boolean(info?.features?.includes(feature)),
  ready,
  call,
  version: () => info?.version || null,
};
