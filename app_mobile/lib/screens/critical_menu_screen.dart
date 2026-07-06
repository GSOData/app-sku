import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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
      setState(() {
        _bloqueadosVencidos = result.bloqueados;
        _riscoVencimento = result.riscoVencimento;
        _preBloqueio = result.preBloqueio;
      });
    } on AuthException catch (e) {
      _handleAuthError(e.message);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleAuthError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error));
    Provider.of<AuthService>(context, listen: false).logout();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  void _navigateToList(String title, List<Sku> items, Color themeColor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CriticalItemsScreen(
          title: title,
          skus: items,
          themeColor: themeColor,
          onRefreshData: _loadData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final canManage = authService.usuario?.isControle == true || authService.usuario?.isAdmin == true;
    final showBackButton = kIsWeb || Navigator.canPop(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Atenção Necessária', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.error))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.error,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text('Selecione a categoria', style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.md),
                  if (authService.usuario?.isVendedor == false) ...[
                    _buildMenuCard(
                      title: 'Bloqueado',
                      subtitle: 'Produtos vencidos na filial',
                      count: _bloqueadosVencidos.length,
                      color: Colors.black87,
                      icon: Icons.block,
                      onTap: () => _navigateToList('Bloqueados', _bloqueadosVencidos, Colors.black87),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _buildMenuCard(
                    title: 'Risco de Vencimento',
                    subtitle: 'Críticos e bloqueados para venda futura',
                    count: _riscoVencimento.length,
                    color: AppColors.error,
                    icon: Icons.warning_amber_rounded,
                    onTap: () => _navigateToList('Risco de Vencimento', _riscoVencimento, AppColors.error),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showAddCriticalBottomSheet(context),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.post_add, color: Colors.white),
              label: Text('Lançar Crítico', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required int count, required Color color, required IconData icon, required VoidCallback onTap}) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(width: 60, height: 60, decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.md)), child: Icon(icon, size: 32, color: color)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600)),
                    Text(subtitle, style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)), child: Text(count.toString(), style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.bold, color: Colors.white))),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCriticalBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(AppRadius.lg), topRight: Radius.circular(AppRadius.lg))),
      builder: (_) => const _AddCriticalFormModal(),
    ).then((value) {
      if (value == true) _loadData();
    });
  }
}

class _AddCriticalFormModal extends StatefulWidget {
  const _AddCriticalFormModal();
  @override
  State<_AddCriticalFormModal> createState() => _AddCriticalFormModalState();
}

class _AddCriticalFormModalState extends State<_AddCriticalFormModal> {
  final _skuController = TextEditingController();
  final _qtdController = TextEditingController();
  
  bool _searchingSku = false;
  bool _isSaving = false;
  int? _foundSkuId;
  String? _skuNome;
  String? _skuCategoria;
  DateTime? _selectedDate;

  Future<void> _buscarSku() async {
    if (_skuController.text.isEmpty) return;
    setState(() { _searchingSku = true; _skuNome = null; _foundSkuId = null; });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final response = await http.get(
        Uri.parse('${Constants.apiUrl}skus/buscar_por_codigo/?codigo=${_skuController.text}&unidade_id=${authService.unidadeAtiva?.id}'),
        headers: {'Authorization': 'Bearer ${authService.accessToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _foundSkuId = data['id'];
          _skuNome = data['nome_produto'];
          _skuCategoria = data['categoria'];
        });
      } else {
        _showSnackBar('Produto não localizado no estoque.', AppColors.error);
      }
    } catch (e) {
      _showSnackBar('Erro de conexão.', AppColors.error);
    } finally {
      setState(() => _searchingSku = false);
    }
  }

  Future<void> _selecionarData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _salvar() async {
    if (_foundSkuId == null || _qtdController.text.isEmpty || _selectedDate == null) {
      _showSnackBar('Preencha todos os campos obrigatórios.', AppColors.error);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final response = await http.post(
        Uri.parse('${Constants.apiUrl}lancamentos-criticos/'),
        headers: {'Authorization': 'Bearer ${authService.accessToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'sku': _foundSkuId,
          'unidade_negocio': authService.unidadeAtiva?.id,
          'quantidade_critica': int.parse(_qtdController.text),
          'data_validade': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        }),
      );
      if (response.statusCode == 201) {
        _showSnackBar('Lançamento realizado com sucesso!', AppColors.success);
        Navigator.pop(context, true);
      } else {
        _showSnackBar('Erro ao salvar lançamento.', AppColors.error);
      }
    } catch (e) {
      _showSnackBar('Erro interno.', AppColors.error);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lançar Item Crítico Manual', style: GoogleFonts.poppins(fontSize: AppFontSizes.title, fontWeight: FontWeight.bold)),
          Text('Filial: ${authService.unidadeAtiva?.nome ?? ""}', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: TextField(controller: _skuController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Código do SKU', border: OutlineInputBorder()))),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(onPressed: _searchingSku ? null : _buscarSku, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(18)), child: _searchingSku ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search)),
            ],
          ),
          if (_skuNome != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: Colors.grey.withAlpha(20), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: Colors.grey.withAlpha(60))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_skuNome!, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                Text('Categoria: $_skuCategoria', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _qtdController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade Crítica (Caixas)', border: OutlineInputBorder())),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _selecionarData,
              icon: const Icon(Icons.calendar_month),
              label: Text(_selectedDate == null ? 'Selecionar Data de Validade' : 'Validade: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isSaving ? null : _salvar, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16)), child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : Text('Salvar Alerta', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)))),
          ]
        ],
      ),
    );
  }
}