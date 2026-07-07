import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import 'login_screen.dart';

class SkuDetailScreen extends StatefulWidget {
  final Sku sku;
  // NOVO: Interruptor que define se a tela está no modo Controle ou Estoque Geral
  final bool isCriticalItem;

  const SkuDetailScreen({
    super.key, 
    required this.sku, 
    this.isCriticalItem = false, // Por padrão, é falso (Estoque Geral)
  });

  @override
  State<SkuDetailScreen> createState() => _SkuDetailScreenState();
}

class _SkuDetailScreenState extends State<SkuDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sku = widget.sku;
    final dateFormat = DateFormat('dd/MM/yyyy');
    final unidadeText = sku.unidadeMedida != null ? sku.unidadeMedida!.toLowerCase() : 'un';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(sku.codigoSku, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: AppFontSizes.subtitle)),
              background: _buildHeaderBackground(sku),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoCard(sku, dateFormat, unidadeText),
                _buildTabBar(),
              ],
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Renderiza a aba dinamicamente com base no interruptor!
                widget.isCriticalItem 
                    ? _buildValidadeManualTab(sku, dateFormat, unidadeText)
                    : _buildValidadeEstoqueTab(sku),
                _buildInfoTab(sku),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBackground(Sku sku) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (sku.imagemUrl != null && sku.imagemUrl!.isNotEmpty)
          Image.network(sku.imagemUrl!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => _buildDefaultBackground(sku))
        else
          _buildDefaultBackground(sku),
        Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.primary.withAlpha(200)]))),
        Positioned(top: 80, right: 16, child: _buildStatusBadgeLarge(sku)),
      ],
    );
  }

  Widget _buildDefaultBackground(Sku sku) {
    return Container(color: AppColors.primary.withAlpha(180), child: Center(child: Icon(Icons.inventory_2_outlined, size: 80, color: AppColors.onPrimary.withAlpha(100))));
  }

  Widget _buildStatusBadgeLarge(Sku sku) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: sku.statusColor, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getStatusIcon(sku.statusTexto), color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(sku.statusTexto, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'bloqueado':
      case 'vencido':
        return Icons.block;
      case 'risco de vencimento':
      case 'crítico':
      case 'extremamente crítico':
        return Icons.warning;
      case 'pré-bloqueio':
        return Icons.schedule;
      default:
        return Icons.check_circle;
    }
  }

  Widget _buildInfoCard(Sku sku, DateFormat dateFormat, String unidadeText) {
    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sku.nomeProduto, style: GoogleFonts.poppins(fontSize: AppFontSizes.title, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            if (sku.unidadeNegocio != null)
              _buildInfoRow(Icons.business, 'Unidade', '${sku.unidadeNegocio!.codigoUnb} - ${sku.unidadeNegocio!.nome}'),
            const Divider(height: AppSpacing.lg),
            
            // RENDENRIZAÇÃO CONDICIONAL DOS QUADRADINHOS
            Row(
              children: widget.isCriticalItem 
              ? [
                  // MODO CONTROLE MANUAL
                  Expanded(child: _buildInfoTile(Icons.inventory, 'Retido ($unidadeText)', sku.qtdDisponivelVenda.toString(), AppColors.error)),
                  Expanded(child: _buildInfoTile(Icons.schedule, 'Dias Restantes', sku.statusDiasRestantes != null ? '${sku.statusDiasRestantes}' : '-', sku.statusColor)),
                ]
              : [
                  // MODO ESTOQUE GERAL
                  Expanded(child: _buildInfoTile(Icons.inventory, 'Disp. Venda', sku.qtdDisponivelVenda.toString(), AppColors.success)),
                  Expanded(child: _buildInfoTile(Icons.warning_amber_rounded, 'Buffer', '${sku.qtdBuffer020304}', AppColors.error)),
                  Expanded(child: _buildInfoTile(Icons.schedule, 'Dias Restantes', sku.statusDiasRestantes != null ? '${sku.statusDiasRestantes}' : '-', sku.statusColor)),
                ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Text('$label: ', style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.textSecondary)),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 32,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(value, style: GoogleFonts.poppins(fontSize: AppFontSizes.title, fontWeight: FontWeight.bold, color: color)),
          ),
        ),
        Text(label, style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: AppFontSizes.body),
        tabs: [
          Tab(
            // Nome da aba dinâmico
            text: widget.isCriticalItem ? 'Apontamento Manual' : 'Estoque/Validade', 
            icon: Icon(widget.isCriticalItem ? Icons.crisis_alert : Icons.layers)
          ),
          const Tab(text: 'Informações', icon: Icon(Icons.info_outline)),
        ],
      ),
    );
  }

  // =========================================================================
  // ABA DO ESTOQUE GERAL (PLANILHA)
  // =========================================================================
  Widget _buildValidadeEstoqueTab(Sku sku) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.md, top: AppSpacing.md, bottom: 100.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: sku.statusColor.withAlpha(50), width: 1)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Icon(Icons.calendar_month, color: sku.statusColor, size: 40),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Range de Validade', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: AppFontSizes.body)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    sku.getRangeValidadeFormatado(), 
                    style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.bold), 
                    textAlign: TextAlign.center
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Composição do Estoque', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600)),
                  const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Divider()),
                  _buildEstoqueRow('Estoque Físico Total (020502)', sku.qtdTotal020502.toString(), AppColors.info),
                  const SizedBox(height: AppSpacing.sm),
                  _buildEstoqueRow('Retido em Pedidos (020304)', '- ${sku.qtdBuffer020304}', AppColors.error),
                  const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Divider()),
                  _buildEstoqueRow('Disponível para Venda', sku.qtdDisponivelVenda.toString(), AppColors.success, isBold: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ABA DO LANÇAMENTO MANUAL (CONTROLE)
  // =========================================================================
  Widget _buildValidadeManualTab(Sku sku, DateFormat formatador, String unidadeText) {
    final dataExata = sku.validadeInicioRange != null ? formatador.format(sku.validadeInicioRange!) : 'Indefinida';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.md, top: AppSpacing.md, bottom: 100.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: sku.statusColor.withAlpha(50), width: 1)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Icon(Icons.calendar_today, color: sku.statusColor, size: 40),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Data de Validade (Informada pelo Controle)', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: AppFontSizes.body), textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.xs),
                  Text(dataExata, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Volume Crítico', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600)),
                  const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Divider()),
                  _buildEstoqueRow('Total retido nesta validade', '${sku.qtdDisponivelVenda} $unidadeText', sku.statusColor, isBold: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstoqueRow(String label, String value, Color valueColor, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: AppFontSizes.body))),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: GoogleFonts.poppins(color: valueColor, fontSize: isBold ? AppFontSizes.title : AppFontSizes.body, fontWeight: isBold ? FontWeight.bold : FontWeight.w600))),
      ],
    );
  }

  Widget _buildInfoTab(Sku sku) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.md, top: AppSpacing.md, bottom: 100.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Identificação', [
            _buildDetailRow('Código SKU', sku.codigoSku),
            _buildDetailRow('Nome', sku.nomeProduto),
            if (sku.categoria != null) _buildDetailRow('Categoria', sku.categoria!),
            if (sku.unidadeMedida != null) _buildDetailRow('Unidade de Medida', sku.unidadeMedida!),
          ]),
          const SizedBox(height: AppSpacing.md),
          if (sku.unidadeNegocio != null)
            _buildSection('Unidade de Negócio', [
              _buildDetailRow('Código', sku.unidadeNegocio!.codigoUnb),
              _buildDetailRow('Nome', sku.unidadeNegocio!.nome),
            ]),
          if (sku.descricao != null && sku.descricao!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildSection('Descrição', [Text(sku.descricao!, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.textSecondary))]),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(title, style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600, color: AppColors.primary)), const Divider(), ...children],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}