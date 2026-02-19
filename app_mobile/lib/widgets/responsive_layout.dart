import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../screens/login_screen.dart';
import 'web_navigation_menu.dart';

/// Breakpoints para responsividade
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 800;
  static const double desktop = 1200;
}

/// Widget principal que gerencia o layout responsivo
/// Mobile: Navegação tradicional (AppBar + conteúdo)
/// Web/Desktop: SideBar fixa + AppBar de gestão + conteúdo
class ResponsiveLayout extends StatefulWidget {
  final Widget mobileBody;
  final Widget? webBody;
  final String title;
  final List<Widget>? actions;
  final bool showAppBar;
  final WebMenuSection currentSection;

  const ResponsiveLayout({
    super.key,
    required this.mobileBody,
    this.webBody,
    this.title = 'SKU+',
    this.actions,
    this.showAppBar = true,
    this.currentSection = WebMenuSection.dashboard,
  });

  @override
  State<ResponsiveLayout> createState() => _ResponsiveLayoutState();
}

class _ResponsiveLayoutState extends State<ResponsiveLayout> {
  bool _isSidebarCollapsed = false;

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Deseja realmente sair do aplicativo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.logout();

      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWebLayout = constraints.maxWidth >= Breakpoints.tablet;

        if (isWebLayout) {
          return _buildWebLayout(context, constraints);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  /// Layout Mobile - AppBar tradicional + conteúdo
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(
                widget.title,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              actions: widget.actions ??
                  [
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () => _handleLogout(context),
                      tooltip: 'Sair',
                    ),
                  ],
            )
          : null,
      body: widget.mobileBody,
    );
  }

  /// Layout Web - SideBar + AppBar de gestão + conteúdo
  Widget _buildWebLayout(BuildContext context, BoxConstraints constraints) {
    final authService = Provider.of<AuthService>(context);
    final usuario = authService.usuario;
    final sidebarWidth = _isSidebarCollapsed ? 70.0 : 260.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Menu Lateral (SideBar)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sidebarWidth,
            child: WebNavigationMenu(
              currentSection: widget.currentSection,
              isCollapsed: _isSidebarCollapsed,
              onToggleCollapse: () {
                setState(() {
                  _isSidebarCollapsed = !_isSidebarCollapsed;
                });
              },
            ),
          ),

          // Área Principal
          Expanded(
            child: Column(
              children: [
                // AppBar de Gestão Web
                _buildWebAppBar(context, usuario),

                // Conteúdo Principal
                Expanded(
                  child: widget.webBody ?? widget.mobileBody,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// AppBar customizada para Web
  Widget _buildWebAppBar(BuildContext context, Usuario? usuario) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Título da Página
          Text(
            widget.title,
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.title,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),

          // Breadcrumb (opcional)
          if (widget.currentSection != WebMenuSection.dashboard) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              _getSectionLabel(widget.currentSection),
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
          ],

          const Spacer(),

          // Ações customizadas
          if (widget.actions != null) ...widget.actions!,

          const SizedBox(width: AppSpacing.md),

          // Notificações (placeholder)
          IconButton(
            icon: Badge(
              label: const Text('3'),
              child: Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notificações em breve!')),
              );
            },
            tooltip: 'Notificações',
          ),

          const SizedBox(width: AppSpacing.sm),

          // Divisor vertical
          Container(
            height: 32,
            width: 1,
            color: AppColors.divider,
          ),

          const SizedBox(width: AppSpacing.md),

          // Avatar e Menu do Usuário
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    (usuario?.nomeCompleto ?? usuario?.username ?? 'U')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.body,
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usuario?.nomeCompleto ?? usuario?.username ?? 'Usuário',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.body,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      usuario?.cargo ?? 'Administrador',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
              ],
            ),
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout(context);
              } else if (value == 'profile') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Perfil em breve!')),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                    const Text('Meu Perfil'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Sair', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getSectionLabel(WebMenuSection section) {
    switch (section) {
      case WebMenuSection.dashboard:
        return 'Dashboard';
      case WebMenuSection.skus:
        return 'Lista de SKUs';
      case WebMenuSection.critical:
        return 'Itens Críticos';
      case WebMenuSection.stockReport:
        return 'Relatório de Estoque';
      case WebMenuSection.users:
        return 'Gerenciar Usuários';
      case WebMenuSection.upload:
        return 'Upload de Dados';
      case WebMenuSection.settings:
        return 'Configurações';
    }
  }
}

/// Helper para verificar se é layout Web
bool isWebLayout(BuildContext context) {
  return MediaQuery.of(context).size.width >= Breakpoints.tablet;
}
