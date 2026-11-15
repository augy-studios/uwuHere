// Same-wifi check-in: host and attendee over PeerJS, STUN only (main-site/js/p2p.js,
// docs/STUN-p2p-spec.md).
//
// The host page registers with the public PeerJS broker as "uwuhere-" plus the event code. An
// attendee who presses the button connects to that id, and if the data channel opens, the two
// devices reached each other directly. That's the "nearby" proof: with no TURN relay, a direct
// channel almost always means the same wifi or a hotspot.
//
// A single exchange:
//
//   { type: "checkin", v, deviceHash, name, note }   attendee to host
//   { type: "checked-in", at }                       host to attendee
//   { type: "refused", reason, message }             host to attendee
//   { type: "full" }                                 host to attendee
//   { type: "bye" }                                  attendee to host
import 'dart:async';

import 'peer.dart';

const peerPrefix = 'uwuhere-';
const protocolVersion = 1;
const _connectTimeout = Duration(seconds: 15);

/// "idle", "connecting", "waiting", "connected", "error" (host); "unreachable", "dropped" (guest).
class P2pStatus {
  const P2pStatus(this.status, {this.message = '', this.taken = false, this.type = ''});
  final String status;
  final String message;
  final bool taken;
  final String type;
}

/// The host page's end: takes check-ins while it's open.
class P2pHost {
  P2pHost({this.maxGuests = 40, required this.onStatus, required this.onMessage});

  final int maxGuests;
  final void Function(P2pStatus status) onStatus;
  final void Function(Map<String, dynamic> message, ShareLink from) onMessage;

  PeerListener? _listener;
  final Set<ShareLink> _links = {};
  bool _closed = false;

  Future<void> start(String code) async {
    onStatus(const P2pStatus('connecting'));
    final l = PeerListener(
      code,
      onOpen: _refresh,
      onLink: (link) {
        if (_links.length >= maxGuests) {
          link.onOpen = () {
            link.send({'type': 'full'});
            link.close(flush: true);
          };
          return;
        }
        link.onOpen = () {
          _links.add(link);
          _refresh();
        };
        link.onData = (m) => onMessage(m, link);
        link.onClose = () {
          if (_links.remove(link)) _refresh();
        };
      },
      onError: (type) {
        if (_closed) return;
        if (type == 'unavailable-id') {
          onStatus(P2pStatus('error', message: describePeerError(type), taken: true));
          return;
        }
        // Attendees already attached don't need the broker.
        if (_links.isNotEmpty && brokerErrors.contains(type)) return;
        onStatus(P2pStatus('error', message: describePeerError(type)));
      },
    );
    _listener = l;
    await l.start();
  }

  void _refresh() {
    if (_closed) return;
    onStatus(P2pStatus(_links.isNotEmpty ? 'connected' : 'waiting'));
  }

  void send(Map<String, Object?> message, ShareLink to) {
    try {
      to.send(message);
    } catch (_) {
      // Closed between the check and the send; its close handler reports it.
    }
  }

  void close() {
    _closed = true;
    for (final l in List.of(_links)) {
      l.close();
    }
    _links.clear();
    _listener?.close();
    _listener = null;
  }
}

/// The attendee's end: one check-in, then gone.
class P2pGuest {
  P2pGuest({required this.onStatus, required this.onMessage});

  final void Function(P2pStatus status) onStatus;
  final void Function(Map<String, dynamic> message) onMessage;

  PeerDialer? _dialer;
  ShareLink? _link;
  Timer? _timer;
  String _status = 'idle';

  void _set(P2pStatus s) {
    _status = s.status;
    onStatus(s);
  }

  Future<void> connect(String code) async {
    _set(const P2pStatus('connecting'));
    // Nothing errors when ICE can't find a path; it just keeps trying.
    _timer = Timer(_connectTimeout, () {
      if (_status != 'connecting') return;
      hangUp();
      _set(const P2pStatus('unreachable'));
    });
    final d = PeerDialer(
      onLink: (link) {
        _link = link;
        link.onOpen = () {
          _timer?.cancel();
          _set(const P2pStatus('connected'));
        };
        link.onData = onMessage;
        link.onClose = () {
          if (_link != link) return;
          _link = null;
          _set(P2pStatus(link.everOpened ? 'dropped' : 'unreachable'));
        };
      },
      onError: (type) {
        if (_status == 'connected' && brokerErrors.contains(type)) return;
        hangUp();
        _set(P2pStatus('error', message: describePeerError(type), type: type));
      },
    );
    _dialer = d;
    await d.connect(code);
  }

  void send(Map<String, Object?> message) {
    final l = _link;
    if (l == null || !l.isOpen) return;
    try {
      l.send(message);
    } catch (_) {
      // As on the host.
    }
  }

  /// Leaving on purpose: `bye` first, and a flushed close so it arrives.
  void leave() {
    send({'type': 'bye'});
    _timer?.cancel();
    final l = _link;
    _link = null;
    l?.close(flush: true);
    final d = _dialer;
    _dialer = null;
    Timer(const Duration(seconds: 1), () => d?.close());
    _status = 'idle';
  }

  void hangUp() {
    _timer?.cancel();
    final l = _link;
    _link = null;
    l?.close();
    _dialer?.close();
    _dialer = null;
  }

  void close() {
    hangUp();
    _status = 'idle';
  }
}
