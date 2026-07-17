import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';
import '../../services/auth_service.dart';
import '../../services/upload_service.dart' hide UnidadeNegocio;
import '../../services/sku_service.dart' hide AuthException;
import '../login_screen.dart';

/// Tela de Upload de Arquivos (Web)
///
/// Suporta o Processamento FEFO Reverso (3 planilhas) e a Importação de Itens Críticos (1 planilha).
class WebUploadScreen extends StatefulWidget {
  const WebUploadScreen({super.key});

  @override
  State<WebUploadScreen> createState() => _WebUploadScreenState();
}

class _WebUploadScreenState extends State<WebUploadScreen> {
  late UploadService _uploadService;
  late SkuService _skuService;

  // Estados globais
  bool _isLoadingUnidades = true;
  bool _isUploadingFefo = false;
  bool _isUploadingCriticos = false;
  bool _isLoadingHistory = false;

  // Unidades
  List<UnidadeNegocio> _unidades = [];
  UnidadeNegocio? _selectedUnidade;

  // Arquivos FEFO
  ArquivoUpload? _arquivo020502;
  ArquivoUpload? _arquivo020304;
  ArquivoUpload? _arquivoNri;

  // Arquivo Críticos
  ArquivoUpload? _arquivoCriticos;

  // Histórico
  List<HistoricoUpload> _uploadHistory = [];

