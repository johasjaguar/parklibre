// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'city_config.dart';

/// Status ob Adresse verfügbar ist oder Reverse Geocoding braucht
enum AddressSource {
  hasAddress, // API liefert echte Adresse
  needsReverse, // Muss via Reverse Geocoding geladen werden
}

/// Koordinaten-Transformation von UTM zu WGS84
final _utmProj =
    proj4.Projection.get('EPSG:25832') ??
    proj4.Projection.add(
      'EPSG:25832',
      '+proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
    );
final _wgs84Proj =
    proj4.Projection.get('EPSG:4326') ??
    proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');

class DisabledParkingSpot {
  final String id;
  final String district;
  final String designation;
  final String? remark;

  /// Zeitliche Angaben im Wortlaut (z.B. "Mo-Fr 8-18h").
  /// `null` bedeutet: keine Angabe – bewusst KEINE ganztägige Verfügbarkeit.
  final String? usageTimes;

  /// Zeitliche Einschränkungen im Wortlaut (z.B. "bis 3 Stunden").
  /// `null` bedeutet: keine Angabe.
  final String? timeRestrictions;
  final int count;
  final String? policeSection;
  final String location;
  final String? postalCode;
  final String? neighborhood;
  final LatLng position;
  final DateTime? lastUpdated;
  final String cityId;
  final AddressSource addressSource;

  const DisabledParkingSpot({
    required this.id,
    required this.district,
    required this.designation,
    this.remark,
    this.usageTimes,
    this.timeRestrictions,
    required this.count,
    this.policeSection,
    required this.location,
    this.postalCode,
    this.neighborhood,
    required this.position,
    this.lastUpdated,
    required this.cityId,
    this.addressSource = AddressSource.hasAddress,
  });

  factory DisabledParkingSpot.fromJson(Map<String, dynamic> json) {
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    final geom = json['geometry'] as Map<String, dynamic>?;

    LatLng position;
    if (props['gps_lat'] != null && props['gps_lon'] != null) {
      position = LatLng(
        (props['gps_lat'] as num).toDouble(),
        (props['gps_lon'] as num).toDouble(),
      );
    } else if (geom != null && geom['coordinates'] != null) {
      final coords = geom['coordinates'] as List;
      position = LatLng(coords[1].toDouble(), coords[0].toDouble());
    } else {
      position = const LatLng(52.52, 13.405);
    }

    return DisabledParkingSpot(
      id: props['uid']?.toString() ?? '',
      district: props['bezirk']?.toString() ?? '',
      designation: props['bezeichnun']?.toString() ?? '',
      remark: props['bemerkung']?.toString(),
      count: (props['anzahl'] as num?)?.toInt() ?? 1,
      policeSection: props['polizei']?.toString(),
      location: props['standort']?.toString() ?? '',
      postalCode: props['plz']?.toString(),
      neighborhood: props['ortsteil']?.toString(),
      position: position,
      lastUpdated: props['datum'] != null
          ? DateTime.tryParse(props['datum'].toString())
          : null,
      cityId: 'berlin',
      addressSource: AddressSource.hasAddress,
    );
  }

  /// Factory-Methode für WFS-Daten mit CityConfig
  factory DisabledParkingSpot.fromWfsJson(
    Map<String, dynamic> json,
    CityConfig config,
  ) {
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    final geom = json['geometry'] as Map<String, dynamic>?;
    final mapping = config.fieldMapping;

    // Liest ein gemapptes Feld als getrimmten Text; leere Werte werden
    // als "keine Angabe" (null) behandelt und nie interpretiert.
    String? readMapped(String key) {
      final field = mapping[key];
      if (field == null) return null;
      final value = props[field]?.toString().trim();
      if (value == null || value.isEmpty) return null;
      return value;
    }

    LatLng position;

    // ZUERST: Versuche explizite Koordinatenfelder (gps_lat/gps_lon)
    final latField = mapping['latitude'];
    final lonField = mapping['longitude'];
    if (latField != null &&
        lonField != null &&
        props[latField] != null &&
        props[lonField] != null) {
      position = LatLng(
        (props[latField] as num).toDouble(),
        (props[lonField] as num).toDouble(),
      );
    }
    // FALLBACK: Geometry verwenden wenn keine expliziten Felder
    else if (geom != null && geom['coordinates'] != null) {
      final coords = geom['coordinates'] as List;
      final x = (coords[0] as num).toDouble();
      final y = (coords[1] as num).toDouble();

      if (config.coordinateSystem == CoordinateSystem.utm32) {
        // Konvertiere UTM zu WGS84
        final wgs84Point = _utmProj.transform(
          _wgs84Proj,
          proj4.Point(x: x, y: y),
        );
        position = LatLng(wgs84Point.y, wgs84Point.x);
      } else {
        // Bereits in WGS84 (Lat/Lng)
        position = LatLng(y, x);
      }
    } else {
      // Final fallback: Stadt-Zentrum
      position = config.defaultCenter;
    }

    // Bestimme addressSource: Wenn API ein location-Feld hat → hasAddress, sonst needsReverse
    final hasLocationField =
        mapping['location'] != null &&
        props[mapping['location']] != null &&
        props[mapping['location']].toString().isNotEmpty;
    final addressSource = hasLocationField
        ? AddressSource.hasAddress
        : AddressSource.needsReverse;

    return DisabledParkingSpot(
      id: props[mapping['id']]?.toString() ?? '',
      district: props[mapping['district']]?.toString() ?? '',
      designation: props[mapping['designation']]?.toString() ?? '',
      remark: mapping['remark'] != null
          ? props[mapping['remark']]?.toString()
          : null,
      usageTimes: readMapped('usageTimes'),
      timeRestrictions: readMapped('timeRestrictions'),
      count: (props[mapping['count']] as num?)?.toInt() ?? 1,
      policeSection: mapping['policeSection'] != null
          ? props[mapping['policeSection']]?.toString()
          : null,
      location: hasLocationField
          ? props[mapping['location']].toString()
          : '${config.cityNameInAddress} (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})',
      postalCode: mapping['postalCode'] != null
          ? props[mapping['postalCode']]?.toString()
          : null,
      neighborhood: mapping['neighborhood'] != null
          ? props[mapping['neighborhood']]?.toString()
          : null,
      position: position,
      lastUpdated:
          mapping['lastUpdated'] != null &&
              props[mapping['lastUpdated']] != null
          ? DateTime.tryParse(props[mapping['lastUpdated']].toString())
          : null,
      cityId: config.id,
      addressSource: addressSource,
    );
  }

  String get formattedAddress {
    final cityConfig = CityConfig.findById(cityId);
    final cityName = cityConfig?.cityNameInAddress ?? 'Berlin';
    final parts = [location];
    if (postalCode != null) parts.add('$postalCode $cityName');
    return parts.join(', ');
  }

  String get shortInfo {
    if (remark != null && remark!.isNotEmpty) {
      return remark!;
    }
    return '$count Parkplatz${count > 1 ? 'e' : ''}';
  }
}
