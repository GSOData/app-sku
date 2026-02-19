import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/constants.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/web_navigation_menu.dart';

/// Tela de Gerenciamento de Usuários (Web)
class WebUserManagementScreen extends StatefulWidget {
  const WebUserManagementScreen({super.key});

  @override
  State<WebUserManagementScreen> createState() => _WebUserManagementScreenState();
}

class _WebUserManagementScreenState extends State<WebUserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'Todos';
  
  // Dados mockados de usuários
  final List<MockUser> _users = [
    MockUser(
      id: 1,
      nome: 'Carlos Silva',
      email: 'carlos.silva@empresa.com',
      perfil: 'Gerente',
      status: true,
      ultimoAcesso: '18/02/2026 15:30',
    ),
    MockUser(
      id: 2,
      nome: 'Maria Santos',
      email: 'maria.santos@empresa.com',
      perfil: 'Supervisor',
      status: true,
      ultimoAcesso: '18/02/2026 14:45',
    ),
    MockUser(
      id: 3,
      nome: 'João Oliveira',
      email: 'joao.oliveira@empresa.com',
      perfil: 'Operador',
      status: true,
      ultimoAcesso: '18/02/2026 10:20',
    ),
    MockUser(
      id: 4,
      nome: 'Ana Costa',
      email: 'ana.costa@empresa.com',
      perfil: 'Operador',
      status: false,
      ultimoAcesso: '10/02/2026 09:00',
    ),
    MockUser(
      id: 5,
      nome: 'Pedro Lima',
      email: 'pedro.lima@empresa.com',
      perfil: 'Supervisor',
      status: true,
      ultimoAcesso: '17/02/2026 16:50',
    ),
    MockUser(
      id: 6,
      nome: 'Fernanda Souza',
      email: 'fernanda.souza@empresa.com',
      perfil: 'Operador',
      status: true,
      ultimoAcesso: '18/02/2026 08:30',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Gerenciamento de Usuários',
      currentSection: WebMenuSection.users,
      mobileBody: _buildMobileContent(),
      webBody: _buildWebContent(),
      actions: [
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

  Widget _buildMobileContent() {
    return const Center(
      child: Text('Gerenciamento de Usuários disponível apenas na versão Web'),
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

                  // Tabela de usuários
                  Expanded(
                    child: _buildUsersTable(),
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

  Widget _buildStatsRow() {
    final totalUsers = _users.length;
    final activeUsers = _users.where((u) => u.status).length;
    final inactiveUsers = _users.where((u) => !u.status).length;

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
              onChanged: (value) => setState(() {}),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Filtro por perfil
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedFilter,
                items: ['Todos', 'Gerente', 'Supervisor', 'Operador']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedFilter = value!);
                },
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Botão de exportar
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exportando lista de usuários...')),
              );
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Exportar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersTable() {
    // Filtrar usuários
    var filteredUsers = _users.where((user) {
      final searchMatch = _searchController.text.isEmpty ||
          user.nome.toLowerCase().contains(_searchController.text.toLowerCase()) ||
          user.email.toLowerCase().contains(_searchController.text.toLowerCase());
      
      final filterMatch = _selectedFilter == 'Todos' ||
          user.perfil == _selectedFilter;
      
      return searchMatch && filterMatch;
    }).toList();

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
                'Perfil',
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
                'Último Acesso',
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
          rows: filteredUsers.map((user) => _buildUserRow(user)).toList(),
        ),
      ),
    );
  }

  DataRow _buildUserRow(MockUser user) {
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
                  user.nome.substring(0, 1).toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                user.nome,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        // Email
        DataCell(Text(user.email)),
        // Perfil
        DataCell(_buildPerfilBadge(user.perfil)),
        // Status
        DataCell(_buildStatusBadge(user.status)),
        // Último Acesso
        DataCell(Text(
          user.ultimoAcesso,
          style: GoogleFonts.poppins(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
        )),
        // Ações
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: AppColors.info,
                onPressed: () => _showEditUserDialog(context, user),
                tooltip: 'Editar',
              ),
              IconButton(
                icon: Icon(
                  user.status ? Icons.block : Icons.check_circle_outline,
                  size: 20,
                ),
                color: user.status ? AppColors.warning : AppColors.success,
                onPressed: () => _toggleUserStatus(user),
                tooltip: user.status ? 'Desativar' : 'Ativar',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.error,
                onPressed: () => _showDeleteConfirmation(context, user),
                tooltip: 'Excluir',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPerfilBadge(String perfil) {
    Color color;
    switch (perfil) {
      case 'Gerente':
        color = AppColors.primary;
        break;
      case 'Supervisor':
        color = AppColors.info;
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
        perfil,
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
            'Mostrando ${_users.length} de ${_users.length} usuários',
            style: GoogleFonts.poppins(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: null,
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
                  '1',
                  style: GoogleFonts.poppins(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: null,
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
        onSave: (user) {
          setState(() {
            _users.add(user);
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usuário criado com sucesso!')),
          );
        },
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, MockUser user) {
    showDialog(
      context: context,
      builder: (context) => _UserFormDialog(
        title: 'Editar Usuário',
        user: user,
        onSave: (updatedUser) {
          setState(() {
            final index = _users.indexWhere((u) => u.id == user.id);
            if (index != -1) {
              _users[index] = updatedUser;
            }
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usuário atualizado com sucesso!')),
          );
        },
      ),
    );
  }

  void _toggleUserStatus(MockUser user) {
    setState(() {
      final index = _users.indexWhere((u) => u.id == user.id);
      if (index != -1) {
        _users[index] = MockUser(
          id: user.id,
          nome: user.nome,
          email: user.email,
          perfil: user.perfil,
          status: !user.status,
          ultimoAcesso: user.ultimoAcesso,
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          user.status ? 'Usuário desativado' : 'Usuário ativado',
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, MockUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Usuário'),
        content: Text('Deseja realmente excluir o usuário "${user.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _users.removeWhere((u) => u.id == user.id);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Usuário excluído com sucesso!')),
              );
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
  final MockUser? user;
  final Function(MockUser) onSave;

  const _UserFormDialog({
    required this.title,
    this.user,
    required this.onSave,
  });

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomeController;
  late TextEditingController _emailController;
  String _selectedPerfil = 'Operador';

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.user?.nome ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _selectedPerfil = widget.user?.perfil ?? 'Operador';
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              Text(
                widget.title,
                style: GoogleFonts.poppins(
                  fontSize: AppFontSizes.title,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome Completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe o nome';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe o email';
                  }
                  if (!value.contains('@')) {
                    return 'Email inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _selectedPerfil,
                decoration: const InputDecoration(
                  labelText: 'Perfil',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: ['Gerente', 'Supervisor', 'Operador']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedPerfil = value!);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSave(MockUser(
                          id: widget.user?.id ?? DateTime.now().millisecondsSinceEpoch,
                          nome: _nomeController.text,
                          email: _emailController.text,
                          perfil: _selectedPerfil,
                          status: widget.user?.status ?? true,
                          ultimoAcesso: widget.user?.ultimoAcesso ?? '-',
                        ));
                      }
                    },
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modelo de usuário mockado
class MockUser {
  final int id;
  final String nome;
  final String email;
  final String perfil;
  final bool status;
  final String ultimoAcesso;

  MockUser({
    required this.id,
    required this.nome,
    required this.email,
    required this.perfil,
    required this.status,
    required this.ultimoAcesso,
  });
}
