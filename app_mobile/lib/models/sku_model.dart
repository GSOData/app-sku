import 'dart:ui';
import 'package:intl/intl.dart';

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

/// Modelo de SKU principal — arquitetura FEFO Reverso.
///
/// Os campos de lote foram substituídos por um range de validade
/// e quantidades gerenciais calculadas pelo backend.
class Sku {
  final int id;
  final String codigoSku;
  final String nomeProduto;
  final UnidadeNegocio? unidadeNegocio;
  final String? categoria;
  final String? unidadeMedida;
  final int? fatorConversao;
  final String? descricao;
  final String? imagemUrl;

  // --- Quantidades gerenciais (FEFO Reverso) ---
  /// Total bruto da Grade 020502.
  final int qtdTotal020502;

  /// Buffer de segurança da Grade 020304.
  final int qtdBuffer020304;

  /// Quantidade líquida disponível para venda (020502 - 020304 - NRI).
  /// Este é o estoque principal a ser exibido na UI.
  final int qtdDisponivelVenda;

  // --- Range de validade ---
  /// Data de validade do lote mais próximo do vencimento com estoque.
  final DateTime? validadeInicioRange;

  /// Data de validade do lote mais distante do vencimento com estoque.
  final DateTime? validadeFimRange;

  // --- Status calculados pelo backend ---
  final String statusTexto;
  final String statusTextoDetalhe; // <--- 1. NOVO CAMPO ADICIONADO
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
    this.fatorConversao,
    this.descricao,
    this.imagemUrl,
    this.qtdTotal020502 = 0,
    this.qtdBuffer020304 = 0,
    this.qtdDisponivelVenda = 0,
    this.validadeInicioRange,
    this.validadeFimRange,
    this.statusTexto = 'Indefinido',
    this.statusTextoDetalhe = 'Indefinido', // <--- INICIALIZADO AQUI
    this.statusCor = '#9E9E9E',
    this.statusDiasRestantes,
    this.ativo = true,
  });

  factory Sku.fromJson(Map<String, dynamic> json) {
    // --- 2. INÍCIO DA MÁGICA DOS LOTES MISTOS ---
    String rawStatus = json['status_texto'] ?? 'Indefinido';
    String textoLista = rawStatus;
    String textoDetalhe = rawStatus;

    // Se o backend mandou o sinal, nós dividimos o comportamento!
    if (rawStatus.startsWith('MIX:')) {
      String baseLabel = rawStatus.substring(4); // Arranca fora o "MIX:"
      textoLista = 'Atenção';
      textoDetalhe = 'Parte dos lotes em alerta ($baseLabel)';
    }
    // --- FIM DA MÁGICA ---

    return Sku(
      id: json['id'] ?? 0,
      codigoSku: json['codigo_sku'] ?? '',
      nomeProduto: json['nome_produto'] ?? '',
      unidadeNegocio: json['unidade_negocio'] != null
          ? UnidadeNegocio.fromJson(json['unidade_negocio'])
          : null,
      categoria: json['categoria'],
      unidadeMedida: json['unidade_medida'],
      fatorConversao: json['fator_conversao'],
      descricao: json['descricao'],
      imagemUrl: json['imagem_url'],
      qtdTotal020502: json['qtd_total_020502'] ?? 0,
      qtdBuffer020304: json['qtd_buffer_020304'] ?? 0,
      // Aceita também o campo 'quantidade' usado no relatório de criticidade
      qtdDisponivelVenda:
          json['qtd_disponivel_venda'] ?? json['quantidade'] ?? 0,
      validadeInicioRange: json['validade_inicio_range'] != null
          ? DateTime.tryParse(json['validade_inicio_range'])
          : null,
      validadeFimRange: json['validade_fim_range'] != null
          ? DateTime.tryParse(json['validade_fim_range'])
          : null,
      statusTexto: textoLista,           // <--- RECEBE O TEXTO CURTO
      statusTextoDetalhe: textoDetalhe,  // <--- RECEBE O TEXTO LONGO
      statusCor: json['status_cor'] ?? '#9E9E9E',
      statusDiasRestantes:
          json['status_dias_restantes'] ?? json['dias_restantes'],
      ativo: json['ativo'] ?? true,
    );
  }

  // ---------------------------------------------------------------------------
  // Getters auxiliares
  // ---------------------------------------------------------------------------

  /// Cor do status como [Color] do Flutter.
  /// Suporta hex de 6 dígitos (#RRGGBB) e 8 dígitos (#AARRGGBB).
  Color get statusColor {
    final hex = statusCor.replaceAll('#', '');
    final padded = hex.length == 6 ? 'FF$hex' : hex;
    return Color(int.parse(padded, radix: 16));
  }

  // 3. IMPORTANTE: Validadores agora leem o texto detalhado para não quebrar a lógica!
  bool get isVencido => statusTextoDetalhe.toLowerCase().contains('vencido');

  bool get isExtremamenteCritico => statusTextoDetalhe.toLowerCase().contains('crítico');

  bool get isBloqueado => statusTextoDetalhe.toLowerCase().contains('bloqueado');

  bool get isPreBloqueio => statusTextoDetalhe.toLowerCase().contains('pré');

  bool get isOk => statusTextoDetalhe.toLowerCase() == 'ok';

  bool get semEstoque => statusTextoDetalhe.toLowerCase().contains('sem estoque');

  /// Retorna uma string amigável com o range de validade.
  String getRangeValidadeFormatado() {
    if (validadeInicioRange == null) return '—';

    final fmt = DateFormat('MM/yyyy');
    final inicio = fmt.format(validadeInicioRange!);

    if (validadeFimRange == null) return 'Vence em $inicio';

    final fim = fmt.format(validadeFimRange!);

    if (inicio == fim) return 'Vence em $inicio';

    return '$inicio até $fim';
  }

  /// Retorna apenas o número puro formatado com pontuação.
  /// A unidade de medida agora é adicionada pelas telas.
  String formatarQuantidade(int quantidadeRaw) {
    String sigla = (unidadeMedida ?? 'UN').toUpperCase();

    // REGRA 1: Produtos vendidos naturalmente em unidades (ex: garrafas soltas)
    if (fatorConversao == null || fatorConversao! <= 1 || sigla == 'UN') {
      return quantidadeRaw.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    }
    
    // REGRA 2: Produtos em Caixa, Dúzia, Fardo, etc. (Ignora as unidades quebradas)
    int caixas = quantidadeRaw ~/ fatorConversao!; 

    // Coloca ponto nos milhares (ex: 2445 -> 2.445)
    return caixas.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }
}