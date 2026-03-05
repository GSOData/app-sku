import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';
import '../../services/auth_service.dart';

/// Modelo de Configuração de Alerta (ATUALIZADO)
class ConfiguracaoAlerta {
  final int id;
  final int? unidadeId;
  final String? unidadeNome;
  final int diasPreBloqueio;
  final int diasBloqueado;
  final int diasExtremamenteCritico;

  ConfiguracaoAlerta({
    required this.id,
    this.unidadeId,
    this.unidadeNome,
    required this.diasPreBloqueio,
    required this.diasBloqueado,
    required this.diasExtremamenteCritico,
  });

  factory ConfiguracaoAlerta.fromJson(Map<String, dynamic> json) {
    return ConfiguracaoAlerta(
      id: json['id'] ?? 0,
      unidadeId: json['unidade']?['id'],
      unidadeNome: json['unidade']?['nome'],
      diasPreBloqueio: json['dias_pre_bloqueio'] ?? 60,
      diasBloqueado: json['dias_bloqueado'] ?? 30,
      diasExtremamenteCritico: json['dias_extremamente_critico'] ?? 7,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dias_pre_bloqueio': diasPreBloqueio,
      'dias_bloqueado': diasBloqueado,
      'dias_extremamente_critico': diasExtremamenteCritico,
    };
  }
}

/// Tela de Configurações do Sistema (Web)
class WebSettingsScreen extends StatefulWidget {
  const WebSettingsScreen({super.key});

  @override
  State<WebSettingsScreen> createState() => _WebSettingsScreenState();
}

