import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'city_config.dart';

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
  final int count;
  final String? policeSection;
  final String location;
  final String? postalCode;
  final String? neighborhood;
  final LatLng position;
  final DateTime? lastUpdated;
  final String cityId;

  const DisabledParkingSpot({
    required this.id,
    required this.district,
    required this.designation,
    this.remark,
    required this.count,
    this.policeSection,
    required this.location,
    this.postalCode,
    this.neighborhood,
    required this.position,
    this.lastUpdated,
    required this.cityId,
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

    return DisabledParkingSpot(
      id: props[mapping['id']]?.toString() ?? '',
      district: props[mapping['district']]?.toString() ?? '',
      designation: props[mapping['designation']]?.toString() ?? '',
      remark: mapping['remark'] != null
          ? props[mapping['remark']]?.toString()
          : null,
      count: (props[mapping['count']] as num?)?.toInt() ?? 1,
      policeSection: mapping['policeSection'] != null
          ? props[mapping['policeSection']]?.toString()
          : null,
      location: props[mapping['location']]?.toString() ?? '',
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
