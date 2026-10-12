// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parklibre/main.dart';
import 'package:parklibre/models/disabled_parking_spot.dart';
import 'package:parklibre/services/berlin_parking_service.dart';
import 'package:parklibre/services/dresden_parking_service.dart';
import 'package:parklibre/services/munich_parking_service.dart';

import 'helpers/test_doubles.dart';

/// App mit genau einem Test-Parkplatz (offline).
Widget appWithSpot({
  required NominatimMock mock,
  required DisabledParkingSpot spot,
}) {
  return ParkLibreApp(
    serviceFactory: (city) =>
        FakeParkingService(cityConfig: city, spots: [spot]),
    nominatim: mock.service,
    tileProvider: FakeTileProvider(),
  );
}

Map<String, dynamic> wfsFeature(
  Map<String, dynamic> props, {
  List<num> coords = const [392543.9, 5817635.7],
}) {
  return {
    'type': 'Feature',
    'id': 'x.1',
    'geometry': {'type': 'Point', 'coordinates': coords},
    'properties': props,
  };
}

MockClient wfsMock(String body) => MockClient((_) async => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'application/json;charset=UTF-8'},
    ));

void main() {
  group('Parsing der zeitlichen Angaben', () {
    test('Berlin: bemerkung wird als Nutzungszeiten im Wortlaut übernommen',
        () async {
      final body = json.encode({
        'type': 'FeatureCollection',
        'features': [
          wfsFeature({
            'uid': '1',
            'bezirk': 'Pankow',
            'bezeichnun': 'Behindertenparkplatz',
            'bemerkung': 'Mo-Fr 8-18h',
            'anzahl': 1,
            'standort': 'Teststraße 1',
            'plz': '10115',
            'gps_lat': 52.52,
            'gps_lon': 13.405,
          }),
          wfsFeature({
            'uid': '2',
            'bezirk': 'Pankow',
            'bezeichnun': 'Behindertenparkplatz',
            'bemerkung': '',
            'anzahl': 1,
            'standort': 'Teststraße 2',
            'plz': '10115',
            'gps_lat': 52.53,
            'gps_lon': 13.41,
          }),
          wfsFeature({
            'uid': '3',
            'bezirk': 'Pankow',
            'bezeichnun': 'Behindertenparkplatz',
            'bemerkung': 'Durchgehend',
            'anzahl': 1,
            'standort': 'Teststraße 3',
            'plz': '10115',
            'gps_lat': 52.54,
            'gps_lon': 13.42,
          }),
        ],
      });

      final spots =
          await BerlinParkingService(client: wfsMock(body)).fetchAllSpots();

      expect(spots[0].usageTimes, 'Mo-Fr 8-18h', reason: 'Wortlaut bleibt');
      expect(spots[0].timeRestrictions, isNull);
      expect(spots[1].usageTimes, isNull,
          reason: 'Leere Angabe ist "keine Angabe", nicht ganztägig');
      expect(spots[2].usageTimes, 'Durchgehend',
          reason: 'Auch Deutungen der Quelle bleiben im Wortlaut');
    });

    test('München: zeitliche Einschränkungen im Wortlaut, Whitespace = keine '
        'Angabe', () async {
      final body = json.encode({
        'type': 'FeatureCollection',
        'features': [
          wfsFeature(
            {
              'parkplatz_id': 1,
              'stadtbezirk': 'Altstadt-Lehel',
              'bezeichnung': 'Damenstiftstraße 4',
              'anzahl_stellplaetze': 2,
              'plz': '80331',
              'zeitliche_einschraenkung':
                  'werktags Montag bis Freitag von 8 bis 18 Uhr',
            },
            coords: [691107.2, 5334738.4],
          ),
          wfsFeature(
            {
              'parkplatz_id': 2,
              'stadtbezirk': 'Altstadt-Lehel',
              'bezeichnung': 'Damenstiftstraße 5',
              'anzahl_stellplaetze': 1,
              'plz': '80331',
              'zeitliche_einschraenkung': ' ',
            },
            coords: [691108.2, 5334739.4],
          ),
          wfsFeature(
            {
              'parkplatz_id': 3,
              'stadtbezirk': 'Altstadt-Lehel',
              'bezeichnung': 'Damenstiftstraße 6',
              'anzahl_stellplaetze': 1,
              'plz': '80331',
              'zeitliche_einschraenkung': null,
            },
            coords: [691109.2, 5334740.4],
          ),
        ],
      });

      final spots =
          await MunichParkingService(client: wfsMock(body)).fetchAllSpots();

      expect(
        spots[0].timeRestrictions,
        'werktags Montag bis Freitag von 8 bis 18 Uhr',
      );
      expect(spots[0].usageTimes, isNull);
      expect(spots[1].timeRestrictions, isNull,
          reason: 'Whitespace ist "keine Angabe"');
      expect(spots[2].timeRestrictions, isNull);
    });

    test('Dresden: nutzungszeit als Nutzungszeiten, fehlende Angaben null',
        () async {
      final fixtureBytes =
          File('test/fixtures/dresden_sample.json').readAsBytesSync();
      final svc = DresdenParkingService(
        client: MockClient((_) async => http.Response.bytes(
              fixtureBytes,
              200,
              headers: {'content-type': 'application/geo+json'},
            )),
      );

      final spots = await svc.fetchAllSpots();

      expect(spots[0].usageTimes, 'von 00:00 Uhr bis 24:00 Uhr',
          reason: 'Wortlaut der Quelle, keine eigene Deutung');
      expect(spots[1].usageTimes, 'Mo–Fr 9–18 Uhr, Sa 9–14 Uhr');
      expect(spots[2].usageTimes, isNull,
          reason: 'Fehlende Angabe bleibt "keine Angabe"');
    });
  });

  group('Anzeige im Detailfenster', () {
    setUp(() {
      // In-Memory-Store, damit die Stadtinitialisierung nicht haengt.
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Nutzungszeiten werden im Wortlaut angezeigt', (tester) async {
      final mock = NominatimMock(responder: (_) => nominatimReverseResult('X'));
      await tester.pumpWidget(
        appWithSpot(
          mock: mock,
          spot: fakeSpot(
            id: '1',
            usageTimes: 'Mo–Fr 9–18 Uhr, Sa 9–14 Uhr',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.accessible).first);
      await tester.pumpAndSettle();

      expect(find.text('Nutzungszeiten'), findsOneWidget);
      expect(find.text('Mo–Fr 9–18 Uhr, Sa 9–14 Uhr'), findsOneWidget);
      expect(mock.requests, isEmpty);
    });

    testWidgets('Zeitliche Einschränkungen werden im Wortlaut angezeigt', (
      tester,
    ) async {
      final mock = NominatimMock(responder: (_) => nominatimReverseResult('X'));
      await tester.pumpWidget(
        appWithSpot(
          mock: mock,
          spot: fakeSpot(
            id: '1',
            cityId: 'muenchen',
            // Position im sichtbaren Kartenbereich des Tests
            position: const LatLng(52.521, 13.406),
            timeRestrictions: 'bis 3 Stunden',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.accessible).first);
      await tester.pumpAndSettle();

      expect(find.text('Zeitliche Einschränkungen'), findsOneWidget);
      expect(find.text('bis 3 Stunden'), findsOneWidget);
      expect(find.text('Nutzungszeiten'), findsNothing);
    });

    testWidgets('Fehlende Angaben: "Keine Angaben", keine Ganztags-Deutung', (
      tester,
    ) async {
      final mock = NominatimMock(responder: (_) => nominatimReverseResult('X'));
      await tester.pumpWidget(
        appWithSpot(
          mock: mock,
          spot: fakeSpot(id: '1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.accessible).first);
      await tester.pumpAndSettle();

      expect(find.text('Nutzungszeiten'), findsOneWidget);
      expect(find.text('Keine Angaben'), findsOneWidget);
      // Fehlende Angaben duerfen nicht zu 24/7 oder "geoeffnet" gedeutet werden
      expect(find.textContaining('Durchgehend'), findsNothing);
      expect(find.textContaining('ganztägig'), findsNothing);
      expect(find.textContaining('geöffnet'), findsNothing);
      expect(find.textContaining('24'), findsNothing);
    });
  });
}
