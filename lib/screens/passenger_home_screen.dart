import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../models/bus.dart';
import '../models/bus_stop.dart';
import '../models/live_location.dart';
import '../services/stop_service.dart';
import '../services/bus_service.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../services/request_service.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  final StopService _stopService = StopService();
  final BusService _busService = BusService();
  final LocationService _locService = LocationService();
  final AuthService _authService = AuthService();
  final RequestService _reqService = RequestService();

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  List<Marker> _markers = [];
  List<BusModel> _allBuses = [];
  List<BusModel> _filteredBuses = [];
  List<BusStopModel> _busStops = [];
  List<BusStopModel> _searchSuggestions = [];
  Map<String, LiveLocationModel?> _liveCache = {};
  Map<String, List<LatLng>> _allBusRoutes = {}; // All bus routes
  List<LatLng> _selectedBusRoute = [];

  BusStopModel? _selectedStop;
  BusModel? _selectedBus;

  Position? _userPosition;
  bool _isLoading = true;
  bool _mapReady = false;
  bool _showAllBuses = true;
  bool _isLoadingRoute = false;
  String _searchQuery = '';

  OverlayEntry? _overlayEntry;

  // Theme colors
  static const Color primaryNavy = Color(0xFF001F3F);
  static const Color secondaryNavy = Color(0xFF003366);
  static const Color accentBlue = Color(0xFF0066CC);
  static const Color successGreen = Color(0xFF00C853);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color dangerRed = Color(0xFFE53935);
  static const Color textWhite = Colors.white;
  static const Color cardBg = Color(0xFF002147);

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
    _initialize();
  }

  void _onFocusChange() {
    if (!_searchFocusNode.hasFocus && _searchSuggestions.isEmpty) {
      _hideSuggestions();
    }
  }

  Future<void> _initialize() async {
    await _checkLocationPermission();
    await _fetchUserLocation();

    // Listen to all ACTIVE buses only (status = 'active')
    _busService.getActiveBusesStream().listen(_onBusesUpdated);

    // Listen to bus stops
    _stopService.getAllStops().listen((List<BusStopModel> stops) {
      if (mounted) {
        setState(() => _busStops = stops);
        _updateMarkers();
      }
    });
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        _showSnackBar('Location services are disabled', warningOrange);
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          _showSnackBar('Location permissions are denied', dangerRed);
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showSnackBar('Location permissions are permanently denied', dangerRed);
      }
    }
  }

  Future<void> _fetchUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        _userPosition = position;
        _isLoading = false;
      });

      _updateMarkers();

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _mapReady = true;
          _moveCameraToUser();
        }
      });
    } catch (e) {
      debugPrint('Location Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Failed to get location', dangerRed);
      }
    }
  }

  void _moveCameraToUser() {
    if (_userPosition == null || !_mapReady) return;

    try {
      _mapController.move(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        15.0,
      );
    } catch (e) {
      debugPrint('Error moving camera: $e');
    }
  }

  Future<void> _fetchBusRoute(BusModel bus) async {
    if (bus.route.isEmpty || _selectedStop == null) {
      setState(() => _selectedBusRoute = []);
      return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      List<LatLng> waypoints = [];

      // Get selected stop index
      final selectedStopIndex = bus.route.indexOf(_selectedStop!.id);
      if (selectedStopIndex == -1) {
        setState(() {
          _selectedBusRoute = [];
          _isLoadingRoute = false;
        });
        return;
      }

      // Get stops from selected stop to last stop
      final relevantStopIds = bus.route.sublist(selectedStopIndex);

      // Build waypoints from selected stop to end
      for (String stopId in relevantStopIds) {
        final stop = _busStops.firstWhere(
          (s) => s.id == stopId,
          orElse:
              () => BusStopModel(
                id: stopId,
                name: '',
                location: {},
                description: '',
                busesServing: [],
                sequenceInRoutes: {},
                createdAt: DateTime.now(),
              ),
        );

        if (stop.location.isNotEmpty) {
          waypoints.add(LatLng(stop.location['lat']!, stop.location['lng']!));
        }
      }

      if (waypoints.length < 2) {
        setState(() {
          _selectedBusRoute = [];
          _isLoadingRoute = false;
        });
        return;
      }

      final coordinates = waypoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');

      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;

          final roadPoints =
              geometry.map<LatLng>((coord) {
                return LatLng(coord[1].toDouble(), coord[0].toDouble());
              }).toList();

          if (mounted) {
            setState(() {
              _selectedBusRoute = roadPoints;
              _isLoadingRoute = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching bus route: $e");
      if (mounted) {
        setState(() {
          _selectedBusRoute = [];
          _isLoadingRoute = false;
        });
      }
    }
  }

  void _updateMarkers() {
    final List<Marker> markerList = [];

    // Add user location marker
    if (_userPosition != null) {
      markerList.add(
        Marker(
          point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
          width: 60,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              color: accentBlue.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: accentBlue, width: 3),
            ),
            child: const Icon(Icons.my_location, color: accentBlue, size: 32),
          ),
        ),
      );
    }

    // Add bus markers (only for active/tracking buses)
    for (final bus in _filteredBuses) {
      final live = _liveCache[bus.id];
      if (live != null) {
        final isSelected = _selectedBus?.id == bus.id;
        markerList.add(
          Marker(
            point: LatLng(live.lat, live.lng),
            width: 70,
            height: 90,
            child: GestureDetector(
              onTap: () => _selectBus(bus),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isSelected ? successGreen : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? successGreen : dangerRed,
                        width: isSelected ? 4 : 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.directions_bus,
                      color: isSelected ? textWhite : dangerRed,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: textWhite,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      bus.name.length > 12
                          ? '${bus.name.substring(0, 12)}...'
                          : bus.name,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: primaryNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Add stop markers with route numbers
    for (final stop in _busStops) {
      final isSelected = _selectedStop?.id == stop.id;

      // Find which buses serve this stop and their sequence numbers
      List<String> busSequences = [];
      for (final bus in _filteredBuses) {
        final stopIndex = bus.route.indexOf(stop.id);
        if (stopIndex != -1) {
          busSequences.add('${stopIndex + 1}');
        }
      }

      markerList.add(
        Marker(
          point: LatLng(stop.location['lat']!, stop.location['lng']!),
          width: 80,
          height: 100,
          child: GestureDetector(
            onTap: () => _selectStopFromMap(stop),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? successGreen : warningOrange,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: textWhite,
                          width: isSelected ? 3 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: textWhite,
                        size: 24,
                      ),
                    ),
                    // Show route numbers badge
                    if (busSequences.isNotEmpty && _selectedStop != null)
                      Positioned(
                        top: -8,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: accentBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: textWhite, width: 2),
                          ),
                          child: Text(
                            busSequences.join(','),
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: textWhite,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (isSelected || busSequences.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: textWhite,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      stop.name.length > 12
                          ? '${stop.name.substring(0, 12)}...'
                          : stop.name,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: primaryNavy,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (mounted) {
      setState(() => _markers = markerList);
    }
  }

  void _onBusesUpdated(List<BusModel> buses) async {
    // Update live cache for all active buses
    for (final bus in buses) {
      if (_liveCache[bus.id] == null) {
        final live = await _busService.getLiveLocation(bus.id);
        _liveCache[bus.id] = live;
      }
    }

    if (!mounted) return;

    setState(() {
      _allBuses = buses;
      _filterBuses();
    });

    // Fetch routes for all filtered buses
    await _fetchAllBusRoutes();
    _updateMarkers();
  }

  void _filterBuses() {
    if (_showAllBuses) {
      _filteredBuses = _allBuses;
    } else if (_selectedStop != null) {
      // Filter buses that serve the selected stop
      _filteredBuses =
          _allBuses.where((bus) {
            return bus.route.contains(_selectedStop!.id);
          }).toList();
    } else {
      _filteredBuses = [];
    }
  }

  // Fetch routes for all filtered buses (when stop is selected)
  Future<void> _fetchAllBusRoutes() async {
    if (_filteredBuses.isEmpty) {
      setState(() => _allBusRoutes = {});
      return;
    }

    for (final bus in _filteredBuses) {
      if (bus.route.length >= 2) {
        await _fetchBusRouteForMap(bus);
      }
    }
  }

  // Fetch route for display on map (full route)
  Future<void> _fetchBusRouteForMap(BusModel bus) async {
    if (bus.route.isEmpty) return;

    try {
      List<LatLng> waypoints = [];

      // Get live bus location if available
      final live = _liveCache[bus.id];
      if (live != null) {
        waypoints.add(LatLng(live.lat, live.lng));
      }

      // Add all route stops in order
      for (String stopId in bus.route) {
        final stop = _busStops.firstWhere(
          (s) => s.id == stopId,
          orElse:
              () => BusStopModel(
                id: stopId,
                name: '',
                location: {},
                description: '',
                busesServing: [],
                sequenceInRoutes: {},
                createdAt: DateTime.now(),
              ),
        );

        if (stop.location.isNotEmpty) {
          waypoints.add(LatLng(stop.location['lat']!, stop.location['lng']!));
        }
      }

      if (waypoints.length < 2) return;

      final coordinates = waypoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');

      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;

          final roadPoints =
              geometry.map<LatLng>((coord) {
                return LatLng(coord[1].toDouble(), coord[0].toDouble());
              }).toList();

          if (mounted) {
            setState(() {
              _allBusRoutes[bus.id] = roadPoints;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching route for bus ${bus.id}: $e");
    }
  }

  void _selectStopFromMap(BusStopModel stop) {
    _searchController.text = stop.name;
    _hideSuggestions();

    setState(() {
      _selectedStop = stop;
      _selectedBus = null;
      _showAllBuses = false;
      _selectedBusRoute = [];
      _filterBuses();
    });

    // Fetch routes for all buses serving this stop
    _fetchAllBusRoutes();

    _mapController.move(
      LatLng(stop.location['lat']!, stop.location['lng']!),
      16.0,
    );

    _updateMarkers();
    _showStopDetailsDialog(stop);
  }

  void _selectBus(BusModel bus) async {
    setState(() => _selectedBus = bus);
    await _fetchBusRoute(bus);
    _updateMarkers();
    _showBusDetailsDialog(bus);
  }

  void _searchStop(String query) {
    setState(() => _searchQuery = query);

    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
      });
      _hideSuggestions();
      return;
    }

    // Filter matching stops
    final matchingStops =
        _busStops
            .where(
              (stop) => stop.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();

    setState(() {
      _searchSuggestions = matchingStops;
    });

    if (_searchSuggestions.isNotEmpty) {
      _showSuggestionsOverlay();
    } else {
      _hideSuggestions();
    }
  }

  void _showSuggestionsOverlay() {
    _hideSuggestions();

    _overlayEntry = OverlayEntry(
      builder:
          (context) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {},
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 76,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    color: cardBg,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentBlue.withOpacity(0.3)),
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _searchSuggestions.length,
                        separatorBuilder:
                            (context, index) => Divider(
                              height: 1,
                              color: Colors.white.withOpacity(0.1),
                            ),
                        itemBuilder: (context, index) {
                          final stop = _searchSuggestions[index];
                          return InkWell(
                            onTap: () => _selectStopFromSuggestion(stop),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: warningOrange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: warningOrange,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stop.name,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: textWhite,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          stop.description.isNotEmpty
                                              ? stop.description
                                              : 'Lat: ${stop.location['lat']?.toStringAsFixed(4)}, Lng: ${stop.location['lng']?.toStringAsFixed(4)}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.white54,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideSuggestions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectStopFromSuggestion(BusStopModel stop) {
    _searchController.text = stop.name;
    _searchFocusNode.unfocus();
    _hideSuggestions();

    setState(() {
      _selectedStop = stop;
      _selectedBus = null;
      _showAllBuses = false;
      _searchSuggestions = [];
      _selectedBusRoute = [];
      _filterBuses();
    });

    _mapController.move(
      LatLng(stop.location['lat']!, stop.location['lng']!),
      16.0,
    );

    _updateMarkers();
    _showStopDetailsDialog(stop);
  }

  void _showStopDetailsDialog(BusStopModel stop) {
    // Get buses serving this stop
    final servingBuses =
        _allBuses.where((bus) => bus.route.contains(stop.id)).toList();

    showDialog(
      context: context,
      builder:
          (context) => Theme(
            data: ThemeData.dark().copyWith(
              dialogBackgroundColor: cardBg,
              textTheme: GoogleFonts.poppinsTextTheme(
                ThemeData.dark().textTheme,
              ),
            ),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: warningOrange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: warningOrange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.name,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: textWhite,
                          ),
                        ),
                        if (stop.description.isNotEmpty)
                          Text(
                            stop.description,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentBlue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.place, size: 16, color: accentBlue),
                              const SizedBox(width: 6),
                              Text(
                                'Exact Location',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textWhite,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Latitude: ${stop.location['lat']?.toStringAsFixed(6) ?? 'N/A'}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Longitude: ${stop.location['lng']?.toStringAsFixed(6) ?? 'N/A'}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.directions_bus, size: 18, color: dangerRed),
                        const SizedBox(width: 8),
                        Text(
                          'Buses Serving This Stop (${servingBuses.length})',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: textWhite,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (servingBuses.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Icon(
                                Icons.directions_bus_outlined,
                                size: 48,
                                color: Colors.white30,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No buses serve this stop currently',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.white60,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...servingBuses.map((bus) {
                        final live = _liveCache[bus.id];
                        double? distance;

                        if (_userPosition != null && live != null) {
                          distance = _locService.calculateDistance(
                            _userPosition!.latitude,
                            _userPosition!.longitude,
                            live.lat,
                            live.lng,
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: dangerRed.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.directions_bus,
                                  color: dangerRed,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bus.name,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textWhite,
                                      ),
                                    ),
                                    Text(
                                      bus.number,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    if (distance != null)
                                      Text(
                                        '${distance.toStringAsFixed(0)} m away',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: successGreen,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline, size: 20),
                                color: accentBlue,
                                onPressed: () {
                                  Navigator.pop(context);
                                  _selectBus(bus);
                                },
                                tooltip: 'View Bus Details',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showBusDetailsDialog(BusModel bus) {
    final live = _liveCache[bus.id];
    double? distance;

    if (_userPosition != null && live != null) {
      distance = _locService.calculateDistance(
        _userPosition!.latitude,
        _userPosition!.longitude,
        live.lat,
        live.lng,
      );
    }

    // Get destination stop (last stop in route)
    final destinationStopId = bus.route.isNotEmpty ? bus.route.last : null;
    final destinationStop =
        destinationStopId != null
            ? _busStops.firstWhere(
              (s) => s.id == destinationStopId,
              orElse:
                  () => BusStopModel(
                    id: destinationStopId,
                    name: 'Unknown',
                    location: {},
                    description: '',
                    busesServing: [],
                    sequenceInRoutes: {},
                    createdAt: DateTime.now(),
                  ),
            )
            : null;

    showDialog(
      context: context,
      builder:
          (context) => Theme(
            data: ThemeData.dark().copyWith(
              dialogBackgroundColor: cardBg,
              textTheme: GoogleFonts.poppinsTextTheme(
                ThemeData.dark().textTheme,
              ),
            ),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dangerRed.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.directions_bus,
                      color: dangerRed,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bus.name,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: textWhite,
                          ),
                        ),
                        Text(
                          bus.number,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      Icons.airline_seat_recline_normal,
                      'Capacity',
                      '${bus.currentPassengers}/${bus.capacity}',
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.access_time,
                      'ETA to Next Stop',
                      '${bus.etaToNextStop.toStringAsFixed(0)} min',
                    ),
                    if (distance != null) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.near_me,
                        'Distance from You',
                        '${distance.toStringAsFixed(0)} m',
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.info_outline,
                      'Status',
                      bus.status.toUpperCase(),
                    ),
                    if (destinationStop != null) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.flag,
                        'Destination',
                        destinationStop.name,
                      ),
                    ],
                    const Divider(height: 24, color: Colors.white30),
                    Text(
                      'Route Stops (${bus.route.length})',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: textWhite,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...bus.route.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final stopId = entry.value;
                      final stop = _busStops.firstWhere(
                        (s) => s.id == stopId,
                        orElse:
                            () => BusStopModel(
                              id: stopId,
                              name: 'Unknown Stop',
                              location: {},
                              description: '',
                              busesServing: [],
                              sequenceInRoutes: {},
                              createdAt: DateTime.now(),
                            ),
                      );
                      final isSelectedStop = _selectedStop?.id == stopId;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              isSelectedStop
                                  ? successGreen.withOpacity(0.2)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              isSelectedStop
                                  ? Border.all(color: successGreen, width: 2)
                                  : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color:
                                    isSelectedStop
                                        ? successGreen.withOpacity(0.3)
                                        : accentBlue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${idx + 1}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isSelectedStop
                                            ? successGreen
                                            : accentBlue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                stop.name,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color:
                                      isSelectedStop
                                          ? textWhite
                                          : Colors.white70,
                                  fontWeight:
                                      isSelectedStop
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelectedStop)
                              Icon(
                                Icons.check_circle,
                                color: successGreen,
                                size: 18,
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed:
                      _selectedStop == null
                          ? null
                          : () {
                            Navigator.pop(context);
                            _sendPickupRequest(bus);
                          },
                  icon: const Icon(Icons.send),
                  label: Text('Request Pickup', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successGreen,
                    disabledBackgroundColor: Colors.grey,
                    foregroundColor: textWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: accentBlue),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textWhite,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  void _sendPickupRequest(BusModel bus) async {
    if (_selectedStop == null) {
      _showSnackBar('Please select a bus stop first', warningOrange);
      return;
    }

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        _showSnackBar('User not authenticated', dangerRed);
        return;
      }

      await _reqService.sendRequest(
        userId: userId,
        busId: bus.id,
        stopId: _selectedStop!.id,
        userLocation: {
          'lat': _userPosition!.latitude,
          'lng': _userPosition!.longitude,
        },
        notes: 'Passenger request',
      );

      _showSnackBar(
        'Pickup request sent for ${bus.name} at ${_selectedStop!.name}',
        successGreen,
      );
    } catch (e) {
      debugPrint('Error sending request: $e');
      _showSnackBar('Failed to send request', dangerRed);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: textWhite)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearSelection() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _hideSuggestions();

    setState(() {
      _selectedStop = null;
      _selectedBus = null;
      _showAllBuses = true;
      _searchQuery = '';
      _searchSuggestions = [];
      _selectedBusRoute = [];
      _allBusRoutes = {}; // Clear all routes
      _filterBuses();
    });
    _updateMarkers();
    if (_userPosition != null) {
      _moveCameraToUser();
    }
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];

    if (_selectedBus != null && _selectedBusRoute.isNotEmpty) {
      // Show only selected bus route in green
      polylines.add(
        Polyline(
          points: _selectedBusRoute,
          color: successGreen,
          strokeWidth: 6.0,
          pattern: const StrokePattern.solid(),
        ),
      );
    } else if (_selectedStop != null) {
      // Show all bus routes in different colors when stop is selected
      final colors = [
        accentBlue,
        Colors.purple,
        Colors.teal,
        Colors.orange,
        Colors.pink,
        Colors.cyan,
      ];

      int colorIndex = 0;
      for (final entry in _allBusRoutes.entries) {
        if (entry.value.isNotEmpty) {
          polylines.add(
            Polyline(
              points: entry.value,
              color: colors[colorIndex % colors.length],
              strokeWidth: 5.0,
              pattern: const StrokePattern.solid(),
            ),
          );
          colorIndex++;
        }
      }
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: primaryNavy,
          secondary: accentBlue,
          surface: primaryNavy,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        backgroundColor: primaryNavy,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: primaryNavy,
          title: Text(
            'Track My Bus',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textWhite,
            ),
          ),
          actions: [
            if (_selectedStop != null || _selectedBus != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: warningOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.clear, color: warningOrange),
                  onPressed: _clearSelection,
                  tooltip: 'Clear Selection',
                ),
              ),
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.logout_rounded, color: textWhite),
                onPressed: () => _authService.logout(),
                tooltip: 'Logout',
              ),
            ),
          ],
        ),
        body:
            _isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: accentBlue),
                )
                : Column(
                  children: [
                    // Search Bar
                    Container(
                      margin: const EdgeInsets.all(16),
                      child: CompositedTransformTarget(
                        link: _layerLink,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cardBg, secondaryNavy],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onChanged: _searchStop,
                            style: GoogleFonts.poppins(color: textWhite),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.search,
                                color: accentBlue,
                              ),
                              suffixIcon:
                                  _searchController.text.isNotEmpty
                                      ? IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: Colors.white70,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          _searchStop('');
                                          setState(() {
                                            _selectedStop = null;
                                            _showAllBuses = true;
                                            _selectedBusRoute = [];
                                            _filterBuses();
                                          });
                                          _updateMarkers();
                                        },
                                      )
                                      : null,
                              hintText: 'Search bus stop name...',
                              hintStyle: GoogleFonts.poppins(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Info Chips
                    if (_selectedStop != null || _selectedBus != null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            if (_selectedStop != null) ...[
                              Icon(
                                Icons.location_on,
                                color: warningOrange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Stop: ${_selectedStop!.name}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: textWhite,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (_selectedStop != null && _selectedBus != null)
                              const SizedBox(width: 12),
                            if (_selectedBus != null) ...[
                              Icon(
                                Icons.directions_bus,
                                color: dangerRed,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Bus: ${_selectedBus!.name}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: textWhite,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Map
                    Expanded(
                      flex: 2,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter:
                                _userPosition != null
                                    ? LatLng(
                                      _userPosition!.latitude,
                                      _userPosition!.longitude,
                                    )
                                    : const LatLng(16.70, 74.21),
                            initialZoom: 14,
                            minZoom: 5,
                            maxZoom: 18,
                            onMapReady: () {
                              setState(() => _mapReady = true);
                              if (_userPosition != null) {
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  _moveCameraToUser,
                                );
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.track_my_bus',
                            ),
                            PolylineLayer(polylines: _buildPolylines()),
                            MarkerLayer(markers: _markers),
                          ],
                        ),
                      ),
                    ),

                    // Bus List
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cardBg, secondaryNavy],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: dangerRed.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.directions_bus_rounded,
                                      color: dangerRed,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _selectedStop != null
                                          ? 'Buses to ${_selectedStop!.name}'
                                          : 'All Active Buses',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: textWhite,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentBlue,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_filteredBuses.length}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: textWhite,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child:
                                  _filteredBuses.isEmpty
                                      ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.directions_bus_outlined,
                                              size: 64,
                                              color: Colors.white30,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              _selectedStop != null
                                                  ? 'No buses serve this stop'
                                                  : 'No active buses',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      : ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          16,
                                        ),
                                        itemCount: _filteredBuses.length,
                                        itemBuilder: (context, i) {
                                          final bus = _filteredBuses[i];
                                          final live = _liveCache[bus.id];
                                          double? distance;

                                          if (_userPosition != null &&
                                              live != null) {
                                            distance = _locService
                                                .calculateDistance(
                                                  _userPosition!.latitude,
                                                  _userPosition!.longitude,
                                                  live.lat,
                                                  live.lng,
                                                );
                                          }

                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  _selectedBus?.id == bus.id
                                                      ? successGreen
                                                          .withOpacity(0.2)
                                                      : Colors.white
                                                          .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color:
                                                    _selectedBus?.id == bus.id
                                                        ? successGreen
                                                        : Colors.white
                                                            .withOpacity(0.1),
                                                width:
                                                    _selectedBus?.id == bus.id
                                                        ? 2
                                                        : 1,
                                              ),
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => _selectBus(bus),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 50,
                                                        height: 50,
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              dangerRed,
                                                              dangerRed
                                                                  .withOpacity(
                                                                    0.7,
                                                                  ),
                                                            ],
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .directions_bus_rounded,
                                                          color: textWhite,
                                                          size: 26,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              bus.name,
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    textWhite,
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Row(
                                                              children: [
                                                                Icon(
                                                                  Icons.route,
                                                                  size: 14,
                                                                  color:
                                                                      Colors
                                                                          .white70,
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  '${bus.route.length} stops',
                                                                  style: GoogleFonts.poppins(
                                                                    fontSize:
                                                                        12,
                                                                    color:
                                                                        Colors
                                                                            .white70,
                                                                  ),
                                                                ),
                                                                if (distance !=
                                                                    null) ...[
                                                                  const SizedBox(
                                                                    width: 12,
                                                                  ),
                                                                  Icon(
                                                                    Icons
                                                                        .near_me,
                                                                    size: 14,
                                                                    color:
                                                                        Colors
                                                                            .white70,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 4,
                                                                  ),
                                                                  Text(
                                                                    '${distance.toStringAsFixed(0)} m',
                                                                    style: GoogleFonts.poppins(
                                                                      fontSize:
                                                                          12,
                                                                      color:
                                                                          Colors
                                                                              .white70,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Column(
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 6,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: successGreen
                                                                  .withOpacity(
                                                                    0.2,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .access_time,
                                                                  size: 14,
                                                                  color:
                                                                      successGreen,
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  '${bus.etaToNextStop.toStringAsFixed(0)} min',
                                                                  style: GoogleFonts.poppins(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color:
                                                                        successGreen,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: accentBlue
                                                                  .withOpacity(
                                                                    0.2,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              '${bus.currentPassengers}/${bus.capacity}',
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    accentBlue,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Icon(
                                                        Icons.chevron_right,
                                                        color: Colors.white54,
                                                        size: 24,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        floatingActionButton:
            _userPosition == null
                ? null
                : Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accentBlue.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: FloatingActionButton(
                    onPressed: _moveCameraToUser,
                    backgroundColor: accentBlue,
                    elevation: 0,
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: textWhite,
                      size: 28,
                    ),
                  ),
                ),
      ),
    );
  }

  @override
  void dispose() {
    _hideSuggestions();
    _mapController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
