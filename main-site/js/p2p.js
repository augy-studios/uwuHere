// p2p.js: host and attendee pairing over PeerJS, STUN only (STUN-p2p-spec.md).
//
// The host page registers with the public PeerJS broker as "uwuhere-" plus
// the event code. An attendee who taps the button connects to that id, and
// if the data channel opens, the two devices reached each other directly.
// That is the "nearby" proof: with no TURN relay, a direct channel almost
// always means the same wifi or a hotspot.
//
// **There is deliberately no TURN, and must never be.** A relay would let a
// phone anywhere in the world open the channel, and the check would prove
// nothing. PeerJS's default config includes a public TURN server, which is
// why PEER_OPTIONS below replaces it, and why every `new Peer` goes through
// PEER_OPTIONS.
//
// The protocol is a single exchange rather than the spec's running state:
//
//   { type: "checkin", v, deviceHash, name, note }   attendee to host
//   { type: "checked-in", at }                       host to attendee
//   { type: "refused", reason, message }             host to attendee
//   { type: "full" }                                 host to attendee
//   { type: "bye" }                                  attendee to host
//
// so there is no snapshot stream and no heartbeat: each attendee connects,
// says who they are, hears back, and leaves.

const PEERJS_URL = "https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js";
const PEER_PREFIX = "uwuhere-";
// The same alphabet as the server and the code column in the database.
const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXYZ23456789";
export const CODE_LENGTH = 6;
export const PROTOCOL_VERSION = 1;
const CONNECT_TIMEOUT_MS = 15000;

// STUN only. Supplying `config` replaces PeerJS's default, which includes a
// public TURN relay.
const ICE_SERVERS = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun.cloudflare.com:3478" },
];
const PEER_OPTIONS = { debug: 0, config: { iceServers: ICE_SERVERS } };

const BROKER_ERRORS = new Set([
  "network", "server-error", "socket-error", "socket-closed", "disconnected",
]);

/* ---- codes ---- */

export function normaliseCode(input) {
  return String(input || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, CODE_LENGTH);
}

export function isValidCode(input) {
  const code = normaliseCode(input);
  return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c));
}

/* ---- library ---- */

let peerLibrary = null;

function loadPeerJs() {
  if (peerLibrary) return Promise.resolve(peerLibrary);
  if (window.Peer) return Promise.resolve((peerLibrary = window.Peer));

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = PEERJS_URL;
    script.async = true;
    script.onload = () =>
      window.Peer ? resolve((peerLibrary = window.Peer)) : reject(new Error("PeerJS did not define Peer"));
    script.onerror = () => reject(new Error("Could not load PeerJS"));
    document.head.appendChild(script);
  });
}

export function describePeerError(error) {
  switch (error?.type) {
    case "peer-unavailable":
      return "The host's screen is not taking nearby check-ins right now.";
    case "unavailable-id":
      return "This event is already open on another screen.";
    case "network":
    case "server-error":
    case "socket-error":
    case "socket-closed":
      return "Cannot reach the pairing service.";
    case "browser-incompatible":
      return "This browser cannot make peer-to-peer connections.";
    default:
      return "The connection failed.";
  }
}

/* ---- shared ---- */

class Connection extends EventTarget {
  constructor() {
    super();
    this.peer = null;
    this.status = "idle";
  }

  setStatus(status, detail = {}) {
    this.status = status;
    this.dispatchEvent(new CustomEvent("status", { detail: { status, ...detail } }));
  }

  bindLink(link) {
    // A link that closes without ever opening never reached the other device.
    let everOpened = false;
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      this.onLinkClosed(link, everOpened);
    };

    link.on("open", () => {
      everOpened = true;
      this.onLinkOpen(link);
    });
    link.on("data", (message) => {
      if (!message || typeof message !== "object" || typeof message.type !== "string") return;
      this.dispatchEvent(new CustomEvent("message", { detail: { message, from: link.peer } }));
    });
    link.on("close", finish);
    link.on("error", finish);
  }

  // The broker socket can drop while channels stay up. Re-register under the
  // same id, backing off while it keeps failing.
  watchBroker() {
    const peer = this.peer;
    let delay = 1000;
    peer.on("open", () => { delay = 1000; });
    peer.on("disconnected", () => {
      setTimeout(() => {
        if (this.peer === peer && !peer.destroyed && peer.disconnected) peer.reconnect();
      }, delay);
      delay = Math.min(delay * 2, 30000);
    });
  }

  destroyPeer() {
    // Cleared first, so the disconnect that destroy() causes is not retried.
    const peer = this.peer;
    this.peer = null;
    peer?.destroy();
  }
}

