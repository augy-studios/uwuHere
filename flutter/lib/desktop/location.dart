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

  static Position2? _lastPosition;
  static DateTime? _lastFoundAt;

  /// Where this computer is, from the Wi-Fi networks around it, or null when it can't be told.
  static Future<Position2?> find() async {
    if (!Platform.isLinux) return null;
    final lastFoundAt = _lastFoundAt;
    if (_lastPosition != null && lastFoundAt != null && DateTime.now().difference(lastFoundAt) < const Duration(seconds: 4)) return _lastPosition;
    try {
      final gsettingsResult = await Process.run('gsettings', ['get', 'org.gnome.system.location', 'enabled']);
      if ('${gsettingsResult.stdout}'.trim() == 'false') {
        throw GeoError('Location Services are off. Turn them on in Settings, Privacy, Location, then try again.');
      }
    } on GeoError {
      rethrow;
    } catch (_) {
      // Not GNOME: carry on.
    }
    final nmcliResult = await Process.run('nmcli', ['-t', '-f', 'SSID,BSSID,SIGNAL,FREQ', 'dev', 'wifi', 'list', '--rescan', 'auto']);
    if (nmcliResult.exitCode != 0) return null;
    final accessPoints = <Map<String, Object>>[];
    for (final line in '${nmcliResult.stdout}'.split('\n')) {
      // Fields are split by unescaped colons; the BSSID's own are escaped as \:.
      final parts = line.replaceAll(r'\:', '\u0000').split(':').map((part) {
        return part.replaceAll('\u0000', ':');
      }).toList();
      if (parts.length < 4) continue;
      final networkName = parts[0];
      if (networkName.endsWith('_nomap')) continue;
      int signal = 0;
      final parsedSignal = int.tryParse(parts[2]);
      if (parsedSignal != null) signal = parsedSignal;
      int frequency = 0;
      final parsedFrequency = int.tryParse(parts[3].replaceAll(RegExp(r'\D'), ''));
      if (parsedFrequency != null) frequency = parsedFrequency;
      accessPoints.add({'macAddress': parts[1].toLowerCase(), 'signalStrength': signal ~/ 2 - 100, 'frequency': frequency});
    }
    // Strongest first.
    accessPoints.sort((first, second) {
      return (second['signalStrength'] as int).compareTo(first['signalStrength'] as int);
    });
    if (accessPoints.isEmpty) return null;
    final response = await http
        .post(
          Uri.parse('https://api.beacondb.net/v1/geolocate'),
          headers: {'Content-Type': 'application/json', 'User-Agent': 'uwuHere desktop'},
          body: jsonEncode({'considerIp': true, 'wifiAccessPoints': accessPoints.take(40).toList()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    Object? location;
    double? accuracy;
    if (decoded is Map) {
      location = decoded['location'];
      final accuracyNumber = decoded['accuracy'] as num?;
      if (accuracyNumber != null) accuracy = accuracyNumber.toDouble();
    }
    if (location is! Map || accuracy == null || accuracy > 3000) return null;
    _lastPosition = Position2((location['lat'] as num).toDouble(), (location['lng'] as num).toDouble(), accuracy);
    _lastFoundAt = DateTime.now();
    return _lastPosition;
  }
}
