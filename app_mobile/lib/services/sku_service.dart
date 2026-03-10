import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sku_model.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// Resultado paginado da API
class PaginatedResult<T> {
  final int count;
  final String? next;
  final String? previous;
  final List<T> results;

  PaginatedResult({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });
}

/// Resultado do relatório de criticidade
class CriticidadeResult {
  final int totalBloqueados;
  final int totalPreBloqueio;
  final List<Sku> bloqueados;
  final List<Sku> preBloqueio;

  CriticidadeResult({
    required this.totalBloqueados,
    required this.totalPreBloqueio,
    required this.bloqueados,
    required this.preBloqueio,
  });
}

/// Dados do último upload
class UltimoUpload {
  final DateTime? dataUpload;
  final String? tipoArquivo;
  final String? tipoArquivoDisplay;

  UltimoUpload({
    this.dataUpload,
    this.tipoArquivo,
    this.tipoArquivoDisplay,
  });

  factory UltimoUpload.fromJson(Map<String, dynamic> json) {
    return UltimoUpload(
      dataUpload: json['data_upload'] != null 
          ? DateTime.parse(json['data_upload']) 
          : null,
      tipoArquivo: json['tipo_arquivo'],
      tipoArquivoDisplay: json['tipo_arquivo_display'],
    );
  }
}

/// Item do histórico de upload completo
class HistoricoUpload {
  final int id;
  final String tipoArquivo;
  final String tipoArquivoDisplay;
  final int? usuarioId;
  final String usuarioNome;
  final int unidadeNegocioId;
  final String unidadeCodigo;
  final String unidadeNome;
  final String status;
  final String statusDisplay;
  final int linhasProcessadas;
  final String nomeArquivo;
  final String? mensagemErro;
  final DateTime createdAt;

  HistoricoUpload({
    required this.id,
    required this.tipoArquivo,
    required this.tipoArquivoDisplay,
    this.usuarioId,
    required this.usuarioNome,
    required this.unidadeNegocioId,
    required this.unidadeCodigo,
    required this.unidadeNome,
    required this.status,
    required this.statusDisplay,
    required this.linhasProcessadas,
    required this.nomeArquivo,
    this.mensagemErro,
    required this.createdAt,
  });

