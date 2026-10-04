import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api.dart/api.dart';
import 'mn_amount_text.dart';
import 'mn_card.dart';
import 'mn_empty_state.dart';
import 'movement_list_item.dart';

/// Lista de movimientos agrupada cronológicamente por día con subtotales.
class GroupedMovementList extends StatelessWidget {
  final List<MovementDto> movements;
  final Function(MovementDto)? onItemTap;
  final Function(MovementDto)? onItemDismissed;
  final VoidCallback? onEmptyAction;
  final ScrollController? controller;
  final Widget? footer;

  const GroupedMovementList({
    super.key,
    required this.movements,
    this.onItemTap,
    this.onItemDismissed,
    this.onEmptyAction,
    this.controller,
    this.footer,
  });

  String _formatDateHeader(String rawDate) {
    final now = DateTime.now();
    final todayStr = now.toIso8601String().substring(0, 10);
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = yesterday.toIso8601String().substring(0, 10);

    if (rawDate == todayStr) return 'Hoy';
    if (rawDate == yesterdayStr) return 'Ayer';

    try {
      final parts = rawDate.split('-');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        const months = [
          'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
          'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
        ];
        const daysOfWeek = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
        final dt = DateTime(year, month, day);
        final dow = daysOfWeek[dt.weekday - 1];
        final mon = months[month - 1];
        return '$dow $day $mon';
      }
    } catch (_) {}
    return rawDate;
  }

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return MnEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Registrá tu primer gasto',
        message: 'Escribí o dictá algo como "almuerzo 4500" y MoneyNeedle lo entiende al instante.',
        actionLabel: 'Empezar ahora',
        onAction: onEmptyAction,
      );
    }

    // Agrupar movimientos por fecha manteniendo orden cronológico
    final Map<String, List<MovementDto>> grouped = {};
    for (final m in movements) {
      final dateKey = m.fecha.isNotEmpty ? m.fecha : 'Sin fecha';
      grouped.putIfAbsent(dateKey, () => []).add(m);
    }

    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: dateKeys.length + (footer != null ? 1 : 0),
      itemBuilder: (context, groupIndex) {
        if (groupIndex == dateKeys.length) {
          return footer!;
        }
        final dateKey = dateKeys[groupIndex];
        final dayMovements = grouped[dateKey]!;

        // Subtotal de gastos del día
        double dayExpenses = 0;
        String dayCurrency = 'ARS';
        for (final m in dayMovements) {
          if (m.tipo.toLowerCase() == 'gasto' || m.tipo.toLowerCase() == 'expense') {
            dayExpenses += m.monto;
            dayCurrency = m.moneda;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDateHeader(dateKey),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (dayExpenses > 0)
                    Text(
                      '-${MnAmountText.format(dayExpenses, currency: dayCurrency, includeDecimals: false)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                ],
              ),
            ),
            MnCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: dayMovements.length,
                  separatorBuilder: (context, _) => Divider(
                    height: 1,
                    indent: 64,
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  itemBuilder: (context, itemIndex) {
                    final mov = dayMovements[itemIndex];
                    final itemWidget = MovementListItem(
                      movement: mov,
                      onTap: onItemTap != null ? () => onItemTap!(mov) : null,
                    );

                    if (onItemDismissed == null) return itemWidget;

                    return Dismissible(
                      key: ValueKey('movement_${mov.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Theme.of(context).colorScheme.error,
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        HapticFeedback.heavyImpact();
                        onItemDismissed!(mov);
                      },
                      child: itemWidget,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
