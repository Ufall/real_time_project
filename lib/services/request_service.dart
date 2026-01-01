import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/request.dart';

class RequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all requests for a bus (pending, accepted, rejected, completed)
  Stream<List<RequestModel>> getAllRequestsStream(String busId) {
    return _firestore
        .collection('requests')
        .where('busId', isEqualTo: busId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
        .toList());
  }

  // Get only pending requests for a bus
  Stream<List<RequestModel>> getPendingRequestsStream(String busId) {
    return _firestore
        .collection('requests')
        .where('busId', isEqualTo: busId)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
        .toList());
  }

  // Check if user already has a request for this bus
  Future<bool> hasExistingRequest(String userId, String busId) async {
    final querySnapshot = await _firestore
        .collection('requests')
        .where('userId', isEqualTo: userId)
        .where('busId', isEqualTo: busId)
        .where('status', whereIn: ['pending', 'accepted']).get();

    return querySnapshot.docs.isNotEmpty;
  }

  // Send a new pickup request (for passengers)
  Future<String?> sendRequest({
    required String userId,
    required String busId,
    required String stopId,
    required Map<String, double> userLocation,
    String notes = '',
  }) async {
    try {
      // Check for existing request
      final hasRequest = await hasExistingRequest(userId, busId);
      if (hasRequest) {
        throw Exception(
            'You already have a pending or accepted request for this bus');
      }

      // Get bus and stop info for distance calculations
      final busDoc = await _firestore.collection('buses').doc(busId).get();
      final stopDoc = await _firestore.collection('bus_stops').doc(stopId).get();

      double distanceBusToStop = 0.0;
      double distanceStopToUser = 0.0;

      if (busDoc.exists && stopDoc.exists) {
        final busLocation = Map<String, double>.from(
            busDoc.data()?['currentLocation'] ?? {'lat': 0.0, 'lng': 0.0});
        final stopLocation = Map<String, double>.from(
            stopDoc.data()?['location'] ?? {'lat': 0.0, 'lng': 0.0});

        // Simple distance calculation (you can use LocationService for more accuracy)
        distanceBusToStop = _calculateDistance(
          busLocation['lat']!,
          busLocation['lng']!,
          stopLocation['lat']!,
          stopLocation['lng']!,
        );

        distanceStopToUser = _calculateDistance(
          stopLocation['lat']!,
          stopLocation['lng']!,
          userLocation['lat']!,
          userLocation['lng']!,
        );
      }

      final docRef = await _firestore.collection('requests').add({
        'userId': userId,
        'busId': busId,
        'stopId': stopId,
        'userLocationAtRequest': userLocation,
        'status': 'pending',
        'notes': notes,
        'distanceBusToStop': distanceBusToStop,
        'distanceStopToUser': distanceStopToUser,
        'timestamp': FieldValue.serverTimestamp(),
        'acceptedAt': null,
      });

      return docRef.id;
    } catch (e) {
      print('Error sending request: $e');
      rethrow;
    }
  }

  // Simple distance calculation (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_degreesToRadians(lat1)) *
            _cos(_degreesToRadians(lat2)) *
            _sin(dLon / 2) *
            _sin(dLon / 2);

    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * 3.141592653589793 / 180;
  }

  double _sin(double x) {
    return _sinCos(x, true);
  }

  double _cos(double x) {
    return _sinCos(x, false);
  }

  double _sinCos(double x, bool isSin) {
    // Simple Taylor series approximation
    double result = isSin ? x : 1.0;
    double term = isSin ? x : 1.0;
    int sign = -1;

    for (int i = 1; i < 10; i++) {
      term *= x * x / ((2 * i + (isSin ? 0 : -1)) * (2 * i + (isSin ? 1 : 0)));
      result += sign * term;
      sign *= -1;
    }

    return result;
  }

  double _sqrt(double x) {
    if (x < 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  double _atan2(double y, double x) {
    if (x == 0) return y > 0 ? 1.5707963267948966 : -1.5707963267948966;
    double atan = y / x;
    if (x < 0) {
      atan += y >= 0 ? 3.141592653589793 : -3.141592653589793;
    }
    return atan;
  }

  // Accept a request (driver accepts)
  Future<void> acceptRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  // Reject a request (driver rejects)
  Future<void> rejectRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  // Complete a request (when passenger has boarded)
  Future<void> completeRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  // Cancel a request (user cancels their own request)
  Future<void> cancelRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  // Get user's all requests
  Stream<List<RequestModel>> getUserRequestsStream(String userId) {
    return _firestore
        .collection('requests')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
        .toList());
  }

  // Get user's requests for a specific bus
  Stream<List<RequestModel>> getUserRequestsForBus(String userId, String busId) {
    return _firestore
        .collection('requests')
        .where('userId', isEqualTo: userId)
        .where('busId', isEqualTo: busId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
        .toList());
  }

  // Delete old completed/rejected requests (cleanup)
  Future<void> deleteOldRequests({int daysOld = 7}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    final snapshot = await _firestore
        .collection('requests')
        .where('status', whereIn: ['completed', 'rejected', 'cancelled']).where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  // Get request by ID
  Future<RequestModel?> getRequest(String requestId) async {
    final doc = await _firestore.collection('requests').doc(requestId).get();
    if (doc.exists) {
      return RequestModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  // Get all requests (for admin)
  Future<List<RequestModel>> getAllRequests() async {
    final snapshot = await _firestore
        .collection('requests')
        .orderBy('timestamp', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
        .toList();
  }
}