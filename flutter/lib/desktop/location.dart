// Location where the system can't give it (docs/desktop-features-spec.md §12): Linux without a
// location service. The app scans Wi-Fi with NetworkManager, drops networks whose name ends
// _nomap, takes up to 40 strongest, turns signal 0–100 into dBm (signal/2 - 100), and asks
// BeaconDB with a user agent naming the app. It refuses anything less accurate than 3 km (a guess
// from the internet address), keeps an answer for 4 s, and respects GNOME's Location Services
// switch: off, it says so and doesn't look. Only hardware addresses and strengths leave the
// computer.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/geo.dart';

class LinuxLocation {
  LinuxLocation._();

  static Position2? _last;
  static DateTime? _at;

  static Future<Position2?> find() async {
    if (!Platform.isLinux) return null;
    final at = _at;
    if (_last != null && at != null && DateTime.now().difference(at) < const Duration(seconds: 4)) return _last;
    try {
      final g = await Process.run('gsettings', ['get', 'org.gnome.system.location', 'enabled']);
      if ('${g.stdout}'.trim() == 'false') {
        throw GeoError('Location Services are off. Turn them on in Settings, Privacy, Location, then try again.');
      }
    } on GeoError {
      rethrow;
    } catch (_) {
      // Not GNOME: carry on.
    }
    final r = await Process.run('nmcli', ['-t', '-f', 'SSID,BSSID,SIGNAL,FREQ', 'dev', 'wifi', 'list', '--rescan', 'auto']);
    if (r.exitCode != 0) return null;
    final aps = <Map<String, Object>>[];
    for (final line in '${r.stdout}'.split('\n')) {
      // Fields are split by unescaped colons; the BSSID's own are escaped as \:.
      final parts = line.replaceAll(r'\:', '\u0000').split(':').map((p) => p.replaceAll('\u0000', ':')).toList();
      if (parts.length < 4) continue;
      final ssid = parts[0];
      if (ssid.endsWith('_nomap')) continue;
      final signal = int.tryParse(parts[2]) ?? 0;
      final freq = int.tryParse(parts[3].replaceAll(RegExp(r'\D'), '')) ?? 0;
      aps.add({'macAddress': parts[1].toLowerCase(), 'signalStrength': signal ~/ 2 - 100, 'frequency': freq});
    }
    aps.sort((a, b) => (b['signalStrength'] as int).compareTo(a['signalStrength'] as int));
    if (aps.isEmpty) return null;
    final res = await http
        .post(
          Uri.parse('https://api.beacondb.net/v1/geolocate'),
          headers: {'Content-Type': 'application/json', 'User-Agent': 'uwuHere desktop'},
          body: jsonEncode({'considerIp': true, 'wifiAccessPoints': aps.take(40).toList()}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final v = jsonDecode(res.body);
    final loc = v is Map ? v['location'] : null;
    final acc = v is Map ? (v['accuracy'] as num?)?.toDouble() : null;
    if (loc is! Map || acc == null || acc > 3000) return null;
    _last = Position2((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble(), acc);
    _at = DateTime.now();
    return _last;
  }
}
