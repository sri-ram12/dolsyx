import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    _user = updatedUser;
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

      // Try to fetch fresh user data from server
      final userData = await _apiService.getUserById(userId);
      if (userData != null) {
        _isAuthenticated = true;
        _user = userData;
        _token = tkn;
        // Cache user data for offline use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_data', jsonEncode(userData));
        await _socketService.connect(_user!['id']);
        _setupSocketListeners();
        notifyListeners();
        return true;
      }

      // Network failed — try cached user data
      final prefs = await SharedPreferences.getInstance();
      final cachedUserStr = prefs.getString('cached_user_data');
      if (cachedUserStr != null) {
        final cachedUser = jsonDecode(cachedUserStr) as Map<String, dynamic>;
        _isAuthenticated = true;
        _user = cachedUser;
        _token = tkn;
        // Don't connect socket (no network), just restore the session
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
          notifyListeners();
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.login(email, password);

    if (result['success']) {
      _isAuthenticated = true;
      _user = result['data']['user'];
      _token = result['data']['token'];
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

  Future<void> register(String email, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.register(email, username, password);

    if (result['success']) {
      _isAuthenticated = true;
      _user = result['data']['user'];
      _token = result['data']['token'];
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

  void _setupSocketListeners() {
    _socketService.onProfileUpdated((data) {
      if (data['user'] != null && _user != null && data['user']['id'] == _user!['id']) {
        _user = data['user'];
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
    await _apiService.logout();
    // Also clear cached user data on explicit logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user_data');
    _socketService.disconnect();
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
