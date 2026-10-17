// The "Your event" home screen widget, in the Android app only
// (EventWidget.java): the event this phone hosts, with how many are here, who
// checked in last, and its code, drawn with the app closed.
//
// The host page tells the app what it has each time it has the event from the
// server (tellWidget), and the widget refreshes itself from /api/host with the
// same host key from then on (WidgetData.java). Once the page no longer has
// the event (forgotten, deleted, or the key stopped working), forgetWidget
// takes it off the widget.
//
// Quietly nothing in a browser, or in an app too old to have the widget.

import { AppBridge } from "./app-bridge.js";

// Said again once a minute even when nothing changed, so the widget's
// "Updated" time keeps up while the host page is open.
const RESAY_MS = 60000;

let lastSaid = "";
let lastSaidAt = 0;

async function available() {
  return AppBridge.native && (await AppBridge.ready(5000)) && AppBridge.has("widget");
}

/** The numbers the widget shows. WidgetData.summarise works out the same. */
function summary(code, hostKey, event, attendees) {
  let latest = null;
  for (const a of attendees) {
    if (!latest || Date.parse(a.checkedInAt) > Date.parse(latest.checkedInAt)) latest = a;
  }
  return {
    code,
    hostKey,
    title: event.title || "",
    paused: Boolean(event.paused),
    ended: Boolean(event.ended),
    count: attendees.length,
    left: attendees.filter((a) => a.leftEarlyAt).length,
    latestName: latest?.name ?? null,
    latestAt: latest?.checkedInAt ?? null,
  };
}

/** The event as the host page has just had it from the server. */
export async function tellWidget(code, hostKey, event, attendees) {
  if (!AppBridge.native || !hostKey || !event) return;
  const said = summary(code, hostKey, event, attendees);
  const key = JSON.stringify(said);
  if (key === lastSaid && Date.now() - lastSaidAt < RESAY_MS) return;
  if (!(await available())) return;
  lastSaid = key;
  lastSaidAt = Date.now();
  AppBridge.call("Here", "widget", said).catch(() => {
    lastSaid = "";
  });
}

/** This phone no longer hosts the event: off the widget, if it was there. */
export async function forgetWidget(code) {
  if (!AppBridge.native) return;
  lastSaid = "";
  if (!(await available())) return;
  AppBridge.call("Here", "widget", { code, clear: true }).catch(() => {});
}
