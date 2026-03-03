import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

/// Modelo de Notificação de Alerta de Validade
class NotificacaoAlerta {
  final int id;
  final int skuId;
  final String skuCodigo;
  final String skuNome;
  final String numeroLote;
  final DateTime dataValidade;
  final int diasRestantes;
  final int qtdEstoque;
  final String status;
  final String statusLabel;
  final String statusCor;
  final int unidadeId;
  final String unidadeCodigo;
  final String unidadeNome;

  NotificacaoAlerta({
    required this.id,
    required this.skuId,
    required this.skuCodigo,
    required this.skuNome,
    required this.numeroLote,
    required this.dataValidade,
    required this.diasRestantes,
    required this.qtdEstoque,
    required this.status,
    required this.statusLabel,
    required this.statusCor,
    required this.unidadeId,
    required this.unidadeCodigo,
    required this.unidadeNome,
  });

  factory NotificacaoAlerta.fromJson(Map<String, dynamic> json) {
    return NotificacaoAlerta(
      id: json['id'] ?? 0,
      skuId: json['sku_id'] ?? 0,
      skuCodigo: json['sku_codigo'] ?? '',
      skuNome: json['sku_nome'] ?? '',
      numeroLote: json['numero_lote'] ?? '',
      dataValidade: DateTime.parse(json['data_validade']),
      diasRestantes: json['dias_restantes'] ?? 0,
      qtdEstoque: json['qtd_estoque'] ?? 0,
      status: json['status'] ?? '',
      statusLabel: json['status_label'] ?? '',
      statusCor: json['status_cor'] ?? '#9E9E9E',
      unidadeId: json['unidade_id'] ?? 0,
      unidadeCodigo: json['unidade_codigo'] ?? '',
      unidadeNome: json['unidade_nome'] ?? '',
    );
  }

  /// Retorna a cor como objeto Color
  Color get cor {
    final hex = statusCor.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

/// Resumo das notificações por status
class ResumoNotificacoes {
  final int extremamenteCritico;
  final int bloqueado;
  final int preBloqueio;
  final int total;

  ResumoNotificacoes({
    required this.extremamenteCritico,
    required this.bloqueado,
    required this.preBloqueio,
    required this.total,
  });

  factory ResumoNotificacoes.fromJson(Map<String, dynamic> json) {
    return ResumoNotificacoes(
      extremamenteCritico: json['extremamente_critico'] ?? 0,
      bloqueado: json['bloqueado'] ?? 0,
      preBloqueio: json['pre_bloqueio'] ?? 0,
      total: json['total'] ?? 0,
    );
  }
}

/// Resposta completa das notificações
class NotificacoesResponse {
  final ResumoNotificacoes resumo;
  final List<NotificacaoAlerta> notificacoes;

  NotificacoesResponse({
    required this.resumo,
    required this.notificacoes,
  });

  factory NotificacoesResponse.fromJson(Map<String, dynamic> json) {
    final resumoJson = json['resumo'] as Map<String, dynamic>? ?? {};
    final notificacoesJson = json['notificacoes'] as List? ?? [];

    return NotificacoesResponse(
      resumo: ResumoNotificacoes.fromJson(resumoJson),
      notificacoes: notificacoesJson
          .map((n) => NotificacaoAlerta.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Serviço para buscar notificações de alerta de validade
class NotificationService extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  NotificacoesResponse? _response;
  String? _accessToken;
  int? _unidadeId;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  NotificacoesResponse? get response => _response;
  ResumoNotificacoes? get resumo => _response?.resumo;
  List<NotificacaoAlerta> get notificacoes => _response?.notificacoes ?? [];
  int get totalAlertas => _response?.resumo.total ?? 0;
  bool get hasAlertas => totalAlertas > 0;

  /// Define o token de acesso
  void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// Define a unidade ativa
  void setUnidadeId(int? unidadeId) {
    if (_unidadeId != unidadeId) {
      _unidadeId = unidadeId;
      // Recarrega notificações quando muda a unidade
      if (_accessToken != null && unidadeId != null) {
        fetchNotificacoes();
      }
    }
  }

  /// Busca as notificações da API
  Future<void> fetchNotificacoes() async {
    if (_accessToken == null || _unidadeId == null) {
      _response = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(
        '${Constants.apiUrl}notificacoes/?unidade_id=$_unidadeId',
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _response = NotificacoesResponse.fromJson(data);
        _errorMessage = null;
      } else if (response.statusCode == 400) {
        _errorMessage = 'Unidade não informada';
        _response = null;
      } else if (response.statusCode == 401) {
        _errorMessage = 'Sessão expirada';
        _response = null;
      } else {
        _errorMessage = 'Erro ao carregar notificações';
        _response = null;
      }
    } catch (e) {
      debugPrint('Erro ao buscar notificações: $e');
      _errorMessage = 'Erro de conexão';
      _response = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpa as notificações
  void clear() {
    _response = null;
    _errorMessage = null;
    notifyListeners();
  }
}
