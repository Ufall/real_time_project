import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Focus nodes
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();

  // State
  String _role = 'passenger'; // only used in signup
  bool _isSignup = false;
  bool _isLoading = false;
  bool _passwordVisible = false;

  // Animations
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  // Theme colors (navy professional)
  static const Color primaryNavy = Color(0xFF001F3F);
  static const Color secondaryNavy = Color(0xFF003366);
  static const Color accentBlack = Colors.black87;
  static const Color textWhite = Colors.white;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();

    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();

    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();

    super.dispose();
  }

  Future<Map<String, double>?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      final pos = await Geolocator.getCurrentPosition();
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (e) {
      // Ignore location failures — not fatal for auth flow
      debugPrint('Location error: $e');
      return null;
    }
  }

  // Future<void> _handleAuth() async {
  //   if (!_formKey.currentState!.validate()) return;
  //
  //   setState(() => _isLoading = true);
  //   try {
  //     final location = await _getCurrentLocation();
  //
  //     if (_isSignup) {
  //       // Signup
  //       await _auth.createOrUpdateUser(
  //         email: _emailController.text.trim(),
  //         password: _passwordController.text.trim(),
  //         name: _nameController.text.trim(),
  //         phone: _phoneController.text.trim(),
  //         role: _role,
  //         location: location,
  //       );
  //       debugPrint(
  //         '✅ Signup successful for ${_emailController.text.trim()} as $_role',
  //       );
  //     } else {
  //       // Login
  //       final enteredEmail = _emailController.text.trim();
  //       final enteredPassword = _passwordController.text.trim();
  //
  //       // Optional admin shortcut (keeps your previous logic)
  //       if (_auth.isAdmin(enteredEmail) && enteredPassword == 'admin') {
  //         await _auth.createOrUpdateUser(
  //           email: 'admin@example.com',
  //           password: 'admin@21',
  //           name: 'Admin',
  //           phone: '0000000000',
  //           role: 'admin',
  //           location: location,
  //         );
  //         debugPrint('✅ Admin created/updated');
  //       }
  //
  //       await _auth.login(enteredEmail, enteredPassword);
  //       debugPrint('✅ Login successful for $enteredEmail');
  //     }
  //
  //     // StreamBuilder/push handled elsewhere (you mentioned main.dart handles it)
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Error: ${_friendlyError(e)}'),
  //         backgroundColor: primaryNavy,
  //         behavior: SnackBarBehavior.floating,
  //       ),
  //     );
  //     debugPrint('❌ Auth error: $e');
  //   } finally {
  //     if (mounted) setState(() => _isLoading = false);
  //   }
  // }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final enteredEmail = _emailController.text.trim();
      final enteredPassword = _passwordController.text.trim();

      if (_isSignup) {
        // 🔒 Block admin signup
        if (_role == 'admin') {
          throw Exception('Admin accounts cannot be created through signup. Contact system administrator.');
        }

        final location = await _getCurrentLocation();

        // Signup for passenger/driver only
        await _auth.createOrUpdateUser(
          email: enteredEmail,
          password: enteredPassword,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          role: _role,
          location: location,
        );
        debugPrint('✅ Signup successful for $enteredEmail as $_role');
      } else {
        // Login flow
        final location = await _getCurrentLocation();

        // 🔐 Auto-create admin ONLY if logging in with admin email
        if (_auth.isAdmin(enteredEmail)) {
          try {
            // Try to create admin account (will fail silently if exists)
            await _auth.createOrUpdateUser(
              email: 'admin@example.com',
              password: 'admin@21',
              name: 'Admin',
              phone: '0000000000',
              role: 'admin',
              location: location,
            );
            debugPrint('✅ Admin account ensured');
          } catch (e) {
            debugPrint('⚠️ Admin already exists or creation failed: $e');
          }
        }

        await _auth.login(enteredEmail, enteredPassword);
        debugPrint('✅ Login successful for $enteredEmail');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${_friendlyError(e)}'),
          backgroundColor: primaryNavy,
          behavior: SnackBarBehavior.floating,
        ),
      );
      debugPrint('❌ Auth error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object e) {
    // You can expand mapping of errors to friendlier messages here.
    return e.toString();
  }

  // Basic email pattern
  final RegExp _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  Widget build(BuildContext context) {
    // Use GoogleFonts Poppins for a professional brand look
    final baseTextTheme = Theme.of(context).textTheme;
    final textTheme = baseTextTheme.copyWith(
      headlineMedium: GoogleFonts.poppins(
        textStyle: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: textWhite,
        ),
      ),
      titleLarge: GoogleFonts.poppins(
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textWhite,
        ),
      ),
      bodyLarge: GoogleFonts.poppins(
        textStyle: const TextStyle(fontSize: 16, color: textWhite),
      ),
      bodyMedium: GoogleFonts.poppins(
        textStyle: const TextStyle(fontSize: 14, color: Colors.white70),
      ),
    );

    final theme = ThemeData(
      colorScheme: ColorScheme.dark(
        primary: primaryNavy,
        secondary: secondaryNavy,
        surface: primaryNavy,
        background: primaryNavy,
        onPrimary: textWhite,
        onSecondary: textWhite,
        onSurface: textWhite,
        onBackground: textWhite,
      ),
      useMaterial3: true,
      textTheme: textTheme,
    );

    return Theme(
      data: theme,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [primaryNavy, accentBlack],
                stops: [0.0, 1.0],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Constrain width for large screens
                  final maxWidth =
                      constraints.maxWidth > 900
                          ? 700.0
                          : constraints.maxWidth * 0.95;

                  return Center(
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 250),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 28),

                              // Title
                              FadeTransition(
                                opacity: _fadeAnimation,
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: Text(
                                    'Welcome',
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              FadeTransition(
                                opacity: _fadeAnimation,
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0,
                                    ),
                                    child: Text(
                                      _isSignup
                                          ? 'Create your account'
                                          : 'Sign in to continue',
                                      style: theme.textTheme.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                              // Card
                              FadeTransition(
                                opacity: _fadeAnimation,
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: Card(
                                    elevation: 14,
                                    color: primaryNavy.withOpacity(0.95),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(22.0),
                                      child: Form(
                                        key: _formKey,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Email
                                            _buildTextField(
                                              controller: _emailController,
                                              focusNode: _emailFocus,
                                              label: 'Email',
                                              hint: 'you@company.com',
                                              prefix: Icons.email_outlined,
                                              keyboardType:
                                                  TextInputType.emailAddress,
                                              textInputAction:
                                                  TextInputAction.next,
                                              onFieldSubmitted: (_) {
                                                FocusScope.of(
                                                  context,
                                                ).requestFocus(_passwordFocus);
                                              },
                                              validator: (v) {
                                                if (v == null ||
                                                    v.trim().isEmpty)
                                                  return 'Please enter email';
                                                if (!_emailRegExp.hasMatch(
                                                  v.trim(),
                                                ))
                                                  return 'Enter a valid email';
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 14),

                                            // Password
                                            _buildTextField(
                                              controller: _passwordController,
                                              focusNode: _passwordFocus,
                                              label: 'Password',
                                              hint: 'Enter your password',
                                              prefix: Icons.lock_outline,
                                              obscureText: !_passwordVisible,
                                              textInputAction:
                                                  TextInputAction.done,
                                              onFieldSubmitted:
                                                  (_) => _handleAuth(),
                                              suffix: IconButton(
                                                onPressed:
                                                    () => setState(
                                                      () =>
                                                          _passwordVisible =
                                                              !_passwordVisible,
                                                    ),
                                                icon: Icon(
                                                  _passwordVisible
                                                      ? Icons
                                                          .visibility_outlined
                                                      : Icons
                                                          .visibility_off_outlined,
                                                  color: Colors.white70,
                                                ),
                                                tooltip:
                                                    _passwordVisible
                                                        ? 'Hide password'
                                                        : 'Show password',
                                              ),
                                              validator: (v) {
                                                if (v == null || v.isEmpty)
                                                  return 'Please enter password';
                                                if (v.length < 6)
                                                  return 'Password should be at least 6 characters';
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 16),

                                            // Signup extra fields
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              switchInCurve: Curves.easeOut,
                                              child:
                                                  _isSignup
                                                      ? Column(
                                                        key: const ValueKey(
                                                          'signup',
                                                        ),
                                                        children: [
                                                          _buildTextField(
                                                            controller:
                                                                _nameController,
                                                            focusNode:
                                                                _nameFocus,
                                                            label: 'Full Name',
                                                            hint: 'John Doe',
                                                            prefix:
                                                                Icons
                                                                    .person_outline,
                                                            textInputAction:
                                                                TextInputAction
                                                                    .next,
                                                            onFieldSubmitted:
                                                                (
                                                                  _,
                                                                ) => FocusScope.of(
                                                                  context,
                                                                ).requestFocus(
                                                                  _phoneFocus,
                                                                ),
                                                            validator: (v) {
                                                              if (v == null ||
                                                                  v
                                                                      .trim()
                                                                      .isEmpty)
                                                                return 'Please enter your full name';
                                                              return null;
                                                            },
                                                          ),
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          _buildTextField(
                                                            controller:
                                                                _phoneController,
                                                            focusNode:
                                                                _phoneFocus,
                                                            label:
                                                                'Phone Number',
                                                            hint:
                                                                '+1 234 567 890',
                                                            prefix:
                                                                Icons
                                                                    .phone_outlined,
                                                            keyboardType:
                                                                TextInputType
                                                                    .phone,
                                                            textInputAction:
                                                                TextInputAction
                                                                    .next,
                                                            onFieldSubmitted: (
                                                              _,
                                                            ) {
                                                              // move to role or done
                                                              FocusScope.of(
                                                                context,
                                                              ).unfocus();
                                                            },
                                                            validator: (v) {
                                                              if (v == null ||
                                                                  v
                                                                      .trim()
                                                                      .isEmpty)
                                                                return 'Please enter phone number';
                                                              // optional: add phone pattern check if you want
                                                              return null;
                                                            },
                                                          ),
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          // Role Dropdown
                                                          // Around line 450, replace the DropdownButtonFormField items with:
                                                          DropdownButtonFormField<String>(
                                                            value: _role,
                                                            dropdownColor: primaryNavy,
                                                            decoration: _inputDecoration(
                                                              label: 'Role',
                                                              prefix: Icons.badge_outlined,
                                                            ),
                                                            onChanged: (val) => setState(() => _role = val ?? 'passenger'),
                                                            items: ['passenger', 'driver']  // 🔒 Removed 'admin'
                                                                .map(
                                                                  (r) => DropdownMenuItem(
                                                                value: r,
                                                                child: Text(
                                                                  _capitalize(r),
                                                                  style: theme.textTheme.bodyLarge,
                                                                ),
                                                              ),
                                                            )
                                                                .toList(),
                                                          ),
                                                          // DropdownButtonFormField<
                                                          //   String
                                                          // >(
                                                          //   value: _role,
                                                          //   dropdownColor:
                                                          //       primaryNavy,
                                                          //   decoration:
                                                          //       _inputDecoration(
                                                          //         label: 'Role',
                                                          //         prefix:
                                                          //             Icons
                                                          //                 .badge_outlined,
                                                          //       ),
                                                          //   onChanged:
                                                          //       (
                                                          //         val,
                                                          //       ) => setState(
                                                          //         () =>
                                                          //             _role =
                                                          //                 val ??
                                                          //                 'passenger',
                                                          //       ),
                                                          //   items:
                                                          //       [
                                                          //             'passenger',
                                                          //             'driver',
                                                          //           ]
                                                          //           .map(
                                                          //             (
                                                          //               r,
                                                          //             ) => DropdownMenuItem(
                                                          //               value:
                                                          //                   r,
                                                          //               child: Text(
                                                          //                 _capitalize(
                                                          //                   r,
                                                          //                 ),
                                                          //                 style:
                                                          //                     theme.textTheme.bodyLarge,
                                                          //               ),
                                                          //             ),
                                                          //           )
                                                          //           .toList(),
                                                          // ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                        ],
                                                      )
                                                      : const SizedBox.shrink(
                                                        key: ValueKey('login'),
                                                      ),
                                            ),

                                            const SizedBox(height: 20),

                                            // Action Button
                                            SizedBox(
                                              width: double.infinity,
                                              height: 56,
                                              child: ElevatedButton(
                                                onPressed:
                                                    _isLoading
                                                        ? null
                                                        : _handleAuth,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      secondaryNavy,
                                                  foregroundColor: textWhite,
                                                  elevation: 6,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child:
                                                    _isLoading
                                                        ? const SizedBox(
                                                          height: 24,
                                                          width: 24,
                                                          child:
                                                              CircularProgressIndicator(
                                                                color:
                                                                    textWhite,
                                                                strokeWidth: 2,
                                                              ),
                                                        )
                                                        : Text(
                                                          _isSignup
                                                              ? 'Create account'
                                                              : 'Sign in',
                                                          style:
                                                              theme
                                                                  .textTheme
                                                                  .titleLarge,
                                                        ),
                                              ),
                                            ),

                                            const SizedBox(height: 12),

                                            // Toggle SignUp / SignIn
                                            TextButton(
                                              onPressed:
                                                  () => setState(
                                                    () =>
                                                        _isSignup = !_isSignup,
                                                  ),
                                              child: RichText(
                                                text: TextSpan(
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Colors.white70,
                                                  ),
                                                  children: [
                                                    TextSpan(
                                                      text:
                                                          _isSignup
                                                              ? 'Already have an account? '
                                                              : "Don't have an account? ",
                                                    ),
                                                    TextSpan(
                                                      text:
                                                          _isSignup
                                                              ? 'Sign in'
                                                              : 'Sign up',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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
            ),
          ),
        ),
      ),
    );
  }

  // Reusable text field builder
  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    String? hint,
    IconData? prefix,
    Widget? suffix,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      cursorColor: Colors.white,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: const TextStyle(color: textWhite),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        prefix: prefix,
        suffix: suffix,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white54),
      prefixIcon: prefix != null ? Icon(prefix, color: secondaryNavy) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: secondaryNavy, width: 2),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
