import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../services/sku_service.dart';
import '../utils/constants.dart';
import 'login_screen.dart';
import 'sku_detail_screen.dart';

/// Tela de Itens em Criticidade - mostra apenas produtos vencidos ou críticos
class CriticalItemsScreen extends StatefulWidget {
  const CriticalItemsScreen({super.key});

  @override
  State<CriticalItemsScreen> createState() => _CriticalItemsScreenState();
}

class _CriticalItemsScreenState extends State<CriticalItemsScreen> {
  late SkuService _skuService;

  List<Sku> _criticalSkus = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Contadores
  int _vencidosCount = 0;
  int _criticosCount = 0;
  int _preBloqueioCount = 0;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _skuService = SkuService(authService: authService);

    _loadCriticalItems();
  }

  Future<void> _loadCriticalItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Busca todos os SKUs
      final result = await _skuService.getSkus();

      // Filtra apenas os itens problemáticos
      final criticalItems = result.results.where((sku) {
        final status = sku.statusTexto.toLowerCase();
        return status == 'vencido' ||
            status == 'crítico' ||
            status.contains('pré') ||
            status == 'critico'; // sem acento
      }).toList();

      // Ordena por prioridade (vencidos primeiro, depois críticos, depois pré-bloqueio)
      criticalItems.sort((a, b) {
        final prioridadeA = _getPrioridade(a.statusTexto);
        final prioridadeB = _getPrioridade(b.statusTexto);

        if (prioridadeA != prioridadeB) {
          return prioridadeA.compareTo(prioridadeB);
        }

        // Mesmo status: ordena por dias restantes (menor primeiro)
        final diasA = a.statusDiasRestantes ?? 999;
        final diasB = b.statusDiasRestantes ?? 999;
        return diasA.compareTo(diasB);
      });

      // Conta por categoria
      int vencidos = 0;
      int criticos = 0;
      int preBloqueio = 0;

      for (final sku in criticalItems) {
        final status = sku.statusTexto.toLowerCase();
        if (status == 'vencido') {
          vencidos++;
        } else if (status == 'crítico' || status == 'critico') {
          criticos++;
        } else if (status.contains('pré')) {
          preBloqueio++;
        }
      }

      setState(() {
        _criticalSkus = criticalItems;
        _vencidosCount = vencidos;
        _criticosCount = criticos;
        _preBloqueioCount = preBloqueio;
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

  int _getPrioridade(String status) {
    final s = status.toLowerCase();
    if (s == 'vencido') return 0;
    if (s == 'crítico' || s == 'critico') return 1;
    if (s.contains('pré')) return 2;
    return 3;
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Atenção Necessária',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Resumo no topo
          _buildSummaryHeader(),

          // Lista de itens
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryTile(
              'Vencidos',
              _vencidosCount,
              Colors.black,
              Icons.block,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withAlpha(77),
          ),
          Expanded(
            child: _buildSummaryTile(
              'Críticos',
              _criticosCount,
              Colors.white,
              Icons.warning,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withAlpha(77),
          ),
          Expanded(
            child: _buildSummaryTile(
              'Pré-Bloqueio',
              _preBloqueioCount,
              AppColors.warning,
              Icons.schedule,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(String label, int count, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.headline,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: Colors.white.withAlpha(220),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.error),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_criticalSkus.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadCriticalItems,
      color: AppColors.error,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _criticalSkus.length,
        itemBuilder: (context, index) {
          return _buildCriticalCard(_criticalSkus[index]);
        },
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
              onPressed: _loadCriticalItems,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: AppColors.success.withAlpha(180),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Tudo certo! 🎉',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.headline,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Não há produtos vencidos ou em estado crítico.',
              textAlign: TextAlign.center,
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

  Widget _buildCriticalCard(Sku sku) {
    final isVencido = sku.statusTexto.toLowerCase() == 'vencido';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: sku.statusColor.withAlpha(100),
          width: 2,
        ),
      ),
      elevation: 3,
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
        child: Column(
          children: [
            // Header colorido
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: sku.statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.md),
                  topRight: Radius.circular(AppRadius.md),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isVencido ? Icons.block : Icons.warning,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    sku.statusTexto.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.body,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (sku.statusDiasRestantes != null)
                    Text(
                      isVencido
                          ? 'Há ${sku.statusDiasRestantes!.abs()} dias'
                          : '${sku.statusDiasRestantes} dias restantes',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.caption,
                        color: Colors.white.withAlpha(220),
                      ),
                    ),
                ],
              ),
            ),

            // Conteúdo
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  // Ícone
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: sku.statusColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: sku.statusColor,
                      size: 24,
                    ),
                  ),

                  const SizedBox(width: AppSpacing.md),

                  // Informações
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sku.nomeProduto,
                          style: GoogleFonts.poppins(
                            fontSize: AppFontSizes.subtitle,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: ${sku.codigoSku}',
                          style: GoogleFonts.poppins(
                            fontSize: AppFontSizes.body,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.inventory,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Qtd em estoque: ${sku.quantidadeTotal}',
                              style: GoogleFonts.poppins(
                                fontSize: AppFontSizes.caption,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
