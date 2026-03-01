import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/disabled_parking_spot.dart';
import 'services/berlin_parking_service.dart';
import 'services/location_service.dart';

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
  bool _isLoading = false;
  String? _error;

  List<DisabledParkingSpot> get spots => _spots;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSpots() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _spots = await _service.fetchAllSpots();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle für Mobile
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
                // Header
                Row(
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
                          Text(
                            spot.location,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Details
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
                if (spot.postalCode != null)
                  _DetailCard(
                    icon: Icons.markunread_mailbox,
                    title: 'PLZ',
                    value: spot.postalCode!,
                  ),
                if (spot.lastUpdated != null)
                  _DetailCard(
                    icon: Icons.update,
                    title: 'Letzte Aktualisierung',
                    value:
                        '${spot.lastUpdated!.day}.${spot.lastUpdated!.month}.${spot.lastUpdated!.year}',
                  ),
                const SizedBox(height: 24),
                // Navigation Button
                SizedBox(
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
              ],
            ),
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
