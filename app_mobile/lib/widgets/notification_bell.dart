import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

/// Widget do sininho de notificações com badge e dropdown
class NotificationBell extends StatefulWidget {
  /// Se true, usa estilo para AppBar (texto branco)
  final bool forAppBar;
  
  /// Tamanho do ícone
  final double iconSize;

  const NotificationBell({
    super.key,
    this.forAppBar = false,
    this.iconSize = 24,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final GlobalKey _bellKey = GlobalKey();

  void _showNotificationsPopup() {
    final RenderBox renderBox =
        _bellKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          // Área clicável para fechar
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Popup posicionado
          Positioned(
            top: position.dy + size.height + 8,
            right: MediaQuery.of(context).size.width - position.dx - size.width,
            child: const NotificationDropdown(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notificationService = Provider.of<NotificationService>(context);
    final totalAlertas = notificationService.totalAlertas;
    final iconColor = widget.forAppBar ? Colors.white : AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: _bellKey,
        onTap: _showNotificationsPopup,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_outlined,
                size: widget.iconSize,
                color: iconColor,
              ),
              // Badge com contador
              if (totalAlertas > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      totalAlertas > 99 ? '99+' : totalAlertas.toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dropdown/Popup que mostra a lista de notificações
class NotificationDropdown extends StatelessWidget {
  const NotificationDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final notificationService = Provider.of<NotificationService>(context);
    final notificacoes = notificationService.notificacoes;
    final resumo = notificationService.resumo;
    final isLoading = notificationService.isLoading;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Alertas de Validade',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  // Botão atualizar
                  IconButton(
                    onPressed: () => notificationService.fetchNotificacoes(),
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh, color: Colors.white, size: 20),
                    tooltip: 'Atualizar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // Resumo por status
            if (resumo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem(
                      label: 'Crítico',
                      count: resumo.extremamenteCritico,
                      color: const Color(0xFFF44336),
                    ),
                    _buildResumoItem(
                      label: 'Bloqueado',
                      count: resumo.bloqueado,
                      color: const Color(0xFFFF9800),
                    ),
                    _buildResumoItem(
                      label: 'Pré-Bloqueio',
                      count: resumo.preBloqueio,
                      color: const Color(0xFFFFC107),
                    ),
                  ],
                ),
              ),

            // Lista de notificações
            if (notificacoes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum alerta!',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Todos os lotes estão OK',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notificacoes.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    final notif = notificacoes[index];
                    return _NotificationItem(notificacao: notif);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoItem({
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

/// Item individual da lista de notificações
class _NotificationItem extends StatelessWidget {
  final NotificacaoAlerta notificacao;

  const _NotificationItem({required this.notificacao});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return InkWell(
      onTap: () {
        // TODO: Navegar para detalhes do SKU
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Indicador de cor
            Container(
              width: 4,
              height: 50,
              decoration: BoxDecoration(
                color: notificacao.cor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            
            // Informações do SKU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notificacao.skuNome,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Badge de status
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: notificacao.cor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          notificacao.statusLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: notificacao.cor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        notificacao.skuCodigo,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        ' • Lote: ${notificacao.numeroLote}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateFormat.format(notificacao.dataValidade),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: notificacao.cor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${notificacao.diasRestantes}d',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: notificacao.cor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${notificacao.qtdEstoque} un',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
