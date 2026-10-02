import 'package:flutter/material.dart';
import '../theme/mn_theme.dart';
import 'mn_amount_text.dart';
import 'mn_card.dart';

/// Tarjeta de indicador clave (KPI) para el Home Tab y Métricas.
class MnKpiCard extends StatelessWidget {
  final String title;
  final double amount;
  final String currency;
  final IconData? icon;
  final Color? color;
  final double? deltaPercentage;
  final String? subtitle;
  final VoidCallback? onTap;

  const MnKpiCard({
    super.key,
    required this.title,
    required this.amount,
    this.currency = 'ARS',
    this.icon,
    this.color,
    this.deltaPercentage,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.colorScheme.primary;

    return MnCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: cardColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          MnAmountText(
            amount: amount,
            currency: currency,
            colorize: false,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (deltaPercentage != null || subtitle != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (deltaPercentage != null) ...[
                  Icon(
                    deltaPercentage! >= 0 ? Icons.trending_up : Icons.trending_down,
                    size: 14,
                    color: deltaPercentage! >= 0 ? context.mnColors.expense : context.mnColors.income,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${deltaPercentage! >= 0 ? '+' : ''}${deltaPercentage!.toStringAsFixed(1)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: deltaPercentage! >= 0 ? context.mnColors.expense : context.mnColors.income,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (subtitle != null)
                  Expanded(
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
