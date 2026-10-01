import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Extensión de colores semánticos de MoneyNeedle para evitar hardcodear rojos/verdes.
class MnColors extends ThemeExtension<MnColors> {
  final Color income;
  final Color expense;
  final Color transfer;
  final Color warning;
  final Color success;
  final Color info;
  final Color textMuted;
  final Color cardBorder;

  const MnColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.success,
    required this.info,
    required this.textMuted,
    required this.cardBorder,
  });

  static const light = MnColors(
    income: Color(0xFF2E7D32),
    expense: Color(0xFFC62828),
    transfer: Color(0xFF1565C0),
    warning: Color(0xFFE65100),
    success: Color(0xFF2E7D32),
    info: Color(0xFF0288D1),
    textMuted: Color(0xFF757575),
    cardBorder: Color(0xFFE0E0E0),
  );

  static const dark = MnColors(
    income: Color(0xFF81C784),
    expense: Color(0xFFE57373),
    transfer: Color(0xFF64B5F6),
    warning: Color(0xFFFFB74D),
    success: Color(0xFF81C784),
    info: Color(0xFF4FC3F7),
    textMuted: Color(0xFFB0BEC5),
    cardBorder: Color(0xFF37474F),
  );

  @override
  ThemeExtension<MnColors> copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? success,
    Color? info,
    Color? textMuted,
    Color? cardBorder,
  }) {
    return MnColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      info: info ?? this.info,
      textMuted: textMuted ?? this.textMuted,
      cardBorder: cardBorder ?? this.cardBorder,
    );
  }

  @override
  ThemeExtension<MnColors> lerp(ThemeExtension<MnColors>? other, double t) {
    if (other is! MnColors) return this;
    return MnColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
    );
  }
}

/// Helper para acceder a MnColors fácilmente: `context.mnColors`.
extension MnColorsContext on BuildContext {
  MnColors get mnColors =>
      Theme.of(this).extension<MnColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? MnColors.dark : MnColors.light);
}

/// Sistema de diseño y temas visuales de MoneyNeedle con Teal `#00695C`.
class MnTheme {
  static const Color seedColor = Color(0xFF00695C);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      extensions: const [MnColors.light],
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      extensions: const [MnColors.dark],
    );
  }
}
