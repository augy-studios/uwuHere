// One reading from the Geolocation API, as { lat, lng, accuracy }, with a
// sentence ready for each way it can fail. Asked for only when somebody
// presses something that needs it, never on page load.

export function getPosition({ timeout = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) {
      reject(new Error("This browser cannot share its location."));
      return;
    }

    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy }),
      (error) => {
        const message =
          error.code === 1
            ? "Location access is blocked. Allow it for this site in your browser's settings, then try again."
            : error.code === 3
              ? "Finding your location took too long. Try again."
              : "Your location could not be found. Try again.";
        reject(new Error(message));
      },
      { enableHighAccuracy: true, timeout, maximumAge: 0 }
    );
  });
}
