import 'package:flutter/material.dart';
import 'mn_color_utils.dart';

/// Ícono y avatar estilizado de categoría con mapeo robusto a Material Icons.
class MnCategoryIcon extends StatelessWidget {
  final String category;
  final String? iconName;
  final String? colorHex;
  final double size;
  final double radius;

  const MnCategoryIcon({
    super.key,
    required this.category,
    this.iconName,
    this.colorHex,
    this.size = 20,
    this.radius = 20,
  });

  static IconData getIcon(String key) {
    switch (key.toLowerCase().trim()) {
      case 'shopping_cart':
      case 'supermercado':
      case 'super':
        return Icons.shopping_cart;
      case 'directions_bus':
      case 'transporte':
      case 'sube':
      case 'auto':
      case 'nafta':
        return Icons.directions_bus;
      case 'restaurant':
      case 'comida':
      case 'cena':
      case 'almuerzo':
      case 'cafe':
        return Icons.restaurant;
      case 'receipt':
      case 'receipt_long':
      case 'servicios':
      case 'luz':
      case 'gas':
      case 'internet':
        return Icons.receipt_long;
      case 'home':
      case 'hogar':
      case 'alquiler':
        return Icons.home;
      case 'local_hospital':
      case 'medical_services':
      case 'salud':
      case 'farmacia':
        return Icons.local_hospital;
      case 'school':
      case 'educacion':
        return Icons.school;
      case 'movie':
      case 'entretenimiento':
      case 'cine':
        return Icons.movie;
      case 'flight':
      case 'vacaciones':
      case 'viaje':
        return Icons.flight;
      case 'work':
      case 'sueldo':
      case 'salario':
      case 'ingreso':
        return Icons.work;
      case 'shield':
      case 'emergencia':
        return Icons.shield;
      case 'pets':
      case 'mascotas':
        return Icons.pets;
      case 'tv':
      case 'streaming':
      case 'subscriptions':
        return Icons.tv;
      case 'transfer':
      case 'transferencia':
        return Icons.swap_horiz;
      default:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconData = getIcon(iconName ?? category);
    final color = colorHex != null
        ? MnColorUtils.parseHex(colorHex!)
        : Theme.of(context).colorScheme.primary;

    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(
        iconData,
        size: size,
        color: color,
      ),
    );
  }
}
