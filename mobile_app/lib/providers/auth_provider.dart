import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/e2ee/e2ee_api.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  final CryptoService _cryptoService = CryptoService();
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;
  SocketService get socketService => _socketService;
  
  String? _token;
  String? get token => _token;

  void updateUser(Map<String, dynamic> updatedUser) {
    if (_user != null) {
      _user = {..._user!, ...updatedUser};
    } else {
      _user = updatedUser;
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('cached_user_data', jsonEncode(_user));
    }).catchError((_) {});
    notifyListeners();
  }

  Future<bool> tryAutoLogin() async {
    final tkn = await _apiService.getToken();
    if (tkn == null) return false;
    
    try {
      final parts = tkn.split('.');
      if (parts.length != 3) return false;
      
      String payload = parts[1];
      int padding = payload.length % 4;
      if (padding != 0) {
        payload += '=' * (4 - padding);
      }
      
      final decodedPayload = utf8.decode(base64Url.decode(payload));
      final payloadMap = jsonDecode(decodedPayload);
      final userId = payloadMap['id'];
      
      // Check token expiry first
      if (payloadMap['exp'] != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(payloadMap['exp'] * 1000);
        if (DateTime.now().isAfter(expiry)) {
          // Token truly expired — clear it
          await _apiService.logout();
          return false;
        }
      }

      // Immediate local cache hydration for sub-millisecond app launch
      final prefs = await SharedPreferences.getInstance();
      final cachedUserStr = prefs.getString('cached_user_data');
      if (cachedUserStr != null) {
        try {
          final cachedUser = jsonDecode(cachedUserStr) as Map<String, dynamic>;
          _isAuthenticated = true;
          _user = cachedUser;
          _token = tkn;
          notifyListeners();
          _socketService.connect(_user!['id']);
          _setupSocketListeners();

          // Non-blocking background revalidation
          _apiService.getUserById(userId).then((userData) async {
            if (userData != null) {
              _user = userData;
              await prefs.setString('cached_user_data', jsonEncode(userData));
              await _saveAccountToDevice(_user!, _token!);
              notifyListeners();
            }
          }).catchError((_) {});
          return true;
        } catch (_) {}
      }

      // If no local cache yet, construct immediate offline user from token payload (0ms instant boot)
      final immediateUser = {
        'id': userId,
        '_id': userId,
        'username': payloadMap['username'] ?? 'User',
        'email': payloadMap['email'] ?? '',
      };
      _isAuthenticated = true;
      _user = immediateUser;
      _token = tkn;
      _socketService.connect(userId);
      _setupSocketListeners();
      notifyListeners();

      // Non-blocking background revalidation with server
      _apiService.getUserById(userId).then((userData) async {
        if (userData != null) {
          _user = userData;
          await prefs.setString('cached_user_data', jsonEncode(userData));
          await _saveAccountToDevice(_user!, _token!);
          notifyListeners();
        }
      }).catchError((_) {});
      return true;

      // If token was cleared (e.g. 401/403 Access Denied), do not fallback to cached login
      final validToken = await _apiService.getToken();
      if (validToken == null) return false;

      // Fallback: if cached user data was available with a valid token
      final fallbackUserStr = prefs.getString('cached_user_data');
      if (fallbackUserStr != null) {
        final cachedUser = jsonDecode(fallbackUserStr) as Map<String, dynamic>;
        _isAuthenticated = true;
        _user = cachedUser;
        _token = validToken;
        await _saveAccountToDevice(_user!, _token!);
        await _socketService.connect(_user!['id']);
        _setupSocketListeners();
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("Auto login error: $e");
      // On any error, try cached user data before giving up
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedUserStr = prefs.getString('cached_user_data');
        final tkn2 = await _apiService.getToken();
        if (cachedUserStr != null && tkn2 != null) {
          final cachedUser = jsonDecode(cachedUserStr) as Map<String, dynamic>;
          _isAuthenticated = true;
          _user = cachedUser;
          _token = tkn2;
          await _socketService.connect(_user!['id']);
          _setupSocketListeners();
          notifyListeners();
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  bool _requiresTwoStep = false;
  bool get requiresTwoStep => _requiresTwoStep;
  String? _pendingTwoStepEmail;
  String? get pendingTwoStepEmail => _pendingTwoStepEmail;
  bool _hasPendingTwoStepReset = false;
  bool get hasPendingTwoStepReset => _hasPendingTwoStepReset;
  DateTime? _pendingTwoStepResetDate;
  DateTime? get pendingTwoStepResetDate => _pendingTwoStepResetDate;
  bool _needsPasswordSetup = false;
  bool get needsPasswordSetup => _needsPasswordSetup;

  Future<Map<String, dynamic>> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    _requiresTwoStep = false;
    _pendingTwoStepEmail = null;
    _hasPendingTwoStepReset = false;
    _needsPasswordSetup = false;
    notifyListeners();

    final result = await _apiService.login(email, password);

    if (result['success'] == true) {
      _isAuthenticated = true;
      _user = result['data']['user'];
      _token = result['data']['token'];
      await _saveAccountToDevice(_user!, _token!);
      await _socketService.connect(_user!['id']);
      _setupSocketListeners();
      // Initialize E2EE keys in the background
      _initializeE2EE(_user!['id'], _token!);
    } else if (result['needsPasswordSetup'] == true) {
      _isAuthenticated = false;
      _needsPasswordSetup = true;
      _errorMessage = result['message'];
    } else if (result['requiresTwoStep'] == true) {
      _isAuthenticated = false;
      _requiresTwoStep = true;
      _pendingTwoStepEmail = email;
      _hasPendingTwoStepReset = result['hasPendingReset'] ?? false;
      _errorMessage = result['message'];
    } else {
      _isAuthenticated = false;
      _errorMessage = result['message'];
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Map<String, dynamic>> setPassword({
    required String email,
    required String newPassword,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.setAccountPassword(email: email, newPassword: newPassword);

    if (result['success'] == true) {
      _isAuthenticated = true;
      _needsPasswordSetup = false;
      _user = result['data']['user'];
      _token = result['data']['token'];
      await _saveAccountToDevice(_user!, _token!);
      await _socketService.connect(_user!['id']);
      _setupSocketListeners();
      _initializeE2EE(_user!['id'], _token!);
    } else {
      _isAuthenticated = false;
      _errorMessage = result['message'];
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Map<String, dynamic>> completeTwoStepLogin({
    required String email,
    required String pin,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.verifyTwoStepLogin(email: email, pin: pin);

    if (result['success'] == true) {
      _isAuthenticated = true;
      _requiresTwoStep = false;
      _pendingTwoStepEmail = null;
      _hasPendingTwoStepReset = false;
      _user = result['data']['user'];
      _token = result['data']['token'];
      await _saveAccountToDevice(_user!, _token!);
      await _socketService.connect(_user!['id']);
      _setupSocketListeners();
      _initializeE2EE(_user!['id'], _token!);
    } else {
      _isAuthenticated = false;
      _errorMessage = result['message'];
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<void> loginWithGoogle({
    required String email,
    String? displayName,
    String? googleId,
    String? avatarUrl,
    String? idToken,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.googleLogin(
      email: email,
      displayName: displayName,
      googleId: googleId,
      avatarUrl: avatarUrl,
      idToken: idToken,
    );

    if (result['requiresTwoStep'] == true) {
      _requiresTwoStep = true;
      _pendingTwoStepEmail = result['email'] ?? email;
      _hasPendingTwoStepReset = result['hasPendingReset'] ?? false;
      _pendingTwoStepResetDate = result['resetRequestedAt'] != null
          ? DateTime.tryParse(result['resetRequestedAt'])
          : null;
      _isAuthenticated = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (result['success']) {
      _isAuthenticated = true;
      _requiresTwoStep = false;
      _pendingTwoStepEmail = null;
      _hasPendingTwoStepReset = false;
      _pendingTwoStepResetDate = null;
      _user = result['data']['user'];
      _token = result['data']['token'];
      await _saveAccountToDevice(_user!, _token!);
      await _socketService.connect(_user!['id']);
      _setupSocketListeners();
      _initializeE2EE(_user!['id'], _token!);
    } else {
      _isAuthenticated = false;
      _errorMessage = result['message'];
    }

    _isLoading = false;
    notifyListeners();
  }


  Future<void> register(String email, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.register(email, username, password);

    if (result['success']) {
      _isAuthenticated = true;
      _user = result['data']['user'];
      _token = result['data']['token'];
      await _saveAccountToDevice(_user!, _token!);
      await _socketService.connect(_user!['id']);
      _setupSocketListeners();
      // Initialize E2EE keys in the background
      _initializeE2EE(_user!['id'], _token!);
    } else {
      _isAuthenticated = false;
      _errorMessage = result['message'];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Saves or updates the account in the saved accounts list on this device
  Future<void> _saveAccountToDevice(Map<String, dynamic> user, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getString('saved_device_accounts');
      List<dynamic> accounts = [];
      if (rawList != null) {
        try {
          accounts = jsonDecode(rawList);
        } catch (_) {}
      }

      final userId = (user['id'] ?? user['_id'])?.toString();
      if (userId == null) return;

      accounts.removeWhere((a) => (a['id'] ?? a['userData']?['id'])?.toString() == userId);
      accounts.insert(0, {
        'id': userId,
        'username': user['username'] ?? 'User',
        'email': user['email'] ?? '',
        'phoneNumber': user['phoneNumber'] ?? '',
        'avatarUrl': user['avatarUrl'],
        'token': token,
        'userData': user,
        'lastActive': DateTime.now().toIso8601String(),
      });

      await prefs.setString('saved_device_accounts', jsonEncode(accounts));
    } catch (e) {
      debugPrint('Error saving account to device: $e');
    }
  }

  /// Get list of all accounts saved on this device
  Future<List<Map<String, dynamic>>> getSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getString('saved_device_accounts');
      if (rawList != null) {
        final List<dynamic> decoded = jsonDecode(rawList);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Switch to a previously saved account instantly
  Future<bool> switchAccount(Map<String, dynamic> targetAccount) async {
    try {
      final targetToken = targetAccount['token']?.toString();
      final targetUserData = targetAccount['userData'] != null 
          ? Map<String, dynamic>.from(targetAccount['userData'])
          : null;

      if (targetToken == null || targetUserData == null) return false;

      _isLoading = true;
      notifyListeners();

      // Disconnect current socket
      _socketService.disconnect();

      // Save token and cached user data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', targetToken);
      await prefs.setString('cached_user_data', jsonEncode(targetUserData));

      _token = targetToken;
      _user = targetUserData;
      _isAuthenticated = true;

      // Update lastActive in saved accounts list
      await _saveAccountToDevice(_user!, _token!);

      // Connect socket with new user id
      await _socketService.connect(_user!['id']);
      _setupSocketListeners();
      _initializeE2EE(_user!['id'], _token!);

      // Refresh full profile in background
      try {
        final profile = await _apiService.getProfile();
        if (profile != null) {
          _user = profile;
          await prefs.setString('cached_user_data', jsonEncode(profile));
          await _saveAccountToDevice(_user!, _token!);
        }
      } catch (_) {}

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Switch account error: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Remove a saved account from the device
  Future<void> removeSavedAccount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getString('saved_device_accounts');
      if (rawList != null) {
        List<dynamic> accounts = jsonDecode(rawList);
        accounts.removeWhere((a) => (a['id'] ?? a['userData']?['id'])?.toString() == userId);
        await prefs.setString('saved_device_accounts', jsonEncode(accounts));
      }
    } catch (_) {}
  }

  void _setupSocketListeners() {
    _socketService.onProfileUpdated((data) {
      if (data['user'] != null && _user != null && data['user']['id'] == _user!['id']) {
        _user = data['user'];
        _saveAccountToDevice(_user!, _token!);
        notifyListeners();
      }
    });
  }

  /// Generates E2EE keys on first run and uploads the public key bundle to the server.
  Future<void> _initializeE2EE(String userId, String token) async {
    try {
      final hasKeys = await _cryptoService.hasKeys();
      if (!hasKeys) {
        final keyBundle = await _cryptoService.generateAndStoreAllKeys(userId);
        await E2EEApi.uploadKeys(keyBundle, token);
        print('✅ E2EE keys generated and uploaded.');
      } else {
        print('✅ E2EE keys already exist.');
      }
    } catch (e) {
      print('⚠️ E2EE initialization failed: $e');
    }
  }

  Future<void> logout() async {
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '135176717661-ugfua55saob2pfm6er1f8o9bunubhdsp.apps.googleusercontent.com',
      );
      await googleSignIn.signOut();
    } catch (_) {}
    await _apiService.logout();
    // Remove current user from active session but keep in saved accounts
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('cached_user_data');
    _socketService.disconnect();
    _isAuthenticated = false;
    _user = null;
    _token = null;
    notifyListeners();
  }

  /// Mandatory Google Play Policy: Delete user account on backend and wipe all local keys & sessions
  Future<bool> deleteAccountAndWipeLocalData() async {
    if (_token == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      final success = await _apiService.deleteAccount(_token!);
      if (success) {
        if (_user?['id'] != null) {
          await removeSavedAccount(_user!['id'].toString());
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('jwt_token');
        await prefs.remove('cached_user_data');
        _socketService.disconnect();
        _isAuthenticated = false;
        _user = null;
        _token = null;
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Delete account error: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}

