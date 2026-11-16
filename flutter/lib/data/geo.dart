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
  String toString() {
    return message;
  }
}

/// One location reading: where, and how sure (accuracy in metres).
class Position2 {
  const Position2(this.latitude, this.longitude, this.accuracy);
  final double latitude;
  final double longitude;
  final double accuracy;

  /// The site's shape, { lat, lng, accuracy }: these keys are what the server reads.
  Map<String, dynamic> toJson() {
    return {'lat': latitude, 'lng': longitude, 'accuracy': accuracy};
  }
}

class Geo {
  Geo._();

  /// Set by the desktop layer on Linux: a reading when the system's own can't give one.
  static Future<Position2?> Function()? fallback;

  /// What to say when location is blocked, in the words of this platform's settings.
  static String get _blocked {
    if (kIsWeb) return "Location access is blocked. Allow it for this site in your browser's settings, then try again.";
    if (Env.android) return "Location is off for uwuHere. Allow it in Android's settings (Apps, uwuHere, Permissions), then try again.";
    if (Env.windows) return 'Location is off. Turn it on in Settings, Privacy & security, Location, then try again.';
    if (Env.macOS) return 'Location is off for uwuHere. Allow it in System Settings, Privacy & Security, Location Services, then try again.';
    return 'Location is off on this computer. Turn on its location service, then try again.';
  }

  /// One reading, asking for permission first if it hasn't been given. Throws a [GeoError] with a
  /// sentence for the person when there's no reading to be had; the desktop's [fallback] is tried
  /// before giving up.
  static Future<Position2> getPosition({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        final fallbackReading = await _fallback();
        if (fallbackReading != null) {
          return fallbackReading;
        }
        if (Env.android) {
          throw GeoError("Location is switched off on this phone. Turn it on, then try again.");
        } else {
          throw GeoError(_blocked);
        }
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw GeoError(_blocked);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout),
      );
      return Position2(position.latitude, position.longitude, position.accuracy);
    } on GeoError {
      rethrow;
    } on PermissionDeniedException {
      throw GeoError(_blocked);
    } catch (error) {
      final fallbackReading = await _fallback();
      if (fallbackReading != null) {
        return fallbackReading;
      }
      final text = '$error'.toLowerCase();
      if (text.contains('timeout') || text.contains('time limit')) {
        throw GeoError('Finding your location took too long. Try again.');
      }
      throw GeoError('Your location could not be found. Try again.');
    }
  }

  /// The desktop's own reading, or null when there's none (a [GeoError] from it is passed on).
  static Future<Position2?> _fallback() async {
    final fallbackGetter = fallback;
    if (fallbackGetter == null) {
      return null;
    }
    try {
      return await fallbackGetter();
    } on GeoError {
      rethrow;
    } catch (_) {
      return null;
    }
  }
}
