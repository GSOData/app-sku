import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_mobile/utils/constants.dart';

/// Modelo de Unidade de Negócio
class UnidadeNegocio {
  final int id;
  final String codigoUnb;
  final String nome;

  UnidadeNegocio({
    required this.id,
    required this.codigoUnb,
    required this.nome,
  });

  factory UnidadeNegocio.fromJson(Map<String, dynamic> json) {
    return UnidadeNegocio(
      id: json['id'] ?? 0,
      codigoUnb: json['codigo_unb'] ?? '',
      nome: json['nome'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo_unb': codigoUnb,
      'nome': nome,
    };
  }

  @override
  String toString() => '$codigoUnb - $nome';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnidadeNegocio && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

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
  
  // Multi-tenant: Unidade Ativa
  UnidadeNegocio? _unidadeAtiva;
  List<UnidadeNegocio> _unidadesPermitidas = [];

  // Getters
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get accessToken => _accessToken;
  Usuario? get usuario => _usuario;
  String? get errorMessage => _errorMessage;
  
  // Getters Multi-tenant
  UnidadeNegocio? get unidadeAtiva => _unidadeAtiva;
  List<UnidadeNegocio> get unidadesPermitidas => _unidadesPermitidas;
  bool get hasUnidadeAtiva => _unidadeAtiva != null;
  
  /// Query param para concatenar nas URLs de API
  String get unidadeQueryParam => _unidadeAtiva != null 
      ? 'unidade_id=${_unidadeAtiva!.id}' 
      : '';

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
        
        // Carrega unidades permitidas e ativa
        if (_isAuthenticated) {
          await _loadUnidadesPermitidas();
          await _loadUnidadeAtivaSalva(prefs);
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
  
  /// Carrega unidades permitidas do backend ou do usuário
  Future<void> _loadUnidadesPermitidas() async {
    try {
      // Primeiro tenta buscar do endpoint de unidades
      final response = await http.get(
        Uri.parse('${Constants.apiUrl}unidades/'),
        headers: authHeaders,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> unidadesJson;
        
        // Verifica se é paginado ou lista direta
        if (data is Map && data.containsKey('results')) {
          unidadesJson = data['results'] as List;
        } else if (data is List) {
          unidadesJson = data;
        } else {
          unidadesJson = [];
        }
        
        _unidadesPermitidas = unidadesJson
            .map((json) => UnidadeNegocio.fromJson(json))
            .toList();
      }
    } catch (e) {
      debugPrint('Erro ao carregar unidades: $e');
      // Fallback: carrega do usuário se disponível
      if (_usuario != null && _usuario!.unidadesAcesso.isNotEmpty) {
        _unidadesPermitidas = _usuario!.unidadesAcesso
            .map((json) => UnidadeNegocio.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    }
  }
  
  /// Carrega unidade ativa salva no SharedPreferences
  Future<void> _loadUnidadeAtivaSalva(SharedPreferences prefs) async {
    final unidadeStr = prefs.getString(StorageKeys.unidadeAtiva);
    if (unidadeStr != null) {
      try {
        final unidadeJson = jsonDecode(unidadeStr);
        final savedUnidade = UnidadeNegocio.fromJson(unidadeJson);
        
        // Verifica se a unidade salva ainda está nas permitidas
        if (_unidadesPermitidas.any((u) => u.id == savedUnidade.id)) {
          _unidadeAtiva = savedUnidade;
        } else if (_unidadesPermitidas.isNotEmpty) {
          // Se não está mais permitida, seleciona a primeira
          _unidadeAtiva = _unidadesPermitidas.first;
          await _saveUnidadeAtiva();
        }
      } catch (e) {
        debugPrint('Erro ao carregar unidade ativa: $e');
      }
    } else if (_unidadesPermitidas.isNotEmpty) {
      // Se não há unidade salva, seleciona a primeira
      _unidadeAtiva = _unidadesPermitidas.first;
      await _saveUnidadeAtiva();
    }
  }
  
  /// Altera a unidade ativa
  Future<void> setUnidadeAtiva(UnidadeNegocio unidade) async {
    if (!_unidadesPermitidas.any((u) => u.id == unidade.id)) {
      debugPrint('Unidade não permitida: ${unidade.id}');
      return;
    }
    
    _unidadeAtiva = unidade;
    await _saveUnidadeAtiva();
    notifyListeners();
  }
  
  /// Salva unidade ativa no SharedPreferences
  Future<void> _saveUnidadeAtiva() async {
    if (_unidadeAtiva == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StorageKeys.unidadeAtiva,
      jsonEncode(_unidadeAtiva!.toJson()),
    );
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
        
        // Carrega unidades permitidas e seleciona a primeira como ativa
        await _loadUnidadesPermitidas();
        if (_unidadesPermitidas.isNotEmpty && _unidadeAtiva == null) {
          _unidadeAtiva = _unidadesPermitidas.first;
          await _saveUnidadeAtiva();
        }

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
    _unidadeAtiva = null;
    _unidadesPermitidas = [];
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
    await prefs.remove(StorageKeys.unidadeAtiva);
  }

  /// Retorna headers de autenticação para requisições
  Map<String, String> get authHeaders {
    return {
      'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }
}
