import 'package:latlong2/latlong.dart';

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
      position = LatLng(52.52, 13.405);
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
    );
  }

  String get formattedAddress {
    final parts = [location];
    if (postalCode != null) parts.add('$postalCode Berlin');
    return parts.join(', ');
  }

  String get shortInfo {
    if (remark != null && remark!.isNotEmpty) {
      return remark!;
    }
    return '$count Parkplatz${count > 1 ? 'e' : ''}';
  }
}
