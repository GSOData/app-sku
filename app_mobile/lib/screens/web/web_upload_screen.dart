import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';

/// Tela de Upload de Arquivos (Web)
class WebUploadScreen extends StatefulWidget {
  const WebUploadScreen({super.key});

  @override
  State<WebUploadScreen> createState() => _WebUploadScreenState();
}

class _WebUploadScreenState extends State<WebUploadScreen> {
  bool _isDragging = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _selectedFileName;

  // Histórico de uploads mockado
  final List<UploadHistory> _uploadHistory = [
    UploadHistory(
      id: 1,
      fileName: 'estoque_janeiro_2026.xlsx',
      uploadDate: '15/02/2026 14:30',
      status: UploadStatus.success,
      recordCount: 1248,
      uploadedBy: 'Carlos Silva',
    ),
    UploadHistory(
      id: 2,
      fileName: 'novos_produtos.csv',
      uploadDate: '10/02/2026 09:15',
      status: UploadStatus.success,
      recordCount: 156,
      uploadedBy: 'Maria Santos',
    ),
    UploadHistory(
      id: 3,
      fileName: 'lotes_fevereiro.xlsx',
      uploadDate: '05/02/2026 16:45',
      status: UploadStatus.error,
      recordCount: 0,
      uploadedBy: 'João Oliveira',
      errorMessage: 'Formato de data inválido na coluna D',
    ),
    UploadHistory(
      id: 4,
      fileName: 'atualizacao_precos.xlsx',
      uploadDate: '01/02/2026 11:20',
      status: UploadStatus.success,
      recordCount: 892,
      uploadedBy: 'Carlos Silva',
    ),
    UploadHistory(
      id: 5,
      fileName: 'categorias_v2.csv',
      uploadDate: '28/01/2026 08:00',
      status: UploadStatus.warning,
      recordCount: 45,
      uploadedBy: 'Ana Costa',
      errorMessage: '3 registros ignorados por duplicidade',
    ),
  ];

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
          // Área de Upload
          _buildUploadArea(),

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

  Widget _buildUploadArea() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.divider.withAlpha(128)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            // Área de Drag and Drop
            MouseRegion(
              onEnter: (_) => setState(() => _isDragging = true),
              onExit: (_) => setState(() => _isDragging = false),
              child: GestureDetector(
                onTap: _selectFile,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 250,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? AppColors.primary.withAlpha(13)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: _isDragging ? AppColors.primary : AppColors.divider,
                      width: _isDragging ? 2 : 1,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: _isUploading
                      ? _buildUploadProgress()
                      : _buildDropZone(),
                ),
              ),
            ),

            if (_selectedFileName != null && !_isUploading) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildSelectedFile(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(26),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_upload_outlined,
            size: 48,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Arraste e solte seu arquivo aqui',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.subtitle,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'ou',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton.icon(
          onPressed: _selectFile,
          icon: const Icon(Icons.folder_open, size: 20),
          label: const Text('Selecionar Arquivo'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Formatos aceitos: .xlsx, .xls, .csv (máx. 10MB)',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildUploadProgress() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _uploadProgress,
                strokeWidth: 6,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.subtitle,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Enviando arquivo...',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.subtitle,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _selectedFileName ?? '',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedFile() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(13),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withAlpha(77)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withAlpha(26),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.description,
              color: AppColors.success,
              size: 24,
            ),
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
                  'Pronto para enviar',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _selectedFileName = null),
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: _simulateUpload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildInstructionColumn(
                    'Planilha de SKUs',
                    Icons.inventory_2_outlined,
                    [
                      'Código SKU (obrigatório)',
                      'Nome do Produto',
                      'Categoria',
                      'Unidade de Medida',
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: _buildInstructionColumn(
                    'Planilha de Lotes',
                    Icons.layers_outlined,
                    [
                      'Código SKU (obrigatório)',
                      'Número do Lote',
                      'Data de Validade (DD/MM/AAAA)',
                      'Quantidade',
                      'Custo Unitário',
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: _buildInstructionColumn(
                    'Planilha de Usuários',
                    Icons.people_outline,
                    [
                      'Nome Completo',
                      'Email (obrigatório)',
                      'Perfil (Gerente/Supervisor/Operador)',
                      'Unidade de Acesso',
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Baixando modelo...')),
                    );
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Baixar Modelo Excel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Abrindo documentação...')),
                    );
                  },
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Ver Documentação'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.divider),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionColumn(String title, IconData icon, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle,
                size: 14,
                color: AppColors.success,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  item,
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

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
                TextButton.icon(
                  onPressed: () {
                    setState(() => _uploadHistory.clear());
                  },
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Limpar Histórico'),
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
              itemBuilder: (context, index) {
                final upload = _uploadHistory[index];
                return _buildHistoryItem(upload);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(UploadHistory upload) {
    IconData statusIcon;
    Color statusColor;

    switch (upload.status) {
      case UploadStatus.success:
        statusIcon = Icons.check_circle;
        statusColor = AppColors.success;
        break;
      case UploadStatus.error:
        statusIcon = Icons.error;
        statusColor = AppColors.error;
        break;
      case UploadStatus.warning:
        statusIcon = Icons.warning;
        statusColor = AppColors.warning;
        break;
    }

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
        upload.fileName,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${upload.uploadDate} • ${upload.uploadedBy}',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          if (upload.errorMessage != null)
            Text(
              upload.errorMessage!,
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.caption,
                color: statusColor,
              ),
            ),
        ],
      ),
      trailing: upload.recordCount > 0
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
                '${upload.recordCount} registros',
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

  void _selectFile() {
    // Simulação - em produção, usar file_picker package
    setState(() {
      _selectedFileName = 'estoque_fevereiro_2026.xlsx';
    });
  }

  void _simulateUpload() async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    // Simula progresso de upload
    for (int i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() => _uploadProgress = i / 100);
      }
    }

    // Adiciona ao histórico
    if (mounted) {
      setState(() {
        _uploadHistory.insert(
          0,
          UploadHistory(
            id: DateTime.now().millisecondsSinceEpoch,
            fileName: _selectedFileName!,
            uploadDate: '18/02/2026 ${TimeOfDay.now().format(context)}',
            status: UploadStatus.success,
            recordCount: 234,
            uploadedBy: 'Usuário Atual',
          ),
        );
        _isUploading = false;
        _selectedFileName = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Arquivo processado com sucesso!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

/// Status do upload
enum UploadStatus { success, error, warning }

/// Modelo de histórico de upload
class UploadHistory {
  final int id;
  final String fileName;
  final String uploadDate;
  final UploadStatus status;
  final int recordCount;
  final String uploadedBy;
  final String? errorMessage;

  UploadHistory({
    required this.id,
    required this.fileName,
    required this.uploadDate,
    required this.status,
    required this.recordCount,
    required this.uploadedBy,
    this.errorMessage,
  });
}
