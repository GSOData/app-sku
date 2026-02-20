import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import 'home_screen.dart';
import 'web/web_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Loading state com mensagens rotativas
  bool _isLoggingIn = false;
  int _currentMessageIndex = 0;
  Timer? _messageTimer;

  // Mensagens de loading para Cold Start
  static const List<String> _loadingMessages = [
    'Conectando ao servidor de forma segura...',
    'Verificando lotes próximos ao vencimento...',
    'Organizando as prateleiras virtuais...',
    'Sincronizando categorias de produtos...',
    'Calculando indicadores de criticidade...',
    'Estamos quase lá! Preparando seu Dashboard...',
  ];

  // Animação de fade para as mensagens
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _stopMessageTimer();
    _fadeController.dispose();
    super.dispose();
  }

  void _startMessageTimer() {
    _currentMessageIndex = 0;
    _messageTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _currentMessageIndex =
              (_currentMessageIndex + 1) % _loadingMessages.length;
        });
        // Anima a troca de mensagem
        _fadeController.reset();
        _fadeController.forward();
      }
    });
  }

  void _stopMessageTimer() {
    _messageTimer?.cancel();
    _messageTimer = null;
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Inicia o loading com mensagens
    setState(() {
      _isLoggingIn = true;
    });
    _startMessageTimer();

    final authService = Provider.of<AuthService>(context, listen: false);

    final success = await authService.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    // Para o timer antes de qualquer navegação/atualização
    _stopMessageTimer();

    if (!mounted) return;

    if (success) {
      // Verifica se é Web/Desktop para redirecionar ao Dashboard Web
      final isWebLayout = kIsWeb || MediaQuery.of(context).size.width >= 800;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isWebLayout 
              ? const WebDashboardScreen() 
              : const HomeScreen(),
        ),
      );
    } else {
      // Volta ao formulário e mostra erro
      setState(() {
        _isLoggingIn = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authService.errorMessage ?? 'Erro ao realizar login',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Limita a largura máxima na web
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWideScreen ? 450 : double.infinity,
              ),
              child: _isLoggingIn ? _buildLoadingView() : _buildLoginForm(),
            ),
          ),
        ),
      ),
    );
  }

  /// Tela de Loading com mensagens rotativas
  Widget _buildLoadingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo
        _buildHeader(),

        const SizedBox(height: AppSpacing.xxl),

        // Card de Loading
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador de progresso estilizado
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                    backgroundColor: AppColors.primary.withAlpha(40),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Mensagem animada
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Text(
                    _loadingMessages[_currentMessageIndex],
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.body,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Indicador de progresso das mensagens (dots)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _loadingMessages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: index == _currentMessageIndex ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: index == _currentMessageIndex
                            ? AppColors.primary
                            : AppColors.primary.withAlpha(60),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.xl),

        // Dica sobre Cold Start
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.info.withAlpha(20),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.info.withAlpha(50),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.info,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Primeira conexão pode levar alguns segundos',
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Formulário de Login
  Widget _buildLoginForm() {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        return Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo / Título
              _buildHeader(),

              const SizedBox(height: AppSpacing.xxl),

              // Card de Login
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Entrar',
                        style: GoogleFonts.poppins(
                          fontSize: AppFontSizes.headline,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Campo Usuário
                      _buildUsernameField(),

                      const SizedBox(height: AppSpacing.md),

                      // Campo Senha
                      _buildPasswordField(),

                      const SizedBox(height: AppSpacing.lg),

                      // Botão Entrar
                      _buildLoginButton(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Versão do app
              Text(
                'v1.0.0',
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.caption,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo do App
        Image.asset(
          'assets/images/sku_logo.png',
          height: 140,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback caso a imagem não exista
            return Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                size: 50,
                color: AppColors.onPrimary,
              ),
            );
          },
        ),

        const SizedBox(height: AppSpacing.sm),

        Text(
          'Gestão de Validade e Estoque',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Usuário',
        hintText: 'Digite seu usuário',
        prefixIcon: const Icon(Icons.person_outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Informe o usuário';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _handleLogin(),
      decoration: InputDecoration(
        labelText: 'Senha',
        hintText: 'Digite sua senha',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Informe a senha';
        }
        return null;
      },
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          elevation: 2,
        ),
        child: Text(
          'Entrar',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.subtitle,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