  // -----------------------------------------------------------------------
  // Inicialização
  // -----------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _uploadService = UploadService(authService: authService);
    _skuService = SkuService(authService: authService);
    _loadUnidades();
    _loadUploadHistory();
  }

  Future<void> _loadUnidades() async {
    setState(() => _isLoadingUnidades = true);
    try {
      final unidades = await _uploadService.getUnidades();
      setState(() {
        _unidades = unidades;
        _isLoadingUnidades = false;
      });
    } catch (e) {
      setState(() => _isLoadingUnidades = false);
      if (mounted) _showError('Erro ao carregar unidades: $e');
    }
  }

  Future<void> _loadUploadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final result = await _skuService.getHistoricoUpload();
      setState(() {
        _uploadHistory = result.results;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      debugPrint('Erro ao carregar histórico: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Build principal
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Upload de Dados',
      currentSection: WebMenuSection.upload,
      mobileBody: _buildMobileContent(),
      webBody: _buildWebContent(),
    );
  }

  Widget _buildMobileContent() {
    return const Center(
      child: Text('Upload de Dados disponível apenas na versão Web'),
    );
  }

  Widget _buildWebContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUnidadeSelector(),
          const SizedBox(height: AppSpacing.xl),
          
          // Layout lado a lado em telas grandes ou empilhado em telas menores
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return IntrinsicHeight( // MÁGICA: Iguala a altura dos cards
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildFefoUploadSection()),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(child: _buildCriticosUploadSection()),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  _buildFefoUploadSection(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildCriticosUploadSection(),
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.xl),
          _buildInstructions(),
          const SizedBox(height: AppSpacing.xl),
          _buildUploadHistory(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Seleção de unidade
  // -----------------------------------------------------------------------

  Widget _buildUnidadeSelector() {
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
              children: [
                Icon(Icons.business, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Unidade de Negócio',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Selecione a filial para qual os dados serão importados',
              style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isLoadingUnidades)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<UnidadeNegocio>(
                value: _selectedUnidade,
                decoration: InputDecoration(
                  hintText: 'Selecione uma unidade...',
                  prefixIcon: const Icon(Icons.store),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                ),
                items: _unidades.map((u) {
                  return DropdownMenuItem<UnidadeNegocio>(
                    value: u,
                    child: Text('${u.codigoUnb} - ${u.nome}'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedUnidade = value),
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Formulário FEFO (3 planilhas)
  // -----------------------------------------------------------------------

  Widget _buildFefoUploadSection() {
    final int selecionados = [_arquivo020502, _arquivo020304, _arquivoNri].where((a) => a != null).length;
    final bool todosArquivosSelecionados = selecionados == 3;
    final bool podeProcesar = _selectedUnidade != null && todosArquivosSelecionados && !_isUploadingFefo && !_isUploadingCriticos;

    String hint = '';
    if (_selectedUnidade == null) {
      hint = 'Selecione a unidade de negócio.';
    } else if (!todosArquivosSelecionados) {
      hint = 'Selecione as 3 planilhas.';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.divider.withAlpha(128))),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Empurra o botão pro rodapé
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(color: AppColors.primary.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Icon(Icons.auto_awesome, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Processamento FEFO', style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text('Selecione as 3 planilhas para atualizar o Estoque Geral', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildProgressIndicator(3, selecionados),
                const SizedBox(height: AppSpacing.xl),
                _buildFilePicker(
                  label: 'Grade 020502', sublabel: 'Estoque Total Diário', icon: Icons.inventory_2_outlined, color: AppColors.primary,
                  arquivo: _arquivo020502, onSelect: () => _selectFile('020502'), onClear: () => setState(() => _arquivo020502 = null),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildFilePicker(
                  label: 'Grade 020304', sublabel: 'Buffer de Segurança', icon: Icons.safety_check_outlined, color: AppColors.info,
                  arquivo: _arquivo020304, onSelect: () => _selectFile('020304'), onClear: () => setState(() => _arquivo020304 = null),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildFilePicker(
                  label: 'Planilha NRI', sublabel: 'Não-Regular de Inventário', icon: Icons.description_outlined, color: AppColors.warning,
                  arquivo: _arquivoNri, onSelect: () => _selectFile('nri'), onClear: () => setState(() => _arquivoNri = null),
                ),
              ],
            ),
            
            const SizedBox(height: AppSpacing.xl),
            
            if (_isUploadingFefo)
              _buildUploadProgress('Processando estoque FEFO...', [
                _arquivo020502?.nome ?? '',
                _arquivo020304?.nome ?? '',
                _arquivoNri?.nome ?? '',
              ].where((n) => n.isNotEmpty).join(' • '))
            else
              _buildProcessarButton(
                label: 'Processar Estoque FEFO',
                icon: Icons.bolt,
                enabled: podeProcesar,
                hint: hint,
                onPressed: _performUploadFefo,
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Formulário CRÍTICOS (1 planilha)
  // -----------------------------------------------------------------------

  Widget _buildCriticosUploadSection() {
    final bool selecionado = _arquivoCriticos != null;
    final bool podeProcesar = _selectedUnidade != null && selecionado && !_isUploadingFefo && !_isUploadingCriticos;

    String hint = '';
    if (_selectedUnidade == null) {
      hint = 'Selecione a unidade de negócio.';
    } else if (!selecionado) {
      hint = 'Selecione a planilha de críticos.';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.divider.withAlpha(128))),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Empurra o botão pro rodapé
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(color: AppColors.error.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Icon(Icons.crisis_alert, color: AppColors.error, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Importação de Itens Críticos', style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text('Envie a planilha de apontamento manual', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildProgressIndicator(1, selecionado ? 1 : 0),
                const SizedBox(height: AppSpacing.xl),
                _buildFilePicker(
                  label: 'Planilha de Críticos', sublabel: 'Formato: Cod, Qtd, Vencto...', icon: Icons.table_view_outlined, color: AppColors.error,
                  arquivo: _arquivoCriticos, onSelect: () => _selectFile('criticos'), onClear: () => setState(() => _arquivoCriticos = null),
                ),
                const SizedBox(height: AppSpacing.md),
                
                // Área de aviso de Ground Zero
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: AppColors.error.withAlpha(50))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta importação sobrescreve todos os lançamentos críticos anteriores da filial (Fotografia).',
                          style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: AppSpacing.xl),

            if (_isUploadingCriticos)
              _buildUploadProgress('Processando itens críticos...', _arquivoCriticos?.nome ?? '')
            else
              _buildProcessarButton(
                label: 'Importar Críticos',
                icon: Icons.upload,
                color: AppColors.error,
                enabled: podeProcesar,
                hint: hint,
                onPressed: _performUploadCriticos,
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Componentes Auxiliares Compartilhados
  // -----------------------------------------------------------------------

  Widget _buildProgressIndicator(int total, int preenchidos) {
    return Row(
      children: List.generate(total, (i) {
        final filled = i < preenchidos;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < (total - 1) ? AppSpacing.xs : 0),
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: filled ? AppColors.primary : AppColors.divider.withAlpha(128),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFilePicker({
    required String label, required String sublabel, required IconData icon, required Color color,
    required ArquivoUpload? arquivo, required VoidCallback onSelect, required VoidCallback onClear,
  }) {
    final bool selecionado = arquivo != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: selecionado ? color.withAlpha(13) : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: selecionado ? color.withAlpha(128) : AppColors.divider, width: selecionado ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(selecionado ? Icons.check_circle : icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(selecionado ? arquivo.nome : sublabel, style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: selecionado ? color : AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (selecionado)
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: (_isUploadingFefo || _isUploadingCriticos) ? null : onClear, color: AppColors.textSecondary)
          else
            TextButton.icon(
              onPressed: _selectedUnidade == null || _isUploadingFefo || _isUploadingCriticos ? null : onSelect,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Selecionar'),
              style: TextButton.styleFrom(foregroundColor: color),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessarButton({required String label, required IconData icon, required bool enabled, required String hint, required VoidCallback onPressed, Color color = AppColors.primary}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.divider,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(hint, style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.warning), textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _buildUploadProgress(String titulo, String subtitulo) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.divider)),
      child: Row(
        children: [
          const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(subtitulo, style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Instruções
  // -----------------------------------------------------------------------

  Widget _buildInstructions() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.divider.withAlpha(128))),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Text('Instruções de Upload', style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _buildInstructionStep('Estoque FEFO:', 'Requer 3 planilhas (020502, 020304, NRI). Serve para atualizar a visão macro dos vendedores.'),
            _buildInstructionStep('Itens Críticos:', 'Requer 1 planilha contendo as colunas exatas: "Cod produto", "Qtd", "Data Vencto", "Data Recebimento". Sobrescreve alertas anteriores da filial.'),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.warning.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Formatos aceitos: .xlsx, .xls, .csv (máximo 10MB por arquivo)', style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.warning))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: AppFontSizes.body, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Histórico
  // -----------------------------------------------------------------------

  Widget _buildUploadHistory() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.divider.withAlpha(128))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Histórico de Uploads', style: GoogleFonts.poppins(fontSize: AppFontSizes.subtitle, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                IconButton(
                  onPressed: _loadUploadHistory,
                  icon: _isLoadingHistory ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 18),
                  tooltip: 'Atualizar histórico',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoadingHistory && _uploadHistory.isEmpty)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
          else if (_uploadHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.history, size: 48, color: AppColors.textSecondary.withAlpha(128)),
                    const SizedBox(height: AppSpacing.md),
                    Text('Nenhum upload realizado', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _uploadHistory.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _buildHistoryItem(_uploadHistory[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(HistoricoUpload item) {
    final statusColor = item.isSuccess ? AppColors.success : AppColors.error;
    final statusIcon = item.isSuccess ? Icons.check_circle : Icons.error;
    final timestamp = _formatTimestamp(item.createdAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(color: statusColor.withAlpha(26), borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(statusIcon, color: statusColor, size: 24),
      ),
      title: Text(item.nomeArquivo, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${item.tipoArquivoDisplay} • ${item.unidadeNome} • $timestamp', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary)),
          Text('Por ${item.usuarioNome}', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: AppColors.textSecondary)),
          if (item.mensagemErro != null && item.mensagemErro!.isNotEmpty)
            Text(item.mensagemErro!, style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, color: statusColor)),
        ],
      ),
      trailing: item.linhasProcessadas > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Text('${item.linhasProcessadas} SKUs', style: GoogleFonts.poppins(fontSize: AppFontSizes.caption, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            )
          : null,
    );
  }

  // -----------------------------------------------------------------------
  // Métodos de Arquivo e API
  // -----------------------------------------------------------------------

  Future<void> _selectFile(String tipo) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'], withData: true);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.size > 10 * 1024 * 1024) {
        _showError('Arquivo muito grande. Máximo permitido: 10MB');
        return;
      }
      if (file.bytes == null) {
        _showError('Não foi possível ler o arquivo. Tente novamente.');
        return;
      }

      final arquivo = ArquivoUpload(nome: file.name, bytes: file.bytes!);

      setState(() {
        if (tipo == '020502') _arquivo020502 = arquivo;
        else if (tipo == '020304') _arquivo020304 = arquivo;
        else if (tipo == 'nri') _arquivoNri = arquivo;
        else if (tipo == 'criticos') _arquivoCriticos = arquivo;
      });
    } catch (e) {
      _showError('Erro ao selecionar arquivo: $e');
    }
  }

  Future<void> _performUploadFefo() async {
    if (_selectedUnidade == null || _arquivo020502 == null || _arquivo020304 == null || _arquivoNri == null) return;
    setState(() => _isUploadingFefo = true);

    try {
      final result = await _uploadService.uploadEstoqueFefo(arquivo020502: _arquivo020502!, arquivo020304: _arquivo020304!, arquivoNri: _arquivoNri!, unidadeNegocioId: _selectedUnidade!.id);
      setState(() {
        _isUploadingFefo = false;
        if (result.success) { _arquivo020502 = null; _arquivo020304 = null; _arquivoNri = null; }
      });

      if (result.success) {
        _showSuccess('Estoque FEFO processado com sucesso! ${result.skusAtualizados} SKUs atualizados.');
      } else {
        _showError(result.errorMessage ?? 'Erro ao processar arquivos.');
      }
      if (result.warnings.isNotEmpty) _showWarning('Avisos: ${result.warnings.join(", ")}');
      _loadUploadHistory();
    } on AuthException catch (e) {
      setState(() => _isUploadingFefo = false);
      _handleAuthError(e.message);
    } catch (e) {
      setState(() => _isUploadingFefo = false);
      _showError('Erro ao enviar arquivos: $e');
    }
  }

  Future<void> _performUploadCriticos() async {
    if (_selectedUnidade == null || _arquivoCriticos == null) return;
    setState(() => _isUploadingCriticos = true);

    try {
      final result = await _uploadService.uploadPlanilhaCriticos(arquivo: _arquivoCriticos!, unidadeNegocioId: _selectedUnidade!.id);
      
      setState(() {
        _isUploadingCriticos = false;
        if (result.success) _arquivoCriticos = null; 
      });

      if (result.success) {
        _showSuccess('Importação concluída! ${result.skusAtualizados} itens críticos atualizados.');
      } else {
        _showErrorDialog('Falha na Importação', result.errorMessage ?? 'Verifique a formatação da sua planilha.');
      }
      _loadUploadHistory();
    } on AuthException catch (e) {
      setState(() => _isUploadingCriticos = false);
      _handleAuthError(e.message);
    } catch (e) {
      setState(() => _isUploadingCriticos = false);
      _showError('Erro ao enviar a planilha: $e');
    }
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.success, duration: const Duration(seconds: 4)));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error, duration: const Duration(seconds: 5)));
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.warning));
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(child: Text(message, style: GoogleFonts.poppins(fontSize: 14))),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Entendi, vou corrigir', style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  void _handleAuthError(String message) {
    _showError(message);
    Provider.of<AuthService>(context, listen: false).logout();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }
}