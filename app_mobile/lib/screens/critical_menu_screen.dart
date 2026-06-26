import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../services/sku_service.dart';
import '../utils/constants.dart';
import 'login_screen.dart';
import 'critical_items_screen.dart';
import 'web/web_dashboard_screen.dart';

class CriticalMenuScreen extends StatefulWidget {
  const CriticalMenuScreen({super.key});

  @override
  State<CriticalMenuScreen> createState() => _CriticalMenuScreenState();
}

class _CriticalMenuScreenState extends State<CriticalMenuScreen> {
  late SkuService _skuService;
  
  bool _isLoading = true;
  String? _errorMessage;

  // Listas separadas para passar para a próxima tela
  List<Sku> _bloqueadosVencidos = [];
  List<Sku> _riscoVencimento = [];
  List<Sku> _preBloqueio = [];

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _skuService = SkuService(authService: authService);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _skuService.getRelatorioCriticidade();
      
      List<Sku> vencidos = [];
      List<Sku> criticos = [];
      
      // Separa os itens que vêm do backend
      for (final sku in result.bloqueados) {
        final status = sku.statusTexto.toLowerCase();
        if (status == 'vencido') {
          vencidos.add(sku);
        } else {
          criticos.add(sku);
        }
      }

      // Ordena cada lista internamente pelos dias restantes
      vencidos.sort((a, b) => (a.statusDiasRestantes ?? 999).compareTo(b.statusDiasRestantes ?? 999));
      criticos.sort((a, b) => (a.statusDiasRestantes ?? 999).compareTo(b.statusDiasRestantes ?? 999));
      result.preBloqueio.sort((a, b) => (a.statusDiasRestantes ?? 999).compareTo(b.statusDiasRestantes ?? 999));

      setState(() {
        _bloqueadosVencidos = vencidos;
        _riscoVencimento = criticos;
        _preBloqueio = result.preBloqueio;
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
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _navigateToList(String title, List<Sku> items, Color themeColor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CriticalItemsScreen(
          title: title,
          skus: items,
          themeColor: themeColor,
          onRefreshData: _loadData, // Permite que a tela de lista mande recarregar tudo
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final isVendedor = authService.usuario?.isVendedor ?? false;
    final showBackButton = kIsWeb || Navigator.canPop(context);

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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.error))
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.error,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Text(
                        'Selecione a categoria',
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.subtitle,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Botão 1: Bloqueado (Oculto se for Vendedor)
                      if (!isVendedor) ...[
                        _buildMenuCard(
                          title: 'Bloqueado',
                          subtitle: 'Vencidos ou sem lote',
                          count: _bloqueadosVencidos.length,
                          color: Colors.black87,
                          icon: Icons.block,
                          onTap: () => _navigateToList('Bloqueados', _bloqueadosVencidos, Colors.black87),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Botão 2: Risco de Vencimento
                      _buildMenuCard(
                        title: 'Risco de Vencimento',
                        subtitle: 'Críticos e bloqueados para venda futura',
                        count: _riscoVencimento.length,
                        color: AppColors.error,
                        icon: Icons.warning_amber_rounded,
                        onTap: () => _navigateToList('Risco de Vencimento', _riscoVencimento, AppColors.error),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Botão 3: Pré-bloqueio
                      _buildMenuCard(
                        title: 'Pré-bloqueio',
                        subtitle: 'Itens em alerta amarelo',
                        count: _preBloqueio.length,
                        color: AppColors.warning,
                        icon: Icons.schedule,
                        onTap: () => _navigateToList('Pré-bloqueio', _preBloqueio, AppColors.warning),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: color.withAlpha(50), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                child: Icon(icon, size: 32, color: color),
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
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  count.toString(),
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
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
            Icon(Icons.error_outline, size: 64, color: AppColors.error.withAlpha(180)),
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
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: _loadData,
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
}