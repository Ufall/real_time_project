import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/passenger_home_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/admin_home_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase initialized successfully');
    } else {
      print('⚠️ Firebase already initialized');
    }
  } catch (e) {
    print('❌ Firebase initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {  // FIXED: Changed to StatefulWidget for retry functionality
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {  // FIXED: Defined _MyAppState
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // ✅ if not sign-in → show login immediately
          if (!snapshot.hasData) {
            return const LoginScreen();
          }

          // ✅ user logged-in → fetch role
          return FutureBuilder<String?>(
            future: AuthService().getUserRole(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // FIXED: Add error handling/logging for role fetch failures
              if (roleSnapshot.hasError) {
                print('❌ Role fetch error: ${roleSnapshot.error}'); // Debug log
                // Show error screen with retry
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Error loading user role.', style: TextStyle(fontSize: 18)),
                        const Text('Retrying in a moment...'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}), // FIXED: Direct setState in _MyAppState (no need for findAncestor)
                          child: const Text('Retry Now'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final role = roleSnapshot.data;
              print('✅ Fetched role: $role for UID: ${snapshot.data!.uid}'); // Debug log
              if (role == 'passenger') return const PassengerHomeScreen();
              if (role == 'driver') return const DriverHomeScreen();
              if (role == 'admin') return const AdminHomeScreen();

              // FIXED: Log fallback to login
              print('⚠️ Unknown role or null: $role → Showing login');
              return const LoginScreen();
            },
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
