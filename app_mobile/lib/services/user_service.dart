import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:app_mobile/utils/constants.dart';
import 'package:app_mobile/services/auth_service.dart';

/// Modelo de Usuário da API
class ApiUsuario {
  final int id;
  final String username;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? nomeCompleto;
  final String? telefone;
  final String? cargo;
  final bool isActive;
  final bool isSuperuser;
  final String maxPapel;
  final List<UsuarioUnidadeVinculo> unidadesAcesso;

  ApiUsuario({
    required this.id,
    required this.username,
    required this.email,
    this.firstName,
    this.lastName,
    this.nomeCompleto,
    this.telefone,
    this.cargo,
    this.isActive = true,
    this.isSuperuser = false,
    this.maxPapel = 'VENDEDOR',
    this.unidadesAcesso = const [],
  });

  factory ApiUsuario.fromJson(Map<String, dynamic> json) {
    return ApiUsuario(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      firstName: json['first_name'],
      lastName: json['last_name'],
      nomeCompleto: json['nome_completo'],
      telefone: json['telefone'],
      cargo: json['cargo'],
      isActive: json['is_active'] ?? true,
      isSuperuser: json['is_superuser'] ?? false,
      maxPapel: json['max_papel'] ?? 'VENDEDOR',
      unidadesAcesso: (json['unidades_acesso'] as List<dynamic>?)
              ?.map((e) => UsuarioUnidadeVinculo.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// Nome de exibição
  String get displayName => nomeCompleto ?? '$firstName $lastName'.trim();
  
  /// Label do papel
  String get papelLabel {
    switch (maxPapel) {
      case 'ADMIN':
        return 'Administrador';
      case 'DIRETORIA':
        return 'Diretoria';
      case 'GERENTE':
        return 'Gerente';
      case 'VENDEDOR':
      default:
        return 'Vendedor';
    }
  }
}

/// Modelo de vínculo Usuário-Unidade
class UsuarioUnidadeVinculo {
  final int id;
  final UnidadeResumo? unidade;
  final int? unidadeId;
  final String papel;
  final String? dataVinculo;

  UsuarioUnidadeVinculo({
    required this.id,
    this.unidade,
    this.unidadeId,
    required this.papel,
    this.dataVinculo,
  });

  factory UsuarioUnidadeVinculo.fromJson(Map<String, dynamic> json) {
    return UsuarioUnidadeVinculo(
      id: json['id'] ?? 0,
      unidade: json['unidade'] != null 
          ? UnidadeResumo.fromJson(json['unidade']) 
          : null,
      unidadeId: json['unidade_id'],
      papel: json['papel'] ?? 'VENDEDOR',
      dataVinculo: json['data_vinculo'],
    );
  }
  
  String get papelLabel {
    switch (papel) {
      case 'ADMIN':
        return 'Administrador';
      case 'DIRETORIA':
        return 'Diretoria';
      case 'GERENTE':
        return 'Gerente';
      case 'VENDEDOR':
      default:
        return 'Vendedor';
    }
  }
}

/// Modelo resumido de Unidade
class UnidadeResumo {
  final int id;
  final String codigoUnb;
  final String nome;

  UnidadeResumo({
    required this.id,
    required this.codigoUnb,
    required this.nome,
  });

  factory UnidadeResumo.fromJson(Map<String, dynamic> json) {
    return UnidadeResumo(
      id: json['id'] ?? 0,
      codigoUnb: json['codigo_unb'] ?? '',
      nome: json['nome'] ?? '',
    );
  }
  
  @override
  String toString() => '$codigoUnb - $nome';
}

/// Serviço para gerenciamento de usuários
class UserService extends ChangeNotifier {
  final AuthService _authService;
  
  List<ApiUsuario> _usuarios = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _totalCount = 0;
  int _currentPage = 1;
  final int _pageSize = 20;

  UserService(this._authService);

  // Getters
  List<ApiUsuario> get usuarios => _usuarios;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get totalCount => _totalCount;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  int get totalPages => (_totalCount / _pageSize).ceil();

  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer ${_authService.accessToken}',
    'Content-Type': 'application/json',
  };

  /// Carrega lista de usuários
  Future<void> loadUsuarios({
    String? search,
    String? papel,
    int? unidadeId,
    int page = 1,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _currentPage = page;
    notifyListeners();

    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': _pageSize.toString(),
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      
      // Filtra por unidade ativa se não especificada
      final targetUnidadeId = unidadeId ?? _authService.unidadeAtiva?.id;
      if (targetUnidadeId != null) {
        queryParams['unidade_id'] = targetUnidadeId.toString();
      }

      final uri = Uri.parse('${Constants.apiUrl}usuarios/')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: _authHeaders);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is Map && data.containsKey('results')) {
          _usuarios = (data['results'] as List)
              .map((json) => ApiUsuario.fromJson(json))
              .toList();
          _totalCount = data['count'] ?? _usuarios.length;
        } else if (data is List) {
          _usuarios = data.map((json) => ApiUsuario.fromJson(json)).toList();
          _totalCount = _usuarios.length;
        }
        
        // Filtra por papel localmente se especificado
        if (papel != null && papel.isNotEmpty && papel != 'Todos') {
          final papelApi = _papelToApi(papel);
          _usuarios = _usuarios.where((u) => u.maxPapel == papelApi).toList();
        }
      } else if (response.statusCode == 403) {
        _errorMessage = 'Você não tem permissão para visualizar usuários';
        _usuarios = [];
      } else {
        _errorMessage = 'Erro ao carregar usuários: ${response.statusCode}';
        _usuarios = [];
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      _usuarios = [];
      debugPrint('Erro ao carregar usuários: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cria novo usuário
  Future<ApiUsuario?> createUsuario({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    String? telefone,
    String? cargo,
    int? unidadeId,
    String papel = 'VENDEDOR',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final body = jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'password_confirm': password,
        'first_name': firstName,
        'last_name': lastName,
        'telefone': telefone,
        'cargo': cargo,
      });

      final response = await http.post(
        Uri.parse('${Constants.apiUrl}usuarios/'),
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final novoUsuario = ApiUsuario.fromJson(data);
        
        // Se especificou unidade, vincula o usuário
        if (unidadeId != null) {
          await vincularUnidade(novoUsuario.id, unidadeId, papel);
        }
        
        // Recarrega lista
        await loadUsuarios();
        return novoUsuario;
      } else {
        final error = jsonDecode(response.body);
        _errorMessage = error['detail'] ?? 'Erro ao criar usuário';
        return null;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Atualiza usuário existente
  Future<bool> updateUsuario(int id, Map<String, dynamic> dados) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.patch(
        Uri.parse('${Constants.apiUrl}usuarios/$id/'),
        headers: _authHeaders,
        body: jsonEncode(dados),
      );

      if (response.statusCode == 200) {
        await loadUsuarios(page: _currentPage);
        return true;
      } else {
        final error = jsonDecode(response.body);
        _errorMessage = error['detail'] ?? 'Erro ao atualizar usuário';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Exclui usuário
  Future<bool> deleteUsuario(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.delete(
        Uri.parse('${Constants.apiUrl}usuarios/$id/'),
        headers: _authHeaders,
      );

      if (response.statusCode == 204) {
        _usuarios.removeWhere((u) => u.id == id);
        notifyListeners();
        return true;
      } else {
        final error = jsonDecode(response.body);
        _errorMessage = error['detail'] ?? 'Erro ao excluir usuário';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Vincula usuário a uma unidade
  Future<bool> vincularUnidade(int usuarioId, int unidadeId, String papel) async {
    try {
      final response = await http.post(
        Uri.parse('${Constants.apiUrl}usuarios/$usuarioId/vincular_unidade/'),
        headers: _authHeaders,
        body: jsonEncode({
          'unidade_id': unidadeId,
          'papel': papel,
        }),
      );

      if (response.statusCode == 200) {
        await loadUsuarios(page: _currentPage);
        return true;
      } else {
        final error = jsonDecode(response.body);
        _errorMessage = error['error'] ?? 'Erro ao vincular unidade';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    }
  }

  /// Desvincula usuário de uma unidade
  Future<bool> desvincularUnidade(int usuarioId, int unidadeId) async {
    try {
      final response = await http.post(
        Uri.parse('${Constants.apiUrl}usuarios/$usuarioId/desvincular_unidade/'),
        headers: _authHeaders,
        body: jsonEncode({'unidade_id': unidadeId}),
      );

      if (response.statusCode == 200) {
        await loadUsuarios(page: _currentPage);
        return true;
      } else {
        final error = jsonDecode(response.body);
        _errorMessage = error['error'] ?? 'Erro ao desvincular unidade';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    }
  }

  /// Converte label de papel para valor da API
  String _papelToApi(String label) {
    switch (label.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return 'ADMIN';
      case 'diretoria':
        return 'DIRETORIA';
      case 'gerente':
        return 'GERENTE';
      case 'vendedor':
      default:
        return 'VENDEDOR';
    }
  }

  /// Limpa erro
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
