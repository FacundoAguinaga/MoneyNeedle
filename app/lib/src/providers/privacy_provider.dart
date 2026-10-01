import 'package:flutter/material.dart';

/// Controlador global del modo privacidad (ocultar montos en pantalla).
class PrivacyController extends ValueNotifier<bool> {
  PrivacyController._() : super(false);

  static final PrivacyController instance = PrivacyController._();

  void toggle() {
    value = !value;
  }

  void setPrivacy(bool isPrivate) {
    value = isPrivate;
  }
}
