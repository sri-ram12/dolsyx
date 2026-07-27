import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  
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
      
      final userData = await _apiService.getUserById(userId);
      if (userData != null) {
        _isAuthenticated = true;
        _user = userData;
        _token = tkn;
        await _socketService.connect(_user!['id']);
        _setupSocketListeners();
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("Auto login error: $e");
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

  Future<void> logout() async {
    await _apiService.logout();
    _socketService.disconnect();
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
