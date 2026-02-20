import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';

/// Tela de Dashboard Web com KPIs e Gráficos
class WebDashboardScreen extends StatefulWidget {
  const WebDashboardScreen({super.key});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Dashboard',
      currentSection: WebMenuSection.dashboard,
      mobileBody: _buildMobileContent(),
      webBody: _buildWebContent(),
    );
  }

  Widget _buildMobileContent() {
    // Para mobile, redireciona para a home existente
    return const Center(
      child: Text('Dashboard Mobile - Use a Home Screen'),
    );
  }

  Widget _buildWebContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título da Seção
          Text(
            'Visão Geral',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.headline,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Acompanhe os indicadores principais do seu estoque',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.body,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // KPI Cards
          _buildKPIGrid(),

          const SizedBox(height: AppSpacing.xl),

          // Seção de Gráficos
          _buildChartsSection(),

          const SizedBox(height: AppSpacing.xl),

          // Tabela de Itens Críticos
          _buildCriticalItemsTable(),
        ],
      ),
    );
  }

  Widget _buildKPIGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Define número de colunas baseado na largura
        final crossAxisCount = constraints.maxWidth > 1200 ? 4 : 2;
        // Aspect ratio menor = cards mais altos
        final childAspectRatio = constraints.maxWidth > 1200 ? 1.8 : 1.5;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: childAspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildKPICard(
              title: 'Total SKUs',
              value: '1,248',
              subtitle: '+12 este mês',
              icon: Icons.inventory_2_outlined,
              iconColor: AppColors.primary,
              iconBgColor: AppColors.primary.withAlpha(26),
              trend: TrendType.up,
              trendValue: '2.5%',
            ),
            _buildKPICard(
              title: 'Valor em Estoque',
              value: 'R\$ 458.293',
              subtitle: 'Custo total',
              icon: Icons.attach_money,
              iconColor: AppColors.success,
              iconBgColor: AppColors.success.withAlpha(26),
              trend: TrendType.up,
              trendValue: '8.2%',
            ),
            _buildKPICard(
              title: 'Itens Críticos',
              value: '23',
              subtitle: 'Vencendo em 7 dias',
              icon: Icons.warning_amber_outlined,
              iconColor: AppColors.error,
              iconBgColor: AppColors.error.withAlpha(26),
              trend: TrendType.down,
              trendValue: '5 menos',
            ),
            _buildKPICard(
              title: 'Usuários Ativos',
              value: '8',
              subtitle: 'Online agora: 3',
              icon: Icons.people_outline,
              iconColor: AppColors.info,
              iconBgColor: AppColors.info.withAlpha(26),
              trend: TrendType.neutral,
              trendValue: 'Estável',
            ),
          ],
        );
      },
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required TrendType trend,
    required String trendValue,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.divider.withAlpha(128)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                _buildTrendBadge(trend, trendValue),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.caption,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendBadge(TrendType trend, String value) {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (trend) {
      case TrendType.up:
        bgColor = AppColors.success.withAlpha(26);
        textColor = AppColors.success;
        icon = Icons.trending_up;
        break;
      case TrendType.down:
        bgColor = AppColors.error.withAlpha(26);
        textColor = AppColors.error;
        icon = Icons.trending_down;
        break;
      case TrendType.neutral:
        bgColor = AppColors.textSecondary.withAlpha(26);
        textColor = AppColors.textSecondary;
        icon = Icons.trending_flat;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.circular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gráfico Principal (2/3 da largura)
        Expanded(
          flex: 2,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: AppColors.divider.withAlpha(128)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Validade por Período',
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.subtitle,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      DropdownButton<String>(
                        value: 'Últimos 30 dias',
                        items: ['Últimos 7 dias', 'Últimos 30 dias', 'Últimos 90 dias']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (value) {},
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.body,
                          color: AppColors.textSecondary,
                        ),
                        underline: const SizedBox(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Placeholder do Gráfico
                  Container(
                    height: 280,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: AppColors.divider,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bar_chart_rounded,
                            size: 64,
                            color: AppColors.textSecondary.withAlpha(128),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Gráfico de Barras',
                            style: GoogleFonts.poppins(
                              fontSize: AppFontSizes.subtitle,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            'Integrar fl_chart ou syncfusion_charts',
                            style: GoogleFonts.poppins(
                              fontSize: AppFontSizes.caption,
                              color: AppColors.textSecondary.withAlpha(178),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: AppSpacing.md),

        // Gráfico de Pizza (1/3 da largura)
        Expanded(
          flex: 1,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: AppColors.divider.withAlpha(128)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status dos SKUs',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.subtitle,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Placeholder do Gráfico de Pizza
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.pie_chart_rounded,
                        size: 80,
                        color: AppColors.textSecondary.withAlpha(128),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Legenda
                  _buildLegendItem('OK', AppColors.success, '842'),
                  _buildLegendItem('Pré-Bloqueio', AppColors.warning, '256'),
                  _buildLegendItem('Crítico', AppColors.error, '98'),
                  _buildLegendItem('Vencido', Colors.black87, '52'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriticalItemsTable() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.divider.withAlpha(128)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Itens Próximos ao Vencimento',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Mini tabela de itens críticos
            DataTable(
              headingRowColor: WidgetStateProperty.all(
                AppColors.background,
              ),
              columns: const [
                DataColumn(label: Text('SKU')),
                DataColumn(label: Text('Produto')),
                DataColumn(label: Text('Lote')),
                DataColumn(label: Text('Vencimento')),
                DataColumn(label: Text('Status')),
              ],
              rows: [
                _buildDataRow('SKU001', 'Cerveja Pilsen 600ml', 'L2024-001', '25/02/2026', 'Crítico'),
                _buildDataRow('SKU015', 'Refrigerante Cola 2L', 'L2024-045', '28/02/2026', 'Crítico'),
                _buildDataRow('SKU023', 'Água Mineral 500ml', 'L2024-078', '01/03/2026', 'Pré-Bloqueio'),
                _buildDataRow('SKU042', 'Suco Natural 1L', 'L2024-112', '05/03/2026', 'Pré-Bloqueio'),
                _buildDataRow('SKU056', 'Energético 250ml', 'L2024-089', '07/03/2026', 'Pré-Bloqueio'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(String sku, String produto, String lote, String vencimento, String status) {
    Color statusColor;
    switch (status) {
      case 'Crítico':
        statusColor = AppColors.error;
        break;
      case 'Pré-Bloqueio':
        statusColor = AppColors.warning;
        break;
      default:
        statusColor = AppColors.success;
    }

    return DataRow(
      cells: [
        DataCell(Text(
          sku,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        )),
        DataCell(Text(produto)),
        DataCell(Text(lote)),
        DataCell(Text(vencimento)),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(26),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              status,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.caption,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum TrendType { up, down, neutral }
