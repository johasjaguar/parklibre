import 'package:latlong2/latlong.dart';

enum FilterMode { currentLocation, targetAddress }

class FilterCriteria {
  final FilterMode mode;
  final double radiusMeters;
  final LatLng? center;
  final String? address;
  final bool persistFilter;

  const FilterCriteria({
    required this.mode,
    required this.radiusMeters,
    this.center,
    this.address,
    this.persistFilter = false,
  });

  // Radius-Optionen in Metern
  static const List<double> radiusOptions = [
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
  ];

  String get radiusLabel {
    if (radiusMeters < 1000) {
      return '${radiusMeters.toInt()}m';
    }
    return '${(radiusMeters / 1000).toStringAsFixed(radiusMeters == 1000 ? 0 : 1)}km';
  }

  bool get isValid {
    if (mode == FilterMode.targetAddress) {
      return center != null && address != null && address!.isNotEmpty;
    }
    return true;
  }

  FilterCriteria copyWith({
    FilterMode? mode,
    double? radiusMeters,
    LatLng? center,
    String? address,
    bool? persistFilter,
  }) {
    return FilterCriteria(
      mode: mode ?? this.mode,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      center: center ?? this.center,
      address: address ?? this.address,
      persistFilter: persistFilter ?? this.persistFilter,
    );
  }
}
