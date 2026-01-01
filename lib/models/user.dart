import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String authId;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final Map<String, double>? currentLocation;
  final Map<String, dynamic>? preferences;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.authId,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.currentLocation,
    this.preferences,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      authId: map['authId'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      role: map['role'] ?? 'passenger',
      currentLocation: Map<String, double>.from(map['currentLocation'] ?? {}),
      preferences: map['preferences'],
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as Timestamp).millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authId': authId,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'currentLocation': currentLocation,
      'preferences': preferences,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}