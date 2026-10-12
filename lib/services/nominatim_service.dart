// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Service für Geocoding via Nominatim (OpenStreetMap)
///
/// Hält die offiziellen Nutzungsvorgaben ein
/// (https://operations.osmfoundation.org/policies/nominatim/):
/// - maximal eine Anfrage pro Sekunde – Suche, Geocoding und Reverse
///   Geocoding laufen gemeinsam durch eine serialisierte Warteschlange
/// - keine Auto-complete-Suche – die Suche wird nur explizit ausgelöst
/// - Ergebnisse werden gecacht – Reverse-Geocoding wird geteilt und
///   parallele Anfragen werden dedupliziert
/// - der Dienst muss wechselbar sein – die Basis-Adresse ist ohne
///   Software-Update konfigurierbar (--dart-define=NOMINATIM_BASE_URL)
///
/// F-Droid konform, Open Source, kostenlos.
class NominatimService {
  /// Standard-Dienstadresse.
  ///
  /// Konfigurierbar ohne Software-Update, z.B.:
  /// `flutter run --dart-define=NOMINATIM_BASE_URL=https://nominatim.example.org`
  static const String defaultBaseUrl = String.fromEnvironment(
    'NOMINATIM_BASE_URL',
    defaultValue: 'https://nominatim.openstreetmap.org',
  );

  static const _userAgent = 'ParkLibre/1.0 (F-Droid)';
  static const _defaultCity = 'Berlin, Deutschland';

  /// Maximale Anzahl gecachter Reverse-Geocoding-Ergebnisse.
  static const _reverseCacheLimit = 256;

  final http.Client _client;
  final String _baseUrl;
  final Duration _minRequestInterval;
  final Future<void> Function(Duration) _delay;

  /// Serialisierte Warteschlange für alle Anfragen (Suche, Geocoding,
  /// Reverse). Hält den Mindestabstand zwischen dem Start zweier Anfragen.
  Future<void> _requestQueue = Future<void>.value();
  DateTime? _lastRequestStart;

  /// Reverse-Geocoding-Cache, dient gleichzeitig dem De-Duplizieren
  /// paralleler Anfragen auf dieselbe Position.
  final Map<String, Future<String?>> _reverseCache = {};

  /// Erstellt den Dienst.
  ///
  /// [minRequestInterval] ist der Mindestabstand zwischen zwei Anfragen
  /// (Vorgabe: eine Anfrage pro Sekunde). [delay] ist nur für Tests
  /// vorgesehen, um das Warten zu simulieren.
  NominatimService({
    http.Client? client,
    String? baseUrl,
    Duration minRequestInterval = const Duration(seconds: 1),
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? defaultBaseUrl,
       _minRequestInterval = minRequestInterval,
       _delay = delay ?? Future<void>.delayed;

  /// Sucht Adressen (explizite Suche, kein Auto-complete).
  ///
  /// [cityName] z.B. "Berlin, Deutschland" oder "München, Deutschland"
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

      final response = await _scheduleRequest(() => _client.get(
            uri,
            headers: {'User-Agent': _userAgent},
          ));

      if (response.statusCode != 200) {
        throw NominatimException(
          'Server antwortete mit Status ${response.statusCode}',
        );
      }

      final data = json.decode(utf8.decode(response.bodyBytes)) as List;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      if (e is NominatimException) rethrow;
      throw NominatimException('Fehler bei der Suche: $e');
    }
  }

  /// Geocodiert eine Adresse zu Koordinaten.
  ///
  /// [cityName] z.B. "Berlin, Deutschland" oder "München, Deutschland"
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

      final response = await _scheduleRequest(() => _client.get(
            uri,
            headers: {'User-Agent': _userAgent},
          ));

      if (response.statusCode != 200) {
        throw NominatimException(
          'Server antwortete mit Status ${response.statusCode}',
        );
      }

      final data = json.decode(utf8.decode(response.bodyBytes)) as List;
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

  /// Reverse Geocoding (Koordinaten zu Adresse).
  ///
  /// Ergebnisse werden gecacht; mehrere Aufrufe für dieselbe Position
  /// (auch parallel) lösen nur eine Anfrage aus. Fehlgeschlagene Anfragen
  /// werden nicht dauerhaft gecacht.
  Future<String?> reverseGeocode(LatLng position) {
    final key = _cacheKey(position);
    final cached = _reverseCache[key];
    if (cached != null) {
      return cached;
    }

    if (_reverseCache.length >= _reverseCacheLimit) {
      _reverseCache.clear();
    }

    final future = _scheduleRequest(() => _fetchReverse(position));
    _reverseCache[key] = future;
    // Fehler nicht cachen: beim nächsten Aufruf wird erneut versucht.
    unawaited(future.then<void>(
      (_) {},
      onError: (Object _) {
        _reverseCache.remove(key);
      },
    ));
    return future;
  }

  String _cacheKey(LatLng position) => '${position.latitude.toStringAsFixed(5)},'
      '${position.longitude.toStringAsFixed(5)}';

  Future<String?> _fetchReverse(LatLng position) async {
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

      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return data['display_name'] as String?;
    } catch (e) {
      if (e is NominatimException) rethrow;
      throw NominatimException('Fehler beim Reverse Geocoding: $e');
    }
  }

  /// Führt eine Anfrage aus, begrenzt alle Anfragen gemeinsam auf
  /// höchstens eine pro [_minRequestInterval] (Nominatim-Vorgabe:
  /// maximal eine Anfrage pro Sekunde).
  Future<T> _scheduleRequest<T>(Future<T> Function() request) {
    final completer = Completer<T>();
    _requestQueue = _requestQueue.then((_) async {
      final last = _lastRequestStart;
      if (last != null) {
        final gap = _minRequestInterval - DateTime.now().difference(last);
        if (gap > Duration.zero) {
          await _delay(gap);
        }
      }
      _lastRequestStart = DateTime.now();
      try {
        completer.complete(await request());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
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
