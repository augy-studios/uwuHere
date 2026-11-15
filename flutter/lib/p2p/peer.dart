// PeerJS's public broker and its data channels (main-site/js/p2p.js, which loads PeerJS 1.5.4,
// and docs/STUN-p2p-spec.md): the same broker, ids, wire and BinaryPack as PeerJS's, so the app's
// host page takes check-ins from the site's attendee page, and the other way round.
//
//   The broker  wss://0.peerjs.com/peerjs?key=peerjs&id=…&token=…: OPEN once registered, ID-TAKEN,
//               EXPIRE (the peer asked for isn't there), and OFFER, ANSWER and CANDIDATE between
//               peers, relayed by `dst` and `src`; a HEARTBEAT every 5 s.
//   A link      one WebRTC data channel, made by the attendee (its label the connection's id,
//               "dc_…"), each message BinaryPack-packed, and one over 16300 bytes sent as chunks:
//               { __peerData, n, total, data }, put back together on arrival.
//
// STUN only (ice.dart): never a relay.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'binarypack.dart';
import 'here_p2p.dart' show peerPrefix;
import 'ice.dart';

const _brokerHost = '0.peerjs.com';
const _mtu = 16300;
const _bufferHigh = 1024 * 1024;

// Not 1 << 32, which is 0 in Dart on the web.
String _token() => [for (var i = 0; i < 2; i++) math.Random.secure().nextInt(0x7fffffff).toRadixString(36)].join();

/// A link to one other device over PeerJS.
abstract class ShareLink {
  /// Whether the channel ever opened: a link that closes without having opened never reached the
  /// other end (remote.js's everOpened).
  bool get everOpened;

  /// The other end's name: its broker id.
  String get peer;
  bool get isOpen;

  void Function()? onOpen;
  void Function(Map<String, dynamic> message)? onData;
  void Function()? onClose;

  void send(Map<String, Object?> message);
  Future<void> close({bool flush = false});

  /// Whether the next chunk should wait.
  Future<bool> congested();
}

/// What went wrong, as p2p.js's describePeerError says it.
String describePeerError(String type) => switch (type) {
  'peer-unavailable' => "The host's screen is not taking nearby check-ins right now.",
  'unavailable-id' => 'This event is already open on another screen.',
  'network' || 'server-error' || 'socket-error' || 'socket-closed' => 'Cannot reach the pairing service.',
  'browser-incompatible' => 'This device cannot make peer-to-peer connections.',
  _ => 'The connection failed.',
};

const brokerErrors = {'network', 'server-error', 'socket-error', 'socket-closed', 'disconnected'};

/// One id on the broker. The socket can drop while channels stay up: it comes back under the same
/// id, backing off while it keeps failing.
class PeerBroker {
  PeerBroker(this.id, {required this.onMessage, required this.onOpen, required this.onError});

  final String id;
  final Future<void> Function(Map<String, dynamic> m) onMessage;
  final void Function() onOpen;
  final void Function(String type) onError;
  final String _tokenValue = _token();

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _beat;
  Timer? _retry;
  Duration _delay = const Duration(seconds: 1);
  bool _closed = false;
  bool isOpen = false;

  // One at a time, in order: a candidate must not overtake the offer it belongs to.
  Future<void> _queue = Future.value();

  /// A random id from the broker, for a guest.
  static Future<String> newId() async {
    final r = await http
        .get(Uri.parse('https://$_brokerHost:443/peerjs/id?ts=${DateTime.now().millisecondsSinceEpoch}${math.Random().nextDouble()}'))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'server-error';
    return r.body.trim();
  }

  Future<void> connect() async {
    if (_closed) return;
    final url = 'wss://$_brokerHost:443/peerjs?key=peerjs&id=${Uri.encodeComponent(id)}&token=$_tokenValue&version=1.5.4';
    final WebSocketChannel ws;
    try {
      ws = WebSocketChannel.connect(Uri.parse(url));
      await ws.ready.timeout(const Duration(seconds: 15));
    } catch (_) {
      _dropped('network');
      return;
    }
    if (_closed) {
      ws.sink.close();
      return;
    }
    _ws = ws;
    _sub = ws.stream.listen(
      (raw) {
        final Map<String, dynamic> m;
        try {
          m = Map<String, dynamic>.from(jsonDecode('$raw') as Map);
        } catch (_) {
          return;
        }
        switch (m['type']) {
          case 'OPEN':
            isOpen = true;
            _delay = const Duration(seconds: 1);
            onOpen();
          case 'ID-TAKEN':
            onError('unavailable-id');
          case 'ERROR':
            onError('server-error');
          case 'HEARTBEAT':
            break;
          default:
            _queue = _queue.then((_) => onMessage(m)).catchError((Object _) {});
        }
      },
      onDone: () => _dropped('socket-closed'),
      onError: (Object _) => _dropped('socket-error'),
    );
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 5), (_) => send({'type': 'HEARTBEAT'}));
  }

  void _dropped(String why) {
    _beat?.cancel();
    _sub?.cancel();
    _sub = null;
    _ws = null;
    final was = isOpen;
    isOpen = false;
    if (_closed) return;
    // Said once for each time it's lost, and tried again after a while.
    if (was || why == 'network') onError(why);
    _retry?.cancel();
    _retry = Timer(_delay, connect);
    _delay = Duration(milliseconds: math.min(_delay.inMilliseconds * 2, 30000));
  }

  void send(Map<String, Object?> m) {
    try {
      _ws?.sink.add(jsonEncode(m));
    } catch (_) {
      // Going down: its close says so.
    }
  }

  void close() {
    _closed = true;
    isOpen = false;
    _beat?.cancel();
    _retry?.cancel();
    _sub?.cancel();
    _ws?.sink.close();
    _ws = null;
  }
}

