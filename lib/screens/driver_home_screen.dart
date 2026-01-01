import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/bus_service.dart';
import '../services/location_service.dart';
import '../services/request_service.dart';
import '../services/stop_service.dart';
import '../models/request.dart';
import '../models/bus_stop.dart';
import '../models/bus.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final BusService _busService = BusService();
  final RequestService _reqService = RequestService();
  final LocationService _locService = LocationService();
  final StopService _stopService = StopService();
  final AuthService _authService = AuthService();

  MapController _mapController = MapController();
  Timer? _locationTimer;
  bool _isTracking = false;
  String? _assignedBusId;
  BusModel? _assignedBus;
  Position? _driverPosition;

  List<RequestModel> _allRequests = [];
  Map<String, String> _userNames = {};
  List<BusStopModel> _routeStops = [];
  List<LatLng> _roadRoutePoints = [];
  bool _isLoadingRoute = false;

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
    _initData();
  }

  Future<void> _initData() async {
    await _fetchAssignedBus();
    if (_assignedBusId != null) {
      await _busService.ensureBusExists(_assignedBusId!);
      _listenToBusUpdates();

      _reqService.getAllRequestsStream(_assignedBusId!).listen((reqs) async {
        if (mounted) {
          for (var req in reqs) {
            if (!_userNames.containsKey(req.userId)) {
              final userName = await _fetchUserName(req.userId);
              _userNames[req.userId] = userName;
            }
          }
          setState(() => _allRequests = reqs);
        }
      });
    }
  }

  Future<String> _fetchUserName(String userId) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

      if (userDoc.exists) {
        return userDoc.data()?['name'] ?? 'Unknown User';
      }
      return 'Unknown User';
    } catch (e) {
      debugPrint('Error fetching user name: $e');
      return 'Unknown User';
    }
  }

  void _listenToBusUpdates() {
    FirebaseFirestore.instance
        .collection('buses')
        .doc(_assignedBusId)
        .snapshots()
        .listen((snapshot) async {
          if (snapshot.exists && mounted) {
            final bus = BusModel.fromMap(snapshot.data()!, snapshot.id);
            setState(() => _assignedBus = bus);
            await _loadRouteStops(bus.route);
            if (_isTracking) {
              await _fetchRoadRoute();
            }
          }
        });
  }

  Future<void> _fetchAssignedBus() async {
    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final busQuery =
          await FirebaseFirestore.instance
              .collection('buses')
              .where('driverId', isEqualTo: currentUserId)
              .limit(1)
              .get();

      if (busQuery.docs.isNotEmpty) {
        _assignedBusId = busQuery.docs.first.id;
        final bus = BusModel.fromMap(
          busQuery.docs.first.data(),
          busQuery.docs.first.id,
        );
        if (mounted) {
          setState(() => _assignedBus = bus);
          await _loadRouteStops(bus.route);
        }
      } else {
        _assignedBusId = 'bus_$currentUserId';
        await _busService.ensureBusExists(_assignedBusId!);

        await FirebaseFirestore.instance
            .collection('buses')
            .doc(_assignedBusId)
            .update({'driverId': currentUserId});

        final bus = await _busService.getBus(_assignedBusId!);
        if (mounted && bus != null) {
          setState(() => _assignedBus = bus);
        }
      }
    } catch (e) {
      debugPrint('Error fetching assigned bus: $e');
    }
  }

  Future<void> _loadRouteStops(List<String> stopIds) async {
    if (stopIds.isEmpty) {
      setState(() => _routeStops = []);
      return;
    }

    final stops = <BusStopModel>[];
    for (String id in stopIds) {
      try {
        final doc =
            await FirebaseFirestore.instance
                .collection('bus_stops')
                .doc(id)
                .get();
        if (doc.exists) {
          stops.add(BusStopModel.fromMap(doc.data()!, doc.id));
        }
      } catch (e) {
        debugPrint("Error loading stop $id: $e");
      }
    }
    if (mounted) {
      setState(() => _routeStops = stops);
    }
  }

  Future<void> _fetchRoadRoute() async {
    // Only fetch route if tracking and have at least one stop
    if (!_isTracking || _routeStops.isEmpty) {
      setState(() => _roadRoutePoints = []);
      return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      List<LatLng> waypoints = [];

      // Always start from driver's current position when tracking
      if (_driverPosition != null) {
        waypoints.add(
          LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
        );
      }

      // Add all route stops
      waypoints.addAll(
        _routeStops.map(
          (stop) => LatLng(stop.location['lat']!, stop.location['lng']!),
        ),
      );

      // Need at least 2 points for a route
      if (waypoints.length < 2) {
        setState(() {
          _roadRoutePoints = [];
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
              _roadRoutePoints = roadPoints;
              _isLoadingRoute = false;
            });
          }
        } else if (data['code'] == 'NoRoute') {
          if (mounted) {
            setState(() {
              _roadRoutePoints = [];
              _isLoadingRoute = false;
            });
          }
        }
      } else {
        throw Exception('Failed to fetch route');
      }
    } catch (e) {
      debugPrint("Error fetching road route: $e");
      if (mounted) {
        setState(() {
          _roadRoutePoints = [];
          _isLoadingRoute = false;
        });
      }
    }
  }

  void _startTracking() async {
    if (_assignedBusId == null) {
      _showSnackBar('No bus assigned!', warningOrange);
      return;
    }

    bool hasPermission = await _locService.checkPermissions();
    if (!hasPermission) {
      _showSnackBar('Location permission required!', dangerRed);
      return;
    }

    setState(() => _isTracking = true);

    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _driverPosition = pos);

      await _locService.updateLiveLocation(
        _assignedBusId!,
        pos.latitude,
        pos.longitude,
        speed: pos.speed,
        heading: pos.heading,
        busStatus: 'active',
      );

      await _fetchRoadRoute();
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
    } catch (e) {
      debugPrint("Initial location error: $e");
    }

    _locationTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        if (mounted) {
          setState(() => _driverPosition = pos);
        }

        await _locService.updateLiveLocation(
          _assignedBusId!,
          pos.latitude,
          pos.longitude,
          speed: pos.speed,
          heading: pos.heading,
          busStatus: 'active',
        );

        await _fetchRoadRoute();

        if (mounted) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
        }
      } catch (e) {
        debugPrint("Location update error: $e");
      }
    });
  }

  void _stopTracking() async {
    _locationTimer?.cancel();
    setState(() {
      _isTracking = false;
      _roadRoutePoints = []; // Clear route when stopping
    });

    if (_assignedBusId != null) {
      try {
        await _busService.updateBusStatus(_assignedBusId!, 'offline');
      } catch (e) {
        debugPrint("Error updating bus status: $e");
      }
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_driverPosition != null && _isTracking) {
      markers.add(
        Marker(
          point: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
          width: 60,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              color: successGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: successGreen.withOpacity(0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              color: textWhite,
              size: 32,
            ),
          ),
        ),
      );
    }

    for (int i = 0; i < _routeStops.length; i++) {
      final stop = _routeStops[i];
      markers.add(
        Marker(
          point: LatLng(stop.location['lat']!, stop.location['lng']!),
          width: 80,
          height: 80,
          child: GestureDetector(
            onLongPress: () => _showRemoveStopDialog(stop),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: textWhite, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.poppins(
                        color: textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: textWhite,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    stop.name,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
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

    return markers;
  }

  List<Polyline> _buildPolylines() {
    if (_roadRoutePoints.isEmpty || !_isTracking) return [];

    return [
      Polyline(
        points: _roadRoutePoints,
        color: accentBlue,
        strokeWidth: 6.0,
        pattern: const StrokePattern.solid(),
      ),
    ];
  }

  void _showEditBusInfoDialog() {
    if (_assignedBus == null) return;

    final nameController = TextEditingController(text: _assignedBus!.name);
    final numberController = TextEditingController(text: _assignedBus!.number);
    final capacityController = TextEditingController(
      text: _assignedBus!.capacity.toString(),
    );

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
                      color: accentBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit, color: accentBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Bus Information',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: GoogleFonts.poppins(color: textWhite),
                      decoration: InputDecoration(
                        labelText: 'Bus Name',
                        labelStyle: GoogleFonts.poppins(color: Colors.white70),
                        prefixIcon: const Icon(
                          Icons.directions_bus,
                          color: accentBlue,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: accentBlue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: numberController,
                      style: GoogleFonts.poppins(color: textWhite),
                      decoration: InputDecoration(
                        labelText: 'Bus Number (License Plate)',
                        labelStyle: GoogleFonts.poppins(color: Colors.white70),
                        prefixIcon: const Icon(
                          Icons.confirmation_number,
                          color: accentBlue,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: accentBlue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: capacityController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(color: textWhite),
                      decoration: InputDecoration(
                        labelText: 'Capacity (Total Seats)',
                        labelStyle: GoogleFonts.poppins(color: Colors.white70),
                        prefixIcon: const Icon(
                          Icons.airline_seat_recline_normal,
                          color: accentBlue,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: accentBlue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final number = numberController.text.trim();
                    final capacity =
                        int.tryParse(capacityController.text.trim()) ?? 50;

                    if (name.isEmpty || number.isEmpty) {
                      _showSnackBar('Please fill all fields', warningOrange);
                      return;
                    }

                    Navigator.pop(context);

                    try {
                      await FirebaseFirestore.instance
                          .collection('buses')
                          .doc(_assignedBusId)
                          .update({
                            'name': name,
                            'number': number,
                            'capacity': capacity,
                            'lastUpdated': FieldValue.serverTimestamp(),
                          });

                      _showSnackBar(
                        'Bus information updated successfully!',
                        successGreen,
                      );
                    } catch (e) {
                      debugPrint('Error updating bus info: $e');
                      _showSnackBar(
                        'Error updating bus information',
                        dangerRed,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Save', style: GoogleFonts.poppins()),
                ),
              ],
            ),
          ),
    );
  }

  void _showRemoveStopDialog(BusStopModel stop) {
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
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                "Remove Stop?",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              content: Text(
                "Remove '${stop.name}' from this route?",
                style: GoogleFonts.poppins(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Cancel",
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      if (_assignedBus != null) {
                        final newRoute =
                            _assignedBus!.route
                                .where((id) => id != stop.id)
                                .toList();

                        await FirebaseFirestore.instance
                            .collection('buses')
                            .doc(_assignedBusId)
                            .update({'route': newRoute});

                        await FirebaseFirestore.instance
                            .collection('bus_stops')
                            .doc(stop.id)
                            .update({
                              'busesServing': FieldValue.arrayRemove([
                                _assignedBusId,
                              ]),
                            });

                        _showSnackBar(
                          "${stop.name} removed from route",
                          successGreen,
                        );
                      }
                    } catch (e) {
                      _showSnackBar("Error removing stop", dangerRed);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dangerRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text("Remove", style: GoogleFonts.poppins()),
                ),
              ],
            ),
          ),
    );
  }

  void _handleMapTap(TapPosition tapPos, LatLng point) {
    _showCreateStopDialog(point);
  }

  void _showCreateStopDialog(LatLng point) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

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
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                "Add New Stop",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.poppins(color: textWhite),
                    decoration: InputDecoration(
                      labelText: "Stop Name",
                      labelStyle: GoogleFonts.poppins(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: accentBlue,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: GoogleFonts.poppins(color: textWhite),
                    decoration: InputDecoration(
                      labelText: "Description (e.g., City, State)",
                      labelStyle: GoogleFonts.poppins(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: accentBlue,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Cancel",
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final description = descCtrl.text.trim();

                    if (name.isEmpty) {
                      _showSnackBar('Please enter a stop name', warningOrange);
                      return;
                    }
                    Navigator.pop(context);

                    try {
                      final newStopId =
                          'stop_${DateTime.now().millisecondsSinceEpoch}';
                      final newStop = BusStopModel(
                        id: newStopId,
                        name: name,
                        location: {
                          'lat': point.latitude,
                          'lng': point.longitude,
                        },
                        description:
                            description.isNotEmpty
                                ? description
                                : "Added by driver",
                        busesServing: [_assignedBusId!],
                        sequenceInRoutes: {},
                        createdAt: DateTime.now(),
                      );

                      await FirebaseFirestore.instance
                          .collection('bus_stops')
                          .doc(newStopId)
                          .set(newStop.toMap());

                      await FirebaseFirestore.instance
                          .collection('buses')
                          .doc(_assignedBusId)
                          .update({
                            'route': FieldValue.arrayUnion([newStopId]),
                          });

                      _showSnackBar("$name added to route!", successGreen);
                    } catch (e) {
                      _showSnackBar("Error creating stop", dangerRed);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text("Add", style: GoogleFonts.poppins()),
                ),
              ],
            ),
          ),
    );
  }

  void _acceptRequest(String reqId) async {
    try {
      await _reqService.acceptRequest(reqId);
      await _busService.updatePassengers(_assignedBusId!, true);
      _showSnackBar('Request Accepted ✓', successGreen);
    } catch (e) {
      _showSnackBar('Error accepting request', dangerRed);
    }
  }

  void _rejectRequest(String reqId) async {
    try {
      await _reqService.rejectRequest(reqId);
      _showSnackBar('Request Rejected ✗', warningOrange);
    } catch (e) {
      _showSnackBar('Error rejecting request', dangerRed);
    }
  }

  void _completeRequest(String reqId) async {
    try {
      await _reqService.completeRequest(reqId);
      await _busService.updatePassengers(_assignedBusId!, false);
      _showSnackBar('Request Completed ✓', successGreen);
    } catch (e) {
      _showSnackBar('Error completing request', dangerRed);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return warningOrange;
      case 'accepted':
        return successGreen;
      case 'rejected':
        return dangerRed;
      case 'completed':
        return accentBlue;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.white70;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'PENDING';
      case 'accepted':
        return 'ACCEPTED';
      case 'rejected':
        return 'REJECTED';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
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
      ),
    );
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
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
            'Driver Dashboard',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textWhite,
            ),
          ),
          actions: [
            if (_isLoadingRoute)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: textWhite,
                    strokeWidth: 3,
                  ),
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
        body: Column(
          children: [
            // Control Panel
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accentBlue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.directions_bus_rounded,
                          color: accentBlue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _assignedBus?.name ?? "Loading...",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textWhite,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_routeStops.length} stops',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Icon(
                                  _isTracking ? Icons.gps_fixed : Icons.gps_off,
                                  size: 16,
                                  color:
                                      _isTracking
                                          ? successGreen
                                          : Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isTracking ? "Tracking" : "Offline",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color:
                                        _isTracking
                                            ? successGreen
                                            : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: accentBlue),
                        onPressed: _showEditBusInfoDialog,
                        tooltip: 'Edit Bus Info',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isTracking ? _stopTracking : _startTracking,
                      icon: Icon(
                        _isTracking
                            ? Icons.stop_circle_rounded
                            : Icons.play_circle_rounded,
                        size: 24,
                      ),
                      label: Text(
                        _isTracking ? 'Stop Tracking' : 'Start Tracking',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isTracking ? dangerRed : successGreen,
                        foregroundColor: textWhite,
                        elevation: 6,
                        shadowColor: (_isTracking ? dangerRed : successGreen)
                            .withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
                    initialCenter: const LatLng(16.70, 74.21),
                    initialZoom: 13.0,
                    onTap: _handleMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.track_my_bus',
                    ),
                    PolylineLayer(polylines: _buildPolylines()),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),
              ),
            ),

            // Requests Panel
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
                              color: warningOrange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.people_rounded,
                              color: warningOrange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Pickup Requests',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textWhite,
                            ),
                          ),
                          const Spacer(),
                          if (_allRequests.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: warningOrange,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_allRequests.length}',
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
                          _allRequests.isEmpty
                              ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inbox_rounded,
                                      size: 64,
                                      color: Colors.white30,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No requests yet',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              // Replace the ListView.builder section in your code (around line 1147)
                              // This improved version properly handles request states
                              : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemCount: _allRequests.length,
                                itemBuilder: (context, i) {
                                  final req = _allRequests[i];
                                  final userName =
                                      _userNames[req.userId] ?? 'Loading...';

                                  // Determine the current state
                                  final isPending = req.status == 'pending';
                                  final isAccepted = req.status == 'accepted';
                                  final isRejected = req.status == 'rejected';
                                  final isCompleted = req.status == 'completed';

                                  final stop = _routeStops.firstWhere(
                                    (s) => s.id == req.stopId,
                                    orElse:
                                        () => BusStopModel(
                                          id: req.stopId,
                                          name: req.stopId,
                                          location: {},
                                          description: '',
                                          busesServing: [],
                                          sequenceInRoutes: {},
                                          createdAt: DateTime.now(),
                                        ),
                                  );

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _getStatusColor(
                                          req.status,
                                        ).withOpacity(0.3),
                                        width: 2,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      _getStatusColor(
                                                        req.status,
                                                      ),
                                                      _getStatusColor(
                                                        req.status,
                                                      ).withOpacity(0.7),
                                                    ],
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.person_rounded,
                                                  color: textWhite,
                                                  size: 26,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            userName,
                                                            style:
                                                                GoogleFonts.poppins(
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
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                _getStatusColor(
                                                                  req.status,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            _getStatusText(
                                                              req.status,
                                                            ),
                                                            style:
                                                                GoogleFonts.poppins(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color:
                                                                      textWhite,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.location_on,
                                                          size: 14,
                                                          color: Colors.white70,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            stop.name,
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 12,
                                                              color:
                                                                  Colors
                                                                      .white70,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          // Action buttons based on status
                                          if (isPending) ...[
                                            // Show Accept/Reject buttons ONLY for pending requests
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed:
                                                        () => _rejectRequest(
                                                          req.id,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.cancel_rounded,
                                                      size: 20,
                                                    ),
                                                    label: Text(
                                                      'Reject',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 13,
                                                          ),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          dangerRed,
                                                      foregroundColor:
                                                          textWhite,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 10,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed:
                                                        () => _acceptRequest(
                                                          req.id,
                                                        ),
                                                    icon: const Icon(
                                                      Icons
                                                          .check_circle_rounded,
                                                      size: 20,
                                                    ),
                                                    label: Text(
                                                      'Accept',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 13,
                                                          ),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          successGreen,
                                                      foregroundColor:
                                                          textWhite,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 10,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ] else if (isAccepted) ...[
                                            // Show Complete button ONLY for accepted requests
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed:
                                                    () => _completeRequest(
                                                      req.id,
                                                    ),
                                                icon: const Icon(
                                                  Icons.done_all,
                                                  size: 20,
                                                ),
                                                label: Text(
                                                  'Mark as Completed',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: accentBlue,
                                                  foregroundColor: textWhite,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ] else if (isRejected) ...[
                                            // Show rejection message
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: dangerRed.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: dangerRed,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.block,
                                                    color: dangerRed,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Request Rejected',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: dangerRed,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else if (isCompleted) ...[
                                            // Show completion message
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: successGreen.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: successGreen,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.check_circle,
                                                    color: successGreen,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Trip Completed',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: successGreen,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
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
            _driverPosition == null
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
                    onPressed: () {
                      _mapController.move(
                        LatLng(
                          _driverPosition!.latitude,
                          _driverPosition!.longitude,
                        ),
                        16.0,
                      );
                    },
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
}
