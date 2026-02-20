import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/constants.dart';
import '../screens/web/web_dashboard_screen.dart';
import '../screens/web/web_user_management_screen.dart';
import '../screens/web/web_upload_screen.dart';
import '../screens/sku_list_screen.dart';
import '../screens/critical_items_screen.dart';
import '../screens/stock_report_screen.dart';

/// Seções do menu web
enum WebMenuSection {
  dashboard,
  skus,
  critical,
  stockReport,
  users,
  upload,
  settings,
}

/// Menu lateral de navegação para layout Web/Desktop
class WebNavigationMenu extends StatelessWidget {
  final WebMenuSection currentSection;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;

  const WebNavigationMenu({
    super.key,
    required this.currentSection,
    this.isCollapsed = false,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header com Logo
          _buildHeader(context),

          const SizedBox(height: AppSpacing.md),

          // Menu Items
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Seção Principal
                  if (!isCollapsed)
                    _buildSectionLabel('PRINCIPAL'),
                  
                  _buildMenuItem(
                    context,
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    section: WebMenuSection.dashboard,
                    onTap: () => _navigateTo(context, WebMenuSection.dashboard),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.inventory_2_outlined,
                    activeIcon: Icons.inventory_2,
                    label: 'Lista de SKUs',
                    section: WebMenuSection.skus,
                    onTap: () => _navigateTo(context, WebMenuSection.skus),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.warning_amber_outlined,
                    activeIcon: Icons.warning_amber,
                    label: 'Itens Críticos',
                    section: WebMenuSection.critical,
                    badge: '12',
                    badgeColor: AppColors.error,
                    onTap: () => _navigateTo(context, WebMenuSection.critical),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.assessment_outlined,
                    activeIcon: Icons.assessment,
                    label: 'Relatório Estoque',
                    section: WebMenuSection.stockReport,
                    onTap: () => _navigateTo(context, WebMenuSection.stockReport),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Seção Gestão
                  if (!isCollapsed)
                    _buildSectionLabel('GESTÃO'),
                  
                  _buildMenuItem(
                    context,
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Usuários',
                    section: WebMenuSection.users,
                    onTap: () => _navigateTo(context, WebMenuSection.users),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.upload_file_outlined,
                    activeIcon: Icons.upload_file,
                    label: 'Upload Dados',
                    section: WebMenuSection.upload,
                    onTap: () => _navigateTo(context, WebMenuSection.upload),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Seção Sistema
                  if (!isCollapsed)
                    _buildSectionLabel('SISTEMA'),
                  
                  _buildMenuItem(
                    context,
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Configurações',
                    section: WebMenuSection.settings,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Configurações em breve!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Footer com toggle
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 80,
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? AppSpacing.sm : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
      ),
      child: Row(
        mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          // Logo do App
          Image.asset(
            'assets/images/sku_logo.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // Fallback caso a imagem não exista
              return Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.onPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              );
            },
          ),

          if (!isCollapsed) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SKU+',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.title,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onPrimary,
                    ),
                  ),
                  Text(
                    'Painel Admin',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.onPrimary.withAlpha(178),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        top: AppSpacing.sm,
        bottom: AppSpacing.xs,
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.onPrimary.withAlpha(127),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required WebMenuSection section,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    final isActive = currentSection == section;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? AppSpacing.sm : AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.onPrimary.withAlpha(26)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: isActive
                  ? Border.all(
                      color: AppColors.onPrimary.withAlpha(51),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisAlignment:
                  isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive
                      ? AppColors.onPrimary
                      : AppColors.onPrimary.withAlpha(178),
                  size: 22,
                ),

                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.body,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive
                            ? AppColors.onPrimary
                            : AppColors.onPrimary.withAlpha(204),
                      ),
                    ),
                  ),

                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor ?? AppColors.secondary,
                        borderRadius: BorderRadius.circular(AppRadius.circular),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.onPrimary.withAlpha(26),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleCollapse,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              mainAxisAlignment:
                  isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  isCollapsed
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  color: AppColors.onPrimary.withAlpha(178),
                  size: 24,
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Recolher Menu',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.onPrimary.withAlpha(178),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, WebMenuSection section) {
    if (section == currentSection) return;

    Widget screen;
    switch (section) {
      case WebMenuSection.dashboard:
        screen = const WebDashboardScreen();
        break;
      case WebMenuSection.skus:
        screen = const SkuListScreen();
        break;
      case WebMenuSection.critical:
        screen = const CriticalItemsScreen();
        break;
      case WebMenuSection.stockReport:
        screen = const StockReportScreen();
        break;
      case WebMenuSection.users:
        screen = const WebUserManagementScreen();
        break;
      case WebMenuSection.upload:
        screen = const WebUploadScreen();
        break;
      case WebMenuSection.settings:
        // TODO: Implementar tela de configurações
        return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}
