import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/city_config.dart';
import '../services/parking_service.dart';
import '../services/berlin_parking_service.dart';
import '../services/munich_parking_service.dart';

/// Model für die aktuell ausgewählte Stadt
/// Verwaltet Stadt-Auswahl und Service-Instanz
class CityModel extends ChangeNotifier {
  static const _cityKey = 'selected_city_id';

  CityConfig _currentCity = CityConfig.berlin;
  ParkingService? _service;

  CityConfig get currentCity => _currentCity;
  ParkingService get service {
    _service ??= _createService(_currentCity);
    return _service!;
  }

  String get currentCityName => _currentCity.name;
  String get currentCityId => _currentCity.id;

  CityModel() {
    _service = _createService(_currentCity);
    _loadSavedCity();
  }

  /// Erstellt den passenden Service für eine Stadt
  ParkingService _createService(CityConfig city) {
    switch (city.id) {
      case 'berlin':
        return BerlinParkingService();
      case 'muenchen':
        return MunichParkingService();
      default:
        throw UnsupportedError('City ${city.id} not supported');
    }
  }

  /// Lädt die zuletzt ausgewählte Stadt aus SharedPreferences
  Future<void> _loadSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCityId = prefs.getString(_cityKey);

    if (savedCityId != null) {
      final city = CityConfig.findById(savedCityId);
      if (city != null && city.id != _currentCity.id) {
        _switchCity(city);
      }
    }
  }

  /// Wechselt zu einer anderen Stadt
  Future<void> switchCity(CityConfig city) async {
    if (city.id == _currentCity.id) return;

    _switchCity(city);

    // Speichere Auswahl
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cityKey, city.id);
  }

  void _switchCity(CityConfig city) {
    // Erstelle neuen Service - alter Service wird später garbage collected
    // Nicht sofort disposed wegen möglicher offener Requests
    _service = _createService(city);

    _currentCity = city;
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}
