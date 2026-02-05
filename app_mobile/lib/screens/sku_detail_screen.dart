import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../services/sku_service.dart';
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
  late SkuService _skuService;
  
  List<Lote> _lotes = [];
  bool _isLoadingLotes = true;
  String? _lotesError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    final authService = Provider.of<AuthService>(context, listen: false);
    _skuService = SkuService(authService: authService);
    
    _loadLotes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLotes() async {
    setState(() {
      _isLoadingLotes = true;
      _lotesError = null;
    });

    try {
      final lotes = await _skuService.getLotesBySku(widget.sku.id);
      // Ordena lotes por prioridade de status e data de validade
      lotes.sort((a, b) {
        final prioridadeA = _getPrioridadeStatus(a);
        final prioridadeB = _getPrioridadeStatus(b);
        
        if (prioridadeA != prioridadeB) {
          return prioridadeA.compareTo(prioridadeB);
        }
        // Mesmo status: ordena por data de validade (mais próxima primeiro)
        return a.dataValidade.compareTo(b.dataValidade);
      });
      
      setState(() {
        _lotes = lotes;
      });
    } on AuthException catch (e) {
      _handleAuthError(e.message);
    } catch (e) {
      setState(() {
        _lotesError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoadingLotes = false;
      });
    }
  }

  /// Retorna prioridade do status (menor = mais crítico)
  int _getPrioridadeStatus(Lote lote) {
    if (lote.estaVencido) return 0; // Vencido - maior prioridade
    if (lote.diasAteVencimento <= 30) return 1; // Crítico
    if (lote.diasAteVencimento <= 45) return 2; // Pré-Bloqueio
    return 3; // Normal/OK
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
                // Tab Lotes/Validades
                _buildLotesTab(dateFormat),

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
        return Icons.warning;
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

            // Grid de informações
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    Icons.inventory,
                    'Em Estoque',
                    '${sku.quantidadeTotal}',
                    AppColors.success,
                  ),
                ),
                Expanded(
                  child: _buildInfoTile(
                    Icons.local_shipping,
                    'Em Trânsito',
                    '${sku.quantidadeTransito}',
                    AppColors.info,
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

            // Lote mais próximo
            if (sku.loteMaisProximo != null) ...[
              const Divider(height: AppSpacing.lg),
              _buildInfoRow(
                Icons.label,
                'Lote Mais Próximo',
                '${sku.loteMaisProximo!.numeroLote} (Val: ${dateFormat.format(sku.loteMaisProximo!.dataValidade)})',
              ),
            ],
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
          Tab(text: 'Lotes/Validades', icon: Icon(Icons.layers)),
          Tab(text: 'Informações', icon: Icon(Icons.info_outline)),
        ],
      ),
    );
  }

  Widget _buildLotesTab(DateFormat dateFormat) {
    if (_isLoadingLotes) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: AppSpacing.md),
            Text('Carregando lotes...'),
          ],
        ),
      );
    }

    if (_lotesError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(_lotesError!),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _loadLotes,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_lotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nenhum lote encontrado',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.subtitle,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLotes,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _lotes.length,
        itemBuilder: (context, index) {
          return _buildLoteCard(_lotes[index], dateFormat);
        },
      ),
    );
  }

  Widget _buildLoteCard(Lote lote, DateFormat dateFormat) {
    final isVencido = lote.estaVencido;
    final isCritico = lote.diasAteVencimento <= 30 && !isVencido;
    
    Color statusColor;
    if (isVencido) {
      statusColor = Colors.black;
    } else if (isCritico) {
      statusColor = AppColors.error;
    } else if (lote.diasAteVencimento <= 45) {
      statusColor = AppColors.warning;
    } else {
      statusColor = AppColors.success;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: statusColor.withAlpha(100),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.label, color: statusColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Lote: ${lote.numeroLote}',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.subtitle,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    isVencido
                        ? 'Vencido'
                        : '${lote.diasAteVencimento} dias',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),
            const Divider(),

            // Info Grid
            Row(
              children: [
                Expanded(
                  child: _buildLoteInfo(
                    'Validade',
                    dateFormat.format(lote.dataValidade),
                    Icons.event,
                  ),
                ),
                Expanded(
                  child: _buildLoteInfo(
                    'Quantidade',
                    '${lote.qtdEstoque}',
                    Icons.inventory,
                  ),
                ),
              ],
            ),

            if (lote.localizacao != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildLoteInfo(
                'Localização',
                lote.localizacao!,
                Icons.location_on,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoteInfo(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
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
