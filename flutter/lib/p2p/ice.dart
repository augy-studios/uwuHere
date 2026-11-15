// The ICE servers a same-wifi check-in uses: STUN only, as main-site/js/p2p.js has them.
//
// **There is deliberately no TURN, and must never be.** A relay would let a phone anywhere in the
// world open the channel, and the check would prove nothing. A direct channel almost always means
// the same wifi or a hotspot (docs/STUN-p2p-spec.md).
class Ice {
  Ice._();

  static const stun = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  static Future<List<Map<String, dynamic>>> servers() async => stun;
}
