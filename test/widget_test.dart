// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parklibre/main.dart';

import 'helpers/test_doubles.dart';

void main() {
  setUp(() {
    // In-Memory-Store: ohne dies haengt SharedPreferences.getInstance() in
    // der Testumgebung (MethodChannel ohne Handler) und die App wuerde
    // ewig auf die Stadtinitialisierung warten.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ParkLibre App: Widget-Baum und Ladeflow (offline, ohne Netzwerk)', (
    WidgetTester tester,
  ) async {
    final spots = [
      fakeSpot(id: '1', position: const LatLng(52.520, 13.405)),
      fakeSpot(
        id: '2',
        position: const LatLng(52.530, 13.410),
        location: 'Teststraße 2',
      ),
      fakeSpot(
        id: '3',
        position: const LatLng(52.510, 13.390),
        location: 'Teststraße 3',
      ),
    ];
    final mock = NominatimMock(
      responder: (_) => nominatimReverseResult('Teststraße 1, Berlin'),
    );

    await tester.pumpWidget(
      ParkLibreApp(
        serviceFactory: (city) =>
            FakeParkingService(cityConfig: city, spots: spots),
        nominatim: mock.service,
        tileProvider: FakeTileProvider(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ParkLibreApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // Daten wurden ueber den gefakten Dienst geladen (kein Netzwerk).
    expect(find.text('3 Parkplätze'), findsOneWidget);

    // Quellenangaben sind sichtbar (Nutzungsvorgabe OSM/Nominatim).
    expect(find.text('© OpenStreetMap-Mitwirkende'), findsOneWidget);
    expect(find.text('Geocoding: Nominatim'), findsOneWidget);

    // Ohne Interaktion duerfen keine Geocoding-Anfragen entstehen.
    expect(mock.requests, isEmpty);
  });
}
