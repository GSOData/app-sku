import 'dart:ui';

/// Modelos de dados do sistema SKU+

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
}

/// Modelo de Lote/Validade resumido
class LoteResumo {
  final int id;
  final String numeroLote;
  final DateTime dataValidade;
  final int qtdEstoque;
  final int diasAteVencimento;

  LoteResumo({
    required this.id,
    required this.numeroLote,
    required this.dataValidade,
    required this.qtdEstoque,
    required this.diasAteVencimento,
  });

  factory LoteResumo.fromJson(Map<String, dynamic> json) {
    return LoteResumo(
      id: json['id'] ?? 0,
      numeroLote: json['numero_lote'] ?? '',
      dataValidade: DateTime.tryParse(json['data_validade'] ?? '') ?? DateTime.now(),
      qtdEstoque: json['qtd_estoque'] ?? 0,
      diasAteVencimento: json['dias_ate_vencimento'] ?? 0,
    );
  }
}

/// Modelo de SKU principal
class Sku {
  final int id;
  final String codigoSku;
  final String nomeProduto;
  final UnidadeNegocio? unidadeNegocio;
  final String? categoria;
  final String? unidadeMedida;
  final String? descricao;
  final String? imagemUrl;
  final int quantidadeTotal;
  final int quantidadeTransito;
  final double valorEstoque;
  final LoteResumo? loteMaisProximo;
  final String statusTexto;
  final String statusCor;
  final int? statusDiasRestantes;
  final bool ativo;

  Sku({
    required this.id,
    required this.codigoSku,
    required this.nomeProduto,
    this.unidadeNegocio,
    this.categoria,
    this.unidadeMedida,
    this.descricao,
    this.imagemUrl,
    this.quantidadeTotal = 0,
    this.quantidadeTransito = 0,
    this.valorEstoque = 0.0,
    this.loteMaisProximo,
    this.statusTexto = 'Indefinido',
    this.statusCor = '#9E9E9E',
    this.statusDiasRestantes,
    this.ativo = true,
  });

  factory Sku.fromJson(Map<String, dynamic> json) {
    return Sku(
      id: json['id'] ?? 0,
      codigoSku: json['codigo_sku'] ?? '',
      nomeProduto: json['nome_produto'] ?? '',
      unidadeNegocio: json['unidade_negocio'] != null
          ? UnidadeNegocio.fromJson(json['unidade_negocio'])
          : null,
      categoria: json['categoria'],
      unidadeMedida: json['unidade_medida'],
      descricao: json['descricao'],
      imagemUrl: json['imagem_url'],
      quantidadeTotal: json['quantidade_total'] ?? 0,
      quantidadeTransito: json['quantidade_transito'] ?? 0,
      valorEstoque: (json['valor_estoque'] ?? 0).toDouble(),
      loteMaisProximo: json['lote_mais_proximo'] != null
          ? LoteResumo.fromJson(json['lote_mais_proximo'])
          : null,
      statusTexto: json['status_texto'] ?? 'Indefinido',
      statusCor: json['status_cor'] ?? '#9E9E9E',
      statusDiasRestantes: json['status_dias_restantes'],
      ativo: json['ativo'] ?? true,
    );
  }

  /// Retorna a cor do status como Color do Flutter
  Color get statusColor {
    String hex = statusCor.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.parse(hex, radix: 16));
  }

  /// Verifica se o produto está vencido
  bool get isVencido => statusTexto.toLowerCase() == 'vencido';

  /// Verifica se o produto está crítico
  bool get isCritico => statusTexto.toLowerCase() == 'crítico';

  /// Verifica se o produto está em pré-bloqueio
  bool get isPreBloqueio => statusTexto.toLowerCase().contains('pré');
}

/// Modelo de Lote completo
class Lote {
  final int id;
  final int skuId;
  final String? skuCodigo;
  final String? skuNome;
  final String numeroLote;
  final DateTime dataValidade;
  final DateTime? dataFabricacao;
  final int qtdEstoque;
  final String? localizacao;
  final double? custoUnitario;
  final String? fornecedor;
  final int diasAteVencimento;
  final bool estaVencido;
  final bool ativo;

  Lote({
    required this.id,
    required this.skuId,
    this.skuCodigo,
    this.skuNome,
    required this.numeroLote,
    required this.dataValidade,
    this.dataFabricacao,
    this.qtdEstoque = 0,
    this.localizacao,
    this.custoUnitario,
    this.fornecedor,
    this.diasAteVencimento = 0,
    this.estaVencido = false,
    this.ativo = true,
  });

  factory Lote.fromJson(Map<String, dynamic> json) {
    return Lote(
      id: json['id'] ?? 0,
      skuId: json['sku'] ?? 0,
      skuCodigo: json['sku_codigo'],
      skuNome: json['sku_nome'],
      numeroLote: json['numero_lote'] ?? '',
      dataValidade: DateTime.tryParse(json['data_validade'] ?? '') ?? DateTime.now(),
      dataFabricacao: json['data_fabricacao'] != null
          ? DateTime.tryParse(json['data_fabricacao'])
          : null,
      qtdEstoque: json['qtd_estoque'] ?? 0,
      localizacao: json['localizacao'],
      custoUnitario: json['custo_unitario'] != null
          ? double.tryParse(json['custo_unitario'].toString())
          : null,
      fornecedor: json['fornecedor'],
      diasAteVencimento: json['dias_ate_vencimento'] ?? 0,
      estaVencido: json['esta_vencido'] ?? false,
      ativo: json['ativo'] ?? true,
    );
  }
}
