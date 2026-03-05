import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';

/// Tela de Gerenciamento de Usuários (Web)
class WebUserManagementScreen extends StatefulWidget {
  const WebUserManagementScreen({super.key});

  @override
  State<WebUserManagementScreen> createState() => _WebUserManagementScreenState();
}

class _WebUserManagementScreenState extends State<WebUserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'Todos';
  late UserService _userService;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final authService = Provider.of<AuthService>(context, listen: false);
      _userService = UserService(authService);
      _loadUsuarios();
      _initialized = true;
    }
  }

  Future<void> _loadUsuarios() async {
    await _userService.loadUsuarios(
      search: _searchController.text.isEmpty ? null : _searchController.text,
      papel: _selectedFilter == 'Todos' ? null : _selectedFilter,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuario = authService.usuario;
    final canAddUser = usuario?.canManageUsers ?? false;

    return ResponsiveLayout(
      title: 'Gerenciamento de Usuários',
      currentSection: WebMenuSection.users,
      mobileBody: _buildMobileBody(canAddUser),
      webBody: _buildWebContent(),
      actions: [
        if (canAddUser)
          ElevatedButton.icon(
            onPressed: () => _showAddUserDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Novo Usuário'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }

  /// Body mobile com FAB usando Stack
  Widget _buildMobileBody(bool canAddUser) {
    // Calcula o padding do SafeArea para posicionar o FAB corretamente
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Stack(
      children: [
        _buildMobileContent(),
        if (canAddUser)
          Positioned(
            right: AppSpacing.md,
            // Posiciona o FAB acima da barra de navegação nativa
            bottom: AppSpacing.md + bottomPadding,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddUserDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Novo'),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Column(
      children: [
        // Barra de busca mobile
        _buildMobileSearchBar(),
        
        // Conteúdo principal
        Expanded(child: _buildMobileList()),
      ],
    );
  }

  /// Barra de busca adaptada para mobile
  Widget _buildMobileSearchBar() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.surface,
      child: Column(
        children: [
          // Campo de busca
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou email...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _loadUsuarios();
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _loadUsuarios(),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Filtro por papel
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Todos', 'Admin', 'Diretoria', 'Gerente', 'Vendedor']
                        .map((papel) => Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.xs),
                              child: ChoiceChip(
                                label: Text(papel),
                                selected: _selectedFilter == papel,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _selectedFilter = papel);
                                    _loadUsuarios();
                                  }
                                },
                                selectedColor: AppColors.primary.withAlpha(51),
                                labelStyle: GoogleFonts.poppins(
                                  fontSize: AppFontSizes.caption,
                                  color: _selectedFilter == papel
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadUsuarios,
                icon: const Icon(Icons.refresh),
                tooltip: 'Recarregar',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Lista de usuários para mobile
  Widget _buildMobileList() {
    if (_userService.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userService.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              Text(
                _userService.errorMessage!,
                style: GoogleFonts.poppins(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadUsuarios,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_userService.usuarios.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nenhum usuário encontrado',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsuarios,
      child: ListView.builder(
        // Padding com bottom maior para compensar o FAB e a barra nativa
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          100.0, // Espaço extra para o FAB não sobrepor o último item
        ),
        itemCount: _userService.usuarios.length,
        itemBuilder: (context, index) {
          final user = _userService.usuarios[index];
          return _buildUserCard(user);
        },
      ),
    );
  }

  /// Card de usuário para mobile
  Widget _buildUserCard(ApiUsuario user) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final canEdit = authService.usuario?.canManageUsers ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: AppColors.divider.withAlpha(128)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withAlpha(26),
              child: Text(
                (user.displayName.isNotEmpty ? user.displayName : user.username)
                    .substring(0, 1)
                    .toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.subtitle,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Informações do usuário
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome
                  Text(
                    user.displayName.isNotEmpty ? user.displayName : user.username,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.subtitle,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Email
                  Text(
                    user.email,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.body,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Badges de Papel e Status
                  Row(
                    children: [
                      _buildMobilePapelChip(user.papelLabel),
                      const SizedBox(width: AppSpacing.sm),
                      _buildMobileStatusIndicator(user.isActive),
                    ],
                  ),
                ],
              ),
            ),

            // Menu de ações
            if (canEdit)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _showEditUserDialog(context, user);
                      break;
                    case 'delete':
                      _showDeleteConfirmation(context, user);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20, color: AppColors.info),
                        const SizedBox(width: AppSpacing.sm),
                        const Text('Editar'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                        const SizedBox(width: AppSpacing.sm),
                        const Text('Excluir'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Chip de papel para mobile
  Widget _buildMobilePapelChip(String papel) {
    Color color;
    switch (papel) {
      case 'Administrador':
        color = AppColors.error;
        break;
      case 'Diretoria':
        color = AppColors.warning;
        break;
      case 'Gerente':
        color = AppColors.primary;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        papel,
        style: GoogleFonts.poppins(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// Indicador de status para mobile
  Widget _buildMobileStatusIndicator(bool isActive) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppColors.success : AppColors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          isActive ? 'Ativo' : 'Inativo',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: isActive ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }

  Widget _buildWebContent() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com estatísticas
          _buildStatsRow(),

          const SizedBox(height: AppSpacing.lg),

          // Card principal com tabela
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: AppColors.divider.withAlpha(128)),
              ),
              child: Column(
                children: [
                  // Toolbar com busca e filtros
                  _buildToolbar(),

                  // Estado de carregamento, erro ou tabela
                  Expanded(
                    child: _buildContent(),
                  ),

                  // Paginação
                  _buildPagination(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_userService.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_userService.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              _userService.errorMessage!,
              style: GoogleFonts.poppins(color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _loadUsuarios,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_userService.usuarios.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nenhum usuário encontrado',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return _buildUsersTable();
  }

  Widget _buildStatsRow() {
    final usuarios = _userService.usuarios;
    final totalUsers = usuarios.length;
    final activeUsers = usuarios.where((u) => u.isActive).length;
    final inactiveUsers = usuarios.where((u) => !u.isActive).length;

    return Row(
      children: [
        _buildStatCard(
          'Total de Usuários',
          totalUsers.toString(),
          Icons.people_outline,
          AppColors.primary,
        ),
        const SizedBox(width: AppSpacing.md),
        _buildStatCard(
          'Usuários Ativos',
          activeUsers.toString(),
          Icons.check_circle_outline,
          AppColors.success,
        ),
        const SizedBox(width: AppSpacing.md),
        _buildStatCard(
          'Usuários Inativos',
          inactiveUsers.toString(),
          Icons.cancel_outlined,
          AppColors.error,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: AppColors.divider.withAlpha(128)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.headline,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withAlpha(128)),
        ),
      ),
      child: Row(
        children: [
          // Campo de busca
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou email...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _loadUsuarios(),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Filtro por papel
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedFilter,
                items: ['Todos', 'Diretoria', 'Gerente', 'Vendedor']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedFilter = value!);
                  _loadUsuarios();
                },
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Botão de recarregar
          IconButton(
            onPressed: _loadUsuarios,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
          ),
        ],
      ),
    );
  }

  Widget _buildUsersTable() {
    final usuarios = _userService.usuarios;

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.background),
          columnSpacing: AppSpacing.lg,
          columns: [
            DataColumn(
              label: Text(
                'Usuário',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            DataColumn(
              label: Text(
                'Email',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            DataColumn(
              label: Text(
                'Papel',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            DataColumn(
              label: Text(
                'Unidades',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            DataColumn(
              label: Text(
                'Ações',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          rows: usuarios.map((user) => _buildUserRow(user)).toList(),
        ),
      ),
    );
  }

  DataRow _buildUserRow(ApiUsuario user) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final canEdit = authService.usuario?.canManageUsers ?? false;

    return DataRow(
      cells: [
        // Nome com avatar
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withAlpha(26),
                child: Text(
                  (user.displayName.isNotEmpty ? user.displayName : user.username)
                      .substring(0, 1)
                      .toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user.displayName.isNotEmpty ? user.displayName : user.username,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                  if (user.cargo != null)
                    Text(
                      user.cargo!,
                      style: GoogleFonts.poppins(
                        fontSize: AppFontSizes.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Email
        DataCell(Text(user.email)),
        // Papel
        DataCell(_buildPapelBadge(user.papelLabel)),
        // Status
        DataCell(_buildStatusBadge(user.isActive)),
        // Unidades
        DataCell(
          Wrap(
            spacing: 4,
            children: user.unidadesAcesso.take(2).map((v) {
              return Chip(
                label: Text(
                  v.unidade?.codigoUnb ?? 'N/A',
                  style: GoogleFonts.poppins(fontSize: 10),
                ),
                labelPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ),
        // Ações
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canEdit) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppColors.info,
                  onPressed: () => _showEditUserDialog(context, user),
                  tooltip: 'Editar',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppColors.error,
                  onPressed: () => _showDeleteConfirmation(context, user),
                  tooltip: 'Excluir',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPapelBadge(String papel) {
    Color color;
    switch (papel) {
      case 'Diretoria':
        color = AppColors.warning;
        break;
      case 'Gerente':
        color = AppColors.primary;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        papel,
        style: GoogleFonts.poppins(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppColors.success : AppColors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          isActive ? 'Ativo' : 'Inativo',
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.body,
            color: isActive ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.divider.withAlpha(128)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Mostrando ${_userService.usuarios.length} de ${_userService.totalCount} usuários',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _userService.currentPage > 1
                    ? () => _userService.loadUsuarios(
                          page: _userService.currentPage - 1,
                          search: _searchController.text.isEmpty ? null : _searchController.text,
                        ).then((_) => setState(() {}))
                    : null,
                color: AppColors.textSecondary,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${_userService.currentPage}',
                  style: GoogleFonts.poppins(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _userService.currentPage < _userService.totalPages
                    ? () => _userService.loadUsuarios(
                          page: _userService.currentPage + 1,
                          search: _searchController.text.isEmpty ? null : _searchController.text,
                        ).then((_) => setState(() {}))
                    : null,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _UserFormDialog(
        title: 'Novo Usuário',
        userService: _userService,
        onSave: () {
          _loadUsuarios();
        },
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, ApiUsuario user) {
    showDialog(
      context: context,
      builder: (context) => _UserFormDialog(
        title: 'Editar Usuário',
        user: user,
        userService: _userService,
        onSave: () {
          _loadUsuarios();
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ApiUsuario user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Usuário'),
        content: Text('Deseja realmente excluir o usuário "${user.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await _userService.deleteUsuario(user.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Usuário excluído com sucesso!'
                          : _userService.errorMessage ?? 'Erro ao excluir',
                    ),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
                if (success) setState(() {});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}

/// Dialog de formulário de usuário
class _UserFormDialog extends StatefulWidget {
  final String title;
  final ApiUsuario? user;
  final UserService userService;
  final VoidCallback onSave;

  const _UserFormDialog({
    required this.title,
    this.user,
    required this.userService,
    required this.onSave,
  });

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _passwordController;
  String _selectedPapel = 'VENDEDOR';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user?.username ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _firstNameController = TextEditingController(text: widget.user?.firstName ?? '');
    _lastNameController = TextEditingController(text: widget.user?.lastName ?? '');
    _passwordController = TextEditingController();
    _selectedPapel = widget.user?.maxPapel ?? 'VENDEDOR';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.user != null;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: GoogleFonts.poppins(
                      fontSize: AppFontSizes.title,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Campos
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.isEmpty ?? true ? 'Obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Sobrenome',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                enabled: !isEditing,
                validator: (v) => v?.isEmpty ?? true ? 'Obrigatório' : null,
              ),
              const SizedBox(height: AppSpacing.md),

              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Obrigatório';
                  if (!v!.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              if (!isEditing)
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (!isEditing && (v?.isEmpty ?? true)) return 'Obrigatório';
                    if (v != null && v.isNotEmpty && v.length < 8) {
                      return 'Mínimo 8 caracteres';
                    }
                    return null;
                  },
                ),
              if (!isEditing) const SizedBox(height: AppSpacing.md),

              DropdownButtonFormField<String>(
                value: _selectedPapel,
                decoration: const InputDecoration(
                  labelText: 'Papel',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: 'VENDEDOR', child: Text('Vendedor')),
                  const DropdownMenuItem(value: 'GERENTE', child: Text('Gerente')),
                  const DropdownMenuItem(value: 'DIRETORIA', child: Text('Diretoria')),
                ],
                onChanged: (v) => setState(() => _selectedPapel = v!),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Botões
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    bool success;
    if (widget.user != null) {
      // Edição
      success = await widget.userService.updateUsuario(widget.user!.id, {
        'first_name': _firstNameController.text,
        'last_name': _lastNameController.text,
        'email': _emailController.text,
      });
    } else {
      // Criação
      final authService = Provider.of<AuthService>(context, listen: false);
      success = await widget.userService.createUsuario(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        unidadeId: authService.unidadeAtiva?.id,
        papel: _selectedPapel,
      );
    }

    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        Navigator.pop(context);
        widget.onSave();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuário salvo com sucesso!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.userService.errorMessage ?? 'Erro ao salvar'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}