import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sku_model.dart';
import '../utils/constants.dart';
import 'auth_service.dart';
import 'package:app_mobile/utils/constants.dart';

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
  /// [unidadeId] - Filtrar por unidade de negócio
  /// [page] - Página da paginação
  Future<PaginatedResult<Sku>> getSkus({
    String? query,
    int? unidadeId,
    int page = 1,
  }) async {
    try {
      // Monta URL com query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
      };

      if (query != null && query.isNotEmpty) {
        queryParams['search'] = query;
      }

      if (unidadeId != null) {
        queryParams['unidade_id'] = unidadeId.toString();
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
      final response = await http.get(
        Uri.parse('${Constants.apiUrl}skus/$id/'),
        headers: _headers,
      );

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
      final response = await http.get(
        Uri.parse('${Constants.apiUrl}skus/$skuId/lotes/'),
        headers: _headers,
      );

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
      final queryParams = <String, String>{
        'search': search,
      };

      if (unidadeId != null) {
        queryParams['unidade_id'] = unidadeId.toString();
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
}
