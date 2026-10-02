import 'package:flutter/material.dart';
import '../rust/api.dart/api.dart';
import 'mn_amount_text.dart';
import 'mn_card.dart';

/// Tarjeta visual para un insight financiero predictivo o accionable.
class InsightCard extends StatelessWidget {
  final FinancialInsightDto insight;
  final VoidCallback? onTap;

  const InsightCard({
    super.key,
    required this.insight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    Color accentColor;
    IconData iconData;

    switch (insight.insightType.toLowerCase()) {
      case 'warning':
        accentColor = isDark ? const Color(0xFFFBBF24) : Colors.orange.shade800;
        iconData = Icons.warning_amber_rounded;
        break;
      case 'tip':
        accentColor = isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade700;
        iconData = Icons.lightbulb_outline;
        break;
      case 'projection':
        accentColor = isDark ? const Color(0xFF818CF8) : Colors.indigo.shade600;
        iconData = Icons.trending_up;
        break;
      case 'info':
      default:
        accentColor = isDark ? const Color(0xFF94A3B8) : Colors.blueGrey.shade700;
        iconData = Icons.insights_outlined;
        break;
    }

    return MnCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      backgroundColor: accentColor.withValues(alpha: 0.08),
      borderColor: accentColor.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, size: 18, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            insight.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.35,
            ),
          ),
          if (insight.safeToSpendDaily != null || insight.projectedMonthExpense > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (insight.safeToSpendDaily != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF2DD4BF) : Colors.teal).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sugerido: ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        MnAmountText(
                          amount: insight.safeToSpendDaily!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? const Color(0xFF5EEAD4) : Colors.teal.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                          colorize: false,
                        ),
                        Text(
                          '/día',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (insight.projectedMonthExpense > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF818CF8) : Colors.indigo).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Cierre proyectado: ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? const Color(0xFF818CF8) : Colors.indigo.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        MnAmountText(
                          amount: insight.projectedMonthExpense,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? const Color(0xFFA5B4FC) : Colors.indigo.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                          colorize: false,
                        ),
                      ],
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
