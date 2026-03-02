import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../models/city_config.dart';
import '../models/disabled_parking_spot.dart';
import 'parking_service.dart';

/// Service für Behindertenparkplatz-Daten in München
/// Verwendet WFS (Web Feature Service) des Münchener Geoportals
class MunichParkingService extends ParkingService {
  MunichParkingService({http.Client? client})
    : super(cityConfig: CityConfig.muenchen, client: client);

  @override
  Future<List<DisabledParkingSpot>> fetchAllSpots() async {
    final url = Uri.parse(cityConfig.apiEndpoint).replace(
      queryParameters: {
        'service': 'WFS',
        'version': '2.0.0',
        'request': 'GetFeature',
        'typeNames': cityConfig.layerName,
        'outputFormat': 'application/json',
      },
    );

    final response = await client.get(url);

    if (response.statusCode != 200) {
      throw ParkingServiceException(
        'Failed to fetch data: ${response.statusCode}',
        body: response.body,
        cityConfig: cityConfig,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return parseWfsResponse(data, cityConfig);
  }

  @override
  Future<List<DisabledParkingSpot>> fetchSpotsByDistrict(
    String district,
  ) async {
    // München verwendet "stadtbezirk" statt "bezirk"
    final filter =
        '<Filter><PropertyIsEqualTo><PropertyName>stadtbezirk</PropertyName>'
        '<Literal>$district</Literal></PropertyIsEqualTo></Filter>';

    final url = Uri.parse(cityConfig.apiEndpoint).replace(
      queryParameters: {
        'service': 'WFS',
        'version': '2.0.0',
        'request': 'GetFeature',
        'typeNames': cityConfig.layerName,
        'outputFormat': 'application/json',
        'FILTER': filter,
      },
    );

    final response = await client.get(url);

    if (response.statusCode != 200) {
      throw ParkingServiceException(
        'Failed to fetch data: ${response.statusCode}',
        body: response.body,
        cityConfig: cityConfig,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return parseWfsResponse(data, cityConfig);
  }

  @override
  Future<List<DisabledParkingSpot>> fetchSpotsInBounds(
    LatLngBounds bounds,
  ) async {
    final bbox =
        '${bounds.southWest.longitude},${bounds.southWest.latitude},'
        '${bounds.northEast.longitude},${bounds.northEast.latitude},EPSG:4326';

    final url = Uri.parse(cityConfig.apiEndpoint).replace(
      queryParameters: {
        'service': 'WFS',
        'version': '2.0.0',
        'request': 'GetFeature',
        'typeNames': cityConfig.layerName,
        'outputFormat': 'application/json',
        'BBOX': bbox,
      },
    );

    final response = await client.get(url);

    if (response.statusCode != 200) {
      throw ParkingServiceException(
        'Failed to fetch data: ${response.statusCode}',
        body: response.body,
        cityConfig: cityConfig,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return parseWfsResponse(data, cityConfig);
  }
}
