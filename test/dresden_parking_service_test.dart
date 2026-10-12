// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:parklibre/models/disabled_parking_spot.dart';
import 'package:parklibre/services/dresden_parking_service.dart';

void main() {
  // Lokale Fixture als UTF-8-Bytes, mit dem realen Content-Type des Dienstes
  // ("application/geo+json" OHNE charset) – genau die Netzwerksituation, die
  // zuvor Umlaute zerstoert hat.
  final fixtureBytes =
      File('test/fixtures/dresden_sample.json').readAsBytesSync();

  MockClient mockDresden() => MockClient((_) async => http.Response.bytes(
        fixtureBytes,
        200,
        headers: {'content-type': 'application/geo+json'},
      ));

  group('DresdenParkingService (lokale Fixture)', () {
    test('Umlaute werden als UTF-8 korrekt dekodiert', () async {
      final svc = DresdenParkingService(client: mockDresden());
      final spots = await svc.fetchAllSpots();

      expect(spots, hasLength(3));
      expect(
        spots[0].remark,
        'Stellplatz uneingeschränkt nutzbar',
        reason: 'Umlaut a/ae muss unveraendert bleiben',
      );
      expect(spots[1].designation, 'Mo–Fr 9–18 Uhr, Sa 9–14 Uhr');
      expect(spots[1].designation, isNot(contains('Ã')));

      // Explizit kein Mojibake
      for (final s in spots) {
        expect(s.remark, isNot(contains('Ã')));
        expect(s.designation, isNot(contains('Ã')));
        expect(s.location, isNot(contains('Ã')));
      }
      expect(spots[2].location, contains('Dresden ('),
          reason: 'Ersatz-Adresse aus Koordinaten');
    });

    test('IDs werden von Feature-Ebene uebernommen und sind unterscheidlich',
        () async {
      final svc = DresdenParkingService(client: mockDresden());
      final spots = await svc.fetchAllSpots();

      final ids = spots.map((s) => s.id).toList();
      expect(ids, ['1', '10', '1004'],
          reason: 'Feature-IDs muessen laut uebernommen werden');
      expect(ids.toSet(), hasLength(ids.length),
          reason: 'IDs muessen eindeutig sein');
      expect(ids.any((id) => id.isEmpty), isFalse);
    });

    test('Koordinaten aus [lon, lat] korrekt als LatLng', () async {
      final svc = DresdenParkingService(client: mockDresden());
      final spots = await svc.fetchAllSpots();

      expect(spots[0].position.latitude, closeTo(51.029480, 0.000001));
      expect(spots[0].position.longitude, closeTo(13.742269, 0.000001));
      expect(spots[1].position.latitude, closeTo(51.0402, 0.0001));
      expect(spots[1].position.longitude, closeTo(13.7351, 0.0001));
    });

    test('lastUpdated aus "dd.MM.yyyy HH:mm:ss" geparst, fehlende Angaben null',
        () async {
      final svc = DresdenParkingService(client: mockDresden());
      final spots = await svc.fetchAllSpots();

      expect(spots[0].lastUpdated, DateTime(2021, 5, 24));
      expect(spots[2].lastUpdated, isNull);
    });

    test('adressSource: Dresden braucht Reverse Geocoding', () async {
      final svc = DresdenParkingService(client: mockDresden());
      final spots = await svc.fetchAllSpots();
      expect(spots.every((s) => s.addressSource == AddressSource.needsReverse),
          isTrue);
    });

    test('Dienst-Antwort ohne charset, aber mit UTF-8-Bytes bleibt stabil',
        () async {
      // Gegentest: Wuerde man latin1 dekodieren, entstuende Mojibake.
      final latin1View = String.fromCharCodes(fixtureBytes);
      expect(latin1View, contains('Ã'),
          reason: 'Fixture enthaelt Umlaute in UTF-8-Mehrbyte-Kodierung');

      final svc = DresdenParkingService(client: mockDresden());
      final spots = await svc.fetchAllSpots();
      expect(spots[0].remark, contains('ä'));
    });
  });
}
