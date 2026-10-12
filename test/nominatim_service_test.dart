// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:parklibre/services/nominatim_service.dart';

import 'helpers/test_doubles.dart';

void main() {
  group('NominatimService – Dienstnutzung', () {
    test('Standard-Dienstadresse ist ohne Software-Update konfigurierbar', () {
      // Default: offizieller Dienst. Ueberschreibbar via
      // --dart-define=NOMINATIM_BASE_URL=...
      expect(NominatimService.defaultBaseUrl,
          'https://nominatim.openstreetmap.org');
    });

    test('Suche sendet genau eine Anfrage an den konfigurierten Dienst',
        () async {
      final mock = NominatimMock(responder: (_) => nominatimSearchResult());

      final results = await mock.service.searchAddresses(
        'Alexanderplatz',
        cityName: 'Deutschland',
      );

      expect(mock.requests, hasLength(1));
      expect(mock.requests.single.host, 'nominatim.test');
      expect(mock.requests.single.path, '/search');
      expect(mock.requests.single.queryParameters['q'],
          'Alexanderplatz, Deutschland');
      expect(results, hasLength(1));
    });

    test('Zu kurze Suchbegriffe erzeugen keine Anfrage', () async {
      final mock = NominatimMock(responder: (_) => nominatimSearchResult());

      expect(await mock.service.searchAddresses('ab'), isEmpty);
      expect(await mock.service.searchAddresses('   '), isEmpty);
      expect(mock.requests, isEmpty);
    });

    test('Umlaute aus Antworten bleiben korrekt (UTF-8-Bytes)', () async {
      final mock = NominatimMock(
        responder: (_) =>
            nominatimReverseResult('Hauptstraße 5, Südvorstadt, Dresden'),
      );

      final addr =
          await mock.service.reverseGeocode(const LatLng(51.05, 13.74));

      expect(addr, 'Hauptstraße 5, Südvorstadt, Dresden');
    });
  });

  group('NominatimService – Anfragekoordination', () {
    test('Suche und Reverse werden gemeinsam auf 1 Anfrage/Sekunde begrenzt',
        () async {
      final delays = <Duration>[];
      final mock = NominatimMock(
        responder: (url) => url.path.endsWith('/reverse')
            ? nominatimReverseResult('Irgendwo 1, Berlin')
            : nominatimSearchResult(),
        minRequestInterval: const Duration(seconds: 1),
        delay: (d) async => delays.add(d),
      );

      // Suche und Reverse direkt hintereinander ausloesen.
      await Future.wait([
        mock.service.searchAddresses('Alexanderplatz'),
        mock.service.reverseGeocode(const LatLng(52.52, 13.405)),
      ]);

      expect(mock.requests, hasLength(2),
          reason: 'Beide Anfragen muessen ausgefuehrt werden');
      expect(delays, hasLength(1),
          reason: 'Die zweite Anfrage muss warten (max. 1 Anfrage/Sekunde)');
      expect(delays.single.inMilliseconds, inInclusiveRange(900, 1000));
    });

    test('Drei schnelle Anfragen werden serialisiert und begrenzt', () async {
      final delays = <Duration>[];
      final mock = NominatimMock(
        responder: (_) => nominatimReverseResult('X'),
        minRequestInterval: const Duration(seconds: 1),
        delay: (d) async => delays.add(d),
      );

      await Future.wait([
        mock.service.reverseGeocode(const LatLng(1, 1)),
        mock.service.reverseGeocode(const LatLng(2, 2)),
        mock.service.reverseGeocode(const LatLng(3, 3)),
      ]);

      expect(mock.requests, hasLength(3));
      expect(delays, hasLength(2),
          reason: 'Nur die erste Anfrage startet ohne Wartezeit');
    });
  });

  group('NominatimService – Reverse-Cache', () {
    test('Reverse-Anfragen werden gecacht (eine Anfrage pro Position)',
        () async {
      final mock = NominatimMock(
        responder: (_) => nominatimReverseResult('Teststraße 1, Berlin'),
      );
      const position = LatLng(52.52, 13.405);

      final first = await mock.service.reverseGeocode(position);
      final second = await mock.service.reverseGeocode(position);

      expect(mock.requests, hasLength(1));
      expect(first, 'Teststraße 1, Berlin');
      expect(second, first);
    });

    test('Parallele Reverse-Anfragen auf dieselbe Position werden geteilt',
        () async {
      final mock = NominatimMock(
        responder: (_) => nominatimReverseResult('Teststraße 1, Berlin'),
      );
      const position = LatLng(52.52, 13.405);

      final results = await Future.wait([
        mock.service.reverseGeocode(position),
        mock.service.reverseGeocode(position),
      ]);

      expect(mock.requests, hasLength(1),
          reason: 'Doppelte Anfragen muessen zusammengelegt werden');
      expect(results[0], results[1]);
    });

    test('Verschiedene Positionen erzeugen eigene Anfragen', () async {
      final mock = NominatimMock(
        responder: (_) => nominatimReverseResult('Etwas'),
      );

      await mock.service.reverseGeocode(const LatLng(52.52, 13.405));
      await mock.service.reverseGeocode(const LatLng(48.14, 11.58));

      expect(mock.requests, hasLength(2));
    });

    test('Fehlerhafte Reverse-Anfragen werden nicht dauerhaft gecacht',
        () async {
      var calls = 0;
      final mock = NominatimMock(
        responder: (_) => nominatimReverseResult('Zweiter Versuch'),
        status: (_) {
          calls++;
          return calls == 1 ? 500 : 200;
        },
      );
      const position = LatLng(52.52, 13.405);

      await expectLater(
        mock.service.reverseGeocode(position),
        throwsA(isA<NominatimException>()),
      );
      final second = await mock.service.reverseGeocode(position);

      expect(second, 'Zweiter Versuch');
      expect(mock.requests, hasLength(2),
          reason: 'Fehler duerfen nicht dauerhaft gecacht werden');
    });
  });
}
