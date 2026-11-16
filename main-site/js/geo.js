// One reading from the Geolocation API, as { lat, lng, accuracy }, with a
// sentence ready for each way it can fail. Asked for only when somebody
// presses something that needs it, never on page load.
//
// In the Android app the same API works, with Android's own location prompt
// (flutter/android/.../AndroidManifest.xml); only the sentence for a refusal differs.

import { AppBridge } from "./app-bridge.js";

// The sentence shown when location permission was refused. The Android app
// and a browser keep that permission in different places.
let LOCATION_BLOCKED_MESSAGE;
if (AppBridge.native) {
  LOCATION_BLOCKED_MESSAGE =
    "Location is off for uwuHere. Allow it in Android's settings (Apps, uwuHere, Permissions), then try again.";
} else {
  LOCATION_BLOCKED_MESSAGE =
    "Location access is blocked. Allow it for this site in your browser's settings, then try again.";
}

// The Geolocation API's error codes.
const PERMISSION_DENIED_CODE = 1;
const TIMEOUT_CODE = 3;

export function getPosition({ timeout = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) {
      reject(new Error("This browser cannot share its location."));
      return;
    }

    navigator.geolocation.getCurrentPosition(
      (position) => {
        resolve({
          lat: position.coords.latitude,
          lng: position.coords.longitude,
          accuracy: position.coords.accuracy,
        });
      },
      (error) => {
        let message;
        if (error.code === PERMISSION_DENIED_CODE) {
          message = LOCATION_BLOCKED_MESSAGE;
        } else if (error.code === TIMEOUT_CODE) {
          message = "Finding your location took too long. Try again.";
        } else {
          message = "Your location could not be found. Try again.";
        }
        reject(new Error(message));
      },
      { enableHighAccuracy: true, timeout, maximumAge: 0 }
    );
  });
}
