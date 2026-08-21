import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../utils/environment_config.dart';

class AuthService extends ChangeNotifier {
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  AuthService() {
    _token = null;
    _currentUser = null;
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadFromStorage();
      _isInitialized = true;
    } catch (e) {
      debugPrint('AuthService.init error: $e');
    }
    notifyListeners();
  }

  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }

  Future<void> _saveCredentials() async {
    // Ensure we have prefs before saving
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      if (_prefs == null) return;
    }
    await _prefs!.setString('auth_token', _token!);
    await _prefs!.setString('user_id', _currentUser?.id ?? '');
    await _prefs!.setString('current_user', jsonEncode(_currentUser!.toJson()));
  }

  Future<void> _saveRememberedCredentials(String username, String password, bool rememberMe) async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      if (_prefs == null) return;
    }
    if (rememberMe) {
      await _prefs!.setString('remembered_username', username);
      await _prefs!.setBool('remember_me', true);
    } else {
      await _prefs!.remove('remembered_username');
      await _prefs!.remove('remember_me');
    }
  }

  String? _rememberedUsername;
  bool get rememberMe => _prefs?.getBool('remember_me') ?? false;
  String? get rememberedUsername => _rememberedUsername ??= _prefs?.getString('remembered_username');

  void clearError() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  /// Backwards-compatible alias used by some tests and callers
  void clearErrorMessage() => clearError();

  User? _currentUser;
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  bool get isAuthenticated => _token != null && _currentUser != null;

  void _loadFromStorage() {
    if (_prefs == null) return;
    try {
      final tokenJson = _prefs!.getString('auth_token');
      final userJson = _prefs!.getString('current_user');
      
      if (tokenJson != null && userJson != null) {
        _token = tokenJson;
        _currentUser = User.fromJson(jsonDecode(userJson));
      }
    } catch (e) {
      debugPrint('AuthService._loadFromStorage error: $e');
      _token = null;
      _currentUser = null;
    }
  }

  // Pending 2FA temp token (set during login when 2FA required)
  String? _pending2faToken;
  String? get pending2faToken => _pending2faToken;

  Future<dynamic> _decodeResponse(http.Response response) async {
    final contentType = response.headers['content-type'] ?? '';
    final trimmedBody = response.body.trimLeft();

    if (!contentType.toLowerCase().contains('application/json')) {
      if (trimmedBody.startsWith('<')) {
        throw Exception('Unexpected non-JSON response from server: ${response.statusCode}. Response begins with HTML.');
      }
      if (trimmedBody.isEmpty) {
        throw Exception('Empty response body from server: ${response.statusCode}');
      }
    }

    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw Exception('Failed to decode JSON response (${response.statusCode}): ${response.body.length > 256 ? response.body.substring(0, 256) + '...' : response.body}');
    }
  }

  Future<bool> login(String username, String password, {bool rememberMe = false}) async {
    await ensureInitialized();
    _isLoading = true;
    _errorMessage = null;
    _pending2faToken = null;
    notifyListeners();

    try {
      if (username.isEmpty || password.isEmpty) {
        throw Exception('Username and password are required');
      }

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/user/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': username, 'password': password}),
      ).timeout(const Duration(seconds: 15));

      final data = await _decodeResponse(response);

      if (response.statusCode == 200) {
        if (data['success'] == true) {
          if (data['requires_2fa'] == true) {
            _pending2faToken = data['temp_token'];
            _isLoading = false;
            notifyListeners();
            return true;
          }

          _token = data['session_token'];
          _currentUser = User(
            id: data['user_id'] ?? '0',
            username: username,
            email: data['email'] ?? '$username@zwesta.com',
            firstName: data['name']?.split(' ')[0] ?? 'Trading',
            lastName: data['name']?.split(' ').length > 1 ? data['name'].split(' ')[1] : 'User',
            accountType: 'Premium',
          );

          await _saveCredentials();
          _isLoading = false;
          notifyListeners();
          return true;
        }

        throw Exception(data['error'] ?? 'Login failed');
      }

      throw Exception(data['error'] ?? 'Login failed with code ${response.statusCode}');
    } catch (e) {
      _errorMessage = 'Login Error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 2FA/MFA verification
  Future<bool> verifyMfaCode(String? tempToken, String code) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/user/verify-2fa'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'temp_token': tempToken, 'code': code}),
      ).timeout(const Duration(seconds: 10));

      final data = await _decodeResponse(response);

      if (response.statusCode == 200) {
        if (data['success'] == true) {
          _token = data['session_token'];
          _currentUser = User(
            id: data['user_id'] ?? '0',
            username: data['email'] ?? '',
            email: data['email'] ?? '',
            firstName: data['name']?.split(' ')[0] ?? 'Trading',
            lastName: data['name']?.split(' ').length > 1 ? data['name'].split(' ')[1] : 'User',
            accountType: 'Premium',
          );
          await _saveCredentials();
          _isLoading = false;
          notifyListeners();
          return true;
        }

        throw Exception(data['error'] ?? '2FA verification failed');
      }

      throw Exception(data['error'] ?? '2FA failed with code ${response.statusCode}');
    } catch (e) {
      _errorMessage = '2FA Error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> resendMfaCode(String? tempToken) async {
    try {
      await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/user/resend-2fa'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'temp_token': tempToken}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  // Register function
  Future<bool> register(String username, String email, String password, 
      String firstName, String lastName, {String referralCode = ''}) async {
    await ensureInitialized();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (username.isEmpty || email.isEmpty || password.isEmpty) {
        throw Exception('All fields are required');
      }

      final body = {
        'name': '$firstName $lastName',
        'email': email,
        'username': username,
        'password': password,
      };
      if (referralCode.isNotEmpty) {
        body['referrer_code'] = referralCode;
      }

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/user/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      final data = await _decodeResponse(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final returnedToken = data['session_token'];
        if (returnedToken == null || returnedToken.toString().isEmpty) {
          throw Exception('Registration succeeded but no session token was returned by the backend');
        }

        _token = returnedToken;
        _currentUser = User(
          id: data['user_id'] ?? '${DateTime.now().millisecondsSinceEpoch}',
          username: username,
          email: email,
          firstName: firstName,
          lastName: lastName,
          accountType: 'Standard',
        );

        final referralCode = data['referral_code'] ?? '';
          await _saveCredentials();
          await _saveRememberedCredentials(username, password, rememberMe);
          _isLoading = false;
        _errorMessage = null;
        _successMessage = 'Registration successful! Your referral code: $referralCode';
        notifyListeners();
        return true;
      } else {
        throw Exception(data['error'] ?? 'Registration failed');
      }
    } catch (e) {
      _errorMessage = 'Registration Error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    if (_prefs != null) {
      await _prefs!.remove('auth_token');
      await _prefs!.remove('current_user');
      await _prefs!.remove('user_id');
      await _prefs!.remove('mt5_account');
      await _prefs!.remove('mt5_server');
      await _prefs!.remove('active_bots');
      await _prefs!.remove('last_bot_sync');
    }
    notifyListeners();
  }

  Future<bool> updateProfile(String firstName, String lastName, String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_currentUser == null || _token == null) throw Exception('User not logged in');

      final response = await http.put(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/user/update-profile'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': _token!,
        },
        body: jsonEncode({
          'name': '$firstName $lastName',
          'email': email,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _currentUser = User(
          id: _currentUser!.id,
          username: _currentUser!.username,
          email: email,
          firstName: firstName,
          lastName: lastName,
          profileImage: _currentUser!.profileImage,
          accountType: _currentUser!.accountType,
        );
        await _prefs!.setString('current_user', jsonEncode(_currentUser!.toJson()));
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        throw Exception(data['error'] ?? 'Profile update failed');
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_token == null) throw Exception('User not logged in');
      if (oldPassword.isEmpty || newPassword.isEmpty) {
        throw Exception('Both passwords are required');
      }
      if (newPassword.length < 6) {
        throw Exception('New password must be at least 6 characters');
      }

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/user/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': _token!,
        },
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        throw Exception(data['error'] ?? 'Password change failed');
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
