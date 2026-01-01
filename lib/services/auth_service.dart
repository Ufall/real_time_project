import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // for debugPrint
import '../models/user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Create/Update user profile on signup/login
  Future<UserModel?> createOrUpdateUser({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role,
    Map<String, double>? location,
  }) async {
    try {
      debugPrint('AuthService: Starting createOrUpdateUser for $email');

      UserCredential cred;
      if (_auth.currentUser == null) {
        debugPrint('No current user, creating new account...');
        cred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        debugPrint('User already logged in, signing in...');
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final userId = cred.user!.uid;
      debugPrint('Firebase Auth successful, UID: $userId');

      final userRef = _firestore.collection('users').doc(userId);

      await userRef.set({
        'authId': userId,
        'name': name,
        'phone': phone,
        'email': email,
        'role': role,
        'currentLocation': location ?? {},
        'preferences': {'maxDistance': 500},
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
        'Firestore user document created/updated successfully for $email',
      );

      return UserModel(
        id: userId,
        authId: userId,
        name: name,
        phone: phone,
        email: email,
        role: role,
        currentLocation: Map<String, double>.from(location ?? {}),
        preferences: {'maxDistance': 500},
        createdAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      debugPrint('AuthService Error (createOrUpdateUser): $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow; // Keeps original Firebase error message
    }
  }

  // Login
  Future<UserModel?> login(String email, String password) async {
    try {
      debugPrint('AuthService: Attempting login for $email');

      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final role = await getUserRole(cred.user!.uid);

      debugPrint('Login successful for $email (Role: $role)');

      final doc =
          await _firestore.collection('users').doc(cred.user!.uid).get();

      if (!doc.exists) {
        debugPrint('No Firestore user document found for ${cred.user!.uid}');
        return null;
      }

      return UserModel.fromMap(doc.data()!, cred.user!.uid);
    } catch (e, stackTrace) {
      debugPrint('AuthService Error (login): $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  // Get role
  Future<String> getUserRole(String userId) async {
    try {
      debugPrint('Fetching role for userId: $userId');
      final doc = await _firestore.collection('users').doc(userId).get();
      final role = doc.data()?['role'] ?? 'passenger';
      debugPrint('User role found: $role');
      return role;
    } catch (e, stackTrace) {
      debugPrint('Error fetching user role: $e');
      debugPrint('StackTrace: $stackTrace');
      return 'passenger';
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      debugPrint('AuthService: Logging out user...');
      await _auth.signOut();
      debugPrint('Logout successful');
    } catch (e, stackTrace) {
      debugPrint('Logout error: $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  // Hardcoded Admin Check
  bool isAdmin(String email) => email == 'admin@example.com';
}
