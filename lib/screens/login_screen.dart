import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../widgets/logo_widget.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _mfaController;
  bool _obscurePassword = true;
  bool _isLogin = true;
  bool _showForgotPassword = false;
  bool _showMfaPrompt = false;
  String? _pendingSessionToken;
  late TextEditingController _emailController;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _referralCodeController;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _mfaController = TextEditingController();
    _emailController = TextEditingController();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _referralCodeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRememberedUsername();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show forgot password screen
    if (_showForgotPassword) {
      return ForgotPasswordScreen(
        onBackToLogin: () {
          setState(() => _showForgotPassword = false);
        },
      );
    }

    final loc = AppLocalizations.of(context)!;
    try {
      return Scaffold(
        appBar: null,
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0E21), Color(0xFF1A1F3A), Color(0xFF0A0E21)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // Logo and Title
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                          const LogoWidget(size: 120, showText: false),
                          const SizedBox(height: 16),
                          Text(
                            'ZWESTA XM',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'TRADING SYSTEM',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 12,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Broker strip — shows users which brokers we trade on.
                          Text(
                            'AUTO-TRADES ON',
                            style: GoogleFonts.poppins(
                              color: Colors.white54,
                              fontSize: 9.5,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _loginBrokerChip('B', 'Binance', const Color(0xFFF3BA2F)),
                              _loginBrokerChip('E', 'Exness', const Color(0xFF00E5FF)),
                              _loginBrokerChip('F', 'FXCM', const Color(0xFF7C4DFF)),
                              _loginBrokerChip('L', 'Luno', const Color(0xFF6C4CFF)),
                            ],
                          ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                  
                  // Welcome Back heading (only on login)
                  Text(
                    _isLogin && !_showMfaPrompt ? 'Welcome Back' : (!_isLogin ? 'Create Account' : 'Two-Factor Authentication'),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),

                  Consumer<AuthService>(
                    builder: (context, authService, _) {
                      final successMsg = authService.successMessage;
                      final errorMsg = authService.errorMessage;
                      final showSuccess = successMsg != null && successMsg.isNotEmpty;
                      final showError = !showSuccess && errorMsg != null && errorMsg.isNotEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showSuccess)
                            _StatusBanner(
                              icon: Icons.check_circle_outline,
                              color: const Color(0xFF00E676),
                              message: successMsg,
                              onDismiss: () => authService.clearError(),
                            ),
                          if (showError)
                            _StatusBanner(
                              icon: Icons.error_outline,
                              color: const Color(0xFFFF5252),
                              message: errorMsg,
                              onDismiss: () => authService.clearError(),
                            ),
                        ],
                      );
                    },
                  ),

                  if (_showMfaPrompt)
                    _buildMfaForm(loc)
                  else
                    _buildLoginRegisterForm(loc),
                ],
              ),
            ),
          ),
        ),
        bottomSheet: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'v1.0.0',
            style: GoogleFonts.poppins(color: Colors.white30, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (e, st) {
      print('LoginScreen build error: $e\n$st');
      return Scaffold(
        body: Center(child: Text('Login error: $e')),
      );
    }
  }

  Widget _StatusBanner({
    required IconData icon,
    required Color color,
    required String message,
    required VoidCallback onDismiss,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: Colors.white70, size: 18),
          ),
        ],
      ),
    );
  }

  // Build MFA/2FA form
  Widget _buildMfaForm(AppLocalizations loc) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 2FA code sent to your email.',
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _mfaController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, letterSpacing: 2),
          cursorColor: Colors.white,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: GoogleFonts.poppins(color: Colors.white30, fontSize: 18),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 32),
        Consumer<AuthService>(
          builder: (context, authService, _) => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
                onPressed: authService.isLoading ? null : _verifyMfaCode,
                child: authService.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        'Verify Code',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _resendMfaCode,
            child: Text(
              'Resend Code',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
            ),
          ),
        ),
      ],
    );

  // Compact broker chip used on the login page brand strip.
  Widget _loginBrokerChip(String icon, String label, Color color) {
    final assetName = 'assets/images/${label.toLowerCase()}.png';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.55)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              assetName,
              width: 22,
              height: 22,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: color),
                ),
                child: Text(
                  icon,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Auto-fill remembered username on init
  Future<void> _loadRememberedUsername() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.ensureInitialized();
    final remembered = authService.rememberedUsername;
    if (remembered != null && remembered.isNotEmpty) {
      _usernameController.text = remembered;
      _rememberMe = true;
      if (mounted) setState(() {});
    }
  }

  // Build login/register form
  Widget _buildLoginRegisterForm(AppLocalizations loc) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isLogin) ...[
          // Registration fields
          TextField(
            controller: _firstNameController,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'First Name',
              hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 15),
              prefixIcon: const Icon(Icons.person, color: Colors.white70, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lastNameController,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Last Name',
              hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 15),
              prefixIcon: const Icon(Icons.person, color: Colors.white70, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Email',
              hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 15),
              prefixIcon: const Icon(Icons.email, color: Colors.white70, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
          ),
          const SizedBox(height: 16),
          // Referral Code (optional)
          TextField(
            controller: _referralCodeController,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
            cursorColor: Colors.white,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Referral Code (optional)',
              hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 15),
              prefixIcon: const Icon(Icons.card_giftcard, color: Colors.white70, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Username field
        TextField(
          controller: _usernameController,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Username',
            hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 15),
            prefixIcon: const Icon(Icons.person, color: Colors.white70, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
        ),
        const SizedBox(height: 16),

        // Password field
        TextField(
          controller: _passwordController,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
          cursorColor: Colors.white,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 15),
            prefixIcon: const Icon(Icons.lock, color: Colors.white70, size: 20),
            suffixIcon: GestureDetector(
              onTap: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              child: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white70,
                size: 20,
              ),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
        ),
        const SizedBox(height: 40),

        // Submit Button
        Consumer<AuthService>(
          builder: (context, authService, _) => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
                onPressed: authService.isLoading ? null : _handleSubmit,
                child: authService.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        _isLogin ? 'Login' : 'Create Account',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
        ),
        const SizedBox(height: 28),

        // Toggle login/register
        Center(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: _isLogin ? "Don't have an account? " : 'Already have an account? ',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                ),
                TextSpan(
                  text: _isLogin ? 'Register' : 'Login',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      setState(() => _isLogin = !_isLogin);
                    },
                ),
              ],
            ),
          ),
        ),

        // Forgot password
        if (_isLogin)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => _showForgotPassword = true);
                },
                child: Text(
                  'Forgot Password?',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),

        // Remember me checkbox
        if (_isLogin)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (v) => setState(() => _rememberMe = v ?? false),
                  fillColor: MaterialStateProperty.resolveWith((s) => Colors.white),
                ),
                Text(
                  'Remember me',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );

  // Handle login/register submission
  void _handleSubmit() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    if (_isLogin) {
      // Ensure auth service is initialized before login
      await authService.ensureInitialized();
      final success = await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
        rememberMe: _rememberMe,
      );
      if (success && mounted) {
        // Check if 2FA is required
        if (authService.pending2faToken != null) {
          setState(() {
            _pendingSessionToken = authService.pending2faToken;
            _showMfaPrompt = true;
          });
        }
        // If no 2FA, auth service already set the token — 
        // the Consumer/listener navigates automatically
      }
    } else {
      final success = await authService.register(
        _usernameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
        _firstNameController.text.trim(),
        _lastNameController.text.trim(),
        referralCode: _referralCodeController.text.trim(),
      );
      if (success && mounted) {
        setState(() => _isLogin = true);
      }
    }
  }

  // Verify 2FA/MFA code
  void _verifyMfaCode() async {
    final code = _mfaController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 2FA code')),
      );
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final success = await authService.verifyMfaCode(_pendingSessionToken, code);
    
    if (success && mounted) {
      setState(() {
        _showMfaPrompt = false;
        _mfaController.clear();
        _pendingSessionToken = null;
      });
    }
  }

  // Resend 2FA code
  void _resendMfaCode() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.resendMfaCode(_pendingSessionToken);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA code resent to your email')),
      );
    }
  }
}
