import 'package:flutter/material.dart';
import '../theme/mn_theme.dart';

/// Formateador y visualizador de montos monetarios de alta precisión.
class MnAmountText extends StatelessWidget {
  final double amount;
  final String currency;
  final TextStyle? style;
  final bool showSign;
  final bool colorize;
  final bool isExpense;
  final bool isIncome;
  final bool isTransfer;
  final bool obscure;

  const MnAmountText({
    super.key,
    required this.amount,
    this.currency = 'ARS',
    this.style,
    this.showSign = false,
    this.colorize = true,
    this.isExpense = false,
    this.isIncome = false,
    this.isTransfer = false,
    this.obscure = false,
  });

  /// Formatea un monto con separador de miles y 2 decimales estándar rioplatenses.
  static String format(
    double amount, {
    String currency = 'ARS',
    bool showSign = false,
    bool includeDecimals = true,
  }) {
    final isNeg = amount < 0;
    final absAmount = amount.abs();
    final parts = absAmount.toStringAsFixed(includeDecimals ? 2 : 0).split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '';

    final buffer = StringBuffer();
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(integerPart[i]);
    }

    String sign = '';
    if (isNeg) {
      sign = '-';
    } else if (showSign) {
      sign = '+';
    }

    if (includeDecimals && decimalPart.isNotEmpty && decimalPart != '00') {
      return '$sign\$$buffer,$decimalPart $currency';
    }
    return '$sign\$$buffer $currency';
  }

  @override
  Widget build(BuildContext context) {
    if (obscure) {
      return Text(
        '••••••',
        style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final mnColors = context.mnColors;
    Color? textColor;

    if (colorize) {
      if (isExpense || amount < 0) {
        textColor = mnColors.expense;
      } else if (isIncome || amount > 0) {
        textColor = mnColors.income;
      } else if (isTransfer) {
        textColor = mnColors.transfer;
      }
    }

    final formatted = format(
      amount,
      currency: currency,
      showSign: showSign,
    );

    final baseStyle = style ?? Theme.of(context).textTheme.bodyLarge;
    final finalStyle = baseStyle?.copyWith(
      color: textColor ?? baseStyle.color,
      fontWeight: baseStyle.fontWeight ?? FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Text(
      formatted,
      style: finalStyle,
    );
  }
}
