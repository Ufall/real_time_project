import 'package:cloud_firestore/cloud_firestore.dart';

class RouteModel {
  final String id;
  final String name;
  final List<String> stops;  // Ordered stop IDs
  final double totalDistance;  // KM
  final int estimatedTime;  // Minutes
  final DateTime createdAt;

  RouteModel({
    required this.id,
    required this.name,
    required this.stops,
    required this.totalDistance,
    required this.estimatedTime,
    required this.createdAt,
  });

  factory RouteModel.fromMap(Map<String, dynamic> map, String id) {
    return RouteModel(
      id: id,
      name: map['name'] ?? '',
      stops: List<String>.from(map['stops'] ?? []),
      totalDistance: (map['totalDistance'] ?? 0.0).toDouble(),
      estimatedTime: map['estimatedTime'] ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as Timestamp).millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'stops': stops,
      'totalDistance': totalDistance,
      'estimatedTime': estimatedTime,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}