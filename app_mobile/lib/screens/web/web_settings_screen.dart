import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';
import '../../services/auth_service.dart';

/// Modelo de Configuração de Alerta
class ConfiguracaoAlerta {
  final int id;
  final int? unidadeId;
  final String? unidadeNome;
  final int diasParaCritico;
  final int diasParaPreBloqueio;
  final bool alertaAtivo;
  final bool emailAtivo;

  ConfiguracaoAlerta({
    required this.id,
    this.unidadeId,
    this.unidadeNome,
    required this.diasParaCritico,
    required this.diasParaPreBloqueio,
    required this.alertaAtivo,
    required this.emailAtivo,
  });

  factory ConfiguracaoAlerta.fromJson(Map<String, dynamic> json) {
    return ConfiguracaoAlerta(
      id: json['id'] ?? 0,
      unidadeId: json['unidade']?['id'],
      unidadeNome: json['unidade']?['nome'],
      diasParaCritico: json['dias_para_critico'] ?? 30,
      diasParaPreBloqueio: json['dias_para_pre_bloqueio'] ?? 45,
      alertaAtivo: json['alerta_ativo'] ?? true,
      emailAtivo: json['email_ativo'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dias_para_critico': diasParaCritico,
      'dias_para_pre_bloqueio': diasParaPreBloqueio,
      'alerta_ativo': alertaAtivo,
      'email_ativo': emailAtivo,
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
  
  // Controllers
  late TextEditingController _diasCriticoController;
  late TextEditingController _diasPreBloqueioController;
  bool _alertaAtivo = true;
  bool _emailAtivo = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _diasCriticoController = TextEditingController(text: '30');
    _diasPreBloqueioController = TextEditingController(text: '45');
    _loadConfiguracoes();
  }

  @override
  void dispose() {
    _diasCriticoController.dispose();
    _diasPreBloqueioController.dispose();
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
          _diasCriticoController.text = _configuracao!.diasParaCritico.toString();
          _diasPreBloqueioController.text = _configuracao!.diasParaPreBloqueio.toString();
          _alertaAtivo = _configuracao!.alertaAtivo;
          _emailAtivo = _configuracao!.emailAtivo;
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
    setState(() => _isSaving = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final unidadeId = authService.unidadeAtiva?.id;

      final body = jsonEncode({
        'dias_para_critico': int.parse(_diasCriticoController.text),
        'dias_para_pre_bloqueio': int.parse(_diasPreBloqueioController.text),
        'alerta_ativo': _alertaAtivo,
        'email_ativo': _emailAtivo,
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
    return const Center(
      child: Text('Configurações disponíveis apenas na versão Web'),
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
                label: 'Dias para status Crítico',
                hint: 'Produtos com validade em até X dias',
                controller: _diasCriticoController,
                suffix: 'dias',
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildNumberField(
                label: 'Dias para status Pré-Bloqueio',
                hint: 'Produtos com validade entre Crítico e X dias',
                controller: _diasPreBloqueioController,
                suffix: 'dias',
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Card de configurações de notificações
          _buildConfigCard(
            title: 'Notificações',
            icon: Icons.notifications_outlined,
            children: [
              SwitchListTile(
                title: Text(
                  'Alertas Ativos',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Exibir alertas visuais para itens críticos',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
                value: _alertaAtivo,
                onChanged: (v) => setState(() => _alertaAtivo = v),
                activeColor: AppColors.primary,
              ),
              const Divider(),
              SwitchListTile(
                title: Text(
                  'Notificações por Email',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Enviar resumo diário de itens críticos por email',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
                value: _emailAtivo,
                onChanged: (v) => setState(() => _emailAtivo = v),
                activeColor: AppColors.primary,
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
        ],
      ),
    );
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
          ),
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
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: AppColors.primary, width: 2),
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
                  'Como funcionam os status?',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '• Vencido: data de validade já passou\n'
                  '• Crítico: faltam até ${_diasCriticoController.text} dias\n'
                  '• Pré-Bloqueio: entre ${_diasCriticoController.text} e ${_diasPreBloqueioController.text} dias\n'
                  '• OK: mais de ${_diasPreBloqueioController.text} dias',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
