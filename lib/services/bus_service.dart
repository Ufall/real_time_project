import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bus.dart';
import '../models/live_location.dart';
import 'location_service.dart';

class BusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locService = LocationService();

  // Get all active buses stream
  Stream<List<BusModel>> getActiveBusesStream() {
    return _firestore
        .collection('buses')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => BusModel.fromMap(doc.data()!, doc.id))
        .toList());
  }

  // Get all buses (including offline)
  Stream<List<BusModel>> getAllBusesStream() {
    return _firestore
        .collection('buses')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => BusModel.fromMap(doc.data()!, doc.id))
        .toList());
  }

  // Get bus by ID
  Future<BusModel?> getBus(String busId) async {
    final doc = await _firestore.collection('buses').doc(busId).get();
    if (doc.exists) {
      return BusModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  // Get bus by driver ID
  Future<BusModel?> getBusByDriverId(String driverId) async {
    final querySnapshot = await _firestore
        .collection('buses')
        .where('driverId', isEqualTo: driverId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      return BusModel.fromMap(
        querySnapshot.docs.first.data(),
        querySnapshot.docs.first.id,
      );
    }
    return null;
  }

  // Get live location for bus
  Future<LiveLocationModel?> getLiveLocation(String busId) async {
    final snap = await _firestore.collection('live_locations').doc(busId).get();
    if (snap.exists) {
      return LiveLocationModel.fromMap(snap.data()!, busId);
    }
    return null;
  }

  // Get live location stream
  Stream<LiveLocationModel?> getLiveLocationStream(String busId) {
    return _firestore.collection('live_locations').doc(busId).snapshots().map(
          (snapshot) {
        if (snapshot.exists) {
          return LiveLocationModel.fromMap(snapshot.data()!, busId);
        }
        return null;
      },
    );
  }

  // Update bus status
  Future<void> updateBusStatus(String busId, String status) async {
    await _firestore.collection('buses').doc(busId).update({
      'status': status,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // Update current passengers (+1 or -1)
  Future<void> updatePassengers(String busId, bool increment) async {
    final change = increment ? 1 : -1;
    await _firestore.collection('buses').doc(busId).update({
      'currentPassengers': FieldValue.increment(change),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // Update ETA to next stop
  Future<void> updateEtaToNextStop(String busId, double etaMinutes) async {
    await _firestore.collection('buses').doc(busId).update({
      'etaToNextStop': etaMinutes,
    });
  }

  // Add or update bus
  Future<void> addOrUpdateBus(BusModel bus) async {
    await _firestore.collection('buses').doc(bus.id).set(bus.toMap());

    // Update busesServing in stops
    for (String stopId in bus.route) {
      await _firestore.collection('bus_stops').doc(stopId).update({
        'busesServing': FieldValue.arrayUnion([bus.id]),
      });
    }
  }

  // Create bus for driver
  Future<String> createBusForDriver(String driverId, {
    String? name,
    String? number,
    int capacity = 50,
  }) async {
    final busId = 'bus_$driverId';

    await _firestore.collection('buses').doc(busId).set({
      'name': name ?? 'My Bus',
      'number': number ?? 'MH-00-XX-0000',
      'driverId': driverId,
      'routeId': 'route_$driverId',
      'route': [],
      'currentStopIndex': 0,
      'capacity': capacity,
      'currentPassengers': 0,
      'status': 'offline',
      'currentLocation': {'lat': 16.70, 'lng': 74.21},
      'etaToNextStop': 0,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    return busId;
  }

  // Ensure bus exists for driver
  Future<void> ensureBusExists(String busId, {String? driverId}) async {
    final busDoc = await _firestore.collection('buses').doc(busId).get();

    if (!busDoc.exists) {
      await _firestore.collection('buses').doc(busId).set({
        'name': 'My Bus',
        'number': 'MH-00-XX-0000',
        'driverId': driverId ?? 'unknown',
        'routeId': 'route_001',
        'route': [],
        'currentStopIndex': 0,
        'capacity': 50,
        'currentPassengers': 0,
        'status': 'offline',
        'currentLocation': {'lat': 16.70, 'lng': 74.21},
        'etaToNextStop': 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('Bus document created: $busId');
    }
  }

  // Get bus status
  Future<String> getBusStatus(String busId) async {
    final bus = await getBus(busId);
    return bus?.status ?? 'unknown';
  }

  // Filter nearby buses
  Future<List<BusModel>> getNearbyBuses(
      double userLat,
      double userLng, {
        double maxDistance = 500,
      }) async {
    final busesSnapshot = await getActiveBusesStream().first;
    return busesSnapshot.where((bus) {
      final busLat = bus.currentLocation['lat'] ?? 0.0;
      final busLng = bus.currentLocation['lng'] ?? 0.0;
      final dist = _locService.calculateDistance(
        userLat,
        userLng,
        busLat,
        busLng,
      );
      return dist <= maxDistance;
    }).toList();
  }

  // Update bus information (for driver)
  Future<void> updateBusInfo(
      String busId, {
        String? name,
        String? number,
        int? capacity,
      }) async {
    final Map<String, dynamic> updates = {
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    if (name != null) updates['name'] = name;
    if (number != null) updates['number'] = number;
    if (capacity != null) updates['capacity'] = capacity;

    await _firestore.collection('buses').doc(busId).update(updates);
  }

  // Delete bus
  Future<void> deleteBus(String busId) async {
    // Remove bus from all stops
    final bus = await getBus(busId);
    if (bus != null) {
      for (String stopId in bus.route) {
        await _firestore.collection('bus_stops').doc(stopId).update({
          'busesServing': FieldValue.arrayRemove([busId]),
        });
      }
    }

    // Delete live location
    await _firestore.collection('live_locations').doc(busId).delete();

    // Delete bus
    await _firestore.collection('buses').doc(busId).delete();
  }

  // Add stop to bus route
  Future<void> addStopToRoute(String busId, String stopId) async {
    await _firestore.collection('buses').doc(busId).update({
      'route': FieldValue.arrayUnion([stopId]),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('bus_stops').doc(stopId).update({
      'busesServing': FieldValue.arrayUnion([busId]),
    });
  }

  // Remove stop from bus route
  Future<void> removeStopFromRoute(String busId, String stopId) async {
    await _firestore.collection('buses').doc(busId).update({
      'route': FieldValue.arrayRemove([stopId]),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('bus_stops').doc(stopId).update({
      'busesServing': FieldValue.arrayRemove([busId]),
    });
  }
}