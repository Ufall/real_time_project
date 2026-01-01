import 'package:cloud_firestore/cloud_firestore.dart';

class LiveLocationModel {
  final String id;  // Bus ID
  final double lat;
  final double lng;
  final DateTime timestamp;
  final double speed;  // KM/h
  final double heading;  // Degrees

  LiveLocationModel({
    required this.id,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.speed,
    required this.heading,
  });

  factory LiveLocationModel.fromMap(Map<String, dynamic> map, String id) {
    final ts = map['timestamp'] as Timestamp;
    return LiveLocationModel(
      id: id,
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts.millisecondsSinceEpoch),
      speed: (map['speed'] ?? 0.0).toDouble(),
      heading: (map['heading'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'timestamp': Timestamp.fromDate(timestamp),
      'speed': speed,
      'heading': heading,
    };
  }
}