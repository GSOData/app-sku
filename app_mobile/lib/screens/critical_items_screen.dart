import 'dart:convert';
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

  // --- NOVO: Pop-up Inteligente de Motivos ---
  Future<String?> _obterMotivoResolucao(BuildContext context, Sku sku) async {
    String? motivoSelecionado;
    final motivos = [
      'Venda / Saída Normal',
      'Perda / Avaria (Descarte)',
      'Recolhimento / Troca',
      'Lançamento Indevido (Erro)'
    ];

    return await showDialog<String>(
      context: context,
      barrierDismissible: false, // Força a escolha
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              title: Text('Resolver Alerta', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Qual o motivo da baixa deste alerta para:\n"${sku.nomeProduto}"?', style: GoogleFonts.poppins(fontSize: 14)),
                  const SizedBox(height: 16),
                  ...motivos.map((m) => RadioListTile<String>(
                    title: Text(m, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                    value: m,
                    groupValue: motivoSelecionado,
                    onChanged: (val) => setState(() => motivoSelecionado = val),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                  )),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: motivoSelecionado == null ? null : () => Navigator.of(context).pop(motivoSelecionado),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  child: const Text('Confirmar Baixa', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  // --- NOVO: Chama o endpoint POST /resolver/ ---
  Future<bool> _resolverAlertaApi(Sku sku, String motivo) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final lancamentoId = sku.id; 

      final response = await http.post(
        Uri.parse('${Constants.apiUrl}lancamentos-criticos/$lancamentoId/resolver/'),
        headers: {
          'Authorization': 'Bearer ${authService.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'motivo': motivo}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alerta resolvido e registrado no histórico!'), backgroundColor: AppColors.success));
        }
        return true;
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha ao comunicar com o servidor.'), backgroundColor: AppColors.error));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    
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
                    // O Flutter pausa o arrasto até que o usuário responda o Pop-up
                    confirmDismiss: (_) async {
                      if (authService.usuario?.isVendedor == true) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Apenas a equipe de Controle pode resolver alertas.'), backgroundColor: AppColors.error));
                        return false;
                      }

                      // 1. Abre Pop-up e pega o motivo
                      final motivo = await _obterMotivoResolucao(context, sku);
                      if (motivo != null) {
                        // 2. Chama a API para salvar a auditoria
                        final sucesso = await _resolverAlertaApi(sku, motivo);
                        if (sucesso) {
                          setState(() => _localSkus.removeAt(index));
                          widget.onRefreshData(); // Recalcula os números do Menu
                          return true; // Deixa o card sumir da tela
                        }
                      }
                      return false; // Se cancelar ou der erro, o card volta pro lugar
                    },
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
    final unidadeText = sku.unidadeMedida != null ? ' ${sku.unidadeMedida!.toLowerCase()}' : ' un';
    
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: sku.statusColor.withAlpha(100), width: 2)),
      elevation: 3,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SkuDetailScreen(sku: sku, isCriticalItem: true))),
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
                    Text('Volume Retido: ${sku.formatarQuantidade(sku.qtdDisponivelVenda)}$unidadeText', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
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