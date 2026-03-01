import 'package:latlong2/latlong.dart';

/// Koordinatensystem der Stadt
enum CoordinateSystem {
  wgs84, // EPSG:4326 - Lat/Lng (Berlin)
  utm32, // EPSG:25832 - UTM Zone 32 (München)
}

/// Konfiguration für eine Stadt mit Behindertenparkplatz-Daten
class CityConfig {
  final String id;
  final String name;
  final String countryCode;
  final LatLng defaultCenter;
  final String wfsEndpoint;
  final String layerName;
  final String cityNameInAddress;
  final Map<String, String?> fieldMapping;
  final CoordinateSystem coordinateSystem;

  const CityConfig({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.defaultCenter,
    required this.wfsEndpoint,
    required this.layerName,
    required this.cityNameInAddress,
    required this.fieldMapping,
    this.coordinateSystem = CoordinateSystem.wgs84,
  });

  /// Verfügbare Städte
  static const List<CityConfig> availableCities = [berlin, muenchen];

  /// Berlin Konfiguration
  static const CityConfig berlin = CityConfig(
    id: 'berlin',
    name: 'Berlin',
    countryCode: 'DE',
    defaultCenter: LatLng(52.52, 13.405),
    wfsEndpoint: 'https://gdi.berlin.de/services/wfs/behindertenparkplaetze',
    layerName: 'behindertenparkplaetze:bpark',
    cityNameInAddress: 'Berlin',
    coordinateSystem: CoordinateSystem.wgs84,
    fieldMapping: {
      'id': 'uid',
      'district': 'bezirk',
      'designation': 'bezeichnun',
      'remark': 'bemerkung',
      'count': 'anzahl',
      'policeSection': 'polizei',
      'location': 'standort',
      'postalCode': 'plz',
      'neighborhood': 'ortsteil',
      'latitude': 'gps_lat',
      'longitude': 'gps_lon',
      'lastUpdated': 'datum',
    },
  );

  /// München Konfiguration (UTM Koordinaten!)
  static const CityConfig muenchen = CityConfig(
    id: 'muenchen',
    name: 'München',
    countryCode: 'DE',
    defaultCenter: LatLng(48.1351, 11.5820),
    wfsEndpoint: 'https://geoportal.muenchen.de/geoserver/mor_wfs/ows',
    layerName: 'mor_wfs:behindertenparkplaetze',
    cityNameInAddress: 'München',
    coordinateSystem: CoordinateSystem.utm32,
    fieldMapping: {
      'id': 'parkplatz_id',
      'district': 'stadtbezirk',
      'designation': 'bezeichnung',
      'remark': 'hinweis',
      'count': 'anzahl_stellplaetze',
      'policeSection': null,
      'location': 'bezeichnung_anordnung',
      'postalCode': 'plz',
      'neighborhood': 'stadtbezirk',
      'latitude': null,
      'longitude': null,
      'lastUpdated': 'erfasst_bearbeitet',
    },
  );

  /// Findet eine Stadt-Konfiguration anhand der ID
  static CityConfig? findById(String id) {
    try {
      return availableCities.firstWhere((city) => city.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Gibt den angezeigten Namen der Stadt zurück
  String get displayName => name;

  /// Gibt den vollständigen Adresszusatz zurück (für Geocoding)
  String get addressSuffix => '$cityNameInAddress, Deutschland';
}
