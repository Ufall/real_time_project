import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/live_location.dart'; // For toMap usage

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionStream;

  // Check and request location permissions
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false; // Handle in UI: Prompt user to enable
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  // Get current position (one-time)
  Future<Position?> getCurrentPosition() async {
    if (!await checkPermissions()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Start listening to location updates (for driver tracking)
  // StreamSubscription<Position> startLocationStream({
  //   required Function(Position) onUpdate,
  //   Duration interval = const Duration(seconds: 10),
  // }) async{
  //   if (!await checkPermissions()) {
  //   throw Exception('Location permissions denied');
  //   }
  //   return Geolocator.getPositionStream(
  //   locationSettings: LocationSettings(
  //   accuracy: LocationAccuracy.high,
  //   distanceFilter: 10,  // Min distance change
  //   ),
  //   ).listen((Position position) {
  //   onUpdate(position);
  //   });
  // }

  Future<StreamSubscription<Position>> startLocationStream({
    required Function(Position) onUpdate,
    Duration interval = const Duration(seconds: 10),
  }) async {
    if (!await checkPermissions()) {
      throw Exception('Location permissions denied');
    }

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      onUpdate(position);
    });
  }

  // Stop location stream
  void stopLocationStream() {
    _positionStream?.cancel();
  }

  // Calculate distance between two lat/lng points (Haversine formula, in meters)
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    double dLat = (lat2 - lat1) * pi / 180.0;
    double dLng = (lng2 - lng1) * pi / 180.0;
    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // Calculate simple ETA (distance to next stop / avg speed)
  // double calculateEta(double distanceMeters, double speedKmh = 25.0) {
  // double speedMs = speedKmh * 1000 / 3600;  // Convert to m/s
  // double timeSeconds = distanceMeters / speedMs;
  // return timeSeconds / 60.0;  // Minutes
  // }

  double calculateEta({
    required double distanceMeters,
    double speedKmh = 25.0,
  }) {
    double speedMs = speedKmh * 1000 / 3600;
    double timeSeconds = distanceMeters / speedMs;
    return timeSeconds / 60.0;
  }

  // Update live location for a bus (Driver use: writes to /live_locations and /buses)
  Future<void> updateLiveLocation(
    String busId,
    double lat,
    double lng, {
    double speed = 0.0,
    double heading = 0.0,
    String? busStatus,
  }) async {
    final timestamp = FieldValue.serverTimestamp();
    final liveData = {
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      'speed': speed,
      'heading': heading,
    };
    // Update /live_locations
    await _firestore.collection('live_locations').doc(busId).set(liveData);

    // Update /buses currentLocation (and status/eta if provided)
    final busUpdate = {
      'currentLocation': {'lat': lat, 'lng': lng},
      'lastUpdated': timestamp,
    };
    if (busStatus != null) busUpdate['status'] = busStatus;
    await _firestore.collection('buses').doc(busId).update(busUpdate);
  }

  // Get live location for a bus (one-time fetch)
  Future<LiveLocationModel?> getLiveLocation(String busId) async {
    final doc = await _firestore.collection('live_locations').doc(busId).get();
    if (doc.exists) {
      return LiveLocationModel.fromMap(doc.data()!, busId);
    }
    return null;
  }

  // Stream live location for a bus
  Stream<LiveLocationModel?> getLiveLocationStream(String busId) {
    return _firestore.collection('live_locations').doc(busId).snapshots().map((
      snapshot,
    ) {
      if (snapshot.exists) {
        return LiveLocationModel.fromMap(snapshot.data()!, busId);
      }
      return null;
    });
  }

  // Check if location is fresh (e.g., <5 min old)
  bool isLocationFresh(
    LiveLocationModel location, {
    Duration maxAge = const Duration(minutes: 5),
  }) {
    return DateTime.now().difference(location.timestamp).inSeconds <
        maxAge.inSeconds;
  }
}
