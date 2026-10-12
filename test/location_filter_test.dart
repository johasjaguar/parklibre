// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parklibre/main.dart';
import 'package:parklibre/models/city_config.dart';
import 'package:parklibre/models/city_model.dart';
import 'package:parklibre/models/filter_criteria.dart';
import 'package:parklibre/services/location_service.dart';
import 'package:parklibre/services/nominatim_service.dart';

import 'helpers/test_doubles.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Kein erfundener Standort', () {
    test('Linux: getCurrentLocation liefert bewusst keinen Standort', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final model = LocationModel();
      await model.getCurrentLocation();

      expect(
        model.currentLocation,
        isNull,
        reason: 'Es darf kein Platzhalter-Standort erfunden werden',
      );
      expect(
        model.error,
        isNotNull,
        reason: 'Fehlender Standort wird gemeldet',
      );
      expect(model.error, contains('Standort'));
    });

    test('Linux: Standort-Stream und Updates ohne erfundenen Ort', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final service = LocationService();
      expect(await service.getLocationStream().toList(), isEmpty);

      var called = false;
      service.startLocationUpdates((_) => called = true);
      await Future<void>.delayed(Duration.zero);
      expect(called, isFalse, reason: 'Keine Updates mit erfundenem Standort');
    });

    test('FilterCriteria ohne Zentrum ist ungueltig (alle Modi)', () {
      const filter = FilterCriteria(
        mode: FilterMode.currentLocation,
        radiusMeters: 500,
      );
      expect(filter.isValid, isFalse);

      const addressFilter = FilterCriteria(
        mode: FilterMode.targetAddress,
        radiusMeters: 500,
        address: 'Teststraße 1',
      );
      expect(
        addressFilter.isValid,
        isFalse,
        reason: 'Auch Adressfilter brauchen ein echtes Zentrum',
      );
    });
  });

  group('ParkingSpotsModel – Filter und Neuladen', () {
    const center = LatLng(52.52, 13.405);
    final nearSpot = fakeSpot(
      id: 'near',
      position: const LatLng(52.5201, 13.4051),
    );
    final farSpot = fakeSpot(
      id: 'far',
      position: const LatLng(52.60, 13.50),
      location: 'Weitweg 9',
    );
    final nearSpot2 = fakeSpot(
      id: 'near2',
      position: const LatLng(52.5202, 13.4052),
      location: 'Teststraße 2',
    );

    FilterCriteria filterAroundCenter() => const FilterCriteria(
      mode: FilterMode.targetAddress,
      radiusMeters: 200,
      center: center,
      address: 'Teststraße 1',
    );

    test('Ohne gueltiges Zentrum wird nicht gefiltert', () async {
      final service = FakeParkingService(
        cityConfig: CityConfig.berlin,
        spots: [nearSpot, nearSpot2, farSpot],
      );
      final model = ParkingSpotsModel();
      model.setService(service);
      await model.loadSpots();

      model.applyFilter(
        const FilterCriteria(
          mode: FilterMode.currentLocation,
          radiusMeters: 500,
          // center fehlt – z.B. kein Standort verfuegbar
        ),
      );

      expect(
        model.isFiltered,
        isFalse,
        reason: 'Ohne Standort darf keine Filterung stattfinden',
      );
      expect(model.spots, hasLength(3), reason: 'Alle Spots bleiben sichtbar');
    });

    test(
      'Filter wird nach Neuladen derselben Stadt erneut angewendet',
      () async {
        final service = FakeParkingService(
          cityConfig: CityConfig.berlin,
          spots: [nearSpot, nearSpot2, farSpot],
        );
        final model = ParkingSpotsModel();
        model.setService(service);
        await model.loadSpots();

        model.applyFilter(filterAroundCenter());
        expect(model.isFiltered, isTrue);
        expect(model.spots, hasLength(2), reason: '2 von 3 im Umkreis');

        // Daten aendern sich (Neuladen): Filter bleibt aktiv und wird
        // auf die neuen Daten angewendet.
        service.spots = [nearSpot, farSpot];
        await model.loadSpots();

        expect(model.isFiltered, isTrue, reason: 'Filter bleibt aktiv');
        expect(model.currentFilter!.radiusMeters, 200);
        expect(model.allSpots, hasLength(2));
        expect(
          model.spots,
          hasLength(1),
          reason: 'Filter wird auf die neuen Daten angewendet',
        );
      },
    );

    test('Stadtwechsel uebernimmt keine veralteten Ergebnisse', () async {
      final serviceA = FakeParkingService(
        cityConfig: CityConfig.berlin,
        spots: [nearSpot, nearSpot2],
        delay: const Duration(milliseconds: 200),
      );
      final serviceB = FakeParkingService(
        cityConfig: CityConfig.dresden,
        spots: [
          fakeSpot(
            id: 'dd',
            cityId: 'dresden',
            position: const LatLng(51.05, 13.74),
            location: 'Dresden 1',
          ),
        ],
      );

      final model = ParkingSpotsModel();
      model.setService(serviceA);
      model.applyFilter(filterAroundCenter());
      expect(model.isFiltered, isTrue);

      final slowLoad = model.loadSpots(); // laeuft noch
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Stadtwechsel waehrend des Ladens
      model.setService(serviceB);
      expect(
        model.currentFilter,
        isNull,
        reason: 'Filter der alten Stadt wird verworfen',
      );
      await model.loadSpots();

      await slowLoad; // alte Ladung trifft spaeter ein
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(model.allSpots, hasLength(1));
      expect(
        model.allSpots.single.id,
        'dd',
        reason: 'Nur Ergebnisse der neuen Stadt',
      );
      expect(model.isFiltered, isFalse);
    });
  });

  group('FilterBottomSheet – Standortmodus', () {
    testWidgets('Meine Position ohne Standort: Meldung, keine Filterung', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      // Muss im Testkoerper zurueckgesetzt werden (Binding-Invarianten).
      try {
        final spotsModel = ParkingSpotsModel();
        final mock = NominatimMock(responder: (_) => nominatimSearchResult());
        final mapController = MapController();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => CityModel(
                  serviceFactory: (city) =>
                      FakeParkingService(cityConfig: city),
                ),
              ),
              ChangeNotifierProvider.value(value: spotsModel),
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Filter anwenden'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Filter anwenden'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Standort nicht verfügbar'),
          findsOneWidget,
          reason: 'Verstaendliche Meldung statt Stillstand',
        );
        expect(
          spotsModel.isFiltered,
          isFalse,
          reason: 'Ohne Standort darf nicht gefiltert werden',
        );
        expect(
          mock.requests,
          isEmpty,
          reason: 'Keine Geocoding-Anfrage im Standortmodus',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
