import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/mn_card.dart';
import 'accounts_tab.dart';
import 'backups_screen.dart';
import 'budgets_screen.dart';
import 'categories_screen.dart';
import 'recurring_tab.dart';
import 'saving_goals_screen.dart';
import 'security_screen.dart';
import 'settings_screen.dart';

/// Hub central "Más" que reúne las secciones secundarias y el perfil del usuario.
class MoreHub extends StatefulWidget {
  final VoidCallback? onDataRestored;
  final VoidCallback? onLockVault;

  const MoreHub({
    super.key,
    this.onDataRestored,
    this.onLockVault,
  });

  @override
  State<MoreHub> createState() => _MoreHubState();
}

class _MoreHubState extends State<MoreHub> {
  String _userName = 'Usuario';
  StreakDto? _streak;
  int _totalMovements = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final path = await VaultService.getDbPath();
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('mn_user_name') ?? 'Usuario';

      final streak = await getUsageStreak(dbPath: path);
      final movs = await listMovements(dbPath: path, limit: 1000);

      if (!mounted) return;
      setState(() {
        _userName = savedName;
        _streak = streak;
        _totalMovements = movs.length;
      });
    } catch (_) {}
  }

  Future<void> _editarNombreUsuario() async {
    final ctrl = TextEditingController(text: _userName);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nombre o alias'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tu nombre o apodo',
            hintText: 'Ej. Facundo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevo != null && nuevo.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mn_user_name', nuevo);
      if (mounted) {
        setState(() => _userName = nuevo);
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildHubTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.mnColors;
    final streak = _streak;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadProfileData,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Header: Tarjeta de Identidad del Usuario
            MnCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _userName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _editarNombreUsuario,
                              child: Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bóveda local activa y cifrada',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.income,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (streak != null && streak.currentStreak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${streak.currentStreak}d',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Métricas resumidas
            Row(
              children: [
                Expanded(
                  child: MnCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Racha actual',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${streak?.currentStreak ?? 0} días',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Récord: ${streak?.maxStreak ?? 0} días',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MnCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historial',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_totalMovements registros',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Guardados localmente',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // SECCIÓN: GESTIÓN FINANCIERA
            _buildSectionHeader('GESTIÓN FINANCIERA'),
            MnCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildHubTile(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: Colors.blue,
                    title: 'Cuentas y Tarjetas',
                    subtitle: 'Bancos, billeteras, límites de crédito y cierres',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AccountsTab(isStandalone: true),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildHubTile(
                    icon: Icons.pie_chart_outline,
                    iconColor: Colors.purple,
                    title: 'Presupuestos',
                    subtitle: 'Límites mensuales por categoría y alertas de consumo',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BudgetsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildHubTile(
                    icon: Icons.flag_outlined,
                    iconColor: Colors.teal,
                    title: 'Metas de Ahorro',
                    subtitle: 'Objetivos financieros, progresos y aportes',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavingGoalsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildHubTile(
                    icon: Icons.autorenew_rounded,
                    iconColor: Colors.deepOrange,
                    title: 'Suscripciones y Recurrentes',
                    subtitle: 'Servicios mensuales, cuotas y cobros periódicos',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RecurringTab(isStandalone: true),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // SECCIÓN: PERSONALIZACIÓN Y AJUSTES
            _buildSectionHeader('CONFIGURACIÓN'),
            MnCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildHubTile(
                    icon: Icons.category_outlined,
                    iconColor: Colors.indigo,
                    title: 'Categorías y Rubros',
                    subtitle: 'Personalizar nombres, colores e íconos de consumos',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CategoriesScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildHubTile(
                    icon: Icons.tune_rounded,
                    iconColor: Colors.green,
                    title: 'Preferencias Generales',
                    subtitle: 'Tema visual claro/oscuro, recordatorios y privacidad',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // SECCIÓN: SEGURIDAD Y DATOS
            _buildSectionHeader('SEGURIDAD Y DATOS'),
            MnCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildHubTile(
                    icon: Icons.security_rounded,
                    iconColor: Colors.amber.shade800,
                    title: 'Seguridad de la Bóveda',
                    subtitle: 'Clave BIP-39 de 12 palabras, biometría y bloqueo',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SecurityScreen(onLockVault: widget.onLockVault),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildHubTile(
                    icon: Icons.backup_outlined,
                    iconColor: Colors.blueGrey,
                    title: 'Respaldos y Exportación',
                    subtitle: 'Crear o restaurar .mnbackup, exportar CSV, JSON y JSONL',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BackupsScreen(onDataRestored: widget.onDataRestored),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                'MoneyNeedle · 100% Local-First & Cifrado',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
