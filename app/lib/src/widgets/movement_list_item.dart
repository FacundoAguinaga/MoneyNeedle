import 'package:flutter/material.dart';
import '../rust/api.dart/api.dart';
import 'mn_amount_text.dart';
import 'mn_category_icon.dart';

/// Elemento de lista reutilizable para un movimiento financiero.
class MovementListItem extends StatelessWidget {
  final MovementDto movement;
  final VoidCallback? onTap;
  final Widget? trailing;

  const MovementListItem({
    super.key,
    required this.movement,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTransfer = movement.tipo.toLowerCase() == 'transferencia' ||
        movement.tipo.toLowerCase() == 'transfer';
    final isGasto = movement.tipo.toLowerCase() == 'gasto' ||
        movement.tipo.toLowerCase() == 'expense';
    final isIngreso = movement.tipo.toLowerCase() == 'ingreso' ||
        movement.tipo.toLowerCase() == 'income';

    final titleText = movement.descripcion.isNotEmpty
        ? movement.descripcion
        : (movement.categoria.isNotEmpty ? movement.categoria : movement.tipo);

    final subtitleParts = <String>[];
    if (movement.descripcion.isNotEmpty && movement.categoria.isNotEmpty) {
      subtitleParts.add(movement.categoria);
    }
    if (movement.accountName != null && movement.accountName!.isNotEmpty) {
      subtitleParts.add(movement.accountName!);
    }
    final subtitleText = subtitleParts.join(' · ');

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: MnCategoryIcon(
        category: isTransfer ? 'transfer' : movement.categoria,
        iconName: isTransfer ? 'transfer' : null,
        radius: 22,
      ),
      title: Text(
        titleText,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleText.isNotEmpty
          ? Text(
              subtitleText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing ??
          MnAmountText(
            amount: movement.monto,
            currency: movement.moneda,
            isExpense: isGasto,
            isIncome: isIngreso,
            isTransfer: isTransfer,
            showSign: true,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
    );
  }
}
