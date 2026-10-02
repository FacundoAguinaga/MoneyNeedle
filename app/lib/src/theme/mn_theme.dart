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
    income: Color(0xFF059669),
    expense: Color(0xFFE11D48),
    transfer: Color(0xFF0284C7),
    warning: Color(0xFFD97706),
    success: Color(0xFF059669),
    info: Color(0xFF2563EB),
    textMuted: Color(0xFF64748B),
    cardBorder: Color(0xFFE2E8F0),
  );

  static const dark = MnColors(
    income: Color(0xFF34D399),
    expense: Color(0xFFFB7185),
    transfer: Color(0xFF38BDF8),
    warning: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    info: Color(0xFF60A5FA),
    textMuted: Color(0xFF9CA3AF),
    cardBorder: Color(0xFF262F3D),
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

/// Sistema de diseño profesional de MoneyNeedle.
class MnTheme {
  static const Color seedColor = Color(0xFF10B981); // Emerald

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF047857),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD1FAE5),
      onPrimaryContainer: Color(0xFF064E3B),
      secondary: Color(0xFF0284C7),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE0F2FE),
      onSecondaryContainer: Color(0xFF0369A1),
      tertiary: Color(0xFF6366F1),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFEEF2FF),
      onTertiaryContainer: Color(0xFF3730A3),
      error: Color(0xFFE11D48),
      onError: Colors.white,
      errorContainer: Color(0xFFFFE4E6),
      onErrorContainer: Color(0xFF881337),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F172A),
      surfaceContainerHighest: Color(0xFFF1F5F9),
      surfaceContainerHigh: Color(0xFFF8FAFC),
      surfaceContainer: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF8FAFC),
      outline: Color(0xFFCBD5E1),
      outlineVariant: Color(0xFFE2E8F0),
      onSurfaceVariant: Color(0xFF64748B),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(
            color: Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF047857), width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        indicatorColor: const Color(0xFFD1FAE5),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF047857),
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      extensions: const [MnColors.light],
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF10B981),
      onPrimary: Color(0xFF022C22),
      primaryContainer: Color(0xFF064E3B),
      onPrimaryContainer: Color(0xFFA7F3D0),
      secondary: Color(0xFF38BDF8),
      onSecondary: Color(0xFF082F49),
      secondaryContainer: Color(0xFF075985),
      onSecondaryContainer: Color(0xFFBAE6FD),
      tertiary: Color(0xFF818CF8),
      onTertiary: Color(0xFF1E1B4B),
      tertiaryContainer: Color(0xFF3730A3),
      onTertiaryContainer: Color(0xFFE0E7FF),
      error: Color(0xFFFB7185),
      onError: Color(0xFF4C0519),
      errorContainer: Color(0xFF881337),
      onErrorContainer: Color(0xFFFFE4E6),
      surface: Color(0xFF111827),
      onSurface: Color(0xFFF3F4F6),
      surfaceContainerHighest: Color(0xFF1F2937),
      surfaceContainerHigh: Color(0xFF192231),
      surfaceContainer: Color(0xFF141C28),
      surfaceContainerLow: Color(0xFF0F172A),
      outline: Color(0xFF374151),
      outlineVariant: Color(0xFF262F3D),
      onSurfaceVariant: Color(0xFF9CA3AF),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF090D16),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF090D16),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFFF3F4F6),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Color(0xFFF3F4F6)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(
            color: Color(0xFF262F3D),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161F2E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF262F3D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF262F3D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0F172A),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: const Color(0xFF064E3B),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF34D399),
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9CA3AF),
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: Color(0xFF374151)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      extensions: const [MnColors.dark],
    );
  }
}