class _WebSettingsScreenState extends State<WebSettingsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  ConfiguracaoAlerta? _configuracao;
  
  // Controllers (NOVOS CAMPOS)
  late TextEditingController _diasPreBloqueioController;
  late TextEditingController _diasBloqueadoController;
  late TextEditingController _diasExtremamenteCriticoController;
  bool _isSaving = false;
  bool _isDeletingDatabase = false;

  @override
  void initState() {
    super.initState();
    _diasPreBloqueioController = TextEditingController(text: '60');
    _diasBloqueadoController = TextEditingController(text: '30');
    _diasExtremamenteCriticoController = TextEditingController(text: '7');
    _loadConfiguracoes();
  }

  @override
  void dispose() {
    _diasPreBloqueioController.dispose();
    _diasBloqueadoController.dispose();
    _diasExtremamenteCriticoController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguracoes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final unidadeId = authService.unidadeAtiva?.id;
      
      final uri = Uri.parse('${Constants.apiUrl}configuracoes/')
          .replace(queryParameters: unidadeId != null 
              ? {'unidade': unidadeId.toString()} 
              : null);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authService.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> configs;
        
        if (data is Map && data.containsKey('results')) {
          configs = data['results'] as List;
        } else if (data is List) {
          configs = data;
        } else {
          configs = [];
        }
        
        if (configs.isNotEmpty) {
          _configuracao = ConfiguracaoAlerta.fromJson(configs.first);
          _diasPreBloqueioController.text = _configuracao!.diasPreBloqueio.toString();
          _diasBloqueadoController.text = _configuracao!.diasBloqueado.toString();
          _diasExtremamenteCriticoController.text = _configuracao!.diasExtremamenteCritico.toString();
        }
      } else if (response.statusCode == 403) {
        _errorMessage = 'Você não tem permissão para acessar configurações';
      } else {
        _errorMessage = 'Erro ao carregar configurações';
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarConfiguracoes() async {
    // Validação da hierarquia de dias
    final diasPre = int.tryParse(_diasPreBloqueioController.text) ?? 60;
    final diasBloq = int.tryParse(_diasBloqueadoController.text) ?? 30;
    final diasExt = int.tryParse(_diasExtremamenteCriticoController.text) ?? 7;

    if (diasPre <= diasBloq) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dias para Pré-Bloqueio deve ser maior que Bloqueado'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (diasBloq <= diasExt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dias para Bloqueado deve ser maior que Extremamente Crítico'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final unidadeId = authService.unidadeAtiva?.id;

      final body = jsonEncode({
        'dias_pre_bloqueio': diasPre,
        'dias_bloqueado': diasBloq,
        'dias_extremamente_critico': diasExt,
        if (unidadeId != null) 'unidade_id': unidadeId,
      });

      http.Response response;
      if (_configuracao != null) {
        // Atualizar existente
        response = await http.patch(
          Uri.parse('${Constants.apiUrl}configuracoes/${_configuracao!.id}/'),
          headers: {
            'Authorization': 'Bearer ${authService.accessToken}',
            'Content-Type': 'application/json',
          },
          body: body,
        );
      } else {
        // Criar novo
        response = await http.post(
          Uri.parse('${Constants.apiUrl}configuracoes/'),
          headers: {
            'Authorization': 'Bearer ${authService.accessToken}',
            'Content-Type': 'application/json',
          },
          body: body,
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configurações salvas com sucesso!'),
              backgroundColor: AppColors.success,
            ),
          );
          _loadConfiguracoes();
        }
      } else {
        throw Exception('Erro ao salvar');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Configurações',
      currentSection: WebMenuSection.settings,
      mobileBody: _buildMobileContent(),
      webBody: _buildWebContent(),
    );
  }

  Widget _buildMobileContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              Text(
                _errorMessage!,
                style: GoogleFonts.poppins(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadConfiguracoes,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl, // Padding extra no bottom para SafeArea
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título da seção
            Text(
              'Configurações de Alertas',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Configure os parâmetros de alerta para itens próximos da validade',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.body,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Card de configurações de dias (Mobile)
            _buildMobileConfigCard(),

            const SizedBox(height: AppSpacing.lg),

            // Card informativo
            _buildMobileInfoCard(),

            const SizedBox(height: AppSpacing.lg),

            // Botão salvar (largura total no mobile)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _salvarConfiguracoes,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Salvar Configurações'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
              ),
            ),
            
            // Zona de Perigo - apenas para ADMIN
            _buildMobileDangerZone(),
            
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// Card de configurações para mobile (campos ocupam 100% da largura)
  Widget _buildMobileConfigCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.divider.withAlpha(128)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.timer_outlined, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'Parâmetros de Criticidade',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            
            // Campo Pré-Bloqueio
            _buildMobileNumberField(
              label: 'Dias para Pré-Bloqueio',
              hint: 'Alerta amarelo (padrão: 60 dias)',
              controller: _diasPreBloqueioController,
              color: const Color(0xFFFFC107),
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Campo Bloqueado
            _buildMobileNumberField(
              label: 'Dias para Bloqueado',
              hint: 'Alerta laranja (padrão: 30 dias)',
              controller: _diasBloqueadoController,
              color: const Color(0xFFFF9800),
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Campo Extremamente Crítico
            _buildMobileNumberField(
              label: 'Dias para Extremamente Crítico',
              hint: 'Alerta vermelho (padrão: 7 dias)',
              controller: _diasExtremamenteCriticoController,
              color: const Color(0xFFF44336),
            ),
          ],
        ),
      ),
    );
  }

  /// Campo numérico para mobile (100% largura)
  Widget _buildMobileNumberField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.background,
            suffixText: 'dias',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: color),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: color, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  /// Card informativo para mobile
  Widget _buildMobileInfoCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.info.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.info, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Como funcionam os status de validade?',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.info,
                    fontSize: AppFontSizes.body,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildStatusLegend(
            color: Colors.black,
            label: 'Vencido',
            description: 'Data de validade já passou',
          ),
          _buildStatusLegend(
            color: const Color(0xFFF44336),
            label: 'Extremamente Crítico',
            description: 'Até ${_diasExtremamenteCriticoController.text} dias',
          ),
          _buildStatusLegend(
            color: const Color(0xFFFF9800),
            label: 'Bloqueado',
            description: 'Entre ${_diasExtremamenteCriticoController.text} e ${_diasBloqueadoController.text} dias',
          ),
          _buildStatusLegend(
            color: const Color(0xFFFFC107),
            label: 'Pré-Bloqueio',
            description: 'Entre ${_diasBloqueadoController.text} e ${_diasPreBloqueioController.text} dias',
          ),
          _buildStatusLegend(
            color: const Color(0xFF4CAF50),
            label: 'OK',
            description: 'Mais de ${_diasPreBloqueioController.text} dias',
          ),
        ],
      ),
    );
  }

  /// Zona de Perigo para mobile
  Widget _buildMobileDangerZone() {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Só mostra para usuários ADMIN
    if (!authService.usuario!.isAdmin) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        
        // Divider vermelho
        Container(
          height: 2,
          color: AppColors.error.withAlpha(51),
        ),
        
        const SizedBox(height: AppSpacing.lg),
        
        // Título da seção
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Zona de Perigo',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Operações irreversíveis. Tenha certeza do que está fazendo.',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            color: AppColors.textSecondary,
          ),
        ),
        
        const SizedBox(height: AppSpacing.md),
        
        // Card de Limpar Banco (mobile - layout vertical)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.error.withAlpha(13),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.error.withAlpha(77)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Limpar Banco de Dados',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.subtitle,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Remove TODOS os SKUs e Lotes do sistema. Esta ação é IRREVERSÍVEL.',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDeletingDatabase ? null : _confirmarLimpezaBanco,
                  icon: _isDeletingDatabase
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.delete_forever),
                  label: const Text('Limpar Banco'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(_errorMessage!, style: GoogleFonts.poppins(color: AppColors.error)),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _loadConfiguracoes,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título da seção
          Text(
            'Configurações de Alertas de Validade',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.headline,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Configure os parâmetros de alerta para itens próximos da validade',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.body,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Card de configurações de dias
          _buildConfigCard(
            title: 'Parâmetros de Criticidade',
            icon: Icons.timer_outlined,
            children: [
              _buildNumberField(
                label: 'Dias para Pré-Bloqueio',
                hint: 'Alerta amarelo (padrão: 60 dias)',
                controller: _diasPreBloqueioController,
                suffix: 'dias',
                color: const Color(0xFFFFC107),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildNumberField(
                label: 'Dias para Bloqueado',
                hint: 'Alerta laranja (padrão: 30 dias)',
                controller: _diasBloqueadoController,
                suffix: 'dias',
                color: const Color(0xFFFF9800),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildNumberField(
                label: 'Dias para Extremamente Crítico',
                hint: 'Alerta vermelho (padrão: 7 dias)',
                controller: _diasExtremamenteCriticoController,
                suffix: 'dias',
                color: const Color(0xFFF44336),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Card informativo
          _buildInfoCard(),

          const SizedBox(height: AppSpacing.xl),

          // Botão salvar
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _salvarConfiguracoes,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('Salvar Configurações'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
          
          // Zona de Perigo - apenas para ADMIN
          _buildDangerZone(),
        ],
      ),
    );
  }

  /// Constrói a seção "Zona de Perigo" visível apenas para ADMIN
  Widget _buildDangerZone() {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Só mostra para usuários ADMIN
    if (!authService.usuario!.isAdmin) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl * 2),
        
        // Divider vermelho
        Container(
          height: 2,
          color: AppColors.error.withAlpha(51),
        ),
        
        const SizedBox(height: AppSpacing.xl),
        
        // Título da seção
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Zona de Perigo',
              style: GoogleFonts.poppins(
                fontSize: AppFontSizes.headline,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        Text(
          'Operações irreversíveis. Tenha certeza do que está fazendo.',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            color: AppColors.textSecondary,
          ),
        ),
        
        const SizedBox(height: AppSpacing.lg),
        
        // Card de Limpar Banco
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.error.withAlpha(13),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.error.withAlpha(77)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limpar Banco de Dados',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.subtitle,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Remove TODOS os SKUs e Lotes do sistema. Esta ação é IRREVERSÍVEL.',
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.body,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: _isDeletingDatabase ? null : _confirmarLimpezaBanco,
                icon: _isDeletingDatabase
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever),
                label: const Text('Limpar Banco'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Exibe diálogo de confirmação antes de limpar o banco
  Future<void> _confirmarLimpezaBanco() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 32),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'ATENÇÃO!',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Você está prestes a APAGAR TODOS os dados do sistema:',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(26),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Todos os SKUs cadastrados', style: GoogleFonts.poppins()),
                  Text('• Todos os Lotes de validade', style: GoogleFonts.poppins()),
                  Text('• Histórico de movimentações', style: GoogleFonts.poppins()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Esta ação é IRREVERSÍVEL!',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Tem certeza que deseja continuar?',
              style: GoogleFonts.poppins(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Sim, APAGAR TUDO',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _executarLimpezaBanco();
    }
  }

  /// Executa a limpeza do banco de dados
  Future<void> _executarLimpezaBanco() async {
    setState(() {
      _isDeletingDatabase = true;
    });
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      final response = await http.post(
        Uri.parse('${Constants.apiUrl}skus/limpar_banco/'),
        headers: {
          'Authorization': 'Bearer ${authService.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'confirmacao': 'CONFIRMAR EXCLUSAO'}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Banco limpo! ${data['skus_deletados']} SKUs e ${data['lotes_deletados']} Lotes removidos.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['detail'] ?? 'Erro ao limpar banco');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingDatabase = false;
        });
      }
    }
  }

  Widget _buildConfigCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required String label,
    required String hint,
    required TextEditingController controller,
    String? suffix,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (color != null) ...[
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 200,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              suffixText: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: color ?? AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: color ?? AppColors.primary, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.info.withAlpha(51)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funcionam os status de validade?',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildStatusLegend(
                  color: Colors.black,
                  label: 'Vencido',
                  description: 'Data de validade já passou',
                ),
                _buildStatusLegend(
                  color: const Color(0xFFF44336),
                  label: 'Extremamente Crítico',
                  description: 'Até ${_diasExtremamenteCriticoController.text} dias',
                ),
                _buildStatusLegend(
                  color: const Color(0xFFFF9800),
                  label: 'Bloqueado',
                  description: 'Entre ${_diasExtremamenteCriticoController.text} e ${_diasBloqueadoController.text} dias',
                ),
                _buildStatusLegend(
                  color: const Color(0xFFFFC107),
                  label: 'Pré-Bloqueio',
                  description: 'Entre ${_diasBloqueadoController.text} e ${_diasPreBloqueioController.text} dias',
                ),
                _buildStatusLegend(
                  color: const Color(0xFF4CAF50),
                  label: 'OK',
                  description: 'Mais de ${_diasPreBloqueioController.text} dias',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLegend({
    required Color color,
    required String label,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$label: ',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
