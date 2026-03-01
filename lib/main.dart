import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide DistanceCalculator;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/disabled_parking_spot.dart';
import 'models/filter_criteria.dart';
import 'services/berlin_parking_service.dart';
import 'services/location_service.dart';
import 'services/nominatim_service.dart';
import 'utils/distance_calculator.dart';

void main() {
  runApp(const ParkLibreApp());
}

class ParkLibreApp extends StatelessWidget {
  const ParkLibreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ParkingSpotsModel()),
        ChangeNotifierProvider(create: (_) => LocationModel()),
      ],
      child: MaterialApp(
        title: 'ParkLibre',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MapScreen(),
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
  final BerlinParkingService _service = BerlinParkingService();
  List<DisabledParkingSpot> _spots = [];
  List<DisabledParkingSpot> _filteredSpots = [];
  bool _isLoading = false;
  String? _error;
  FilterCriteria? _currentFilter;

  List<DisabledParkingSpot> get spots =>
      _filteredSpots.isEmpty ? _spots : _filteredSpots;
  List<DisabledParkingSpot> get allSpots => _spots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isFiltered => _filteredSpots.isNotEmpty;
  FilterCriteria? get currentFilter => _currentFilter;

  Future<void> loadSpots() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _spots = await _service.fetchAllSpots();
      _filteredSpots = [];
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
    _filteredSpots = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _berlinCenter = LatLng(52.52, 13.405);
  static const _initialZoom = 12.0;
  static const _locateZoom = 14.5;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ParkingSpotsModel>().loadSpots();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _resetToNorth() {
    _mapController.rotate(0);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(locationModel.error ?? 'Standort nicht verfügbar'),
          action: SnackBarAction(
            label: 'Berlin Mitte',
            onPressed: () => _animateToLocation(_berlinCenter),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ParkLibre - Behindertenparkplätze Berlin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer2<ParkingSpotsModel, LocationModel>(
        builder: (context, spotsModel, locationModel, child) {
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
                  initialCenter: _berlinCenter,
                  initialZoom: _initialZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'de.parklibre',
                    maxZoom: 19,
                  ),
                  MarkerLayer(
                    markers: spotsModel.spots
                        .map(
                          (spot) => Marker(
                            point: spot.position,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _showSpotDetails(context, spot),
                              child: const Icon(
                                Icons.accessible,
                                color: Colors.blue,
                                size: 32,
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
                    CircleLayer(
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
                ],
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'compass',
                      onPressed: _resetToNorth,
                      child: const Icon(Icons.compass_calibration),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                child: Chip(
                  label: Text('${spotsModel.spots.length} Parkplätze'),
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              if (locationModel.isLoading)
                const Positioned(
                  bottom: 80,
                  right: 16,
                  child: CircularProgressIndicator(),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Filter-Button
          Consumer<ParkingSpotsModel>(
            builder: (context, model, _) {
              return FloatingActionButton(
                heroTag: 'filter',
                onPressed: () => _showFilterSheet(context),
                backgroundColor: model.isFiltered ? Colors.orange : null,
                child: Icon(
                  model.isFiltered ? Icons.filter_list_off : Icons.filter_list,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'locate',
            onPressed: _locateMe,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'refresh',
            onPressed: () => context.read<ParkingSpotsModel>().loadSpots(),
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  void _showSpotDetails(BuildContext context, DisabledParkingSpot spot) {
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
                                    '${spot.postalCode} Berlin',
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

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const FilterBottomSheet(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
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

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  FilterMode _mode = FilterMode.currentLocation;
  double _radius = 1000; // Default 1km
  final TextEditingController _addressController = TextEditingController();
  bool _isGeocoding = false;
  bool _persistFilter = false;
  String? _errorMessage;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _applyFilter() async {
    LatLng? center;
    String? address;

    if (_mode == FilterMode.currentLocation) {
      final locationModel = context.read<LocationModel>();
      center = locationModel.currentLocation ?? const LatLng(52.52, 13.405);
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
        final service = NominatimService();
        center = await service.geocodeAddress(_addressController.text.trim());
        service.dispose();

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
      persistFilter: _persistFilter,
    );

    context.read<ParkingSpotsModel>().applyFilter(filter);
    Navigator.pop(context);
  }

  void _clearFilter() {
    context.read<ParkingSpotsModel>().clearFilter();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final spotsModel = context.watch<ParkingSpotsModel>();
    final locationModel = context.watch<LocationModel>();

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
                  setState(() => _mode = value.first);
                },
              ),
              const SizedBox(height: 24),
              // Adress-Eingabe (nur bei targetAddress)
              if (_mode == FilterMode.targetAddress) ...[
                TextField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'Zieladresse',
                    hintText: 'z.B. Alexanderplatz 1',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isGeocoding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    errorText: _errorMessage,
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
              const SizedBox(height: 16),
              // Persistenz-Checkbox
              CheckboxListTile(
                title: const Text('Filter merken'),
                subtitle: const Text('Beim nächsten Start wieder anwenden'),
                value: _persistFilter,
                onChanged: (value) =>
                    setState(() => _persistFilter = value ?? false),
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
                      onPressed: _isGeocoding ? null : _applyFilter,
                      child: _isGeocoding
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
