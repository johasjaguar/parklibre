import 'dart:math';
import 'package:latlong2/latlong.dart';

class DistanceCalculator {
  static const double _earthRadiusKm = 6371.0;

  /// Berechnet die Luftlinie (Haversine-Formel) zwischen zwei Punkten
  static double calculateDistance(LatLng p1, LatLng p2) {
    final lat1 = _degreesToRadians(p1.latitude);
    final lat2 = _degreesToRadians(p2.latitude);
    final deltaLat = _degreesToRadians(p2.latitude - p1.latitude);
    final deltaLon = _degreesToRadians(p2.longitude - p1.longitude);

    final a =
        sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusKm * c * 1000; // Rückgabe in Metern
  }

  /// Prüft ob ein Punkt im Umkreis eines Zentrums liegt
  static bool isWithinRadius(LatLng point, LatLng center, double radiusMeters) {
    return calculateDistance(point, center) <= radiusMeters;
  }

  /// Filtert eine Liste von Punkten nach Umkreis
  static List<T> filterByRadius<T>({
    required List<T> items,
    required LatLng Function(T) getPosition,
    required LatLng center,
    required double radiusMeters,
  }) {
    return items.where((item) {
      final distance = calculateDistance(getPosition(item), center);
      return distance <= radiusMeters;
    }).toList();
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Formatiert Distanz für Anzeige
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    if (meters < 10000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${(meters / 1000).round()} km';
  }
}
