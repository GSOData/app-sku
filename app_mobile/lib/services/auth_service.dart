import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_mobile/utils/constants.dart';

/// Modelo do usuário autenticado
class Usuario {
  final int id;
  final String username;
  final String email;
  final String? nomeCompleto;
  final String? telefone;
  final String? cargo;
  final List<dynamic> unidadesAcesso;

  Usuario({
    required this.id,
    required this.username,
    required this.email,
    this.nomeCompleto,
    this.telefone,
    this.cargo,
    this.unidadesAcesso = const [],
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      nomeCompleto: json['nome_completo'],
      telefone: json['telefone'],
      cargo: json['cargo'],
      unidadesAcesso: json['unidades_acesso'] ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'nome_completo': nomeCompleto,
      'telefone': telefone,
      'cargo': cargo,
      'unidades_acesso': unidadesAcesso,
    };
  }
}

/// Serviço de autenticação com ChangeNotifier para gerenciar estado
class AuthService extends ChangeNotifier {
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _accessToken;
  String? _refreshToken;
  Usuario? _usuario;
  String? _errorMessage;

  // Getters
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get accessToken => _accessToken;
  Usuario? get usuario => _usuario;
  String? get errorMessage => _errorMessage;

  /// Inicializa o serviço verificando se há token salvo
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(StorageKeys.accessToken);
      _refreshToken = prefs.getString(StorageKeys.refreshToken);

      if (_accessToken != null) {
        // Carrega dados do usuário salvos
        final userDataStr = prefs.getString(StorageKeys.userData);
        if (userDataStr != null) {
          final userData = jsonDecode(userDataStr);
          _usuario = Usuario.fromJson(userData);
        }

        // Valida se o token ainda é válido tentando acessar /me
        final isValid = await _validateToken();
        _isAuthenticated = isValid;

        if (!isValid) {
          // Tenta renovar o token
          final renewed = await _refreshAccessToken();
          _isAuthenticated = renewed;
        }
      }
    } catch (e) {
      debugPrint('Erro ao inicializar AuthService: $e');
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Realiza login com username e password
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${Constants.apiUrl}auth/login/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _accessToken = data['access'];
        _refreshToken = data['refresh'];
        _usuario = Usuario.fromJson(data['usuario']);
        _isAuthenticated = true;

        // Salva tokens e dados do usuário
        await _saveTokens();

        _isLoading = false;
        notifyListeners();
        return true;
      } else if (response.statusCode == 401) {
        _errorMessage = 'Usuário ou senha inválidos';
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Erro ao realizar login';
      }
    } catch (e) {
      debugPrint('Erro no login: $e');
      _errorMessage = 'Erro de conexão. Verifique sua internet.';
    }

    _isLoading = false;
    _isAuthenticated = false;
    notifyListeners();
    return false;
  }

  /// Realiza logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Tenta invalidar o token no backend
      if (_accessToken != null && _refreshToken != null) {
        await http.post(
          Uri.parse('${Constants.apiUrl}auth/logout/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: jsonEncode({
            'refresh': _refreshToken,
          }),
        );
      }
    } catch (e) {
      debugPrint('Erro ao fazer logout no servidor: $e');
    }

    // Limpa dados locais
    await _clearTokens();

    _accessToken = null;
    _refreshToken = null;
    _usuario = null;
    _isAuthenticated = false;
    _isLoading = false;
    notifyListeners();
  }

  /// Valida se o token atual é válido
  Future<bool> _validateToken() async {
    if (_accessToken == null) return false;

    try {
      final response = await http.get(
        Uri.parse('${Constants.apiUrl}auth/me/'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _usuario = Usuario.fromJson(data);
        return true;
      }
    } catch (e) {
      debugPrint('Erro ao validar token: $e');
    }

    return false;
  }

  /// Renova o access token usando o refresh token
  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('${Constants.apiUrl}auth/token/refresh/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refresh': _refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access'];

        // Salva o novo token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageKeys.accessToken, _accessToken!);

        return true;
      }
    } catch (e) {
      debugPrint('Erro ao renovar token: $e');
    }

    return false;
  }

  /// Salva tokens no SharedPreferences
  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (_accessToken != null) {
      await prefs.setString(StorageKeys.accessToken, _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString(StorageKeys.refreshToken, _refreshToken!);
    }
    if (_usuario != null) {
      await prefs.setString(
        StorageKeys.userData,
        jsonEncode(_usuario!.toJson()),
      );
    }
  }

  /// Remove tokens do SharedPreferences
  Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.accessToken);
    await prefs.remove(StorageKeys.refreshToken);
    await prefs.remove(StorageKeys.userData);
  }

  /// Retorna headers de autenticação para requisições
  Map<String, String> get authHeaders {
    return {
      'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }
}
