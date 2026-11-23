/* Pushes to the Android app (flutter/) through Firebase Cloud Messaging, to
   a topic. The app joins its topics when you turn them on with the bell in
   the Edge Tray (HerePlugin.setTopic), so there is no list of phones to keep:

     uwuhere-host-<40 hex>   an event's check-ins, from api/_lib/alerts.js
     uwuhere-releases        new versions, from api/push/release.js
     uwuhere-news            sent by hand from the Firebase console
                             (flutter/FIREBASE-SETUP.md)

   FCM's HTTP v1 API, with an OAuth token made from the Firebase project's
   service account: FIREBASE_SERVICE_ACCOUNT holds its JSON key, as
   downloaded or base64'd. The token is signed here with node:crypto, so there
   is no Google library, and kept until just before it runs out. */

import { createSign } from "node:crypto";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_MARGIN_SECONDS = 300;

// undefined until the environment has been read once, then the parsed
// service account, or null when there is none to use.
let account;
let cachedToken = null;
let cachedTokenExpiresAt = 0;

// The service account from FIREBASE_SERVICE_ACCOUNT, read and checked once,
// as JSON or as base64 of the JSON. null when it is missing or unusable.
function serviceAccount() {
  if (account !== undefined) {
    return account;
  }
  const setting = process.env.FIREBASE_SERVICE_ACCOUNT;
  let rawSetting = undefined;
  if (setting !== null && setting !== undefined) {
    rawSetting = setting.trim();
  }
  account = null;
  if (!rawSetting) {
    return account;
  }
  try {
    let json;
    if (rawSetting.startsWith("{")) {
      json = rawSetting;
    } else {
      json = Buffer.from(rawSetting, "base64").toString("utf8");
    }
    const parsed = JSON.parse(json);
    if (parsed.project_id && parsed.client_email && parsed.private_key) {
      account = parsed;
    } else {
      console.error("[fcm] FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key");
    }
  } catch {
    console.error("[fcm] FIREBASE_SERVICE_ACCOUNT isn't the service account's JSON key");
  }
  return account;
}

export function fcmConfigured() {
  return Boolean(serviceAccount());
}

// A string, or anything else as JSON, in base64url, for the parts of a JWT.
function toBase64Url(value) {
  let text;
  if (typeof value === "string") {
    text = value;
  } else {
    text = JSON.stringify(value);
  }
  return Buffer.from(text).toString("base64url");
}

// Reads a response's JSON body, or null if it is not JSON.
async function readJsonOrNull(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

// An OAuth access token for FCM: the one kept from last time while it has more
// than TOKEN_MARGIN_SECONDS left, otherwise a fresh one, got by signing a JWT
// with the service account's private key and trading it at Google's token URL.
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now < cachedTokenExpiresAt - TOKEN_MARGIN_SECONDS) {
    return cachedToken;
  }
  const currentAccount = serviceAccount();
  const header = toBase64Url({ alg: "RS256", typ: "JWT" });
  const claims = toBase64Url({
    iss: currentAccount.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  });
  const unsigned = `${header}.${claims}`;
  const signature = createSign("RSA-SHA256").update(unsigned).sign(currentAccount.private_key).toString("base64url");
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${signature}` }),
    cache: "no-store",
    signal: AbortSignal.timeout(10_000),
  });
  const data = await readJsonOrNull(response);

  let hasAccessToken = false;
  if (data !== null && data !== undefined && data.access_token) {
    hasAccessToken = true;
  }
  if (!response.ok || !hasAccessToken) {
    let detail = "";
    if (data !== null && data !== undefined) {
      if (data.error_description) {
        detail = data.error_description;
      } else if (data.error) {
        detail = data.error;
      }
    }
    throw new Error(`Google token responded ${response.status}: ${detail}`);
  }

  cachedToken = data.access_token;
  let lifetimeSeconds = Number(data.expires_in);
  if (!lifetimeSeconds) {
    lifetimeSeconds = 3600;
  }
  cachedTokenExpiresAt = now + lifetimeSeconds;
  return cachedToken;
}

/**
 * A notification to every phone on `topic`, on the app's `channel`
 * (Notifications.java). `tag` replaces an earlier one with the same tag
 * rather than stacking under it. `data` reaches the app when it is tapped
 * (MainActivity.onNewIntent). `ttl` is how long FCM keeps trying a phone
 * that is off, in seconds.
 */
export async function sendToTopic(topic, { title, body, data = {}, channel, tag, ttl = 86400 }) {
  if (!fcmConfigured()) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT is not set");
  }
  // FCM takes data values as strings only.
  const dataAsStrings = Object.fromEntries(Object.entries(data).map(([key, value]) => {
    return [key, String(value)];
  }));
  const message = {
    topic,
    notification: { title, body },
    data: dataAsStrings,
    android: {
      ttl: `${ttl}s`,
      notification: { channel_id: channel, tag, icon: "ic_notification_icon" },
    },
  };

  const sendOnce = async () => {
    const sendUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`;
    return fetch(sendUrl, {
      method: "POST",
      headers: { authorization: `Bearer ${await accessToken()}`, "content-type": "application/json" },
      body: JSON.stringify({ message }),
      cache: "no-store",
      signal: AbortSignal.timeout(10_000),
    });
  };
  let response = await sendOnce();
  // A token Google took back early: once more with a fresh one.
  if (response.status === 401) {
    cachedToken = null;
    response = await sendOnce();
  }
  if (response.ok) {
    return;
  }
  let detail = "";
  try {
    detail = await response.text();
  } catch {
    detail = "";
  }
  throw new Error(`FCM responded ${response.status}: ${detail.slice(0, 300)}`);
}
