import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyneedle_app/src/theme/mn_theme.dart';
import 'package:moneyneedle_app/src/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MnColors', () {
    test('MnColors provides semantic colors for dark and light', () {
      const darkColors = MnColors.dark;
      expect(darkColors.income, const Color(0xFF34D399));
      expect(darkColors.expense, const Color(0xFFFB7185));
      expect(darkColors.transfer, const Color(0xFF38BDF8));
      expect(darkColors.warning, const Color(0xFFFBBF24));

      const lightColors = MnColors.light;
      expect(lightColors.income, const Color(0xFF059669));
      expect(lightColors.expense, const Color(0xFFE11D48));
      expect(lightColors.transfer, const Color(0xFF0284C7));
      expect(lightColors.warning, const Color(0xFFD97706));
    });
  });

  group('ThemeController', () {
    test('updates theme mode and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController.instance;

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.value, ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mn_theme_mode'), 'dark');

      await controller.setThemeMode(ThemeMode.light);
      expect(controller.value, ThemeMode.light);
      expect(prefs.getString('mn_theme_mode'), 'light');

      await controller.setThemeMode(ThemeMode.system);
      expect(controller.value, ThemeMode.system);
      expect(prefs.getString('mn_theme_mode'), 'system');
    });
  });
}
