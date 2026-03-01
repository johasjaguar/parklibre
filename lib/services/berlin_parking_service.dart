import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/disabled_parking_spot.dart';

class BerlinParkingService {
  static const _baseUrl = 'https://gdi.berlin.de/services/wfs/behindertenparkplaetze';
  static const _typeName = 'behindertenparkplaetze:bpark';
  
  final http.Client _client;

  BerlinParkingService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<DisabledParkingSpot>> fetchAllSpots() async {
    final url = Uri.parse(_baseUrl).replace(queryParameters: {
      'service': 'WFS',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typeNames': _typeName,
      'outputFormat': 'application/json',
    });

    final response = await _client.get(url);

    if (response.statusCode != 200) {
      throw BerlinParkingException(
        'Failed to fetch data: ${response.statusCode}',
        response.body,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? [];

    return features
        .map((f) => DisabledParkingSpot.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  Future<List<DisabledParkingSpot>> fetchSpotsByDistrict(String district) async {
    final filter = '<Filter><PropertyIsEqualTo><PropertyName>bezirk</PropertyName>'
        '<Literal>$district</Literal></PropertyIsEqualTo></Filter>';
    
    final url = Uri.parse(_baseUrl).replace(queryParameters: {
      'service': 'WFS',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typeNames': _typeName,
      'outputFormat': 'application/json',
      'FILTER': filter,
    });

    final response = await _client.get(url);

    if (response.statusCode != 200) {
      throw BerlinParkingException(
        'Failed to fetch data: ${response.statusCode}',
        response.body,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? [];

    return features
        .map((f) => DisabledParkingSpot.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  Future<List<DisabledParkingSpot>> fetchSpotsInBounds(LatLngBounds bounds) async {
    final bbox = '${bounds.southWest.longitude},${bounds.southWest.latitude},'
        '${bounds.northEast.longitude},${bounds.northEast.latitude},EPSG:4326';
    
    final url = Uri.parse(_baseUrl).replace(queryParameters: {
      'service': 'WFS',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typeNames': _typeName,
      'outputFormat': 'application/json',
      'BBOX': bbox,
    });

    final response = await _client.get(url);

    if (response.statusCode != 200) {
      throw BerlinParkingException(
        'Failed to fetch data: ${response.statusCode}',
        response.body,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? [];

    return features
        .map((f) => DisabledParkingSpot.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  void dispose() {
    _client.close();
  }
}

class BerlinParkingException implements Exception {
  final String message;
  final String? body;

  BerlinParkingException(this.message, [this.body]);

  @override
  String toString() => 'BerlinParkingException: $message';
}
