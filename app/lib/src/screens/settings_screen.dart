import 'package:flutter/material.dart';
import '../providers/privacy_provider.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../widgets/mn_card.dart';
import 'categories_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _reminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final reminder = await NotificationService.instance.isReminderEnabled();
    if (mounted) {
      setState(() {
        _reminderEnabled = reminder;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
      ),
      body: _buildGeneralTab(),
    );
  }

  Widget _buildGeneralTab() {
    final theme = Theme.of(context);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, currentThemeMode, _) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // Selector Visual de Tema
            _buildSectionTitle('Tema Visual'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildThemeCard(
                    title: 'Claro',
                    icon: Icons.light_mode,
                    isSelected: currentThemeMode == ThemeMode.light,
                    onTap: () => ThemeController.instance.setThemeMode(ThemeMode.light),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildThemeCard(
                    title: 'Oscuro',
                    icon: Icons.dark_mode,
                    isSelected: currentThemeMode == ThemeMode.dark,
                    onTap: () => ThemeController.instance.setThemeMode(ThemeMode.dark),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildThemeCard(
                    title: 'Sistema',
                    icon: Icons.brightness_auto,
                    isSelected: currentThemeMode == ThemeMode.system,
                    onTap: () => ThemeController.instance.setThemeMode(ThemeMode.system),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Hábitos y Notificaciones
            _buildSectionTitle('Hábitos y Notificaciones'),
            const SizedBox(height: 8),
            MnCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined, color: theme.colorScheme.primary),
                title: const Text('Recordatorio nocturno (21:00 hs)'),
                subtitle: const Text(
                  'Aviso discreto para registrar tus compras del día y sostener tu racha.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _reminderEnabled,
                onChanged: (val) async {
                  setState(() => _reminderEnabled = val);
                  await NotificationService.instance.setReminderEnabled(val);
                },
              ),
            ),
            const SizedBox(height: 24),

            // Privacidad en Pantalla
            _buildSectionTitle('Privacidad en Pantalla'),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: PrivacyController.instance,
              builder: (context, isPrivate, _) {
                return MnCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    secondary: Icon(
                      isPrivate ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Ocultar montos visibles'),
                    subtitle: const Text(
                      'Reemplaza cifras por asteriscos para evitar miradas indiscretas.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: isPrivate,
                    onChanged: (val) {
                      PrivacyController.instance.setPrivacy(val);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Personalización de Rubros
            _buildSectionTitle('Personalización'),
            const SizedBox(height: 8),
            MnCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.category_outlined, color: theme.colorScheme.primary),
                title: const Text('Categorías y Rubros'),
                subtitle: const Text(
                  'Configurá los nombres, íconos y colores de tus consumos.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CategoriesScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeCard({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderColor = isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;
    final bgColor = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
        : theme.colorScheme.surface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