/* ---- host ---- */

export class Host extends Connection {
  // Attendees stay connected for a second or two each, so this caps a rush
  // at the door rather than the size of the event.
  constructor({ maxGuests = 40 } = {}) {
    super();
    this.maxGuests = maxGuests;
    this.links = new Map(); // attendee peer id -> open link
  }

  async start(code) {
    const Peer = await loadPeerJs();
    this.code = code;
    this.setStatus("connecting");

    this.peer = new Peer(PEER_PREFIX + code, PEER_OPTIONS);
    this.watchBroker();

    this.peer.on("open", () => this.refreshStatus());
    this.peer.on("connection", (link) => {
      if (this.links.size >= this.maxGuests) {
        link.on("open", () => {
          link.send({ type: "full" });
          link.close({ flush: true });
        });
        return;
      }
      this.bindLink(link);
    });
    this.peer.on("error", (error) => {
      if (error?.type === "unavailable-id") {
        this.setStatus("error", { message: describePeerError(error), taken: true });
        return;
      }
      // Attendees already attached do not need the broker.
      if (this.links.size > 0 && BROKER_ERRORS.has(error?.type)) return;
      this.setStatus("error", { message: describePeerError(error) });
    });
  }

  onLinkOpen(link) {
    this.links.set(link.peer, link);
    this.refreshStatus();
  }

  onLinkClosed(link) {
    // Links this end dropped, and links that never opened, are not in the map.
    if (this.links.get(link.peer) !== link) return;
    this.links.delete(link.peer);
    this.refreshStatus();
  }

  refreshStatus() {
    this.setStatus(this.links.size > 0 ? "connected" : "waiting");
  }

  // Removed before closing: close() emits "close" synchronously.
  drop(id) {
    const link = this.links.get(id);
    if (!link) return;
    this.links.delete(id);
    link.close();
    this.refreshStatus();
  }

  send(message, to) {
    for (const [id, link] of this.links) {
      if (to && id !== to) continue;
      try {
        link.send(message);
      } catch {
        // Closed between the check and the send; its close handler reports it.
      }
    }
  }

  close() {
    for (const id of [...this.links.keys()]) this.drop(id);
    this.destroyPeer();
    this.setStatus("idle");
  }
}

/* ---- attendee ---- */

export class Guest extends Connection {
  constructor() {
    super();
    this.link = null;
    this.timer = null;
  }

  async connect(code) {
    const Peer = await loadPeerJs();
    this.setStatus("connecting");

    this.peer = new Peer(PEER_OPTIONS);
    this.watchBroker();

    // Nothing errors when ICE cannot find a path; it just keeps trying.
    this.timer = setTimeout(() => {
      if (this.status !== "connecting") return;
      this.hangUp();
      this.setStatus("unreachable");
    }, CONNECT_TIMEOUT_MS);

    // once, not on: a broker reconnect fires "open" again.
    this.peer.once("open", () => {
      this.link = this.peer.connect(PEER_PREFIX + code, { reliable: true });
      this.bindLink(this.link);
    });
    this.peer.on("error", (error) => {
      if (this.status === "connected" && BROKER_ERRORS.has(error?.type)) return;
      this.hangUp();
      this.setStatus("error", { message: describePeerError(error), type: error?.type });
    });
  }

  onLinkOpen(link) {
    if (link !== this.link) return;
    clearTimeout(this.timer);
    this.setStatus("connected");
  }

  onLinkClosed(link, everOpened) {
    if (link !== this.link) return;
    this.link = null;
    this.setStatus(everOpened ? "dropped" : "unreachable");
  }

  send(message) {
    if (!this.link?.open) return;
    try {
      this.link.send(message);
    } catch {
      // As on the host.
    }
  }

  // Leaving on purpose: `bye` first, and a flushed close so it arrives.
  leave() {
    this.send({ type: "bye" });
    clearTimeout(this.timer);
    const link = this.link;
    const peer = this.peer;
    this.link = null;
    this.peer = null;
    link?.close({ flush: true });
    setTimeout(() => peer?.destroy(), 1000);
    this.setStatus("idle");
  }

  hangUp() {
    clearTimeout(this.timer);
    const link = this.link;
    this.link = null;
    link?.close();
    this.destroyPeer();
  }

  close() {
    this.hangUp();
    this.setStatus("idle");
  }
}
