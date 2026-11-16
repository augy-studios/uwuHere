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
const RESAY_INTERVAL_MILLISECONDS = 60000;

let lastSaid = "";
let lastSaidAt = 0;

// Whether this is an app that has the widget, once the app has answered.
async function available() {
  if (!AppBridge.native) {
    return false;
  }
  const appAnswered = await AppBridge.ready(5000);
  if (!appAnswered) {
    return appAnswered;
  }
  return AppBridge.has("widget");
}

// A value, or null when it is null or undefined.
function valueOrNull(value) {
  if (value === null || value === undefined) {
    return null;
  }
  return value;
}

/** The numbers the widget shows. WidgetData.summarise works out the same. */
function summary(code, hostKey, event, attendees) {
  let latest = null;
  for (const attendee of attendees) {
    if (!latest || Date.parse(attendee.checkedInAt) > Date.parse(latest.checkedInAt)) {
      latest = attendee;
    }
  }

  let title = "";
  if (event.title) {
    title = event.title;
  }

  let latestName = null;
  let latestAt = null;
  if (latest !== null) {
    latestName = valueOrNull(latest.name);
    latestAt = valueOrNull(latest.checkedInAt);
  }

  const leftEarlyCount = attendees.filter((attendee) => {
    return attendee.leftEarlyAt;
  }).length;

  return {
    code,
    hostKey,
    title,
    paused: Boolean(event.paused),
    ended: Boolean(event.ended),
    count: attendees.length,
    left: leftEarlyCount,
    latestName,
    latestAt,
  };
}

/** The event as the host page has just had it from the server. */
export async function tellWidget(code, hostKey, event, attendees) {
  if (!AppBridge.native || !hostKey || !event) {
    return;
  }
  const said = summary(code, hostKey, event, attendees);
  const key = JSON.stringify(said);
  if (key === lastSaid && Date.now() - lastSaidAt < RESAY_INTERVAL_MILLISECONDS) {
    return;
  }
  if (!(await available())) {
    return;
  }
  lastSaid = key;
  lastSaidAt = Date.now();
  AppBridge.call("Here", "widget", said).catch(() => {
    lastSaid = "";
  });
}

/** This phone no longer hosts the event: off the widget, if it was there. */
export async function forgetWidget(code) {
  if (!AppBridge.native) {
    return;
  }
  lastSaid = "";
  if (!(await available())) {
    return;
  }
  AppBridge.call("Here", "widget", { code, clear: true }).catch(() => {});
}
