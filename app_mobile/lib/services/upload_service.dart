import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:app_mobile/utils/constants.dart';
import 'auth_service.dart';

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

  @override
  String toString() => '$codigoUnb - $nome';
}

/// Resultado do upload
class UploadResult {
  final bool success;
  final String? tipo;
  final String? unidade;
  final int processed;
  final int created;
  final int updated;
  final List<String> errors;
  final List<String> warnings;
  final String? errorMessage;

  UploadResult({
    required this.success,
    this.tipo,
    this.unidade,
    this.processed = 0,
    this.created = 0,
    this.updated = 0,
    this.errors = const [],
    this.warnings = const [],
    this.errorMessage,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      success: json['success'] ?? false,
      tipo: json['tipo'],
      unidade: json['unidade'],
      processed: json['processed'] ?? 0,
      created: json['created'] ?? 0,
      updated: json['updated'] ?? 0,
      errors: List<String>.from(json['errors'] ?? []),
      warnings: List<String>.from(json['warnings'] ?? []),
      errorMessage: json['error'],
    );
  }

  factory UploadResult.error(String message) {
    return UploadResult(
      success: false,
      errorMessage: message,
    );
  }
}

/// Service para upload de arquivos e consulta de unidades
class UploadService {
  final AuthService authService;

  UploadService({required this.authService});

  /// Retorna headers com token de autenticação
  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${authService.accessToken}',
      };

  /// Busca lista de unidades de negócio
  Future<List<UnidadeNegocio>> getUnidades() async {
    try {
      final response = await http.get(
        Uri.parse('${Constants.apiUrl}unidades/'),
        headers: {
          'Authorization': 'Bearer ${authService.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        // 1. Decodifica usando UTF-8 para manter os acentos
        // 2. Transforma em Map para podermos acessar a chave 'results'
        final Map<String, dynamic> decodedData = json.decode(utf8.decode(response.bodyBytes));
        
        // 3. Pega apenas a lista real que está dentro de 'results'
        final List<dynamic> data = decodedData['results']; 
        
        return data.map((item) => UnidadeNegocio.fromJson(item)).toList();
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        throw Exception('Erro ao carregar unidades: ${response.statusCode}');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw Exception('Erro de conexão: $e');
    }
  }

  /// Upload de planilha Grade 020502 (Estoque Total)
  Future<UploadResult> uploadGrade020502({
    required int unidadeNegocioId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    return _uploadFile(
      endpoint: 'upload/grade-020502/',
      unidadeNegocioId: unidadeNegocioId,
      fileName: fileName,
      fileBytes: fileBytes,
    );
  }

  /// Upload de planilha de Contagens (Validades)
  Future<UploadResult> uploadContagens({
    required int unidadeNegocioId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    return _uploadFile(
      endpoint: 'upload/contagens/',
      unidadeNegocioId: unidadeNegocioId,
      fileName: fileName,
      fileBytes: fileBytes,
    );
  }

  /// Método interno para upload de arquivo multipart
  Future<UploadResult> _uploadFile({
    required String endpoint,
    required int unidadeNegocioId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    try {
      final uri = Uri.parse('${Constants.apiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer ${authService.accessToken}';

      // Campos
      request.fields['unidade_negocio_id'] = unidadeNegocioId.toString();

      // Arquivo
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));

      // Envia
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UploadResult.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        // Tenta parsear erro do backend
        try {
          final data = json.decode(response.body);
          return UploadResult.error(
            data['error'] ?? 'Erro no upload: ${response.statusCode}',
          );
        } catch (_) {
          return UploadResult.error('Erro no upload: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      return UploadResult.error('Erro de conexão: $e');
    }
  }
}

/// Exceção de autenticação
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
