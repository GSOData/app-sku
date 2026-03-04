import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/sku_service.dart';
import '../utils/constants.dart';
import '../widgets/mobile_unit_selector.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'sku_list_screen.dart';
import 'critical_items_screen.dart';
import 'stock_report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late SkuService _skuService;
  UltimoUpload? _ultimoUpload;
  bool _isLoadingUpload = false;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _skuService = SkuService(authService: authService);
    _loadUltimoUpload();
  }

  Future<void> _loadUltimoUpload() async {
    setState(() => _isLoadingUpload = true);
    try {
      final upload = await _skuService.getUltimoUpload();
      if (mounted) {
        setState(() => _ultimoUpload = upload);
      }
    } catch (e) {
      debugPrint('Erro ao carregar último upload: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingUpload = false);
      }
    }
  }

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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuario = authService.usuario;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'SKU+',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        actions: [
          // Sininho de Notificações
          const NotificationBell(forAppBar: true),
          // Seletor de Unidade no AppBar
          const MobileUnitSelectorButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Saudação
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          (usuario?.nomeCompleto ?? usuario?.username ?? 'U')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: GoogleFonts.poppins(
                            fontSize: AppFontSizes.headline,
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Olá, ${usuario?.nomeCompleto ?? usuario?.username ?? 'Usuário'}!',
                              style: GoogleFonts.poppins(
                                fontSize: AppFontSizes.subtitle,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              usuario?.perfilLabel ?? 'Usuário',
                              style: GoogleFonts.poppins(
                                fontSize: AppFontSizes.body,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Título Menu
              Text(
                'Menu Principal',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.title,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Botões do Menu
              Expanded(
                child: Column(
                  children: [
                    // Consulta Validade - Visível para todos
                    _buildMenuButton(
                      context,
                      icon: Icons.search,
                      title: 'Consulta Validade',
                      subtitle: 'Buscar produto por SKU ou nome',
                      color: AppColors.info,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SkuListScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Itens em Criticidade - Visível para todos
                    _buildMenuButton(
                      context,
                      icon: Icons.warning_amber_rounded,
                      title: 'Itens em Criticidade',
                      subtitle: 'Produtos bloqueados e pré-bloqueio',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CriticalItemsScreen(),
                          ),
                        );
                      },
                    ),

                    // Estoque Inicial - Visível apenas para GERENTE e DIRETORIA
                    if (usuario?.canViewDashboard ?? false) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildMenuButton(
                        context,
                        icon: Icons.inventory_2_outlined,
                        title: 'Estoque Inicial',
                        subtitle: 'Visão geral do estoque',
                        color: AppColors.success,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StockReportScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              
              // Rodapé de última atualização
              _buildUltimaAtualizacao(),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget do rodapé com data da última atualização de estoque
  Widget _buildUltimaAtualizacao() {
    String texto;
    
    if (_isLoadingUpload) {
      texto = 'Verificando última atualização...';
    } else if (_ultimoUpload?.dataUpload != null) {
      final dateFormat = DateFormat('dd/MM/yyyy');
      final timeFormat = DateFormat('HH:mm');
      final data = _ultimoUpload!.dataUpload!.toLocal(); // Converte UTC para horário local
      texto = 'Última atualização de estoque: ${dateFormat.format(data)} às ${timeFormat.format(data)}';
    } else {
      texto = 'Nenhuma atualização recente';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.update,
            size: 14,
            color: AppColors.textSecondary.withOpacity(0.7),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: color,
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
                          fontSize: AppFontSizes.subtitle,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.body,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
