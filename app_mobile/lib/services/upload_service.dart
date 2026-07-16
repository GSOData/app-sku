import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:app_mobile/utils/constants.dart'; // Verifique se o import bate com o do seu projeto
import 'auth_service.dart';

// Re-exporta UnidadeNegocio do auth_service para manter compatibilidade
export 'auth_service.dart' show UnidadeNegocio;

/// Resultado do upload FEFO e Críticos.
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
      skusAtualizados: json['skus_atualizados'] ?? json['linhas_processadas'] ?? 0,
      errors: List<String>.from(json['errors'] ?? []),
      warnings: List<String>.from(json['warnings'] ?? []),
      errorMessage: json['error'],
    );
  }

  factory UploadResult.error(String message) {
    return UploadResult(success: false, errorMessage: message);
  }
}

/// Arquivo individual para o upload FEFO/Crítico.
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
        final Map<String, dynamic> decodedData = json.decode(utf8.decode(response.bodyBytes));
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

  /// Upload unificado das 3 planilhas FEFO.
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

      request.files.add(http.MultipartFile.fromBytes('file_020502', arquivo020502.bytes, filename: arquivo020502.nome));
      request.files.add(http.MultipartFile.fromBytes('file_020304', arquivo020304.bytes, filename: arquivo020304.nome));
      request.files.add(http.MultipartFile.fromBytes('file_nri', arquivoNri.bytes, filename: arquivoNri.nome));

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
          final fieldErrors = data['errors'];
          if (fieldErrors is Map) {
            final mensagens = fieldErrors.values.join('\n');
            return UploadResult.error(mensagens);
          }
          return UploadResult.error(data['error'] ?? 'Erro no upload: ${response.statusCode}');
        } catch (_) {
          return UploadResult.error('Erro no upload: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      return UploadResult.error('Erro de conexão: $e');
    }
  }

  /// NOVO: Upload da Planilha Única de Itens Críticos (Controle)
  Future<UploadResult> uploadPlanilhaCriticos({
    required ArquivoUpload arquivo,
    required int unidadeNegocioId,
  }) async {
    try {
      final uri = Uri.parse('${Constants.apiUrl}upload-criticos/');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer ${authService.accessToken}';
      request.fields['unidade_id'] = unidadeNegocioId.toString();

      request.files.add(http.MultipartFile.fromBytes(
        'file', // O backend espera o nome 'file'
        arquivo.bytes,
        filename: arquivo.nome,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return UploadResult.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AuthException('Sessão expirada. Faça login novamente.');
      } else {
        try {
          final data = json.decode(utf8.decode(response.bodyBytes));
          // Trata os erros detalhados retornados pela varredura linha a linha
          if (data['detalhes'] != null && data['detalhes'] is List) {
            final detalhes = List<String>.from(data['detalhes']);
            // Mostra o erro principal + até 5 erros de linha para não quebrar a tela
            final amostraErros = detalhes.take(5).join('\n');
            final complemento = detalhes.length > 5 ? '\n... e mais ${detalhes.length - 5} erros.' : '';
            return UploadResult.error('${data['error']}\n$amostraErros$complemento');
          }
          return UploadResult.error(data['error'] ?? 'Erro no upload: ${response.statusCode}');
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