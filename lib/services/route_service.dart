import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/route.dart'; // Assume RouteModel is defined similarly to BusStopModel

class RouteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all routes stream
  Stream<List<RouteModel>> getAllRoutes() {
    return _firestore.collection('routes').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => RouteModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Get single route
  Future<RouteModel?> getRoute(String routeId) async {
    final doc = await _firestore.collection('routes').doc(routeId).get();
    if (doc.exists) {
      return RouteModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  // Add or update route (Admin only)
  Future<void> addOrUpdateRoute(RouteModel route) async {
    await _firestore.collection('routes').doc(route.id).set(route.toMap());
  }

  // Delete route
  Future<void> deleteRoute(String routeId) async {
    await _firestore.collection('routes').doc(routeId).delete();
  }

  // Seed sample routes (Call in Admin)
  // Future<void> seedSampleRoutes() async {
  //   final routesRef = _firestore.collection('routes');
  //   final snapshot = await routesRef.get();
  //   if (snapshot.docs.isEmpty) {
  //     await routesRef.doc('routeId_001').set({
  //       'name': 'Kadamwadi-Pachgaon Local',
  //       'stops': ['stopId_1', 'stopId_2', 'stopId_3'],
  //       'totalDistance': 12.5,
  //       'estimatedTime': 45,
  //       'createdAt': FieldValue.serverTimestamp(),
  //     });
  //     // Add more routes as needed
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(const SnackBar(content: Text('Sample routes seeded!')));
  //   }
  // }
  Future<bool> seedSampleRoutes() async {
    final routesRef = _firestore.collection('routes');
    final snapshot = await routesRef.get();

    if (snapshot.docs.isEmpty) {
      await routesRef.doc('routeId_001').set({
        'name': 'Kadamwadi-Pachgaon Local',
        'stops': ['stopId_1', 'stopId_2', 'stopId_3'],
        'totalDistance': 12.5,
        'estimatedTime': 45,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true; // seeded
    }
    return false; // already exists
  }

}
