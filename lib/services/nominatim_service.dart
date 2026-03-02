import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Service für Geocoding via Nominatim (OpenStreetMap)
/// F-Droid konform, Open Source, kostenlos
class NominatimService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';
  static const _userAgent = 'ParkLibre/1.0 (F-Droid)';
  static const _defaultCity = 'Berlin, Deutschland';

  final http.Client _client;

  NominatimService({http.Client? client}) : _client = client ?? http.Client();

  /// Sucht Adressen mit Autocomplete (fuzzy search)
  /// [cityName] z.B. "Berlin, Deutschland" oder "München, Deutschland"
  /// Rate-Limit: 1 Request pro Sekunde
  Future<List<Map<String, dynamic>>> searchAddresses(
    String query, {
    int limit = 5,
    String? cityName,
  }) async {
    if (query.trim().isEmpty || query.length < 3) {
      return [];
    }

    final city = cityName ?? _defaultCity;

    try {
      final uri = Uri.parse('$_baseUrl/search').replace(
        queryParameters: {
          'q': '$query, $city',
          'format': 'json',
          'limit': limit.toString(),
          'addressdetails': '1',
          'accept-language': 'de',
        },
      );

      final response = await _client.get(
        uri,
        headers: {'User-Agent': _userAgent},
      );

      if (response.statusCode != 200) {
        throw NominatimException(
          'Server antwortete mit Status ${response.statusCode}',
        );
      }

      final data = json.decode(response.body) as List;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      if (e is NominatimException) rethrow;
      throw NominatimException('Fehler bei der Suche: $e');
    }
  }

  /// Geocodiert eine Adresse zu Koordinaten
  /// [cityName] z.B. "Berlin, Deutschland" oder "München, Deutschland"
  /// Rate-Limit: 1 Request pro Sekunde
  Future<LatLng?> geocodeAddress(String address, {String? cityName}) async {
    if (address.trim().isEmpty) {
      return null;
    }

    final city = cityName ?? _defaultCity;

    try {
      final uri = Uri.parse('$_baseUrl/search').replace(
        queryParameters: {
          'q': '$address, $city',
          'format': 'json',
          'limit': '1',
          'addressdetails': '0',
        },
      );

      final response = await _client.get(
        uri,
        headers: {'User-Agent': _userAgent},
      );

      if (response.statusCode != 200) {
        throw NominatimException(
          'Server antwortete mit Status ${response.statusCode}',
        );
      }

      final data = json.decode(response.body) as List;
      if (data.isEmpty) {
        return null;
      }

      final result = data.first as Map<String, dynamic>;
      final lat = double.tryParse(result['lat'].toString());
      final lon = double.tryParse(result['lon'].toString());

      if (lat != null && lon != null) {
        return LatLng(lat, lon);
      }

      return null;
    } catch (e) {
      if (e is NominatimException) rethrow;
      throw NominatimException('Fehler beim Geocoding: $e');
    }
  }

  /// Reverse Geocoding (Koordinaten zu Adresse)
  Future<String?> reverseGeocode(LatLng position) async {
    try {
      final uri = Uri.parse('$_baseUrl/reverse').replace(
        queryParameters: {
          'lat': position.latitude.toString(),
          'lon': position.longitude.toString(),
          'format': 'json',
        },
      );

      final response = await _client.get(
        uri,
        headers: {'User-Agent': _userAgent},
      );

      if (response.statusCode != 200) {
        throw NominatimException(
          'Server antwortete mit Status ${response.statusCode}',
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['display_name'] as String?;
    } catch (e) {
      if (e is NominatimException) rethrow;
      throw NominatimException('Fehler beim Reverse Geocoding: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}

class NominatimException implements Exception {
  final String message;

  NominatimException(this.message);

  @override
  String toString() => 'NominatimException: $message';
}
