import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../models/sku_model.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import 'sku_detail_screen.dart';

class CriticalItemsScreen extends StatefulWidget {
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
  State<CriticalItemsScreen> createState() => _CriticalItemsScreenState();
}

class _CriticalItemsScreenState extends State<CriticalItemsScreen> {
  late List<Sku> _localSkus;

  @override
  void initState() {
    super.initState();
    _localSkus = List.from(widget.skus);
  }

  Future<bool> _confirmarDelecao(BuildContext context, Sku sku) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    // Vendedores não têm privilégio para remover o post-it da controladoria
    if (authService.usuario?.isVendedor == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Apenas a equipe de Controle pode resolver alertas.'), backgroundColor: AppColors.error));
      return false;
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Resolver Alerta?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: Text('Confirmar que a irregularidade do produto "${sku.nomeProduto}" foi sanada e remover o alerta do painel?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary))),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('Sim, Concluir', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _removerAlertaApi(Sku sku, int index) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      // Puxa o ID do lançamento manual que mapeámos dinamicamente na View do Django
      final lancamentoId = sku.id; 

      final response = await http.delete(
        Uri.parse('${Constants.apiUrl}lancamentos-criticos/$lancamentoId/'),
        headers: {'Authorization': 'Bearer ${authService.accessToken}'},
      );

      if (response.statusCode == 204) {
        setState(() { _localSkus.removeAt(index); });
        widget.onRefreshData(); // Avisa o menu para recalcular os contadores numéricos grandes
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alerta resolvido com sucesso!'), backgroundColor: AppColors.success));
        }
      } else {
        throw Exception();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha ao comunicar exclusão com o servidor.'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)), backgroundColor: widget.themeColor, foregroundColor: Colors.white, elevation: 0),
      body: _localSkus.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: widget.onRefreshData,
              color: widget.themeColor,
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _localSkus.length,
                itemBuilder: (context, index) {
                  final sku = _localSkus[index];
                  return Dismissible(
                    key: Key(sku.id.toString()),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmarDelecao(context, sku),
                    onDismissed: (_) => _removerAlertaApi(sku, index),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(AppRadius.md)),
                      alignment: Alignment.centerRight,
                      child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('Resolver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
                    ),
                    child: _buildCriticalCard(context, sku),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline, size: 80, color: AppColors.success.withAlpha(180)),
          const SizedBox(height: AppSpacing.md),
          Text('Tudo resolvido! 🎉', style: GoogleFonts.poppins(fontSize: AppFontSizes.headline, fontWeight: FontWeight.w600, color: AppColors.success)),
          Text('Não há pendências manuais nesta pasta.', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _buildCriticalCard(BuildContext context, Sku sku) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: sku.statusColor.withAlpha(100), width: 2)),
      elevation: 3,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SkuDetailScreen(sku: sku))),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(color: sku.statusColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.md), topRight: Radius.circular(AppRadius.md))),
            child: Row(children: [
              const Icon(Icons.label_important_outline, color: Colors.white, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(sku.statusTexto.toUpperCase(), style: GoogleFonts.poppins(fontSize: AppFontSizes.body, fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: sku.statusColor.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.sm)), child: Icon(Icons.inventory_2_outlined, color: sku.statusColor, size: 24)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sku.nomeProduto, style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('SKU: ${sku.codigoSku}', style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.crisis_alert, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('Volume Retido: ${sku.qtdDisponivelVenda}', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ]),
          ),
        ]),
      ),
    );
  }
}