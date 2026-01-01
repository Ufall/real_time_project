import 'package:cloud_firestore/cloud_firestore.dart';

class RequestModel {
  final String id;
  final String userId;
  final String busId;
  final String stopId;
  final Map<String, double> userLocationAtRequest;
  final String status;  // pending/accepted/rejected/cancelled
  final String notes;
  final double distanceBusToStop;  // Meters
  final double distanceStopToUser;  // Meters
  final DateTime timestamp;
  final DateTime? acceptedAt;

  RequestModel({
    required this.id,
    required this.userId,
    required this.busId,
    required this.stopId,
    required this.userLocationAtRequest,
    required this.status,
    required this.notes,
    required this.distanceBusToStop,
    required this.distanceStopToUser,
    required this.timestamp,
    this.acceptedAt,
  });

  factory RequestModel.fromMap(Map<String, dynamic> map, String id) {
    final timestamp = map['timestamp'] as Timestamp;
    final acceptedAt = map['acceptedAt'] as Timestamp?;
    return RequestModel(
      id: id,
      userId: map['userId'] ?? '',
      busId: map['busId'] ?? '',
      stopId: map['stopId'] ?? '',
      userLocationAtRequest: Map<String, double>.from(map['userLocationAtRequest'] ?? {}),
      status: map['status'] ?? 'pending',
      notes: map['notes'] ?? '',
      distanceBusToStop: (map['distanceBusToStop'] ?? 0.0).toDouble(),
      distanceStopToUser: (map['distanceStopToUser'] ?? 0.0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch),
      acceptedAt: acceptedAt != null ? DateTime.fromMillisecondsSinceEpoch(acceptedAt.millisecondsSinceEpoch) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'busId': busId,
      'stopId': stopId,
      'userLocationAtRequest': userLocationAtRequest,
      'status': status,
      'notes': notes,
      'distanceBusToStop': distanceBusToStop,
      'distanceStopToUser': distanceStopToUser,
      'timestamp': Timestamp.fromDate(timestamp),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
    };
  }
}