import 'package:cloud_firestore/cloud_firestore.dart';

class BusStopModel {
  final String id;
  final String name;
  final Map<String, double> location;
  final String description;
  final List<String> busesServing;
  final Map<String, int> sequenceInRoutes;
  final DateTime createdAt;

  BusStopModel({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.busesServing,
    required this.sequenceInRoutes,
    required this.createdAt,
  });

  factory BusStopModel.fromMap(Map<String, dynamic> map, String id) {
    return BusStopModel(
      id: id,
      name: map['name'] ?? '',
      location: Map<String, double>.from(map['location'] ?? {}),
      description: map['description'] ?? '',
      busesServing: List<String>.from(map['busesServing'] ?? []),
      sequenceInRoutes: Map<String, int>.from(map['sequenceInRoutes'] ?? {}),
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as Timestamp).millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'description': description,
      'busesServing': busesServing,
      'sequenceInRoutes': sequenceInRoutes,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}