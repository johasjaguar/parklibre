import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'models/disabled_parking_spot.dart';
import 'services/berlin_parking_service.dart';

void main() {
  runApp(const ParkLibreApp());
}

class ParkLibreApp extends StatelessWidget {
  const ParkLibreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ParkingSpotsModel(),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ParkingSpotsModel>().loadSpots();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ParkLibre - Behindertenparkplätze Berlin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<ParkingSpotsModel>(
        builder: (context, model, child) {
          if (model.isLoading && model.spots.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (model.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Fehler: ${model.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: model.loadSpots,
                    child: const Text('Erneut laden'),
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: _berlinCenter,
                  initialZoom: _initialZoom,
                  interactionOptions: const InteractionOptions(
                    rotationThreshold: 100.0,
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
                    markers: model.spots
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
                ],
              ),
              Positioned(
                bottom: 16,
                left: 16,
                child: Chip(
                  label: Text('${model.spots.length} Parkplätze'),
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.read<ParkingSpotsModel>().loadSpots(),
        child: const Icon(Icons.refresh),
      ),
    );
  }

  void _showSpotDetails(BuildContext context, DisabledParkingSpot spot) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.accessible, color: Colors.blue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    spot.location,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.location_on, text: spot.district),
            if (spot.neighborhood != null)
              _InfoRow(icon: Icons.location_city, text: spot.neighborhood!),
            _InfoRow(
              icon: Icons.local_parking,
              text: '${spot.count} Stellplatz${spot.count > 1 ? 'e' : ''}',
            ),
            if (spot.remark != null && spot.remark!.isNotEmpty)
              _InfoRow(icon: Icons.schedule, text: spot.remark!),
            if (spot.postalCode != null)
              _InfoRow(icon: Icons.markunread_mailbox, text: spot.postalCode!),
            if (spot.lastUpdated != null)
              _InfoRow(
                icon: Icons.update,
                text:
                    'Aktualisiert: ${spot.lastUpdated!.toLocal().toString().split(' ')[0]}',
              ),
          ],
        ),
      ),
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