Future<RTCPeerConnection> _newConnection() async =>
    createPeerConnection({'iceServers': await Ice.servers(), 'sdpSemantics': 'unified-plan'});

/// One data channel to the other device.
class PeerLink extends ShareLink {
  PeerLink._(this.peer, this.connectionId, this._pc);

  @override
  final String peer;
  final String connectionId;
  final RTCPeerConnection _pc;

  RTCDataChannel? _dc;
  bool _open = false;
  bool _everOpened = false;

  @override
  bool get everOpened => _everOpened;
  bool _gone = false;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _early = [];
  final Map<int, List<Uint8List?>> _chunks = {};
  int _chunkId = 0;

  @override
  bool get isOpen => _open;

  void _bind(RTCDataChannel dc) {
    _dc = dc;
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && !_open) {
        _open = true;
        _everOpened = true;
        onOpen?.call();
      } else if (s == RTCDataChannelState.RTCDataChannelClosed) {
        _closed();
      }
    };
    dc.onMessage = (m) => _receive(m.isBinary ? m.binary : Uint8List.fromList(utf8.encode(m.text)));
    // Opened before the handler above was there.
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen && !_open) {
      _open = true;
      _everOpened = true;
      onOpen?.call();
    }
  }

  void _watch() {
    _pc.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed || s == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _closed();
      }
    };
  }

  void _closed() {
    if (_gone) return;
    _gone = true;
    _open = false;
    onClose?.call();
  }

  void _receive(Uint8List bytes) {
    Object? v;
    try {
      v = BinaryPack.unpack(bytes);
    } catch (_) {
      return;
    }
    if (v is! Map) return;
    if (v['__peerData'] != null) {
      final id = v['__peerData'], total = v['total'], n = v['n'], part = v['data'];
      if (id is! num || total is! num || n is! num || part is! Uint8List) return;
      if (total < 1 || total > 100000 || n < 0 || n >= total) return;
      // Bounded, so a device that starts long messages and never finishes them can't fill this
      // one's memory.
      if (!_chunks.containsKey(id.toInt()) && _chunks.length >= 8) _chunks.remove(_chunks.keys.first);
      final list = _chunks[id.toInt()] ??= List<Uint8List?>.filled(total.toInt(), null);
      if (n >= list.length) return;
      list[n.toInt()] = part;
      if (list.every((c) => c != null)) {
        _chunks.remove(id.toInt());
        final whole = BytesBuilder(copy: false);
        for (final c in list) {
          whole.add(c!);
        }
        _receive(whole.takeBytes());
      }
      return;
    }
    if (v['type'] is String) onData?.call(Map<String, dynamic>.from(v));
  }

  @override
  void send(Map<String, Object?> message) {
    final dc = _dc;
    if (dc == null || !_open) return;
    final bytes = BinaryPack.pack(message);
    if (bytes.length <= _mtu) {
      dc.send(RTCDataChannelMessage.fromBinary(bytes)).catchError((Object _) {});
      return;
    }
    final id = _chunkId++;
    final total = (bytes.length / _mtu).ceil();
    for (var n = 0; n < total; n++) {
      final part = Uint8List.sublistView(bytes, n * _mtu, math.min(bytes.length, (n + 1) * _mtu));
      dc.send(RTCDataChannelMessage.fromBinary(BinaryPack.pack({'__peerData': id, 'n': n, 'total': total, 'data': part}))).catchError((Object _) {});
    }
  }

  @override
  Future<bool> congested() async {
    final dc = _dc;
    if (dc == null) return false;
    try {
      return await dc.getBufferedAmount() > _bufferHigh;
    } catch (_) {
      return false;
    }
  }

  Future<void> _remote(Map sdp) async {
    await _pc.setRemoteDescription(RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'));
    _remoteSet = true;
    for (final c in _early) {
      await _pc.addCandidate(c);
    }
    _early.clear();
  }

  Future<void> _candidate(Map c) async {
    final cand = RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt());
    if (_remoteSet) {
      await _pc.addCandidate(cand);
    } else {
      _early.add(cand);
    }
  }

  @override
  Future<void> close({bool flush = false}) async {
    if (flush) await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await _dc?.close();
    } catch (_) {
      // Already closing.
    }
    try {
      await _pc.close();
    } catch (_) {
      // Already closed.
    }
    _closed();
  }
}

