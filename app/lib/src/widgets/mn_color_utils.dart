import 'package:flutter/material.dart';

/// Utilidades compartidas para parsear colores hexadecimales de la DB.
class MnColorUtils {
  static Color parseHex(String hex, {Color fallback = const Color(0xFF00695C)}) {
    try {
      var clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) {
        clean = 'FF$clean';
      }
      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return fallback;
  }
}
