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

/// Tela de Upload de Arquivos (Web) — Processamento FEFO Reverso.
///
/// Recebe 3 planilhas simultâneas (020502, 020304, NRI) e envia para
/// o endpoint unificado POST /api/upload/grade-020502/.
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
  bool _isUploading = false;
  bool _isLoadingHistory = false;

  // Unidades
  List<UnidadeNegocio> _unidades = [];
  UnidadeNegocio? _selectedUnidade;

  // Arquivos selecionados — null = ainda não selecionado
  ArquivoUpload? _arquivo020502;
  ArquivoUpload? _arquivo020304;
  ArquivoUpload? _arquivoNri;

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
          _buildFefoUploadSection(),
          const SizedBox(height: AppSpacing.xl),
          _buildInstructions(),
          const SizedBox(height: AppSpacing.xl),
          _buildUploadHistory(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Seleção de unidade (sem alterações em relação ao original)
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
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Obrigatório',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Selecione a filial para qual os dados serão importados',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
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
  // Formulário FEFO com 3 seletores + botão de processar
  // -----------------------------------------------------------------------

  Widget _buildFefoUploadSection() {
    final bool todosArquivosSelecionados =
        _arquivo020502 != null &&
        _arquivo020304 != null &&
        _arquivoNri != null;

    final bool podeProcesar =
        _selectedUnidade != null &&
        todosArquivosSelecionados &&
        !_isUploading;

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
            // Cabeçalho
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.auto_awesome,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Processamento FEFO',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.subtitle,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Selecione as 3 planilhas para calcular o estoque gerencial',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // Linha de progresso — indica quantos arquivos foram selecionados
            _buildProgressIndicator(),

            const SizedBox(height: AppSpacing.xl),

            // 3 seletores de arquivo
            _buildFilePicker(
              label: 'Grade 020502',
              sublabel: 'Estoque Total Diário',
              icon: Icons.inventory_2_outlined,
              color: AppColors.primary,
              arquivo: _arquivo020502,
              onSelect: () => _selectFile('020502'),
              onClear: () => setState(() => _arquivo020502 = null),
            ),

            const SizedBox(height: AppSpacing.md),

            _buildFilePicker(
              label: 'Grade 020304',
              sublabel: 'Buffer de Segurança',
              icon: Icons.safety_check_outlined,
              color: AppColors.info,
              arquivo: _arquivo020304,
              onSelect: () => _selectFile('020304'),
              onClear: () => setState(() => _arquivo020304 = null),
            ),

            const SizedBox(height: AppSpacing.md),

            _buildFilePicker(
              label: 'Planilha NRI',
              sublabel: 'Não-Regular de Inventário',
              icon: Icons.description_outlined,
              color: AppColors.warning,
              arquivo: _arquivoNri,
              onSelect: () => _selectFile('nri'),
              onClear: () => setState(() => _arquivoNri = null),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Estado de carregamento OU botão principal
            if (_isUploading)
              _buildUploadProgress()
            else
              _buildProcessarButton(
                enabled: podeProcesar,
                allSelected: todosArquivosSelecionados,
              ),
          ],
        ),
      ),
    );
  }

  /// Barra de progresso visual (0/3, 1/3, 2/3, 3/3 arquivos).
  Widget _buildProgressIndicator() {
    final count = [_arquivo020502, _arquivo020304, _arquivoNri]
        .where((a) => a != null)
        .length;

    return Row(
      children: List.generate(3, (i) {
        final filled = i < count;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? AppSpacing.xs : 0),
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: filled
                  ? AppColors.primary
                  : AppColors.divider.withAlpha(128),
            ),
          ),
        );
      }),
    );
  }

  /// Linha individual de seleção de arquivo.
  Widget _buildFilePicker({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color color,
    required ArquivoUpload? arquivo,
    required VoidCallback onSelect,
    required VoidCallback onClear,
  }) {
    final bool selecionado = arquivo != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: selecionado ? color.withAlpha(13) : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: selecionado ? color.withAlpha(128) : AppColors.divider,
          width: selecionado ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Ícone do tipo de arquivo
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              selecionado ? Icons.check_circle : icon,
              color: color,
              size: 22,
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Nome e status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  selecionado ? arquivo.nome : sublabel,
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: selecionado ? color : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Botão de ação: limpar se selecionado, selecionar se não
          if (selecionado)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: _isUploading ? null : onClear,
              color: AppColors.textSecondary,
              tooltip: 'Remover arquivo',
            )
          else
            TextButton.icon(
              onPressed: _selectedUnidade == null || _isUploading
                  ? null
                  : onSelect,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Selecionar'),
              style: TextButton.styleFrom(foregroundColor: color),
            ),
        ],
      ),
    );
  }

  /// Botão principal de processamento.
  Widget _buildProcessarButton({
    required bool enabled,
    required bool allSelected,
  }) {
    // Mensagem de contexto abaixo do botão
    String hint = '';
    if (_selectedUnidade == null) {
      hint = 'Selecione a unidade de negócio antes de continuar.';
    } else if (!allSelected) {
      final faltando = [
        if (_arquivo020502 == null) '020502',
        if (_arquivo020304 == null) '020304',
        if (_arquivoNri == null) 'NRI',
      ].join(', ');
      hint = 'Ainda faltam: $faltando';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: enabled ? _performUpload : null,
          icon: const Icon(Icons.bolt, size: 20),
          label: const Text(
            'Processar Estoque FEFO',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.divider,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            hint,
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.warning,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Widget de progresso exibido durante o envio.
  Widget _buildUploadProgress() {
    final nomes = [
      _arquivo020502?.nome ?? '',
      _arquivo020304?.nome ?? '',
      _arquivoNri?.nome ?? '',
    ].where((n) => n.isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Processando estoque FEFO...',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  nomes,
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
                Icon(Icons.info_outline, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Instruções de Upload',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _buildInstructionStep(
              '1.',
              'Selecione a Unidade de Negócio (filial) para onde os dados serão importados.',
            ),
            _buildInstructionStep(
              '2.',
              'Selecione as 3 planilhas obrigatórias: Grade 020502, Grade 020304 e NRI.',
            ),
            _buildInstructionStep(
              '3.',
              'Clique em "Processar Estoque FEFO". As 3 planilhas são enviadas juntas '
              'para cálculo do estoque gerencial.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(26),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Formatos aceitos: .xlsx, .xls, .csv (máximo 10MB por arquivo)',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.body,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step,
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Histórico (mantido igual ao original)
  // -----------------------------------------------------------------------

  Widget _buildUploadHistory() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.divider.withAlpha(128)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Histórico de Uploads',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: _loadUploadHistory,
                  icon: _isLoadingHistory
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  tooltip: 'Atualizar histórico',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoadingHistory && _uploadHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_uploadHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: AppColors.textSecondary.withAlpha(128),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Nenhum upload realizado',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                      ),
                    ),
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
              itemBuilder: (context, index) =>
                  _buildHistoryItem(_uploadHistory[index]),
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
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: statusColor.withAlpha(26),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(statusIcon, color: statusColor, size: 24),
      ),
      title: Text(
        item.nomeArquivo,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.tipoArquivoDisplay} • ${item.unidadeNome} • $timestamp',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            'Por ${item.usuarioNome}',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          if (item.mensagemErro != null && item.mensagemErro!.isNotEmpty)
            Text(
              item.mensagemErro!,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.caption,
                color: statusColor,
              ),
            ),
        ],
      ),
      trailing: item.linhasProcessadas > 0
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${item.linhasProcessadas} SKUs',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          : null,
    );
  }

  // -----------------------------------------------------------------------
  // Métodos auxiliares
  // -----------------------------------------------------------------------

  /// Abre o FilePicker para um dos 3 tipos de arquivo.
  /// [tipo] pode ser '020502', '020304' ou 'nri'.
  Future<void> _selectFile(String tipo) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

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
        switch (tipo) {
          case '020502':
            _arquivo020502 = arquivo;
            break;
          case '020304':
            _arquivo020304 = arquivo;
            break;
          case 'nri':
            _arquivoNri = arquivo;
            break;
        }
      });
    } catch (e) {
      _showError('Erro ao selecionar arquivo: $e');
    }
  }

  /// Limpa todos os arquivos selecionados.
  void _clearAllFiles() {
    setState(() {
      _arquivo020502 = null;
      _arquivo020304 = null;
      _arquivoNri = null;
    });
  }

  /// Envia os 3 arquivos para a API.
  Future<void> _performUpload() async {
    if (_selectedUnidade == null ||
        _arquivo020502 == null ||
        _arquivo020304 == null ||
        _arquivoNri == null) return;

    setState(() => _isUploading = true);

    try {
      final result = await _uploadService.uploadEstoqueFefo(
        arquivo020502: _arquivo020502!,
        arquivo020304: _arquivo020304!,
        arquivoNri: _arquivoNri!,
        unidadeNegocioId: _selectedUnidade!.id,
      );

      setState(() {
        _isUploading = false;
        if (result.success) _clearAllFiles();
      });

      if (result.success) {
        _showSuccess(
          'Estoque FEFO processado com sucesso! '
          '${result.skusAtualizados} SKUs atualizados.',
        );
      } else {
        _showError(result.errorMessage ?? 'Erro ao processar arquivos.');
      }

      if (result.warnings.isNotEmpty) {
        _showWarning('Avisos: ${result.warnings.join(", ")}');
      }

      _loadUploadHistory();
    } on AuthException catch (e) {
      setState(() => _isUploading = false);
      _handleAuthError(e.message);
    } catch (e) {
      setState(() => _isUploading = false);
      _showError('Erro ao enviar arquivos: $e');
    }
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.warning),
    );
  }

  void _handleAuthError(String message) {
    _showError(message);
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}