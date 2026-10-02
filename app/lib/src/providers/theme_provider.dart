import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controlador global del modo visual (Claro, Oscuro, Sistema) con persistencia.
class ThemeController extends ValueNotifier<ThemeMode> {
  static const String _prefKey = 'mn_theme_mode';

  ThemeController._() : super(ThemeMode.system) {
    _loadPreference();
  }

  static final ThemeController instance = ThemeController._();

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefKey);
      if (savedMode != null) {
        switch (savedMode) {
          case 'dark':
            value = ThemeMode.dark;
            break;
          case 'light':
            value = ThemeMode.light;
            break;
          case 'system':
          default:
            value = ThemeMode.system;
            break;
        }
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr;
      switch (mode) {
        case ThemeMode.dark:
          modeStr = 'dark';
          break;
        case ThemeMode.light:
          modeStr = 'light';
          break;
        case ThemeMode.system:
          modeStr = 'system';
          break;
      }
      await prefs.setString(_prefKey, modeStr);
    } catch (_) {}
  }

  bool isDarkMode(BuildContext context) {
    if (value == ThemeMode.dark) return true;
    if (value == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }
}
