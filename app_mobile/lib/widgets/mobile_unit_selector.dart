import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:app_mobile/services/auth_service.dart';
import 'package:app_mobile/services/notification_service.dart';

/// Bottom Sheet para seleção de unidade ativa no mobile
class MobileUnitSelector extends StatelessWidget {
  const MobileUnitSelector({super.key});

  /// Exibe o bottom sheet para seleção de unidade
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const MobileUnitSelector(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final unidades = authService.unidadesPermitidas;
    final unidadeAtiva = authService.unidadeAtiva;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Título
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.store_outlined,
                        color: Color(0xFF1E3A5F),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selecionar Unidade',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E3A5F),
                            ),
                          ),
                          if (unidadeAtiva != null)
                            Text(
                              'Atual: ${unidadeAtiva.nome}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Botão fechar
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: Colors.grey[500]),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              
              Divider(height: 1, color: Colors.grey[200]),
              
              // Lista de unidades
              Expanded(
                child: unidades.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.warning_amber_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhuma unidade disponível',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: unidades.length,
                        itemBuilder: (context, index) {
                          final unidade = unidades[index];
                          final isSelected = unidadeAtiva?.id == unidade.id;

                          return _UnidadeTile(
                            unidade: unidade,
                            isSelected: isSelected,
                            onTap: () async {
                              await authService.setUnidadeAtiva(unidade);
                              if (context.mounted) {
                                // Atualiza NotificationService com nova unidade
                                final notificationService = Provider.of<NotificationService>(context, listen: false);
                                notificationService.setUnidadeId(unidade.id);
                                
                                Navigator.of(context).pop();
                                
                                // Feedback visual
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Unidade alterada para ${unidade.nome}',
                                            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: const Color(0xFF4CAF50),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Widget para cada item de unidade na lista
class _UnidadeTile extends StatelessWidget {
  final UnidadeNegocio unidade;
  final bool isSelected;
  final VoidCallback onTap;

  const _UnidadeTile({
    required this.unidade,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1E3A5F);
    const secondaryColor = Color(0xFF4CAF50);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Ícone de loja
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.15)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.storefront,
                color: isSelected ? primaryColor : Colors.grey[600],
                size: 24,
              ),
            ),
            
            const SizedBox(width: 14),
            
            // Informações da unidade
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unidade.nome,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? primaryColor : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.tag,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unidade.codigoUnb,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Check se selecionado
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: secondaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                ),
              )
            else
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.grey[300]!,
                    width: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botão compacto para exibir no AppBar mobile
class MobileUnitSelectorButton extends StatelessWidget {
  const MobileUnitSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final unidadeAtiva = authService.unidadeAtiva;
    final hasMultipleUnidades = authService.unidadesPermitidas.length > 1;

    // Sem unidades, não mostra nada
    if (unidadeAtiva == null && authService.unidadesPermitidas.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!hasMultipleUnidades && unidadeAtiva != null) {
      // Se só tem uma unidade, mostra apenas o nome (não clicável)
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_outlined, size: 18, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              unidadeAtiva.codigoUnb,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Múltiplas unidades - botão clicável
    return InkWell(
      onTap: () => MobileUnitSelector.show(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_outlined, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                unidadeAtiva?.codigoUnb ?? 'Selecionar',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
