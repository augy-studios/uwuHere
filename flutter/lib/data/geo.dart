// One location reading, as { lat, lng, accuracy }, with a sentence ready for each way it can fail
// (main-site/js/geo.js). Asked for only when somebody presses something that needs it, never on
// opening. Android and the desktops through geolocator; on Linux without a location service, the
// desktop layer's Wi-Fi lookup (lib/desktop/location.dart) stands in.
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../app/env.dart';

class GeoError implements Exception {
  GeoError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Position2 {
  const Position2(this.lat, this.lng, this.accuracy);
  final double lat;
  final double lng;
  final double accuracy;
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'accuracy': accuracy};
}

class Geo {
  Geo._();

  /// Set by the desktop layer on Linux: a reading when the system's own can't give one.
  static Future<Position2?> Function()? fallback;

  static String get _blocked {
    if (kIsWeb) return "Location access is blocked. Allow it for this site in your browser's settings, then try again.";
    if (Env.android) return "Location is off for uwuHere. Allow it in Android's settings (Apps, uwuHere, Permissions), then try again.";
    if (Env.windows) return 'Location is off. Turn it on in Settings, Privacy & security, Location, then try again.';
    if (Env.macOS) return 'Location is off for uwuHere. Allow it in System Settings, Privacy & Security, Location Services, then try again.';
    return 'Location is off on this computer. Turn on its location service, then try again.';
  }

  static Future<Position2> getPosition({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        final f = await _fallback();
        if (f != null) return f;
        throw GeoError(Env.android ? "Location is switched off on this phone. Turn it on, then try again." : _blocked);
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw GeoError(_blocked);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout),
      );
      return Position2(pos.latitude, pos.longitude, pos.accuracy);
    } on GeoError {
      rethrow;
    } on PermissionDeniedException {
      throw GeoError(_blocked);
    } catch (e) {
      final f = await _fallback();
      if (f != null) return f;
      final text = '$e'.toLowerCase();
      if (text.contains('timeout') || text.contains('time limit')) throw GeoError('Finding your location took too long. Try again.');
      throw GeoError('Your location could not be found. Try again.');
    }
  }

  static Future<Position2?> _fallback() async {
    final f = fallback;
    if (f == null) return null;
    try {
      return await f();
    } on GeoError {
      rethrow;
    } catch (_) {
      return null;
    }
  }
}
