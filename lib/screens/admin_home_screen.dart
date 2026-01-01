import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../services/bus_service.dart';
import '../services/location_service.dart';
import '../services/request_service.dart';
import '../services/route_service.dart';
import '../services/stop_service.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final AuthService _authService = AuthService();
  final BusService _busService = BusService();
  final RequestService _reqService = RequestService();
  final RouteService _routeService = RouteService();
  final StopService _stopService = StopService();
  final LocationService _locService = LocationService(); // For any location utils if needed

  // Data sections configuration
  final List<Map<String, dynamic>> _dataSections = [
    {
      'title': 'User Logins',
      'icon': Icons.people_outline,
      'color': const Color(0xFF001F3F), // primaryNavy
      'collection': 'users',
      'model': 'UserModel',
      'fields': ['authId', 'name', 'phone', 'email', 'role', 'currentLocation', 'preferences', 'createdAt'],
    },
    {
      'title': 'Buses',
      'icon': Icons.directions_bus,
      'color': const Color(0xFF003366), // secondaryNavy
      'collection': 'buses',
      'model': 'BusModel',
      'fields': ['id', 'name', 'number', 'driverId', 'routeId', 'route', 'currentStopIndex', 'capacity', 'currentPassengers', 'status', 'currentLocation', 'etaToNextStop', 'lastUpdated'],
    },
    {
      'title': 'Bus Stops',
      'icon': Icons.location_on,
      'color': const Color(0xFF0066CC), // accentBlue
      'collection': 'bus_stops',
      'model': 'BusStopModel',
      'fields': ['id', 'name', 'location', 'description', 'busesServing', 'sequenceInRoutes', 'createdAt'],
    },
    {
      'title': 'Routes',
      'icon': Icons.route,
      'color': const Color(0xFF00C853), // successGreen
      'collection': 'routes',
      'model': 'RouteModel',
      'fields': ['id', 'name', 'stops', 'totalDistance', 'estimatedTime', 'createdAt'],
    },
    {
      'title': 'Pickup Requests',
      'icon': Icons.request_page,
      'color': const Color(0xFFFF9800), // warningOrange
      'collection': 'requests',
      'model': 'RequestModel',
      'fields': ['id', 'userId', 'busId', 'stopId', 'userLocationAtRequest', 'status', 'notes', 'distanceBusToStop', 'distanceStopToUser', 'timestamp', 'acceptedAt'],
    },
    {
      'title': 'Live Locations',
      'icon': Icons.gps_fixed,
      'color': const Color(0xFFE53935), // dangerRed
      'collection': 'live_locations',
      'model': 'LiveLocationModel',
      'fields': ['id', 'lat', 'lng', 'timestamp', 'speed', 'heading'],
    },
  ];

  // Theme colors (matching driver UI)
  static const Color primaryNavy = Color(0xFF001F3F);
  static const Color secondaryNavy = Color(0xFF003366);
  static const Color accentBlue = Color(0xFF0066CC);
  static const Color successGreen = Color(0xFF00C853);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color dangerRed = Color(0xFFE53935);
  static const Color textWhite = Colors.white;
  static const Color cardBg = Color(0xFF002147);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: primaryNavy,
          secondary: accentBlue,
          surface: primaryNavy,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        backgroundColor: primaryNavy,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: primaryNavy,
          title: Text(
            'Admin Dashboard',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textWhite,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.logout_rounded, color: textWhite),
                onPressed: () => _authService.logout(),
                tooltip: 'Logout',
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Dashboard Overview Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cardBg, secondaryNavy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accentBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings,
                            color: accentBlue,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Data Management & Exports',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textWhite,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Download comprehensive reports for all system data in professional Excel format.',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Data Sections Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.0, // Adjusted from 1.2 to 1.0 for more vertical space
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _dataSections.length,
                itemBuilder: (context, index) {
                  final section = _dataSections[index];
                  final title = section['title'] as String;
                  final icon = section['icon'] as IconData;
                  final color = section['color'] as Color;
                  final collection = section['collection'] as String;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withOpacity(0.3), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _downloadData(collection, section),
                        child: Padding(
                          padding: const EdgeInsets.all(12), // Reduced from 16 to 12 for more internal space
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min, // Explicitly set to min to avoid unnecessary expansion
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10), // Reduced from 12 to 10
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(icon, color: color, size: 28), // Reduced from 32 to 28
                              ),
                              const SizedBox(height: 8), // Reduced from 12 to 8
                              Flexible( // Wrapped Text in Flexible to allow shrinking if needed
                                child: Text(
                                  title,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13, // Reduced from 14 to 13
                                    fontWeight: FontWeight.w600,
                                    color: textWhite,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis, // Add ellipsis for long titles
                                  maxLines: 2,
                                ),
                              ),
                              const SizedBox(height: 6), // Reduced from 8 to 6
                              SizedBox( // Wrapped button in SizedBox with fixed height to control size
                                height: 36, // Fixed smaller height for button
                                child: ElevatedButton.icon(
                                  onPressed: () => _downloadData(collection, section),
                                  icon: const Icon(Icons.download, size: 16), // Reduced icon size
                                  label: Text(
                                    'Download',
                                    style: GoogleFonts.poppins(fontSize: 11), // Reduced from 12 to 11
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: color,
                                    foregroundColor: textWhite,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8), // Slightly smaller radius
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Compact padding
                                    minimumSize: const Size(0, 0), // Allow smaller size
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              // Seed Data Button (Optional, for initial setup)
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [warningOrange.withOpacity(0.2), warningOrange.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: warningOrange.withOpacity(0.3)),
                ),
                child: ElevatedButton.icon(
                  onPressed: _seedAllData,
                  icon: const Icon(Icons.add, color: textWhite),
                  label: Text(
                    'Seed Sample Data (If Collections Empty)',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textWhite,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: warningOrange,
                    foregroundColor: textWhite,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadData(String collection, Map<String, dynamic> section) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: primaryNavy,
          content: Row(
            children: const [
              CircularProgressIndicator(color: accentBlue),
              SizedBox(width: 16),
              Text('Generating Excel...', style: TextStyle(color: textWhite)),
            ],
          ),
        ),
      );

      // Fetch from Firebase
      final snapshot =
      await FirebaseFirestore.instance.collection(collection).get();

      if (snapshot.docs.isEmpty) {
        Navigator.pop(context);
        _showSnackBar('No data found in $collection', warningOrange);
        return;
      }

      // Create Excel
      final excel = ex.Excel.createExcel();
      final sheet = excel['Sheet1'];
      final fields = section['fields'] as List<String>;

      // ----- WRITE HEADER -----
      for (int i = 0; i < fields.length; i++) {
        final cell = sheet.cell(
          ex.CellIndex.indexByString('${String.fromCharCode(65 + i)}1'),
        );
        cell.value = ex.TextCellValue(fields[i].toUpperCase());
      }

      // ----- WRITE ROWS -----
      int row = 2;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final docId = doc.id;

        for (int i = 0; i < fields.length; i++) {
          final field = fields[i];
          dynamic value = data[field];

          if (value is Timestamp) {
            value = value.toDate().toString();
          } else if (value is Map || value is List) {
            value = value.toString();
          } else if (value == null) {
            value = '';
          }

          final cell = sheet.cell(
            ex.CellIndex.indexByString('${String.fromCharCode(65 + i)}$row'),
          );
          cell.value = ex.TextCellValue(value.toString());
        }

        // If ID not included
        if (!fields.contains('id') && !fields.contains('authId')) {
          final idCell =
          sheet.cell(ex.CellIndex.indexByString('A$row'));
          idCell.value = ex.TextCellValue(docId);
        }
        row++;
      }

      // Set column width
      for (int i = 0; i < fields.length; i++) {
        sheet.setColumnWidth(i, 20);
      }

      // -------------------------
      // STORAGE PERMISSION
      // -------------------------
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        Navigator.pop(context);
        _showSnackBar('Storage permission denied.', dangerRed);
        return;
      }

      // -------------------------
      // GET SAFE DIRECTORY
      // -------------------------
      final directory = await getExternalStorageDirectory();

      if (directory == null) {
        Navigator.pop(context);
        _showSnackBar('Unable to access storage directory.', dangerRed);
        return;
      }

      final fileName =
          '${collection}_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      final file = File('${directory.path}/$fileName');

      final bytes = excel.encode()!;
      await file.writeAsBytes(bytes);

      // Open file automatically
      await OpenFilex.open(file.path);

      Navigator.pop(context);
      _showSnackBar(
          'Export successful. Saved to app folder.\n$fileName', successGreen);
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Error exporting data: $e', dangerRed);
    }
  }


  Future<void> _seedAllData() async {
    try {
      bool seeded = false;
      // Seed stops (void return, assume seeded if called)
      await _stopService.seedSampleStops();
      seeded = true;
      // Seed routes
      final routesSeeded = await _routeService.seedSampleRoutes();
      if (routesSeeded) seeded = true;
      _showSnackBar(seeded ? 'Sample data seeded successfully!' : 'Data already exists.', seeded ? successGreen : warningOrange);
    } catch (e) {
      _showSnackBar('Error seeding data: $e', dangerRed);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: textWhite)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}