import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sku_model.dart';
import '../utils/constants.dart';
import 'sku_detail_screen.dart';

/// Tela de Lista Filtrada - Exibe os itens que foram passados pelo Menu
class CriticalItemsScreen extends StatelessWidget {
  final String title;
  final List<Sku> skus;
  final Color themeColor;
  final Future<void> Function() onRefreshData;

  const CriticalItemsScreen({
    super.key,
    required this.title,
    required this.skus,
    required this.themeColor,
    required this.onRefreshData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: skus.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: onRefreshData,
              color: themeColor,
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: skus.length,
                itemBuilder: (context, index) {
                  return _buildCriticalCard(context, skus[index]);
                },
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
              'Não há produtos nesta categoria.',
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

  Widget _buildCriticalCard(BuildContext context, Sku sku) {
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
                              'Qtd em estoque: ${sku.qtdDisponivelVenda}',
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