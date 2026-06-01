import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:app_mobile/utils/constants.dart';
import 'auth_service.dart';

// Re-exporta UnidadeNegocio do auth_service para manter compatibilidade
export 'auth_service.dart' show UnidadeNegocio;

/// Resultado do upload FEFO.
///
/// O backend agora retorna [skusAtualizados] em vez de processed/created/updated.
class UploadResult {
  final bool success;
  final String? unidade;
  final int skusAtualizados;
  final List<String> errors;
  final List<String> warnings;
  final String? errorMessage;

  UploadResult({
    required this.success,
    this.unidade,
    this.skusAtualizados = 0,
    this.errors = const [],
    this.warnings = const [],
    this.errorMessage,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      success: json['success'] ?? false,
      unidade: json['unidade'],
      skusAtualizados: json['skus_atualizados'] ?? 0,
      errors: List<String>.from(json['errors'] ?? []),
      warnings: List<String>.from(json['warnings'] ?? []),
      errorMessage: json['error'],
    );
  }

  factory UploadResult.error(String message) {
    return UploadResult(success: false, errorMessage: message);
  }
}

/// Arquivo individual para o upload FEFO.
///
/// Agrupa o nome e os bytes de uma planilha selecionada via FilePicker.
class ArquivoUpload {
  final String nome;
  final Uint8List bytes;

  const ArquivoUpload({required this.nome, required this.bytes});
}

/// Service para upload de arquivos e consulta de unidades.
class UploadService {
  final AuthService authService;

  UploadService({required this.authService});

  /// Busca lista de unidades de negócio.
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
        final Map<String, dynamic> decodedData =
            json.decode(utf8.decode(response.bodyBytes));
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

  /// Upload unificado das 3 planilhas FEFO para o endpoint
  /// `POST /api/upload/grade-020502/`.
  ///
  /// Parâmetros:
  /// - [arquivo020502] — Grade 020502 (Estoque Total Diário)
  /// - [arquivo020304] — Grade 020304 (Buffer de Segurança)
  /// - [arquivoNri]    — Planilha NRI (Não-Regular de Inventário)
  /// - [unidadeNegocioId] — ID da unidade de negócio
  Future<UploadResult> uploadEstoqueFefo({
    required ArquivoUpload arquivo020502,
    required ArquivoUpload arquivo020304,
    required ArquivoUpload arquivoNri,
    required int unidadeNegocioId,
  }) async {
    try {
      final uri = Uri.parse('${Constants.apiUrl}upload/grade-020502/');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer ${authService.accessToken}';
      request.fields['unidade_negocio_id'] = unidadeNegocioId.toString();

      // Os 3 arquivos com os field names que o backend espera
      request.files.add(http.MultipartFile.fromBytes(
        'file_020502',
        arquivo020502.bytes,
        filename: arquivo020502.nome,
      ));
      request.files.add(http.MultipartFile.fromBytes(
        'file_020304',
        arquivo020304.bytes,
        filename: arquivo020304.nome,
      ));
      request.files.add(http.MultipartFile.fromBytes(
        'file_nri',
        arquivoNri.bytes,
        filename: arquivoNri.nome,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return UploadResult.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        try {
          final data = json.decode(response.body);
          // O backend retorna erros por campo em 'errors' (dict) ou em 'error' (string)
          final fieldErrors = data['errors'];
          if (fieldErrors is Map) {
            final mensagens = fieldErrors.values.join('\n');
            return UploadResult.error(mensagens);
          }
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