/// The host's end: takes the links that come to its id on the broker.
class PeerListener {
  PeerListener(String code, {required this.onLink, required this.onOpen, required this.onError}) {
    _broker = PeerBroker(peerPrefix + code, onMessage: _heard, onOpen: onOpen, onError: onError);
  }

  final void Function(ShareLink link) onLink;
  final void Function() onOpen;
  final void Function(String type) onError;
  late final PeerBroker _broker;
  final Map<String, PeerLink> _links = {}; // connection id -> link

  Future<void> start() => _broker.connect();

  Future<void> _heard(Map<String, dynamic> m) async {
    final payload = (m['payload'] as Map?) ?? const {};
    final src = '${m['src'] ?? ''}';
    final connectionId = '${payload['connectionId']}';
    if (m['type'] == 'OFFER') {
      final pc = await _newConnection();
      final link = PeerLink._(src, connectionId, pc);
      _links[connectionId] = link;
      pc.onIceCandidate = (c) => _broker.send({
        'type': 'CANDIDATE',
        'payload': {'candidate': c.toMap(), 'type': 'data', 'connectionId': connectionId},
        'dst': src,
      });
      pc.onDataChannel = link._bind;
      link._watch();
      onLink(link);
      await link._remote(payload['sdp'] as Map);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _broker.send({
        'type': 'ANSWER',
        'payload': {
          'sdp': {'type': answer.type, 'sdp': answer.sdp},
          'type': 'data',
          'connectionId': connectionId,
          'browser': 'flutter',
        },
        'dst': src,
      });
    } else if (m['type'] == 'CANDIDATE') {
      await _links[connectionId]?._candidate(payload['candidate'] as Map);
    } else if (m['type'] == 'LEAVE' || m['type'] == 'EXPIRE') {
      // Its channels say so themselves when they close.
    }
  }

  void close() {
    _links.clear();
    _broker.close();
  }
}

/// The attendee's end: connects to the host page showing a code.
class PeerDialer {
  PeerDialer({required this.onLink, required this.onError});

  final void Function(ShareLink link) onLink;
  final void Function(String type) onError;
  PeerBroker? _broker;
  PeerLink? _link;
  bool _closed = false;

  Future<void> connect(String code) async {
    final String id;
    try {
      id = await PeerBroker.newId();
    } catch (_) {
      if (!_closed) onError('network');
      return;
    }
    if (_closed) return;
    var dialed = false;
    late final PeerBroker broker;
    broker = PeerBroker(
      id,
      onMessage: _heard,
      onOpen: () {
        // Once: a broker reconnect says it's open again.
        if (dialed || _closed) return;
        dialed = true;
        _dial(broker, code);
      },
      onError: (type) {
        if (!_closed) onError(type);
      },
    );
    _broker = broker;
    await broker.connect();
  }

  Future<void> _dial(PeerBroker broker, String code) async {
    final pc = await _newConnection();
    if (_closed) {
      await pc.close();
      return;
    }
    final connectionId = 'dc_${_token()}';
    final dst = peerPrefix + code;
    final link = PeerLink._(dst, connectionId, pc);
    _link = link;
    pc.onIceCandidate = (c) => broker.send({
      'type': 'CANDIDATE',
      'payload': {'candidate': c.toMap(), 'type': 'data', 'connectionId': connectionId},
      'dst': dst,
    });
    link._watch();
    onLink(link);
    link._bind(await pc.createDataChannel(connectionId, RTCDataChannelInit()..ordered = true));
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    broker.send({
      'type': 'OFFER',
      'payload': {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
        'type': 'data',
        'connectionId': connectionId,
        'label': connectionId,
        'reliable': true,
        'serialization': 'binary',
        'browser': 'flutter',
      },
      'dst': dst,
    });
  }

  Future<void> _heard(Map<String, dynamic> m) async {
    final payload = (m['payload'] as Map?) ?? const {};
    if (m['type'] == 'EXPIRE') {
      if (!_closed) onError('peer-unavailable');
      return;
    }
    final link = _link;
    if (link == null || payload['connectionId'] != link.connectionId) return;
    if (m['type'] == 'ANSWER') await link._remote(payload['sdp'] as Map);
    if (m['type'] == 'CANDIDATE') await link._candidate(payload['candidate'] as Map);
  }

  /// Off the broker: links already open carry on without it.
  void close() {
    _closed = true;
    _broker?.close();
    _broker = null;
  }
}
