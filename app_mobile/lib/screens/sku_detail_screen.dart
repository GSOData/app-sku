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

  const SkuDetailScreen({super.key, required this.sku});

  @override
  State<SkuDetailScreen> createState() => _SkuDetailScreenState();
}

class _SkuDetailScreenState extends State<SkuDetailScreen>
    with SingleTickerProviderStateMixin {
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

  void _handleAuthError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );

    final authService = Provider.of<AuthService>(context, listen: false);
    authService.logout();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sku = widget.sku;
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // AppBar com imagem
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                sku.codigoSku,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: AppFontSizes.subtitle,
                ),
              ),
              background: _buildHeaderBackground(sku),
            ),
          ),

          // Conteúdo
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card de informações principais
                _buildInfoCard(sku, dateFormat),

                // Tabs
                _buildTabBar(),
              ],
            ),
          ),

          // Conteúdo das tabs
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Nova Tab Estoque/Validade Gerencial
                _buildValidadeEstoqueTab(sku),

                // Tab Informações
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
        // Imagem ou cor de fundo
        if (sku.imagemUrl != null && sku.imagemUrl!.isNotEmpty)
          Image.network(
            sku.imagemUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildDefaultBackground(sku),
          )
        else
          _buildDefaultBackground(sku),

        // Gradiente para legibilidade
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.primary.withAlpha(200),
              ],
            ),
          ),
        ),

        // Badge de status no canto
        Positioned(
          top: 80,
          right: 16,
          child: _buildStatusBadgeLarge(sku),
        ),
      ],
    );
  }

  Widget _buildDefaultBackground(Sku sku) {
    return Container(
      color: AppColors.primary.withAlpha(180),
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 80,
          color: AppColors.onPrimary.withAlpha(100),
        ),
      ),
    );
  }

  Widget _buildStatusBadgeLarge(Sku sku) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: sku.statusColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStatusIcon(sku.statusTexto),
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            sku.statusTexto,
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'vencido':
        return Icons.block;
      case 'crítico':
      case 'extremamente crítico':
        return Icons.warning;
      case 'bloqueado':
      case 'pré-bloqueio':
        return Icons.schedule;
      case 'ok':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildInfoCard(Sku sku, DateFormat dateFormat) {
    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nome do produto
            Text(
              sku.nomeProduto,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // Unidade
            if (sku.unidadeNegocio != null)
              _buildInfoRow(
                Icons.business,
                'Unidade',
                '${sku.unidadeNegocio!.codigoUnb} - ${sku.unidadeNegocio!.nome}',
              ),

            const Divider(height: AppSpacing.lg),

            // Grid de informações principais
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    Icons.inventory,
                    'Disp. Venda',
                    '${sku.qtdDisponivelVenda}',
                    AppColors.success,
                  ),
                ),
                Expanded(
                  child: _buildInfoTile(
                    Icons.warning_amber_rounded,
                    'Buffer',
                    '${sku.qtdBuffer020304}',
                    AppColors.error,
                  ),
                ),
                Expanded(
                  child: _buildInfoTile(
                    Icons.schedule,
                    'Dias Restantes',
                    sku.statusDiasRestantes != null
                        ? '${sku.statusDiasRestantes}'
                        : '-',
                    sku.statusColor,
                  ),
                ),
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
          Text(
            '$label: ',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.body,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.title,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
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
        labelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: AppFontSizes.body,
        ),
        tabs: const [
          Tab(text: 'Estoque/Validade', icon: Icon(Icons.layers)),
          Tab(text: 'Informações', icon: Icon(Icons.info_outline)),
        ],
      ),
    );
  }

  // --- NOVA ABA GERENCIAL (Substitui Lotes) ---
  Widget _buildValidadeEstoqueTab(Sku sku) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card de Range de Validade
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: sku.statusColor.withAlpha(50), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Icon(Icons.calendar_month, color: sku.statusColor, size: 40),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Range de Validade',
                    style: GoogleFonts.poppins(
                      color: AppColors.textSecondary, 
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    sku.getRangeValidadeFormatado(),
                    style: GoogleFonts.poppins(
                      color: AppColors.textPrimary, 
                      fontSize: AppFontSizes.subtitle, 
                      fontWeight: FontWeight.bold
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: AppSpacing.md),
          
          // Card de Composição do Estoque
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Composição do Estoque',
                    style: GoogleFonts.poppins(
                      color: AppColors.textPrimary, 
                      fontSize: AppFontSizes.subtitle, 
                      fontWeight: FontWeight.w600
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Divider(),
                  ),
                  
                  // Físico Total (020502)
                  _buildEstoqueRow(
                    'Estoque Físico Total (020502)', 
                    sku.qtdTotal020502.toString(), 
                    AppColors.info
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  
                  // Buffer/Reservado (020304)
                  _buildEstoqueRow(
                    'Retido em Pedidos (020304)', 
                    '- ${sku.qtdBuffer020304}', 
                    AppColors.error
                  ),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Divider(),
                  ),
                  
                  // Disponível para Venda
                  _buildEstoqueRow(
                    'Disponível para Venda', 
                    sku.qtdDisponivelVenda.toString(), 
                    AppColors.success,
                    isBold: true,
                  ),
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
      children: [
        Text(
          label, 
          style: GoogleFonts.poppins(
            color: AppColors.textSecondary, 
            fontSize: AppFontSizes.body
          )
        ),
        Text(
          value, 
          style: GoogleFonts.poppins(
            color: valueColor, 
            fontSize: isBold ? AppFontSizes.title : AppFontSizes.body, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600
          )
        ),
      ],
    );
  }

  Widget _buildInfoTab(Sku sku) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Identificação', [
            _buildDetailRow('Código SKU', sku.codigoSku),
            _buildDetailRow('Nome', sku.nomeProduto),
            if (sku.categoria != null)
              _buildDetailRow('Categoria', sku.categoria!),
            if (sku.unidadeMedida != null)
              _buildDetailRow('Unidade de Medida', sku.unidadeMedida!),
          ]),

          const SizedBox(height: AppSpacing.md),

          if (sku.unidadeNegocio != null)
            _buildSection('Unidade de Negócio', [
              _buildDetailRow('Código', sku.unidadeNegocio!.codigoUnb),
              _buildDetailRow('Nome', sku.unidadeNegocio!.nome),
            ]),

          if (sku.descricao != null && sku.descricao!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildSection('Descrição', [
              Text(
                sku.descricao!,
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textSecondary,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.subtitle,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const Divider(),
            ...children,
          ],
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
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}