import 'package:flutter/services.dart';

/// Servicio para coordinar eventos provenientes del Android AppWidget nativo.
class WidgetService {
  static const _channel = MethodChannel('moneyneedle/widget');

  static void init({required VoidCallback onQuickAdd}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onQuickAddTriggered') {
        onQuickAdd();
      }
    });
  }

  static Future<bool> checkInitialQuickAdd() async {
    try {
      final triggered = await _channel.invokeMethod<bool>('checkQuickAdd');
      return triggered ?? false;
    } catch (_) {
      return false;
    }
  }
}
