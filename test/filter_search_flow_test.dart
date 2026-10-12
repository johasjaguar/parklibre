// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parklibre/main.dart';
import 'package:parklibre/models/city_model.dart';
import 'package:parklibre/models/filter_criteria.dart';
import 'package:parklibre/services/nominatim_service.dart';

import 'helpers/test_doubles.dart';

void main() {
  late MapController mapController;

  setUp(() {
    // In-Memory-Store, damit die Stadtinitialisierung in Tests nicht haengt.
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpFilterSheet(
    WidgetTester tester,
    NominatimMock mock,
  ) async {
    mapController = MapController();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CityModel(
              serviceFactory: (city) => FakeParkingService(cityConfig: city),
            ),
          ),
          ChangeNotifierProvider(create: (_) => ParkingSpotsModel()),
          ChangeNotifierProvider(create: (_) => LocationModel()),
          Provider<NominatimService>.value(value: mock.service),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FlutterMap(
                  mapController: mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(52.52, 13.405),
                    initialZoom: 12,
                  ),
                  children: [TileLayer(tileProvider: FakeTileProvider())],
                ),
                FilterBottomSheet(
                  mapController: mapController,
                  onFilterApplied: (_, _) {},
                  initialMode: FilterMode.targetAddress,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Tippen löst keine Anfragen aus (kein Auto-complete)', (
    tester,
  ) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 1');
    // Länger warten als der fruehere Debounce (500ms) – es darf trotzdem
    // keine Anfrage geben (Nutzungsvorgabe: kein Auto-complete).
    await tester.pump(const Duration(seconds: 3));

    expect(mock.requests, isEmpty,
        reason: 'Tippen darf die Such-API nicht ausloesen');
  });

  testWidgets('Explizite Suche (Enter) zeigt Ergebnisse zur Auswahl', (
    tester,
  ) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(mock.requests, hasLength(1), reason: 'Genau eine Suchanfrage');
    expect(find.widgetWithText(ListTile, 'Alexanderplatz 1'), findsOneWidget,
        reason: 'Ergebnis wird zur Auswahl angezeigt');
    expect(find.text('10178 Berlin, Mitte'), findsOneWidget);
  });

  testWidgets('Explizite Suche (Such-Button) funktioniert ebenfalls', (
    tester,
  ) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 1');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
    await tester.pumpAndSettle();

    expect(mock.requests, hasLength(1));
    expect(find.widgetWithText(ListTile, 'Alexanderplatz 1'), findsOneWidget);
  });

  testWidgets('Auswahl eines Ergebnisses braucht keine zweite Anfrage', (
    tester,
  ) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(mock.requests, hasLength(1));

    await tester.tap(find.widgetWithText(ListTile, 'Alexanderplatz 1'));
    await tester.pumpAndSettle();

    // Koordinaten kommen aus dem Suchergebnis – kein erneutes Geocoding.
    expect(mock.requests, hasLength(1),
        reason: 'Auswahl darf keine zweite Anfrage ausloesen');

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'Alexanderplatz 1, 10178 Berlin');
  });

  testWidgets('Zu kurze Eingabe zeigt Meldung, ohne Anfrage', (tester) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
    await tester.pump();

    expect(mock.requests, isEmpty);
    expect(find.text('Bitte mindestens 3 Zeichen eingeben'), findsOneWidget);
  });

  testWidgets('Quellenangaben sind sichtbar und verlinkt', (tester) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 1');
    await tester.pump();

    expect(find.text('Nominatim'), findsOneWidget,
        reason: 'Quellenangabe der Suche muss sichtbar sein');
    expect(find.text('© OpenStreetMap-Mitwirkende'), findsOneWidget);
  });

  testWidgets('Bearbeiten des Textes blendet veraltete Vorschläge aus', (
    tester,
  ) async {
    final mock = NominatimMock(responder: (_) => nominatimSearchResult());
    await pumpFilterSheet(tester, mock);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Alexanderplatz 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alexanderplatz 2');
    await tester.pump();

    expect(find.widgetWithText(ListTile, 'Alexanderplatz 1'), findsNothing,
        reason: 'Vorschlaege zur alten Suche duerfen nicht sichtbar bleiben');
    expect(mock.requests, hasLength(1),
        reason: 'Bearbeiten loest keine neue Anfrage aus');
  });
}
