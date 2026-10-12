// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide DistanceCalculator;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/city_config.dart';
import 'models/city_model.dart';
import 'models/disabled_parking_spot.dart';
import 'models/filter_criteria.dart';
import 'services/location_service.dart';
import 'services/nominatim_service.dart';
import 'services/parking_service.dart';
import 'utils/distance_calculator.dart';

void main() {
  runApp(const ParkLibreApp());
}

class ParkLibreApp extends StatelessWidget {
  const ParkLibreApp({
    super.key,
    this.serviceFactory,
    this.nominatim,
    this.tileProvider,
  });

  /// Optionaler Ersatz für die Parkplatz-Dienste (Tests/Offline).
  final ParkingServiceFactory? serviceFactory;

  /// Optionaler Ersatz für den Geocoding-Dienst (Tests/Offline).
  final NominatimService? nominatim;

  /// Optionaler Ersatz für den Karten-Kachel-Provider (Tests/Offline).
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CityModel(serviceFactory: serviceFactory),
        ),
        ChangeNotifierProvider(create: (_) => ParkingSpotsModel()),
        ChangeNotifierProvider(create: (_) => LocationModel()),
        // Gemeinsamer Geocoding-Dienst: begrenzt Suche- und
        // Reverse-Anfragen gemeinsam und teilt Ergebnisse.
        Provider<NominatimService>.value(value: nominatim ?? NominatimService()),
      ],
      child: MaterialApp(
        title: 'ParkLibre',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: MapScreen(tileProvider: tileProvider),
      ),
    );
  }
}

class LocationModel extends ChangeNotifier {
  final LocationService _service = LocationService();
  LatLng? _currentLocation;
  bool _isLoading = false;
  String? _error;
  bool _isTracking = false;

  LatLng? get currentLocation => _currentLocation;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTracking => _isTracking;

