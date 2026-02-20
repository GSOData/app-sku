import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';
import '../../services/auth_service.dart';
import '../../services/upload_service.dart';
import '../login_screen.dart';

/// Tela de Upload de Arquivos (Web)
/// 
/// Permite importar dois tipos de planilhas:
/// 1. Grade 020502: Estoque Total Diário
/// 2. Contagens: Conciliação de Validades
class WebUploadScreen extends StatefulWidget {
  const WebUploadScreen({super.key});

  @override
  State<WebUploadScreen> createState() => _WebUploadScreenState();
}

class _WebUploadScreenState extends State<WebUploadScreen> {
  late UploadService _uploadService;
  
  // Estados
  bool _isLoadingUnidades = true;
  bool _isUploading = false;
  String? _uploadType; // 'grade' ou 'contagens'
  
  // Unidades de Negócio
  List<UnidadeNegocio> _unidades = [];
  UnidadeNegocio? _selectedUnidade;
  
  // Arquivo selecionado
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  
  // Histórico de uploads
  final List<UploadHistoryItem> _uploadHistory = [];

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _uploadService = UploadService(authService: authService);
    _loadUnidades();
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
      if (mounted) {
        _showError('Erro ao carregar unidades: $e');
      }
    }
  }

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
          // Seleção de Unidade (Obrigatório)
          _buildUnidadeSelector(),
          
          const SizedBox(height: AppSpacing.xl),
          
          // Área de Upload com dois tipos
          _buildUploadSection(),

          const SizedBox(height: AppSpacing.xl),

          // Instruções
          _buildInstructions(),

          const SizedBox(height: AppSpacing.xl),

          // Histórico de Uploads
          _buildUploadHistory(),
        ],
      ),
    );
  }

  /// Dropdown de seleção de Unidade de Negócio
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
                items: _unidades.map((unidade) {
                  return DropdownMenuItem<UnidadeNegocio>(
                    value: unidade,
                    child: Text('${unidade.codigoUnb} - ${unidade.nome}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedUnidade = value);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Seção de Upload com dois tipos
  Widget _buildUploadSection() {
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
            Text(
              'Importar Dados',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.subtitle,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Dois cards de upload lado a lado
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Upload Grade 020502
                Expanded(
                  child: _buildUploadCard(
                    title: 'Estoque Total (020502)',
                    subtitle: 'Importa grade diária de inventário',
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.primary,
                    uploadType: 'grade',
                    columns: [
                      'Produto (Código SKU)',
                      'Descricao',
                      'Unidade (cx, un, etc)',
                      'Fator (conversão)',
                      'Inventario (texto)',
                      'Qtd Contagem',
                    ],
                  ),
                ),
                
                const SizedBox(width: AppSpacing.lg),
                
                // Upload Contagens
                Expanded(
                  child: _buildUploadCard(
                    title: 'Validades (Contagens)',
                    subtitle: 'Importa conciliação semanal de validades',
                    icon: Icons.event_available,
                    color: AppColors.success,
                    uploadType: 'contagens',
                    columns: [
                      'Código Item',
                      'Validade Aferida',
                      'Quantidade Cx',
                      'Quantidade Unidade',
                    ],
                  ),
                ),
              ],
            ),
            
            // Arquivo selecionado
            if (_selectedFileName != null && !_isUploading) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildSelectedFile(),
            ],
            
            // Progress de upload
            if (_isUploading) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildUploadProgress(),
            ],
          ],
        ),
      ),
    );
  }

  /// Card individual de upload
  Widget _buildUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String uploadType,
    required List<String> columns,
  }) {
    final isSelected = _uploadType == uploadType && _selectedFileName != null;
    
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isSelected ? color.withAlpha(13) : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isSelected ? color : AppColors.divider,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.body,
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
            ],
          ),
          
          const SizedBox(height: AppSpacing.md),
          
          // Colunas esperadas
          Text(
            'Colunas esperadas:',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...columns.map((col) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 12, color: color),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    col,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )),
          
          const SizedBox(height: AppSpacing.md),
          
          // Botão de selecionar arquivo
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _selectedUnidade == null || _isUploading
                  ? null
                  : () => _selectFile(uploadType),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Selecionar Arquivo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.divider,
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
          
          if (_selectedUnidade == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Selecione uma unidade primeiro',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.caption,
                  color: AppColors.warning,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// Widget do arquivo selecionado
  Widget _buildSelectedFile() {
    final color = _uploadType == 'grade' ? AppColors.primary : AppColors.success;
    final typeLabel = _uploadType == 'grade' 
        ? 'Estoque Total (020502)' 
        : 'Validades (Contagens)';
    
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withAlpha(13),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.description, color: color, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedFileName!,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$typeLabel • ${_selectedUnidade?.nome ?? ""}',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _clearSelection,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: _performUpload,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  /// Progress de upload
  Widget _buildUploadProgress() {
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
                  'Processando arquivo...',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  _selectedFileName ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Instruções de upload
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
            
            Text(
              '1. Selecione a Unidade de Negócio (filial) para onde os dados serão importados.',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '2. Escolha o tipo de importação:',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Estoque Total (020502): Atualiza o inventário base diário',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '• Validades (Contagens): Importa lotes com data de validade',
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '3. Selecione o arquivo .xlsx, .xls ou .csv com as colunas corretas.',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '4. Clique em "Enviar" para processar a importação.',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
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
                      'Formatos aceitos: .xlsx, .xls, .csv (máximo 10MB)',
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

  /// Histórico de uploads
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
                if (_uploadHistory.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _uploadHistory.clear());
                    },
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Limpar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          if (_uploadHistory.isEmpty)
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
                      'Nenhum upload realizado nesta sessão',
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
              itemBuilder: (context, index) {
                return _buildHistoryItem(_uploadHistory[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(UploadHistoryItem item) {
    final statusColor = item.success ? AppColors.success : AppColors.error;
    final statusIcon = item.success ? Icons.check_circle : Icons.error;

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
        item.fileName,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.tipo} • ${item.unidade} • ${item.timestamp}',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          if (item.message != null)
            Text(
              item.message!,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.caption,
                color: statusColor,
              ),
            ),
        ],
      ),
      trailing: item.recordCount > 0
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
                '${item.recordCount} registros',
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

  // ============= MÉTODOS =============

  /// Seleciona arquivo via file_picker
  Future<void> _selectFile(String uploadType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true, // Necessário para web
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // Verifica tamanho (max 10MB)
        if (file.size > 10 * 1024 * 1024) {
          _showError('Arquivo muito grande. Máximo permitido: 10MB');
          return;
        }
        
        setState(() {
          _selectedFileName = file.name;
          _selectedFileBytes = file.bytes;
          _uploadType = uploadType;
        });
      }
    } catch (e) {
      _showError('Erro ao selecionar arquivo: $e');
    }
  }

  /// Limpa seleção de arquivo
  void _clearSelection() {
    setState(() {
      _selectedFileName = null;
      _selectedFileBytes = null;
      _uploadType = null;
    });
  }

  /// Realiza upload do arquivo
  Future<void> _performUpload() async {
    if (_selectedUnidade == null || 
        _selectedFileName == null || 
        _selectedFileBytes == null ||
        _uploadType == null) {
      return;
    }

    setState(() => _isUploading = true);

    try {
      UploadResult result;
      
      if (_uploadType == 'grade') {
        result = await _uploadService.uploadGrade020502(
          unidadeNegocioId: _selectedUnidade!.id,
          fileName: _selectedFileName!,
          fileBytes: _selectedFileBytes!,
        );
      } else {
        result = await _uploadService.uploadContagens(
          unidadeNegocioId: _selectedUnidade!.id,
          fileName: _selectedFileName!,
          fileBytes: _selectedFileBytes!,
        );
      }

      // Adiciona ao histórico
      final tipoLabel = _uploadType == 'grade' ? 'Estoque Total' : 'Validades';
      
      setState(() {
        _uploadHistory.insert(0, UploadHistoryItem(
          fileName: _selectedFileName!,
          tipo: tipoLabel,
          unidade: _selectedUnidade!.nome,
          timestamp: _formatTimestamp(DateTime.now()),
          success: result.success,
          recordCount: result.processed,
          message: result.success 
              ? 'Criados: ${result.created}, Atualizados: ${result.updated}'
              : result.errorMessage ?? 'Erro desconhecido',
        ));
        
        _isUploading = false;
        _clearSelection();
      });

      if (result.success) {
        _showSuccess('Arquivo processado com sucesso! '
            '${result.processed} registros, '
            '${result.created} criados, '
            '${result.updated} atualizados.');
      } else {
        _showError(result.errorMessage ?? 'Erro ao processar arquivo');
      }
      
      // Mostra warnings se houver
      if (result.warnings.isNotEmpty) {
        _showWarning('Avisos: ${result.warnings.join(", ")}');
      }

    } on AuthException catch (e) {
      setState(() => _isUploading = false);
      _handleAuthError(e.message);
    } catch (e) {
      setState(() => _isUploading = false);
      _showError('Erro ao enviar arquivo: $e');
    }
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
           '${dt.month.toString().padLeft(2, '0')}/'
           '${dt.year} '
           '${dt.hour.toString().padLeft(2, '0')}:'
           '${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warning,
      ),
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

/// Item do histórico de upload
class UploadHistoryItem {
  final String fileName;
  final String tipo;
  final String unidade;
  final String timestamp;
  final bool success;
  final int recordCount;
  final String? message;

  UploadHistoryItem({
    required this.fileName,
    required this.tipo,
    required this.unidade,
    required this.timestamp,
    required this.success,
    required this.recordCount,
    this.message,
  });
}
