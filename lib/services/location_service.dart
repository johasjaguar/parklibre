// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;

  bool get isLocationEnabled => _lastPosition != null;
  Position? get lastPosition => _lastPosition;

  Future<bool> checkAndRequestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      debugPrint(
        '[LocationService] Linux platform detected - GPS not available',
      );
      return false;
    }

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] Location service disabled');
      return false;
    }

    permission = await Geolocator.checkPermission();
    debugPrint('[LocationService] Current permission: $permission');

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[LocationService] After requestPermission: $permission');
      if (permission == LocationPermission.denied) {
        debugPrint('[LocationService] Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Location permission denied forever');
      return false;
    }

    return true;
  }

  Future<LatLng?> getCurrentLocation() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Auf Linux gibt es keinen Standortdienst. Bewusst "kein Standort"
      // statt eines erfundenen Ortes – Anwender:innen werden in der UI
      // verstaendlich informiert.
      debugPrint('[LocationService] Linux platform - no location available');
      return null;
    }

    try {
      // Zuerst prüfen ob Location Service enabled ist
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationService] Location service is disabled');
        return null;
      }

      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        debugPrint('[LocationService] No permission to get location');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _lastPosition = position;
      debugPrint(
        '[LocationService] Got position: ${position.latitude}, ${position.longitude}',
      );
      return LatLng(position.latitude, position.longitude);
    } on TimeoutException {
      debugPrint('[LocationService] Timeout getting location');
      return null;
    } catch (e) {
      debugPrint('[LocationService] Error getting location: $e');
      return null;
    }
  }

  Stream<LatLng> getLocationStream() {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Kein Standortdienst: leerer Stream statt eines erfundenen Ortes.
      return const Stream<LatLng>.empty();
    }

    return Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        )
        .map((position) {
          _lastPosition = position;
          return LatLng(position.latitude, position.longitude);
        })
        .handleError((error) {
          debugPrint('[LocationService] Stream error: $error');
        });
  }

  void startLocationUpdates(Function(LatLng) onLocationUpdate) {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Kein Standortdienst: keine Updates mit erfundenem Ort ausloesen.
      debugPrint('[LocationService] Linux platform - no location updates');
      return;
    }

    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (position) {
            _lastPosition = position;
            onLocationUpdate(LatLng(position.latitude, position.longitude));
          },
          onError: (error) {
            debugPrint('[LocationService] Update error: $error');
          },
        );
  }

  void stopLocationUpdates() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void dispose() {
    stopLocationUpdates();
  }
}