  factory HistoricoUpload.fromJson(Map<String, dynamic> json) {
    return HistoricoUpload(
      id: json['id'],
      tipoArquivo: json['tipo_arquivo'] ?? '',
      tipoArquivoDisplay: json['tipo_arquivo_display'] ?? '',
      usuarioId: json['usuario'],
      usuarioNome: json['usuario_nome'] ?? 'Sistema',
      unidadeNegocioId: json['unidade_negocio'] ?? 0,
      unidadeCodigo: json['unidade_codigo'] ?? '',
      unidadeNome: json['unidade_nome'] ?? '',
      status: json['status'] ?? '',
      statusDisplay: json['status_display'] ?? '',
      linhasProcessadas: json['linhas_processadas'] ?? 0,
      nomeArquivo: json['nome_arquivo'] ?? '',
      mensagemErro: json['mensagem_erro'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isSuccess => status == 'SUCESSO';
}

/// Exceção para erros de autenticação
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

/// Serviço para operações com SKUs
class SkuService {
  final AuthService authService;

  SkuService({required this.authService});

  /// Headers de autenticação
  Map<String, String> get _headers => authService.authHeaders;

  /// Busca lista de SKUs com filtros
  /// 
  /// [query] - Termo de busca (codigo_sku ou nome_produto)
  /// [unidadeId] - Filtrar por unidade de negócio (usa unidade ativa por padrão)
  /// [categoria] - Filtrar por categoria (ex: 'CERVEJA', 'REFRIGERANTE')
  /// [page] - Página da paginação
  Future<PaginatedResult<Sku>> getSkus({
    String? query,
    int? unidadeId,
    String? categoria,
    int page = 1,
  }) async {
    try {
      // Usa unidade ativa se não for passada explicitamente
      final effectiveUnidadeId = unidadeId ?? authService.unidadeAtiva?.id;
      
      // Monta URL com query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
      };

      if (query != null && query.isNotEmpty) {
        queryParams['search'] = query;
      }

      // Sempre envia unidade_id (obrigatório no backend)
      if (effectiveUnidadeId != null) {
        queryParams['unidade_id'] = effectiveUnidadeId.toString();
      }

      // Filtro por categoria
      if (categoria != null && categoria.isNotEmpty) {
        queryParams['categoria'] = categoria;
      }

      final uri = Uri.parse('${Constants.apiUrl}skus/').replace(queryParameters: queryParams);

      debugPrint('SkuService.getSkus: $uri');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Verifica se é paginado ou lista direta
        if (data is Map && data.containsKey('results')) {
          // Resposta paginada
          final results = (data['results'] as List)
              .map((json) => Sku.fromJson(json))
              .toList();

          return PaginatedResult(
            count: data['count'] ?? results.length,
            next: data['next'],
            previous: data['previous'],
            results: results,
          );
        } else if (data is List) {
          // Lista direta (sem paginação)
          final results = data.map((json) => Sku.fromJson(json)).toList();
          return PaginatedResult(
            count: results.length,
            results: results,
          );
        }

        return PaginatedResult(count: 0, results: []);
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Erro ao buscar SKUs');
      }
    } catch (e) {
      debugPrint('Erro em getSkus: $e');
      rethrow;
    }
  }

  /// Busca SKU por ID
  Future<Sku> getSkuById(int id) async {
    try {
      // Monta URL com unidade_id obrigatório
      final queryParams = <String, String>{};
      final unidadeId = authService.unidadeAtiva?.id;
      if (unidadeId != null) {
        queryParams['unidade_id'] = unidadeId.toString();
      }
      
      final uri = Uri.parse('${Constants.apiUrl}skus/$id/')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Sku.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else if (response.statusCode == 404) {
        throw Exception('SKU não encontrado');
      } else {
        throw Exception('Erro ao buscar SKU');
      }
    } catch (e) {
      debugPrint('Erro em getSkuById: $e');
      rethrow;
    }
  }

  /// Busca lotes de um SKU específico
  Future<List<Lote>> getLotesBySku(int skuId) async {
    try {
      // Monta URL com unidade_id obrigatório
      final queryParams = <String, String>{};
      final unidadeId = authService.unidadeAtiva?.id;
      if (unidadeId != null) {
        queryParams['unidade_id'] = unidadeId.toString();
      }
      
      final uri = Uri.parse('${Constants.apiUrl}skus/$skuId/lotes/')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      
      debugPrint('SkuService.getLotesBySku: $uri');
      
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is List) {
          return data.map((json) => Lote.fromJson(json)).toList();
        }
        
        return [];
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        throw Exception('Erro ao buscar lotes');
      }
    } catch (e) {
      debugPrint('Erro em getLotesBySku: $e');
      rethrow;
    }
  }

  /// Consulta de validade - busca otimizada para a tela de consulta
  Future<List<Sku>> consultaValidade({
    required String search,
    int? unidadeId,
  }) async {
    try {
      // Usa unidade ativa se não for passada explicitamente
      final effectiveUnidadeId = unidadeId ?? authService.unidadeAtiva?.id;
      
      final queryParams = <String, String>{
        'search': search,
      };

      // Sempre envia unidade_id (obrigatório no backend)
      if (effectiveUnidadeId != null) {
        queryParams['unidade_id'] = effectiveUnidadeId.toString();
      }

      final uri = Uri.parse('${Constants.apiUrl}skus/consulta_validade/')
          .replace(queryParameters: queryParams);

      debugPrint('SkuService.consultaValidade: $uri');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is List) {
          return data.map((json) => Sku.fromJson(json)).toList();
        }
        
        return [];
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Parâmetros inválidos');
      } else {
        throw Exception('Erro ao consultar validade');
      }
    } catch (e) {
      debugPrint('Erro em consultaValidade: $e');
      rethrow;
    }
  }

  /// Busca relatório de criticidade (itens bloqueados e pré-bloqueio)
  Future<CriticidadeResult> getRelatorioCriticidade({int? unidadeId}) async {
    try {
      final effectiveUnidadeId = unidadeId ?? authService.unidadeAtiva?.id;
      
      final queryParams = <String, String>{};
      if (effectiveUnidadeId != null) {
        queryParams['unidade_id'] = effectiveUnidadeId.toString();
      }

      final uri = Uri.parse('${Constants.apiUrl}relatorio-criticidade/')
          .replace(queryParameters: queryParams);

      debugPrint('SkuService.getRelatorioCriticidade: $uri');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final bloqueados = (data['bloqueados'] as List?)
            ?.map((json) => Sku.fromJson(json))
            .toList() ?? [];
        
        final preBloqueio = (data['pre_bloqueio'] as List?)
            ?.map((json) => Sku.fromJson(json))
            .toList() ?? [];
        
        return CriticidadeResult(
          totalBloqueados: data['resumo']?['total_bloqueados'] ?? bloqueados.length,
          totalPreBloqueio: data['resumo']?['total_pre_bloqueio'] ?? preBloqueio.length,
          bloqueados: bloqueados,
          preBloqueio: preBloqueio,
        );
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        throw Exception('Erro ao buscar relatório de criticidade');
      }
    } catch (e) {
      debugPrint('Erro em getRelatorioCriticidade: $e');
      rethrow;
    }
  }

  /// Busca data do último upload de estoque
  Future<UltimoUpload> getUltimoUpload({int? unidadeId}) async {
    try {
      final effectiveUnidadeId = unidadeId ?? authService.unidadeAtiva?.id;
      
      final queryParams = <String, String>{};
      if (effectiveUnidadeId != null) {
        queryParams['unidade_id'] = effectiveUnidadeId.toString();
      }

      final uri = Uri.parse('${Constants.apiUrl}historico-upload/ultimo/')
          .replace(queryParameters: queryParams);

      debugPrint('SkuService.getUltimoUpload: $uri');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UltimoUpload.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        return UltimoUpload();
      }
    } catch (e) {
      debugPrint('Erro em getUltimoUpload: $e');
      return UltimoUpload();
    }
  }

  /// Busca lista de histórico de uploads
  /// 
  /// [unidadeId] - Filtrar por unidade de negócio (usa unidade ativa por padrão)
  /// [page] - Página da paginação
  Future<PaginatedResult<HistoricoUpload>> getHistoricoUpload({
    int? unidadeId,
    int page = 1,
  }) async {
    try {
      final effectiveUnidadeId = unidadeId ?? authService.unidadeAtiva?.id;
      
      final queryParams = <String, String>{
        'page': page.toString(),
      };
      if (effectiveUnidadeId != null) {
        queryParams['unidade_id'] = effectiveUnidadeId.toString();
      }

      final uri = Uri.parse('${Constants.apiUrl}historico-upload/')
          .replace(queryParameters: queryParams);

      debugPrint('SkuService.getHistoricoUpload: $uri');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = (data['results'] as List? ?? [])
            .map((json) => HistoricoUpload.fromJson(json))
            .toList();
        
        return PaginatedResult<HistoricoUpload>(
          count: data['count'] ?? results.length,
          next: data['next'],
          previous: data['previous'],
          results: results,
        );
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        throw Exception('Erro ao buscar histórico de uploads');
      }
    } catch (e) {
      debugPrint('Erro em getHistoricoUpload: $e');
      rethrow;
    }
  }
}
