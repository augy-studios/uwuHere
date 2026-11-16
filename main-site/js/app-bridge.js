// The channel to the 1.0.x Android app (Capacitor; 2.0 is flutter/), when the site is open in it:
// what the app can do for the page that a web page can't do for itself. The
// app is Capacitor: the site runs in its own WebView, which injects
// window.Capacitor before the page's scripts, and calls go straight to its
// plugin (HerePlugin.java, now in git history; the 2.0 app answers the same calls).
//
// In a browser or the PWA there's no window.Capacitor, and the page carries on
// as a website with everything it already has.
//
//   AppBridge.native                    true in the app
//   AppBridge.has("keepawake")          whether the app says it can
//   AppBridge.ready(milliseconds)       resolves true once the app has answered, false after that long
//   AppBridge.call(plugin, method, {})  a plugin's answer
//   AppBridge.listen(plugin, name, handler)  handler(data) each time the plugin says name
//   AppBridge.version()                 the app's version, such as "1.0.0"
//
// Also, in the app: the status bar's icons follow the page's light or dark
// mode, not the phone's, and from app 1.0.1 (user agent uwuHereApp/2) there's
// no status bar to leave room for (data-statusbar="hidden", css/app.css).

const capacitor = window.Capacitor;

// Whether this page is running inside the Android app's WebView: Capacitor is
// there, can make calls, and says the platform is Android.
function isInsideAndroidApp() {
  if (!capacitor) {
    return false;
  }
  if (typeof capacitor.nativePromise !== "function") {
    return false;
  }
  if (capacitor.getPlatform === null || capacitor.getPlatform === undefined) {
    return false;
  }
  return capacitor.getPlatform() === "android";
}

const native = isInsideAndroidApp();

// What the app said about itself (its version and features), once it has answered.
let info = null;
// The resolve functions of every ready() still waiting for that answer.
const waiting = [];

function call(plugin, method, options = {}) {
  if (native) {
    return capacitor.nativePromise(plugin, method, options);
  }
  return Promise.reject(new Error("Not in the app."));
}

// Capacitor's own bridge has addListener on window.Capacitor. Outside the
// app, nothing is ever said.
function listen(plugin, name, handler) {
  if (!native || typeof capacitor.addListener !== "function") {
    return;
  }
  try {
    capacitor.addListener(plugin, name, handler);
  } catch {
    // An app too old to say it: the page carries on without hearing.
  }
}

function heard(answer) {
  info = answer;
  waiting.splice(0).forEach((resolve) => {
    resolve(true);
  });
}

function ready(timeoutMilliseconds = 1500) {
  if (info) {
    return Promise.resolve(true);
  }
  if (!native) {
    return Promise.resolve(false);
  }
  return new Promise((resolve) => {
    waiting.push(resolve);
    setTimeout(() => {
      resolve(false);
    }, timeoutMilliseconds);
  });
}

// The site picks light or dark itself (js/theme.js), whatever the phone is
// set to, so the status bar's icons are told which: dark icons on the light
// page, light on the dark.
function syncStatusBarStyle() {
  let style;
  if (document.documentElement.getAttribute("data-mode") === "dark") {
    style = "DARK";
  } else {
    style = "LIGHT";
  }
  call("SystemBars", "setStyle", { style }).catch(() => {});
}

// The app's build number from the user agent ("uwuHereApp/2" is build 2), or 0.
function readAppBuildNumber() {
  const match = /uwuHereApp\/(\d+)/.exec(navigator.userAgent);
  if (match === null || !match[1]) {
    return 0;
  }
  return Number(match[1]);
}

if (native) {
  document.documentElement.setAttribute("data-app", "android");
  // Read from the user agent, not Here.info, so the page is laid out right
  // from the start. 1.0.0 (uwuHereApp/1) still has the bar.
  const build = readAppBuildNumber();
  if (build >= 2) {
    document.documentElement.setAttribute("data-statusbar", "hidden");
  }
  call("Here", "info")
    .then(heard)
    .catch(() => {
      heard({ features: [] });
    });

  syncStatusBarStyle();
  new MutationObserver(syncStatusBarStyle).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-mode"],
  });
}

// Whether the app said it can do this feature.
function has(feature) {
  if (info === null || info === undefined) {
    return false;
  }
  if (info.features === null || info.features === undefined) {
    return false;
  }
  return Boolean(info.features.includes(feature));
}

// The app's version, such as "1.0.0", or null before it has answered.
function version() {
  if (info === null || info === undefined) {
    return null;
  }
  if (info.version) {
    return info.version;
  }
  return null;
}

export const AppBridge = {
  native,
  has,
  ready,
  call,
  listen,
  version,
};
