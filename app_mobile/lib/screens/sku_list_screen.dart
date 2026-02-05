import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../services/sku_service.dart';
import '../utils/constants.dart';
import 'login_screen.dart';
import 'sku_detail_screen.dart';

class SkuListScreen extends StatefulWidget {
  const SkuListScreen({super.key});

  @override
  State<SkuListScreen> createState() => _SkuListScreenState();
}

class _SkuListScreenState extends State<SkuListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late SkuService _skuService;
  
  List<Sku> _skus = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _skuService = SkuService(authService: authService);
    
    // Carrega lista inicial
    _loadSkus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSkus({String? query}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _skuService.getSkus(query: query);
      setState(() {
        _skus = result.results;
        _hasSearched = query != null && query.isNotEmpty;
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

    // Faz logout e redireciona para login
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.logout();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    _loadSkus(query: query.isNotEmpty ? query : null);
  }

  void _clearSearch() {
    _searchController.clear();
    _loadSkus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Consulta Validade',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Barra de busca
          _buildSearchBar(),

          // Lista de resultados
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _onSearch(),
        style: GoogleFonts.poppins(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar por código SKU ou nome...',
          hintStyle: GoogleFonts.poppins(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                  onPressed: _clearSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search, color: AppColors.primary),
                  onPressed: _onSearch,
                ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() {}); // Atualiza o ícone de limpar
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_skus.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadSkus(
        query: _searchController.text.isNotEmpty 
            ? _searchController.text 
            : null,
      ),
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _skus.length,
        itemBuilder: (context, index) {
          return _buildSkuCard(_skus[index]);
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
              onPressed: _loadSkus,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
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
              _hasSearched ? Icons.search_off : Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.textSecondary.withAlpha(180),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _hasSearched ? 'Nenhum resultado' : 'Nenhum produto',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _hasSearched
                  ? 'Tente buscar com outro termo'
                  : 'Não há produtos cadastrados',
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

  Widget _buildSkuCard(Sku sku) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      elevation: 2,
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
          child: Row(
            children: [
              // Ícone/Imagem do produto
              _buildProductIcon(sku),
              
              const SizedBox(width: AppSpacing.md),

              // Informações do produto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nome do produto
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
                    
                    const SizedBox(height: AppSpacing.xs),

                    // Código SKU
                    Text(
                      'SKU: ${sku.codigoSku}',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.body,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    // Quantidade e Status
                    Row(
                      children: [
                        // Ícone da unidade de medida
                        _getUnidadeMedidaIcon(sku.unidadeMedida, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Qtd: ${sku.quantidadeTotal} ${sku.unidadeMedida ?? ''}',
                          style: GoogleFonts.poppins(
                            fontSize: AppFontSizes.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        
                        const SizedBox(width: AppSpacing.md),

                        // Dias restantes
                        if (sku.statusDiasRestantes != null) ...[
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: sku.statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${sku.statusDiasRestantes} dias',
                            style: GoogleFonts.poppins(
                              fontSize: AppFontSizes.caption,
                              color: sku.statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Badge de status
              _buildStatusBadge(sku),

              const SizedBox(width: AppSpacing.sm),

              // Seta
              Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductIcon(Sku sku) {
    if (sku.imagemUrl != null && sku.imagemUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.network(
          sku.imagemUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildDefaultIcon(sku),
        ),
      );
    }
    return _buildDefaultIcon(sku);
  }

  Widget _buildDefaultIcon(Sku sku) {
    final iconData = _getUnidadeMedidaIconData(sku.unidadeMedida);
    final iconColor = _getUnidadeMedidaColor(sku.unidadeMedida);
    
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: iconColor.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 28,
      ),
    );
  }

  Widget _buildStatusBadge(Sku sku) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: sku.statusColor.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: sku.statusColor.withAlpha(77),
          width: 1,
        ),
      ),
      child: Text(
        sku.statusTexto,
        style: GoogleFonts.poppins(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w600,
          color: sku.statusColor,
        ),
      ),
    );
  }

  /// Retorna o IconData baseado na unidade de medida
  IconData _getUnidadeMedidaIconData(String? unidade) {
    switch (unidade?.toUpperCase()) {
      case 'CX':
        return Icons.inbox_outlined;
      case 'PCT':
        return Icons.shopping_bag_outlined;
      case 'FD':
        return Icons.grid_view;
      case 'UN':
        return Icons.extension_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  /// Retorna a cor baseada na unidade de medida
  Color _getUnidadeMedidaColor(String? unidade) {
    switch (unidade?.toUpperCase()) {
      case 'CX':
        return Colors.brown;
      case 'PCT':
        return Colors.blue;
      case 'FD':
        return Colors.orange;
      case 'UN':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }

  /// Widget helper que retorna o ícone com a cor da unidade de medida
  Widget _getUnidadeMedidaIcon(String? unidade, {double size = 24}) {
    return Icon(
      _getUnidadeMedidaIconData(unidade),
      color: _getUnidadeMedidaColor(unidade),
      size: size,
    );
  }
}
