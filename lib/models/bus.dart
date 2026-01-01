import 'package:cloud_firestore/cloud_firestore.dart';

class BusModel {
  final String id;
  final String name;
  final String number;  // License plate
  final String driverId;  // User ID
  final String routeId;  // Route ID
  final List<String> route;  // Stop IDs in order
  final int currentStopIndex;
  final int capacity;
  final int currentPassengers;
  final String status;  // active/offline/maintenance
  final Map<String, double> currentLocation;
  final double etaToNextStop;  // Minutes
  final DateTime lastUpdated;

  BusModel({
    required this.id,
    required this.name,
    required this.number,
    required this.driverId,
    required this.routeId,
    required this.route,
    required this.currentStopIndex,
    required this.capacity,
    required this.currentPassengers,
    required this.status,
    required this.currentLocation,
    required this.etaToNextStop,
    required this.lastUpdated,
  });

  factory BusModel.fromMap(Map<String, dynamic> map, String id) {
    return BusModel(
      id: id,
      name: map['name'] ?? '',
      number: map['number'] ?? '',
      driverId: map['driverId'] ?? '',
      routeId: map['routeId'] ?? '',
      route: List<String>.from(map['route'] ?? []),
      currentStopIndex: map['currentStopIndex'] ?? 0,
      capacity: map['capacity'] ?? 0,
      currentPassengers: map['currentPassengers'] ?? 0,
      status: map['status'] ?? 'offline',
      currentLocation: Map<String, double>.from(map['currentLocation'] ?? {'lat': 0.0, 'lng': 0.0}),
      etaToNextStop: (map['etaToNextStop'] ?? 0.0).toDouble(),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch((map['lastUpdated'] as Timestamp).millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'number': number,
      'driverId': driverId,
      'routeId': routeId,
      'route': route,
      'currentStopIndex': currentStopIndex,
      'capacity': capacity,
      'currentPassengers': currentPassengers,
      'status': status,
      'currentLocation': currentLocation,
      'etaToNextStop': etaToNextStop,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }
}