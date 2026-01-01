import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bus_stop.dart';

class StopService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all stops
  Stream<List<BusStopModel>> getAllStops() {
    return _firestore.collection('bus_stops').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => BusStopModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Add stop (Admin only)
  Future<void> addStop(BusStopModel stop) async {
    await _firestore.collection('bus_stops').doc(stop.id).set(stop.toMap());
  }

  // Seed sample stops (Call in Admin)
  Future<void> seedSampleStops() async {
    final stopsRef = _firestore.collection('bus_stops');
    final snapshot = await stopsRef.get();
    if (snapshot.docs.isEmpty) {
      await stopsRef.doc('stopId_1').set({
        'name': 'Kadamwadi Bus Stand',
        'location': {'lat': 16.70, 'lng': 74.21},
        'description': 'Near Market Road',
        'busesServing': [],
        'sequenceInRoutes': {'routeId_001': 1},
        'createdAt': FieldValue.serverTimestamp(),
      });
      await stopsRef.doc('stopId_2').set({
        'name': 'Midway Junction',
        'location': {'lat': 16.705, 'lng': 74.215},
        'description': 'Mid route stop',
        'busesServing': [],
        'sequenceInRoutes': {'routeId_001': 2},
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Add more as needed
    }
  }
}