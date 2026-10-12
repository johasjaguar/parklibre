// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Gemeinsame Test-Doubles: lokale Fakes statt Live-Diensten.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:parklibre/models/disabled_parking_spot.dart';
import 'package:parklibre/services/nominatim_service.dart';
import 'package:parklibre/services/parking_service.dart';

/// 1x1 transparentes PNG als Platzhalter-Kachel (kein Netzwerk im Test).
final Uint8List fakeTilePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
  'DwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Kachel-Provider ohne Netzwerkzugriff für Widget-Tests.
class FakeTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(fakeTilePng);
}

/// ParkingService mit vorbereiteten Ergebnissen, ohne Netzwerkzugriff.
class FakeParkingService extends ParkingService {
  FakeParkingService({
    required super.cityConfig,
    this.spots = const [],
    this.delay = Duration.zero,
  }) : super(
          client: MockClient(
            (_) async => http.Response.bytes(const [], 404),
          ),
        );

  List<DisabledParkingSpot> spots;
  final Duration delay;
  int fetchCount = 0;

  @override
  Future<List<DisabledParkingSpot>> fetchAllSpots() async {
    fetchCount++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return List.of(spots);
  }

  @override
  Future<List<DisabledParkingSpot>> fetchSpotsByDistrict(String district) =>
      fetchAllSpots();

  @override
  Future<List<DisabledParkingSpot>> fetchSpotsInBounds(LatLngBounds bounds) =>
      fetchAllSpots();
}

/// Erzeugt einen Test-Parkplatz mit sinnvollen Standardwerten.
DisabledParkingSpot fakeSpot({
  String id = '1',
  LatLng position = const LatLng(52.52, 13.405),
  String cityId = 'berlin',
  String location = 'Teststraße 1',
  String? remark,
  String designation = 'Behindertenparkplatz',
  String? usageTimes,
  String? timeRestrictions,
  int count = 1,
  AddressSource addressSource = AddressSource.hasAddress,
}) {
  return DisabledParkingSpot(
    id: id,
    district: 'Mitte',
    designation: designation,
    remark: remark,
    usageTimes: usageTimes,
    timeRestrictions: timeRestrictions,
    count: count,
    location: location,
    position: position,
    cityId: cityId,
    addressSource: addressSource,
  );
}

/// NominatimService mit MockClient: zeichnet alle Anfragen auf und
/// antwortet mit vorbereiteten JSON-Bytes (UTF-8, wie der echte Dienst).
class NominatimMock {
  NominatimMock({
    String Function(Uri url)? responder,
    int Function(Uri url)? status,
    Future<void> Function(Duration)? delay,
    Duration minRequestInterval = Duration.zero,
  }) {
    client = MockClient((request) async {
      requests.add(request.url);
      final body = responder == null ? '[]' : responder(request.url);
      return http.Response.bytes(
        utf8.encode(body),
        status == null ? 200 : status(request.url),
        headers: {'content-type': 'application/json'},
      );
    });
    service = NominatimService(
      client: client,
      baseUrl: 'https://nominatim.test',
      minRequestInterval: minRequestInterval,
      delay: delay,
    );
  }

  final List<Uri> requests = [];
  late final MockClient client;
  late final NominatimService service;
}

/// Suchergebnis im Nominatim-Format (für NominatimMock.responder).
String nominatimSearchResult({
  String lat = '52.5215058',
  String lon = '13.4170000',
  String displayName = 'Alexanderplatz 1, Mitte, Berlin, 10178, Deutschland',
  Map<String, dynamic>? address,
}) {
  return json.encode([
    {
      'lat': lat,
      'lon': lon,
      'display_name': displayName,
      'address': address ??
          {
            'road': 'Alexanderplatz',
            'house_number': '1',
            'postcode': '10178',
            'city': 'Berlin',
            'suburb': 'Mitte',
          },
    },
  ]);
}

/// Reverse-Ergebnis im Nominatim-Format.
String nominatimReverseResult(String displayName) =>
    json.encode({'display_name': displayName});
