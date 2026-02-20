import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../services/sku_service.dart';
import '../utils/constants.dart';
import 'login_screen.dart';
import 'sku_detail_screen.dart';
import 'web/web_dashboard_screen.dart';

/// Tela de Relatório de Estoque - visão geral do estoque
class StockReportScreen extends StatefulWidget {
  const StockReportScreen({super.key});

  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  late SkuService _skuService;

  List<Sku> _skus = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Métricas
  int _totalSkus = 0;
  int _totalQuantidade = 0;
  double _valorTotalEstoque = 0;
  int _itensVencidos = 0;
  int _quantidadeVencida = 0;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _numberFormat = NumberFormat.decimalPattern('pt_BR');

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _skuService = SkuService(authService: authService);

    _loadStockData();
  }

  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _skuService.getSkus();
      final skus = result.results;

      // Calcula métricas
      int totalQtd = 0;
      double valorTotal = 0;
      int vencidosCount = 0;
      int qtdVencida = 0;

      for (final sku in skus) {
        totalQtd += sku.quantidadeTotal;

        // Usa o valor real do estoque calculado no backend
        valorTotal += sku.valorEstoque;

        if (sku.statusTexto.toLowerCase() == 'vencido') {
          vencidosCount++;
          qtdVencida += sku.quantidadeTotal;
        }
      }

      // Ordena por quantidade (maior primeiro)
      skus.sort((a, b) => b.quantidadeTotal.compareTo(a.quantidadeTotal));

      setState(() {
        _skus = skus;
        _totalSkus = skus.length;
        _totalQuantidade = totalQtd;
        _valorTotalEstoque = valorTotal;
        _itensVencidos = vencidosCount;
        _quantidadeVencida = qtdVencida;
      });
    } on AuthException catch (e) {
      _handleAuthError(e.message);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
    final showBackButton = kIsWeb || Navigator.canPop(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Relatório de Estoque',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const WebDashboardScreen()),
                    );
                  }
                },
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStockData,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.success),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadStockData,
                  color: AppColors.success,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Cards de resumo
                        _buildSummaryCards(),

                        // Título da lista
                        _buildListHeader(),

                        // Lista de produtos
                        _buildProductList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error.withAlpha(180),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Erro ao carregar',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: _loadStockData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          // Primeira linha: Total SKUs e Quantidade
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.category,
                  title: 'Total de SKUs',
                  value: _numberFormat.format(_totalSkus),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.inventory,
                  title: 'Qtd. em Estoque',
                  value: _numberFormat.format(_totalQuantidade),
                  color: AppColors.info,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Segunda linha: Valor Total
          _buildMetricCard(
            icon: Icons.attach_money,
            title: 'Valor Total em Estoque',
            value: _currencyFormat.format(_valorTotalEstoque),
            color: AppColors.success,
            isLarge: true,
          ),

          const SizedBox(height: AppSpacing.md),

          // Terceira linha: Itens Vencidos
          _buildMetricCard(
            icon: Icons.warning_amber,
            title: 'Itens Vencidos',
            value: '$_itensVencidos SKUs ($_quantidadeVencida unidades)',
            color: _itensVencidos > 0 ? AppColors.error : AppColors.success,
            subtitle: _itensVencidos > 0
                ? 'Atenção: produtos vencidos no estoque!'
                : 'Nenhum produto vencido 👍',
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    bool isLarge = false,
    String? subtitle,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border(
            left: BorderSide(
              color: color,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                icon,
                color: color,
                size: isLarge ? 32 : 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.body,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: isLarge ? AppFontSizes.headline : AppFontSizes.title,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.list_alt,
            color: AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Produtos por Quantidade',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.subtitle,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            '${_skus.length} itens',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    if (_skus.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: AppColors.textSecondary.withAlpha(128),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Nenhum produto cadastrado',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: _skus.length,
      itemBuilder: (context, index) {
        return _buildProductTile(_skus[index], index + 1);
      },
    );
  }

  Widget _buildProductTile(Sku sku, int ranking) {
    // Calcula barra de progresso baseada na maior quantidade
    final maxQtd = _skus.isNotEmpty ? _skus.first.quantidadeTotal : 1;
    final progress = maxQtd > 0 ? sku.quantidadeTotal / maxQtd : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SkuDetailScreen(sku: sku),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Ranking
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: ranking <= 3
                          ? AppColors.secondary.withAlpha(26)
                          : AppColors.textSecondary.withAlpha(26),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Center(
                      child: Text(
                        '#$ranking',
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.caption,
                          fontWeight: FontWeight.bold,
                          color: ranking <= 3
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: AppSpacing.sm),

                  // Nome e SKU
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sku.nomeProduto,
                          style: GoogleFonts.poppins(
                            fontSize: AppFontSizes.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          sku.codigoSku,
                          style: GoogleFonts.poppins(
                            fontSize: AppFontSizes.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quantidade
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _numberFormat.format(sku.quantidadeTotal),
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.subtitle,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'unidades',
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: AppSpacing.sm),

                  // Status badge pequeno
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: sku.statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.sm),

              // Barra de progresso
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.primary.withAlpha(26),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    sku.statusColor.withAlpha(180),
                  ),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
