// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../models/city_config.dart';
import '../models/disabled_parking_spot.dart';
import 'parking_service.dart';

/// Service für Behindertenparkplatz-Daten in Dresden
/// Verwendet OGC API (moderner GeoJSON-Standard)
class DresdenParkingService extends ParkingService {
  DresdenParkingService({http.Client? client})
    : super(cityConfig: CityConfig.dresden, client: client);

  @override
  Future<List<DisabledParkingSpot>> fetchAllSpots() async {
    // OGC API: Alle Features abrufen
    final url = Uri.parse(cityConfig.apiEndpoint).replace(
      queryParameters: {
        'limit': '1000', // Maximal 1000 pro Request
      },
    );

    final response = await client.get(url);

    if (response.statusCode != 200) {
      throw ParkingServiceException(
        'Failed to fetch data: ${response.statusCode}',
        body: response.body,
        cityConfig: cityConfig,
      );
    }

    // Explizit als UTF-8 dekodieren: der Dienst sendet
    // "application/geo+json" ohne charset, package:http wuerde sonst
    // latin1 annehmen und Umlaute zerstoeren.
    final data = _decodeJson(response.bodyBytes);
    return _parseOgcApiResponse(data);
  }

  @override
  Future<List<DisabledParkingSpot>> fetchSpotsByDistrict(
    String district,
  ) async {
    // Dresden hat keine Bezirke in den Daten - alle abrufen und filtern
    final all = await fetchAllSpots();
    return all; // Keine Filterung möglich ohne Bezirksfeld
  }

  @override
  Future<List<DisabledParkingSpot>> fetchSpotsInBounds(
    LatLngBounds bounds,
  ) async {
    // Dresden: bounding box Parameter für OGC API
    final url = Uri.parse(cityConfig.apiEndpoint).replace(
      queryParameters: {
        'limit': '1000',
        'bbox':
            '${bounds.southWest.longitude},${bounds.southWest.latitude},'
            '${bounds.northEast.longitude},${bounds.northEast.latitude}',
      },
    );

    final response = await client.get(url);

    if (response.statusCode != 200) {
      throw ParkingServiceException(
        'Failed to fetch data: ${response.statusCode}',
        body: response.body,
        cityConfig: cityConfig,
      );
    }

    final data = _decodeJson(response.bodyBytes);
    return _parseOgcApiResponse(data);
  }

  /// Dekodiert die JSON-Antwort ausdruecklich als UTF-8.
  Map<String, dynamic> _decodeJson(List<int> bodyBytes) {
    return json.decode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
  }

  /// Parst OGC API GeoJSON Response
  List<DisabledParkingSpot> _parseOgcApiResponse(Map<String, dynamic> data) {
    final features = data['features'] as List? ?? [];
    final mapping = cityConfig.fieldMapping;

    return features.map((f) {
      final props = f['properties'] as Map<String, dynamic>? ?? {};
      final geom = f['geometry'] as Map<String, dynamic>?;

      // Koordinaten aus geometry (WGS84)
      LatLng position;
      if (geom != null && geom['coordinates'] != null) {
        final coords = geom['coordinates'] as List;
        // OGC API: [lon, lat]
        position = LatLng(
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        );
      } else {
        position = cityConfig.defaultCenter;
      }

      // ID: in den OGC-API-Daten steht die ID auf Feature-Ebene ("id");
      // die Properties enthalten kein ID-Feld.
      final id =
          f['id']?.toString() ??
          props[mapping['id']]?.toString() ??
          '';

      // Location: Koordinaten als String (da keine Adresse verfügbar)
      final count = (props[mapping['count']] as num?)?.toInt() ?? 1;
      final nutzungszeit = props[mapping['designation']]?.toString() ?? '';
      // Koordinaten formatieren als "Ersatz-Adresse"
      final latStr = position.latitude.toStringAsFixed(5);
      final lonStr = position.longitude.toStringAsFixed(5);
      final standort = 'Dresden ($latStr, $lonStr)';

      // Remark: Bewertung
      final remark = props[mapping['remark']]?.toString();

      // Last Updated
      DateTime? lastUpdated;
      final lastUpdatedStr = props[mapping['lastUpdated']]?.toString();
      if (lastUpdatedStr != null) {
        // Format: "24.05.2021 07:00:16"
        try {
          final parts = lastUpdatedStr.split(' ');
          if (parts.isNotEmpty) {
            final dateParts = parts[0].split('.');
            if (dateParts.length == 3) {
              lastUpdated = DateTime(
                int.parse(dateParts[2]),
                int.parse(dateParts[1]),
                int.parse(dateParts[0]),
              );
            }
          }
        } catch (_) {}
      }

      return DisabledParkingSpot(
        id: id,
        district: '', // Nicht verfügbar in Dresden
        designation: nutzungszeit.isNotEmpty
            ? nutzungszeit
            : 'Behindertenparkplatz',
        remark: remark,
        count: count,
        policeSection: null,
        location: standort,
        postalCode: null,
        neighborhood: null,
        position: position,
        lastUpdated: lastUpdated,
        cityId: cityConfig.id,
        addressSource: AddressSource.needsReverse,
      );
    }).toList();
  }
}