  Future<void> getCurrentLocation() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final location = await _service.getCurrentLocation();
      if (location != null) {
        _currentLocation = location;
      } else {
        _error = 'Standort konnte nicht ermittelt werden';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void startTracking() {
    if (_isTracking) return;
    _isTracking = true;
    _service.startLocationUpdates((location) {
      _currentLocation = location;
      notifyListeners();
    });
  }

  void stopTracking() {
    _isTracking = false;
    _service.stopLocationUpdates();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

class ParkingSpotsModel extends ChangeNotifier {
  ParkingService? _service;
  List<DisabledParkingSpot> _spots = [];
  List<DisabledParkingSpot> _filteredSpots = [];
  bool _isLoading = false;
  String? _error;
  FilterCriteria? _currentFilter;
  bool _isFilterActive = false;
  int _loadCounter = 0; // Force rebuild on change

  List<DisabledParkingSpot> get spots =>
      _isFilterActive ? _filteredSpots : _spots;
  List<DisabledParkingSpot> get allSpots => _spots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isFiltered => _isFilterActive;
  FilterCriteria? get currentFilter => _currentFilter;
  int get loadCounter => _loadCounter;

  /// Setzt den Service (wird aufgerufen wenn Stadt gewechselt wird)
  void setService(ParkingService service) {
    if (_service != service) {
      _service?.dispose();
      _service = service;
      _spots = [];
      _filteredSpots = [];
      _isFilterActive = false;
      _loadCounter++;
      notifyListeners();
    }
  }

  Future<void> loadSpots() async {
    if (_isLoading || _service == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _spots = await _service!.fetchAllSpots();
      _filteredSpots = [];
      _isFilterActive = false;
      _loadCounter++;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void applyFilter(FilterCriteria filter) {
    if (!filter.isValid) {
      clearFilter();
      return;
    }

    final center = filter.mode == FilterMode.currentLocation
        ? filter.center
        : filter.center;

    if (center == null) {
      clearFilter();
      return;
    }

    _currentFilter = filter;
    _isFilterActive = true;
    _filteredSpots = _spots.where((spot) {
      final distance = DistanceCalculator.calculateDistance(
        spot.position,
        center,
      );
      return distance <= filter.radiusMeters;
    }).toList();

    notifyListeners();
  }

  void clearFilter() {
    _currentFilter = null;
    _isFilterActive = false;
    _filteredSpots = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.tileProvider});

  /// Optionaler Ersatz für den Karten-Kachel-Provider (Tests/Offline).
  final TileProvider? tileProvider;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _initialZoom = 12.0;
  static const _locateZoom = 14.5;

  final MapController _mapController = MapController();
  DisabledParkingSpot? _nearestSpot;
  double? _nearestDistance;
  Timer? _nearestInfoTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Warten bis Stadt geladen ist (wichtig für geladene Stadt aus SharedPreferences)
      final cityModel = context.read<CityModel>();
      await cityModel.waitForInitialization();

      final spotsModel = context.read<ParkingSpotsModel>();
      spotsModel.setService(cityModel.service);
      // Dann laden
      spotsModel.loadSpots();
      // Karte auf Stadtzentrum zentrieren
      _mapController.move(cityModel.currentCity.defaultCenter, _initialZoom);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nearestInfoTimer?.cancel();
    super.dispose();
  }

  Future<void> _animateToLocation(LatLng target) async {
    _mapController.move(target, _locateZoom);
  }

  Future<void> _locateMe() async {
    final locationModel = context.read<LocationModel>();

    if (locationModel.currentLocation != null) {
      await _animateToLocation(locationModel.currentLocation!);
      return;
    }

    await locationModel.getCurrentLocation();

    if (locationModel.currentLocation != null) {
      await _animateToLocation(locationModel.currentLocation!);
    } else if (mounted) {
      final cityModel = context.read<CityModel>();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(locationModel.error ?? 'Standort nicht verfügbar'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '${cityModel.currentCityName} Zentrum',
            onPressed: () =>
                _animateToLocation(cityModel.currentCity.defaultCenter),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CityModel>(
      builder: (context, cityModel, _) {
        // Always use the current city's service from CityModel
        // This ensures we always have the right service
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final spotsModel = context.read<ParkingSpotsModel>();
          spotsModel.setService(cityModel.service);
        });

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/logo_parklibre_int.png',
                  height: 30,
                  fit: BoxFit.contain,
                ),
                const Spacer(),
                Text(
                  cityModel.currentCityName,
                  style: TextStyle(
                    fontFamily: 'DIN1451Mittelschrift',
                    color: Colors.grey[400],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF005A8C),
          ),
          body: Consumer2<ParkingSpotsModel, LocationModel>(
            builder: (context, spotsModel, locationModel, child) {
              // Zeige Snackbar wenn Filter aktiv aber keine Ergebnisse
              if (spotsModel.isFiltered &&
                  spotsModel.spots.isEmpty &&
                  spotsModel.currentFilter != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Keine Parkplätze im Umkreis von ${spotsModel.currentFilter!.radiusLabel} gefunden',
                        ),
                        action: SnackBarAction(
                          label: 'Filter zurücksetzen',
                          onPressed: () => spotsModel.clearFilter(),
                        ),
                      ),
                    );
                  }
                });
              }

              // Schließe Snackbar wenn Filter aktiv und Ergebnisse vorhanden
              if (spotsModel.isFiltered && spotsModel.spots.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  }
                });
              }

              if (spotsModel.isLoading && spotsModel.spots.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (spotsModel.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Fehler: ${spotsModel.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: spotsModel.loadSpots,
                        child: const Text('Erneut laden'),
                      ),
                    ],
                  ),
                );
              }

              return Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: context
                          .read<CityModel>()
                          .currentCity
                          .defaultCenter,
                      initialZoom: _initialZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        // Ohne Software-Update wechselbar (Nutzungsvorgabe
                        // der OSM-Kacheldienste):
                        // --dart-define=OSM_TILE_URL=https://...
                        urlTemplate: const String.fromEnvironment(
                          'OSM_TILE_URL',
                          defaultValue:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        ),
                        userAgentPackageName: 'de.parklibre',
                        maxZoom: 19,
                        tileProvider: widget.tileProvider,
                      ),
                      MarkerLayer(
                        key: ValueKey('markers_${spotsModel.loadCounter}'),
                        markers: spotsModel.spots
                            .asMap()
                            .entries
                            .map(
                              (entry) => Marker(
                                key: ValueKey(
                                  '${entry.value.cityId}_${entry.value.id}_${entry.key}',
                                ),
                                point: entry.value.position,
                                width: 40,
                                height: 40,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        _showSpotDetails(context, entry.value),
                                    borderRadius: BorderRadius.circular(20),
                                    child: const Icon(
                                      Icons.accessible,
                                      color: Colors.blue,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      if (locationModel.currentLocation != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: locationModel.currentLocation!,
                              radius: 12,
                              color: Colors.blue.withValues(alpha: 0.3),
                              borderColor: Colors.blue,
                              borderStrokeWidth: 3,
                            ),
                          ],
                        ),
                      // Radius-Kreis wenn Filter aktiv
                      if (spotsModel.isFiltered &&
                          spotsModel.currentFilter?.center != null)
                        IgnorePointer(
                          child: CircleLayer(
                            circles: [
                              CircleMarker(
                                point: spotsModel.currentFilter!.center!,
                                radius: spotsModel.currentFilter!.radiusMeters,
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderColor: Colors.orange,
                                borderStrokeWidth: 2,
                                useRadiusInMeter: true,
                              ),
                            ],
                          ),
                        ),
                      // Quellenangaben: sichtbar und verlinkt
                      // (Nutzungsvorgaben von OSM und Nominatim)
                      const _MapAttribution(),
                    ],
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Chip(
                      label: Text(
                        spotsModel.isFiltered
                            ? (spotsModel.spots.isEmpty
                                  ? 'Keine Parkplätze im Umkreis'
                                  : '${spotsModel.spots.length} Parkplätze im Filter')
                            : '${spotsModel.spots.length} Parkplätze',
                      ),
                      backgroundColor: spotsModel.isFiltered
                          ? (spotsModel.spots.isEmpty
                                    ? Colors.orange
                                    : Colors.green)
                                .withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (locationModel.isLoading)
                    const Positioned(
                      bottom: 80,
                      right: 16,
                      child: CircularProgressIndicator(),
                    ),
                  if (_nearestSpot != null && _nearestDistance != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () {
                          _nearestInfoTimer?.cancel();
                          _navigateToSpot(_nearestSpot!);
                        },
                        child: Card(
                          color: const Color(0xFF005A8C),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.navigation,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        DistanceCalculator.formatDistance(
                                          _nearestDistance!,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        _nearestSpot!.location,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.8,
                                          ),
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    _nearestInfoTimer?.cancel();
                                    setState(() {
                                      _nearestSpot = null;
                                      _nearestDistance = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Stadt-Auswahl Button
              Consumer<CityModel>(
                builder: (context, cityModel, _) {
                  return FloatingActionButton.small(
                    heroTag: 'city',
                    onPressed: () => _showCitySelector(context),
                    tooltip: 'Stadt wechseln (${cityModel.currentCityName})',
                    child: Text(
                      cityModel.currentCityName.substring(0, 2).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Such-Button
              FloatingActionButton(
                heroTag: 'search',
                onPressed: () => _showFilterSheet(
                  context,
                  initialMode: FilterMode.targetAddress,
                ),
                tooltip: 'Adresse suchen',
                child: const Icon(Icons.search),
              ),
              const SizedBox(height: 16),
              // Filter-Button
              Consumer<ParkingSpotsModel>(
                builder: (context, model, _) {
                  return FloatingActionButton(
                    heroTag: 'filter',
                    onPressed: () => _showFilterSheet(context),
                    backgroundColor: model.isFiltered ? Colors.orange : null,
                    child: Icon(
                      model.isFiltered
                          ? Icons.filter_list_off
                          : Icons.filter_list,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                heroTag: 'nearest',
                onPressed: _navigateToNearestSpot,
                tooltip: 'Zum nächsten Parkplatz navigieren',
                child: const Icon(Icons.navigation),
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                heroTag: 'locate',
                onPressed: _locateMe,
                child: const Icon(Icons.my_location),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSpotDetails(BuildContext context, DisabledParkingSpot spot) {
    // Berechne Entfernung zum Filter-Zentrum wenn Filter aktiv
    final spotsModel = context.read<ParkingSpotsModel>();
    // Reverse-Geocoding ueber den gemeinsamen Dienst: geteilte,
    // gecachte Anfrage – eine einzige Anfrage pro Detailansicht.
    final reverseAddress = spot.addressSource == AddressSource.needsReverse
        ? context.read<NominatimService>().reverseGeocode(spot.position)
        : null;
    String? distanceText;
    String distanceTitle = 'Entfernung (Luftlinie)';
    if (spotsModel.isFiltered && spotsModel.currentFilter?.center != null) {
      final distance = DistanceCalculator.calculateDistance(
        spot.position,
        spotsModel.currentFilter!.center!,
      );
      distanceText = DistanceCalculator.formatDistance(distance);

      // Anpassen des Titels je nach Filter-Modus
      if (spotsModel.currentFilter!.mode == FilterMode.currentLocation) {
        distanceTitle = 'Entfernung zu deinem Standort';
      } else if (spotsModel.currentFilter!.mode == FilterMode.targetAddress) {
        distanceTitle = 'Entfernung zur Zieladresse';
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Header-Bereich (nicht scrollbar)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Icon + Titel + Adresse mit PLZ
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.accessible,
                            color: Colors.blue,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Behindertenparkplatz',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 4),
                              // Für Dresden: Reverse Geocoding wenn nötig
                              if (spot.addressSource ==
                                  AddressSource.needsReverse)
                                FutureBuilder<String?>(
                                  future: reverseAddress,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return Row(
                                        children: [
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Adresse wird geladen...',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    final fullAddr = snapshot.data;
                                    if (fullAddr == null) {
                                      return Text(
                                        spot.location,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 18,
                                            ),
                                      );
                                    }

                                    final parts = fullAddr.split(', ');
                                    String? poi;
                                    String? street;
                                    String? houseNumber;

                                    if (parts.isNotEmpty &&
                                        parts[0].isNotEmpty) {
                                      final first = parts[0];
                                      final second = parts.length > 1
                                          ? parts[1]
                                          : '';
                                      final third = parts.length > 2
                                          ? parts[2]
                                          : '';

                                      if (int.tryParse(first) != null) {
                                        houseNumber = first;
                                        street = second;
                                      } else if (int.tryParse(second) != null) {
                                        poi = first;
                                        houseNumber = second;
                                        street = third;
                                      } else {
                                        street = parts.length > 1
                                            ? '$first $second'.trim()
                                            : first;
                                      }
                                    }

                                    String? plz;
                                    String? city;

                                    if (parts.length >= 5) {
                                      city = parts[parts.length - 4];
                                      plz = parts[parts.length - 2];
                                    }

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          houseNumber != null || poi != null
                                              ? '${poi ?? ''} ${street ?? ''} ${houseNumber ?? ''}'
                                                    .trim()
                                              : (street ?? ''),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 18,
                                              ),
                                        ),
                                        if (plz != null || city != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              '${plz ?? ''} ${city ?? ''}'
                                                  .trim(),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                )
                              else
                                Text(
                                  spot.location,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18,
                                      ),
                                ),
                              if (spot.postalCode != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${spot.postalCode} ${CityConfig.findById(spot.cityId)?.name ?? ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Scrollbare Details
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      if (distanceText != null)
                        _DetailCard(
                          icon: Icons.social_distance,
                          title: distanceTitle,
                          value: distanceText,
                        ),
                      if (spot.addressSource == AddressSource.needsReverse)
                        FutureBuilder<String?>(
                          future: reverseAddress,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const _DetailCard(
                                icon: Icons.location_city,
                                title: 'Bezirk',
                                value: '...',
                              );
                            }
                            final fullAddr = snapshot.data;
                            String districtValue = spot.district;
                            if (fullAddr != null) {
                              final parts = fullAddr.split(', ');
                              if (parts.length >= 5) {
                                districtValue = parts[parts.length - 5];
                              }
                            }
                            return _DetailCard(
                              icon: Icons.location_city,
                              title: 'Bezirk',
                              value: districtValue,
                            );
                          },
                        )
                      else
                        _DetailCard(
                          icon: Icons.location_city,
                          title: 'Bezirk',
                          value: spot.district,
                        ),
                      if (spot.neighborhood != null)
                        _DetailCard(
                          icon: Icons.place,
                          title: 'Ortsteil',
                          value: spot.neighborhood!,
                        ),
                      _DetailCard(
                        icon: Icons.local_parking,
                        title: 'Stellplätze',
                        value:
                            '${spot.count} ${spot.count == 1 ? 'Platz' : 'Plätze'}',
                      ),
                      if (spot.lastUpdated != null)
                        _DetailCard(
                          icon: Icons.update,
                          title: 'Letzte Aktualisierung',
                          value:
                              '${spot.lastUpdated!.day}.${spot.lastUpdated!.month}.${spot.lastUpdated!.year}',
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Fixed Button-Bereich
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _navigateToSpot(spot),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Navigation starten'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _navigateToSpot(DisabledParkingSpot spot) async {
    if (Platform.isLinux) {
      // Linux: Hinweis anzeigen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Navigation ist auf Linux nicht verfügbar'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final lat = spot.position.latitude;
    final lng = spot.position.longitude;

    // Versuche 1: google.navigation Schema (öffnet App-Chooser mit Navigation)
    try {
      final navUri = Uri.parse('google.navigation:q=$lat,$lng');
      final launched = await launchUrl(
        navUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {
      // Ignoriere Fehler, versuche nächste Option
    }

    // Versuche 2: Google Maps Navigation Intent (Routenplanung)
    try {
      final mapsUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      );
      final launched = await launchUrl(
        mapsUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {
      // Ignoriere Fehler
    }

    // Versuche 3: OsmAnd direkt
    try {
      final osmandUri = Uri.parse('osmand.api://navigate?lat=$lat&lon=$lng');
      final launched = await launchUrl(
        osmandUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {
      // Ignoriere Fehler
    }

    // Fehler anzeigen wenn nichts funktioniert hat
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keine Navigations-App gefunden. Bitte installiere Organic Maps, OsmAnd oder Google Maps.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _navigateToNearestSpot() async {
    final locationModel = context.read<LocationModel>();
    final spotsModel = context.read<ParkingSpotsModel>();

    // Automatisch Standort ermitteln wenn nicht verfügbar
    if (locationModel.currentLocation == null) {
      await locationModel.getCurrentLocation();
    }

    // Prüfe ob aktueller Standort verfügbar ist
    if (locationModel.currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Standort konnte nicht ermittelt werden. Bitte Standortberechtigung erteilen.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Prüfe ob Parkplätze geladen sind
    if (spotsModel.spots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine Parkplätze geladen'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Finde nächsten Parkplatz
    final currentPos = locationModel.currentLocation!;
    DisabledParkingSpot? nearestSpot;
    double minDistance = double.infinity;

    for (final spot in spotsModel.spots) {
      final distance = DistanceCalculator.calculateDistance(
        currentPos,
        spot.position,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestSpot = spot;
      }
    }

    if (nearestSpot != null) {
      // Speichere für State und zeige Info oben
      setState(() {
        _nearestSpot = nearestSpot;
        _nearestDistance = minDistance;
      });

      // Timer für automatisches Ausblenden nach 20 Sekunden
      _nearestInfoTimer?.cancel();
      _nearestInfoTimer = Timer(const Duration(seconds: 20), () {
        if (mounted) {
          setState(() {
            _nearestSpot = null;
            _nearestDistance = null;
          });
        }
      });

      // Kurze Pause damit UI rendern kann
      await Future.delayed(const Duration(milliseconds: 500));

      // Starte Navigation automatisch
      await _navigateToSpot(nearestSpot);
    }
  }

  void _showFilterSheet(BuildContext context, {FilterMode? initialMode}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FilterBottomSheet(
        mapController: _mapController,
        onFilterApplied: (center, radius) {
          // Zoom to show entire radius
          _zoomToRadius(center, radius);
        },
        initialMode: initialMode,
      ),
    );
  }

  void _zoomToRadius(LatLng center, double radiusMeters) {
    // Calculate zoom level to show the entire radius
    // Formula: zoom = 16 - log2(radius / 500)
    // At radius 500m: zoom ~16
    // At radius 5000m: zoom ~13
    double zoom;
    if (radiusMeters <= 100) {
      zoom = 17;
    } else if (radiusMeters <= 200) {
      zoom = 16;
    } else if (radiusMeters <= 500) {
      zoom = 15;
    } else if (radiusMeters <= 1000) {
      zoom = 14;
    } else if (radiusMeters <= 2000) {
      zoom = 13;
    } else {
      zoom = 12;
    }

    _mapController.move(center, zoom);
  }

  void _showCitySelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Stadt auswählen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(),
              ...CityConfig.availableCities.map((city) {
                final isCurrent =
                    context.watch<CityModel>().currentCityId == city.id;
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.check_circle : Icons.location_city,
                    color: isCurrent ? Colors.green : null,
                  ),
                  title: Text(city.name),
                  subtitle: Text('${city.countryCode} • WFS API'),
                  onTap: isCurrent
                      ? null
                      : () async {
                          final newCity = city;
                          // Erst Service wechseln
                          final cityModel = context.read<CityModel>();
                          await cityModel.switchCity(newCity);
                          // Service im ParkingSpotsModel aktualisieren
                          final spotsModel = context.read<ParkingSpotsModel>();
                          spotsModel.setService(cityModel.service);
                          // Info-Balken schließen bei Stadtwechsel
                          _nearestInfoTimer?.cancel();
                          setState(() {
                            _nearestSpot = null;
                            _nearestDistance = null;
                          });
                          // Dann Daten laden
                          spotsModel.loadSpots();
                          // Dialog schließen
                          Navigator.pop(context);
                          // Zoom auf neue Stadt
                          _mapController.move(newCity.defaultCenter, 12.0);
                        },
                );
              }).toList(),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DetailCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sichtbare, verlinkte Quellenangaben auf der Karte.
///
/// Die Nutzungsvorgaben der OSM-Kacheldienste verlangen eine klar
/// sichtbare Attribution, die nicht hinter Bedienelementen versteckt ist.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttributionLink(
                text: '© OpenStreetMap-Mitwirkende',
                url: 'https://www.openstreetmap.org/copyright',
              ),
              SizedBox(width: 12),
              _AttributionLink(
                text: 'Geocoding: Nominatim',
                url: 'https://nominatim.org',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Verlinkte Quellenangabe (öffnet die Seite im Browser).
class _AttributionLink extends StatelessWidget {
  const _AttributionLink({required this.text, required this.url});

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class FilterBottomSheet extends StatefulWidget {
  final MapController mapController;
  final Function(LatLng center, double radius)? onFilterApplied;
  final FilterMode? initialMode;

  const FilterBottomSheet({
    super.key,
    required this.mapController,
    this.onFilterApplied,
    this.initialMode,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late FilterMode _mode;
  late double _radius;
  final TextEditingController _addressController = TextEditingController();
  bool _isGeocoding = false;
  bool _isSearching = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  LatLng? _selectedCenter;
  String? _selectedAddress;

  /// Gemeinsamer Geocoding-Dienst (begrenzt alle Anfragen).
  late final NominatimService _nominatim;

  @override
  void initState() {
    super.initState();
    _nominatim = context.read<NominatimService>();
    // Lade aktuelle Filter-Einstellungen
    final currentFilter = context.read<ParkingSpotsModel>().currentFilter;
    if (currentFilter != null) {
      _mode = currentFilter.mode;
      _radius = currentFilter.radiusMeters;
      _addressController.text = currentFilter.address ?? '';
    } else {
      // Nutze initialMode wenn vorhanden, sonst Default
      _mode = widget.initialMode ?? FilterMode.currentLocation;
      _radius = 500; // Default 500m
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// Adressfeld wurde geaendert.
  ///
  /// Bewusst ohne Suche: Auto-complete ueber die Nominatim-API ist laut
  /// Nutzungsvorgaben nicht erlaubt. Es wird nur gesucht, wenn die Suche
  /// explizit ausgeloest wird (Button oder Enter).
  void _onAddressChanged(String value) {
    setState(() {
      // Angezeigte Vorschlaege gehoeren zur vorherigen Suche.
      _suggestions = [];
      _showSuggestions = false;
      _errorMessage = null;
      // Auswahl ist nicht mehr gueltig, wenn der Text geaendert wird.
      _selectedCenter = null;
      _selectedAddress = null;
    });
  }

  /// Explizite Suche (Button oder Eingabetaste).
  void _submitSearch() {
    final query = _addressController.text.trim();
    if (query.length < 3) {
      setState(() => _errorMessage = 'Bitte mindestens 3 Zeichen eingeben');
      return;
    }
    _searchAddressSuggestions(query);
  }

  Future<void> _searchAddressSuggestions(String query) async {
    setState(() => _isSearching = true);

    try {
      // Suche in ganz Deutschland, nicht nur in aktueller Stadt
      final results = await _nominatim.searchAddresses(
        query,
        limit: 10,
        cityName: 'Deutschland',
      );

      if (mounted) {
        setState(() {
          _suggestions = results;
          _showSuggestions = results.isNotEmpty;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _showSuggestions = false;
        });
      }
    }
  }

  String? _detectCityIdFromAddress(Map<String, dynamic> suggestion) {
    final address = suggestion['address'] as Map<String, dynamic>?;
    if (address == null) return null;

    // Verschiedene Städte erkennen
    final city =
        address['city'] as String? ??
        address['town'] as String? ??
        address['village'] as String? ??
        address['municipality'] as String?;

    if (city == null) return null;

    final cityLower = city.toLowerCase();
    if (cityLower.contains('berlin')) return 'berlin';
    if (cityLower.contains('münchen') || cityLower.contains('munich'))
      return 'muenchen';
    if (cityLower.contains('dresden')) return 'dresden';

    return null;
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    // Erkenne Stadt aus der Adresse
    final detectedCityId = _detectCityIdFromAddress(suggestion);
    final currentCityId = context.read<CityModel>().currentCityId;

    // Prüfe ob Stadt implementiert ist
    if (detectedCityId == null) {
      // Stadt nicht in Berlin/München/Dresden - zeige Fehlermeldung
      setState(() {
        _showSuggestions = false;
        _errorMessage =
            'Diese Stadt ist noch nicht verfügbar. Verfügbare Städte: Berlin, München, Dresden.';
      });
      return;
    }

    // Stadt erkannt - prüfe ob implementiert
    final targetCity = CityConfig.findById(detectedCityId);
    if (targetCity == null) {
      setState(() {
        _showSuggestions = false;
        _errorMessage =
            'Diese Stadt ist noch nicht verfügbar. Verfügbare Städte: Berlin, München, Dresden.';
      });
      return;
    }

    // Wechsle Stadt wenn nötig
    if (detectedCityId != currentCityId) {
      final targetCity = CityConfig.findById(detectedCityId);
      if (targetCity != null) {
        final cityModel = context.read<CityModel>();
        await cityModel.switchCity(targetCity);
        // Parkplätze für neue Stadt laden
        final spotsModel = context.read<ParkingSpotsModel>();
        spotsModel.setService(cityModel.service);
        spotsModel.loadSpots();
      }
    }

    final cityName = context.read<CityModel>().currentCity.name;

    // Adresse normalisieren
    final normalizedAddress = _normalizeAddress(suggestion, cityName);
    _addressController.text = normalizedAddress;

    setState(() {
      _showSuggestions = false;
      _isGeocoding = true;
    });

    // Koordinaten aus dem Suchergebnis uebernehmen – damit ist keine
    // zweite Anfrage noetig (Nutzungsvorgabe: Anfragen gering halten).
    final lat = double.tryParse(suggestion['lat']?.toString() ?? '');
    final lon = double.tryParse(suggestion['lon']?.toString() ?? '');
    LatLng? center = (lat != null && lon != null) ? LatLng(lat, lon) : null;

    try {
      // Nur falls das Ergebnis keine Koordinaten enthaelt, wird geocodiert.
      center ??= await _nominatim.geocodeAddress(
        normalizedAddress,
        cityName: '$cityName, Deutschland',
      );

      if (center != null && mounted) {
        _selectedCenter = center;
        _selectedAddress = normalizedAddress;
        // Kamera zur Adresse fliegen lassen
        await _animateToLocation(center);
      }
    } catch (e) {
      // Fehler ignorieren
    } finally {
      if (mounted) {
        setState(() => _isGeocoding = false);
      }
    }
  }

  String _normalizeAddress(Map<String, dynamic> suggestion, String cityName) {
    final address = suggestion['address'] as Map<String, dynamic>?;

    if (address == null) {
      // Fallback: display_name verwenden
      final displayName = suggestion['display_name'] as String? ?? '';
      final parts = displayName.split(',');
      if (parts.length >= 2) {
        return '${parts[0].trim()}, ${parts[1].trim()}';
      }
      return displayName;
    }

    // Komponenten extrahieren
    final road =
        address['road'] as String? ??
        address['pedestrian'] as String? ??
        address['square'] as String? ??
        address['place'] as String? ??
        '';
    final houseNumber = address['house_number'] as String? ?? '';
    final postcode = address['postcode'] as String? ?? '';
    final city =
        address['city'] as String? ??
        address['town'] as String? ??
        address['village'] as String? ??
        address['suburb'] as String? ??
        cityName;

    // Format: "Straße Hausnummer, PLZ Ort"
    final streetPart = houseNumber.isNotEmpty ? '$road $houseNumber' : road;

    if (postcode.isNotEmpty) {
      return '$streetPart, $postcode $city';
    }

    return '$streetPart, $city';
  }

  Future<void> _animateToLocation(LatLng target) async {
    // Animation mit mehreren Schritten für "schönen Flug"
    final startZoom = widget.mapController.camera.zoom;
    final targetZoom = 16.0;

    // Step 1: Zoom out leicht
    widget.mapController.move(target, startZoom > 12 ? 12 : startZoom);

    // Kurze Pause
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 2: Move to target with zoom
    widget.mapController.move(target, targetZoom);
  }

  Future<void> _applyFilter() async {
    // Alte Snackbar schließen bevor neue Filterung startet
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    LatLng? center;
    String? address;

    if (_mode == FilterMode.currentLocation) {
      final locationModel = context.read<LocationModel>();

      // Automatisch Standort ermitteln wenn nicht verfügbar
      if (locationModel.currentLocation == null) {
        await locationModel.getCurrentLocation();
      }

      center = locationModel.currentLocation ?? const LatLng(52.52, 13.405);

      if (locationModel.currentLocation == null && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Standort nicht verfügbar, verwende Berlin Mitte'),
            duration: Duration(seconds: 8),
          ),
        );
      }
    } else {
      if (_addressController.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Bitte Adresse eingeben');
        return;
      }

      setState(() {
        _isGeocoding = true;
        _errorMessage = null;
      });

      try {
        final cityName = context.read<CityModel>().currentCity.name;
        // Bereits ausgewaehlte Adresse nicht erneut geocodieren.
        if (_selectedCenter != null &&
            _addressController.text.trim() == _selectedAddress) {
          center = _selectedCenter;
        } else {
          center = await _nominatim.geocodeAddress(
            _addressController.text.trim(),
            cityName: '$cityName, Deutschland',
          );
        }

        if (center == null) {
          setState(() => _errorMessage = 'Adresse nicht gefunden');
          return;
        }
        address = _addressController.text.trim();
      } catch (e) {
        setState(() => _errorMessage = 'Fehler: $e');
        return;
      } finally {
        setState(() => _isGeocoding = false);
      }
    }

    final filter = FilterCriteria(
      mode: _mode,
      radiusMeters: _radius,
      center: center,
      address: address,
    );

    context.read<ParkingSpotsModel>().applyFilter(filter);

    // Callback für Zoom auf Radius
    widget.onFilterApplied!(center, _radius);

    Navigator.pop(context);
  }

  void _clearFilter() {
    context.read<ParkingSpotsModel>().clearFilter();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final spotsModel = context.watch<ParkingSpotsModel>();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Titel
              Text(
                'Parkplätze filtern',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              // Modus-Auswahl
              SegmentedButton<FilterMode>(
                segments: const [
                  ButtonSegment(
                    value: FilterMode.currentLocation,
                    label: Text('Meine Position'),
                    icon: Icon(Icons.my_location),
                  ),
                  ButtonSegment(
                    value: FilterMode.targetAddress,
                    label: Text('Adresse'),
                    icon: Icon(Icons.location_on),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) {
                  setState(() {
                    _mode = value.first;
                    if (_mode == FilterMode.currentLocation) {
                      _showSuggestions = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 24),
              // Adress-Eingabe (nur bei targetAddress)
              if (_mode == FilterMode.targetAddress) ...[
                TextField(
                  controller: _addressController,
                  onChanged: _onAddressChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSearch(),
                  decoration: InputDecoration(
                    labelText: 'Zieladresse',
                    hintText: 'z.B. Alexanderplatz 1',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSearching || _isGeocoding)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (_addressController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.search),
                            tooltip: 'Adresse suchen',
                            onPressed: _submitSearch,
                          ),
                        if (_addressController.text.isNotEmpty &&
                            !_isSearching &&
                            !_isGeocoding)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Eingabe löschen',
                            onPressed: () {
                              _addressController.clear();
                              setState(() {
                                _suggestions = [];
                                _showSuggestions = false;
                                _selectedCenter = null;
                                _selectedAddress = null;
                              });
                            },
                          ),
                      ],
                    ),
                    errorText: _errorMessage,
                  ),
                ),
                // Vorschläge-Liste
                if (_showSuggestions && _suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        final address =
                            suggestion['address'] as Map<String, dynamic>?;

                        // Fallback: display_name
                        final displayName =
                            suggestion['display_name'] as String? ?? '';

                        // Straße und Hausnummer
                        final road =
                            address?['road'] as String? ??
                            address?['pedestrian'] as String? ??
                            address?['square'] as String? ??
                            address?['place'] as String? ??
                            '';
                        final houseNumber =
                            address?['house_number'] as String? ?? '';
                        final streetPart = houseNumber.isNotEmpty
                            ? '$road $houseNumber'
                            : road;

                        // Venue/POI Name extrahieren (z.B. "Kaufland", "Alexanderplatz")
                        final poiName =
                            suggestion['name'] as String? ??
                            address?['name'] as String? ??
                            (address?['shop'] != null ||
                                    address?['amenity'] != null
                                ? displayName.split(',').first.trim()
                                : '');

                        // PLZ und Ort
                        final postcode = address?['postcode'] as String? ?? '';
                        final city =
                            address?['city'] as String? ??
                            address?['town'] as String? ??
                            address?['suburb'] as String? ??
                            'Berlin';

                        // Bezirk für zusätzliche Info
                        final suburb =
                            address?['suburb'] as String? ??
                            address?['neighbourhood'] as String? ??
                            '';

                        // Fallback wenn keine address-Daten
                        final parts = displayName.split(',');
                        final fallbackStreet = parts.isNotEmpty
                            ? parts[0].trim()
                            : '';
                        final fallbackLocation = parts.length > 1
                            ? parts[1].trim()
                            : '';

                        // Titel: Wenn POI-Name vorhanden, zeige "Venue, Adresse", sonst nur Adresse
                        String title;
                        if (poiName.isNotEmpty && streetPart.isNotEmpty) {
                          title = '$poiName, $streetPart';
                        } else if (poiName.isNotEmpty) {
                          title = poiName;
                        } else {
                          title = streetPart.isNotEmpty
                              ? streetPart
                              : fallbackStreet;
                        }

                        final subtitleParts = <String>[];
                        if (postcode.isNotEmpty && city.isNotEmpty) {
                          subtitleParts.add('$postcode $city');
                        } else if (fallbackLocation.isNotEmpty) {
                          subtitleParts.add(fallbackLocation);
                        }
                        if (suburb.isNotEmpty) {
                          subtitleParts.add(suburb);
                        }
                        final subtitle = subtitleParts.join(', ');

                        return ListTile(
                          dense: true,
                          title: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: subtitle.isNotEmpty
                              ? Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                )
                              : null,
                          onTap: () => _selectSuggestion(suggestion),
                        );
                      },
                    ),
                  ),
                // Quellenangabe für die Adresssuche: sichtbar und verlinkt
                // (Nutzungsvorgabe von Nominatim/OSM)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        'Suche & Geocoding: ',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      _AttributionLink(
                        text: 'Nominatim',
                        url: 'https://nominatim.org',
                      ),
                      Text(
                        '/',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      _AttributionLink(
                        text: '© OpenStreetMap-Mitwirkende',
                        url: 'https://www.openstreetmap.org/copyright',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Radius Slider
              Text(
                'Umkreis: ${FilterCriteria(radiusMeters: _radius, mode: _mode).radiusLabel}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _radius,
                min: 50,
                max: 5000,
                divisions: 6,
                label: FilterCriteria(
                  radiusMeters: _radius,
                  mode: _mode,
                ).radiusLabel,
                onChanged: (value) => setState(() => _radius = value),
              ),
              // Radius Optionen als Chips
              Wrap(
                spacing: 8,
                children: FilterCriteria.radiusOptions.map((radius) {
                  return ChoiceChip(
                    label: Text(
                      FilterCriteria(
                        radiusMeters: radius,
                        mode: _mode,
                      ).radiusLabel,
                    ),
                    selected: _radius == radius,
                    onSelected: (_) => setState(() => _radius = radius),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              // Ergebnis-Info
              if (spotsModel.isFiltered)
                Text(
                  'Aktuell: ${spotsModel.spots.length} von ${spotsModel.allSpots.length} Parkplätzen',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              const SizedBox(height: 16),
              // Buttons
              Row(
                children: [
                  if (spotsModel.isFiltered)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clearFilter,
                        child: const Text('Zurücksetzen'),
                      ),
                    ),
                  if (spotsModel.isFiltered) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed:
                          (_isGeocoding ||
                              spotsModel.isLoading ||
                              _errorMessage != null)
                          ? null
                          : _applyFilter,
                      child: _isGeocoding || spotsModel.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Filter anwenden'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
