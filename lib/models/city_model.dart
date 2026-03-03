import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/city_config.dart';
import '../services/parking_service.dart';
import '../services/berlin_parking_service.dart';
import '../services/munich_parking_service.dart';
import '../services/dresden_parking_service.dart';

/// Gemeinsamer HTTP Client für alle Services
final _sharedHttpClient = http.Client();

/// Model für die aktuell ausgewählte Stadt
/// Verwaltet Stadt-Auswahl und Service-Instanz
class CityModel extends ChangeNotifier {
  static const _cityKey = 'selected_city_id';

  CityConfig _currentCity = CityConfig.berlin;
  ParkingService? _service;
  Future<void>? _initializationComplete;

  CityConfig get currentCity => _currentCity;
  ParkingService get service {
    _service ??= _createService(_currentCity);
    return _service!;
  }

  String get currentCityName => _currentCity.name;
  String get currentCityId => _currentCity.id;

  Future<void> waitForInitialization() async {
    await _initializationComplete;
  }

  CityModel() {
    _service = _createService(_currentCity);
    _initializationComplete = _loadSavedCity();
  }

  /// Erstellt den passenden Service für eine Stadt
  ParkingService _createService(CityConfig city) {
    switch (city.id) {
      case 'berlin':
        return BerlinParkingService(client: _sharedHttpClient);
      case 'muenchen':
        return MunichParkingService(client: _sharedHttpClient);
      case 'dresden':
        return DresdenParkingService(client: _sharedHttpClient);
      default:
        throw UnsupportedError('City ${city.id} not supported');
    }
  }

  /// Lädt die zuletzt ausgewählte Stadt aus SharedPreferences
  /// Wenn keine Stadt gespeichert ist, bleibt Berlin als Standard
  Future<void> _loadSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCityId = prefs.getString(_cityKey);

    // Nur laden wenn eine gültige Stadt gespeichert wurde
    if (savedCityId != null && savedCityId.isNotEmpty) {
      final city = CityConfig.findById(savedCityId);
      if (city != null && city.id != _currentCity.id) {
        _switchCity(city);
      }
    }
    // Wenn keine Stadt gespeichert, bleibt Berlin als Standard (wie gewünscht)
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
