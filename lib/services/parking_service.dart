// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../models/city_config.dart';
import '../models/disabled_parking_spot.dart';

/// Abstrakter Service für Behindertenparkplatz-Daten
abstract class ParkingService {
  final CityConfig cityConfig;
  final http.Client client;
  final bool _closeClientOnDispose;

  ParkingService({required this.cityConfig, http.Client? client})
    : client = client ?? http.Client(),
      _closeClientOnDispose = client == null;

  /// Lädt alle Parkplätze für die konfigurierte Stadt
  Future<List<DisabledParkingSpot>> fetchAllSpots();

  /// Lädt Parkplätze nach Bezirk
  Future<List<DisabledParkingSpot>> fetchSpotsByDistrict(String district);

  /// Lädt Parkplätze innerhalb einer Bounding Box
  Future<List<DisabledParkingSpot>> fetchSpotsInBounds(LatLngBounds bounds);

  /// Disposed den HTTP Client nur wenn er intern erstellt wurde
  void dispose() {
    if (_closeClientOnDispose) {
      client.close();
    }
  }

  /// Hilfsmethode zum Parsen der WFS Response
  List<DisabledParkingSpot> parseWfsResponse(
    Map<String, dynamic> data,
    CityConfig config,
  ) {
    final features = data['features'] as List? ?? [];
    return features
        .map(
          (f) => DisabledParkingSpot.fromWfsJson(
            f as Map<String, dynamic>,
            config,
          ),
        )
        .toList();
  }
}

/// Exception für Parking Service Fehler
class ParkingServiceException implements Exception {
  final String message;
  final String? body;
  final CityConfig? cityConfig;

  ParkingServiceException(this.message, {this.body, this.cityConfig});

  @override
  String toString() {
    final cityName = cityConfig?.name ?? 'Unknown';
    return 'ParkingServiceException[$cityName]: $message';
  }
}
