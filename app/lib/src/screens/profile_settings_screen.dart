import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/vault_service.dart';
import '../providers/privacy_provider.dart';
import '../providers/theme_provider.dart';
import '../rust/api.dart/api.dart';
import '../services/notification_service.dart';
import '../theme/mn_theme.dart';
import '../widgets/mn_card.dart';
import 'categories_screen.dart';

/// Pantalla integrada de Perfil y Ajustes con pestañas temáticas.
class ProfileSettingsScreen extends StatefulWidget {
  final VoidCallback? onDataRestored;
  final VoidCallback? onLockVault;

  const ProfileSettingsScreen({
    super.key,
    this.onDataRestored,
    this.onLockVault,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _dbPath;
  bool _loading = false;
  bool _hasBiometrics = false;
  bool _reminderEnabled = false;
  String _userName = 'Usuario';
  StreakDto? _streak;
  int _totalMovements = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final path = await VaultService.getDbPath();
    final bioKey = await VaultService.readMasterKeyBiometric();
    final reminder = await NotificationService.instance.isReminderEnabled();
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('mn_user_name') ?? 'Usuario';

    StreakDto? streak;
    int movCount = 0;
    try {
      streak = await getUsageStreak(dbPath: path);
      final movs = await listMovements(dbPath: path, limit: 1000);
      movCount = movs.length;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _dbPath = path;
        _hasBiometrics = bioKey != null;
        _reminderEnabled = reminder;
        _userName = savedName;
        _streak = streak;
        _totalMovements = movCount;
      });
    }
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
      setState(() => _userName = nuevo);
    }
  }

  // ==========================================================================
  // Acciones de Exportación y Backups
  // ==========================================================================

  Future<void> _exportarCsv() async {
    if (_dbPath == null) return;
    setState(() => _loading = true);
    try {
      final csvContent = await exportTransactionsCsv(dbPath: _dbPath!);
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/movimientos_moneyneedle_$now.csv');
      await file.writeAsString(csvContent);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Movimientos MoneyNeedle (CSV)',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando CSV: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportarJson() async {
    if (_dbPath == null) return;
    setState(() => _loading = true);
    try {
      final jsonContent = await exportAllDataJson(dbPath: _dbPath!);
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/moneyneedle_backup_$now.json');
      await file.writeAsString(jsonContent);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Datos MoneyNeedle (JSON)',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando JSON: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportarJsonlTraining() async {
    if (_dbPath == null) return;
    setState(() => _loading = true);
    try {
      final jsonlContent = await exportCorrectionsForTraining(dbPath: _dbPath!);
      if (jsonlContent.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay movimientos dictados para reentrenamiento aún.')),
          );
        }
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/corrections_needle_$now.jsonl');
      await file.writeAsString(jsonlContent);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/x-jsonlines')],
          subject: 'Correcciones Cactus Needle 3 (JSONL)',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando correcciones: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _crearBackupCifrado() async {
    if (_dbPath == null) return;
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Crear Backup Cifrado (.mnbackup)'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El archivo .mnbackup contiene el snapshot completo de tus finanzas protegido con AES-256-GCM y Argon2id.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña del Backup',
                    helperText: 'Mínimo 6 caracteres',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().length < 6) {
                      return 'Ingresá al menos 6 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final pass = passCtrl.text.trim();
                Navigator.pop(ctx);
                await _ejecutarCrearBackup(pass);
              },
              child: const Text('Generar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _ejecutarCrearBackup(String passphrase) async {
    setState(() => _loading = true);
    try {
      final bytes = await createEncryptedBackup(
        dbPath: _dbPath!,
        passphrase: passphrase,
      );
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/moneyneedle_backup_$now.mnbackup');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: 'Backup Cifrado MoneyNeedle',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restaurarBackupCifrado() async {
    if (_dbPath == null) return;
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      if (!mounted) return;
      final passCtrl = TextEditingController();
      final formKey = GlobalKey<FormState>();

      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Restaurar Backup Cifrado'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Archivo: ${result.files.single.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passCtrl,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña del Backup',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Ingresá la contraseña utilizada para este backup';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final pass = passCtrl.text.trim();
                  Navigator.pop(ctx);
                  await _ejecutarRestauracion(path, pass);
                },
                child: const Text('Restaurar'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error seleccionando archivo: $e')),
        );
      }
    }
  }

  Future<void> _ejecutarRestauracion(String filePath, String passphrase) async {
    setState(() => _loading = true);
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      final summary = await restoreEncryptedBackup(
        dbPath: _dbPath!,
        backupBytes: bytes,
        passphrase: passphrase,
      );

      widget.onDataRestored?.call();

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restauración Exitosa'),
          content: Text(
            'Se restauraron satisfactoriamente:\n\n'
            '• ${summary.transactions} transacciones\n'
            '• ${summary.accounts} cuentas\n'
            '• ${summary.budgets} presupuestos\n'
            '• ${summary.savingGoals} metas de ahorro\n'
            '• ${summary.recurringRules} reglas recurrentes\n'
            '• ${summary.categories} categorías',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al restaurar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mostrarFraseRecuperacion() async {
    final payload = await VaultService.getRecoveryPayload();
    if (!mounted) return;

    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay payload de recuperación en este dispositivo.')),
      );
      return;
    }

    // Modal de advertencia antes de revelar
    final revelar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frase de Recuperación (BIP-39)'),
        content: const Text(
          'Esta frase de 12 palabras permite restaurar tu bóveda completa en cualquier dispositivo. '
          'Asegurate de que nadie esté mirando tu pantalla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revelar Frase'),
          ),
        ],
      ),
    );

    if (revelar != true || !mounted) return;

    final words = payload.split(' ');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tus 12 Palabras Seguras'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(words.length, (i) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      '${i + 1}. ${words[i]}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar frase al portapapeles'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: payload));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Frase copiada al portapapeles')),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Pestaña 1: Perfil
  // ==========================================================================

  Widget _buildProfileTab() {
    final theme = Theme.of(context);
    final colors = context.mnColors;
    final streak = _streak;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Tarjeta de Identidad del Usuario
        MnCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _userName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 4),
                    Text(
                      'Bóveda local activa y cifrada',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Métricas de Perfil
        Row(
          children: [
            Expanded(
              child: MnCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Racha activa',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${streak?.currentStreak ?? 0} días',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Récord: ${streak?.maxStreak ?? 0} días',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MnCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Movimientos',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_totalMovements',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Registros en histórico',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Ficha Local-First
        MnCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Privacidad y Soberanía de Datos',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Tus finanzas no salen de este teléfono. Sin analíticas remotas, sin APIs de terceros ni rastreadores. '
                'Toda la inteligencia artificial corre directamente en el procesador de tu dispositivo.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // Pestaña 2: Ajustes Generales
  // ==========================================================================

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

  // ==========================================================================
  // Pestaña 3: Seguridad de la Bóveda
  // ==========================================================================

  Widget _buildSecurityTab() {
    final theme = Theme.of(context);
    final colors = context.mnColors;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Estado de Bóveda
        MnCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: colors.success),
                  const SizedBox(width: 8),
                  Text(
                    'Bóveda Criptográfica Local',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSecurityItem(
                label: 'Algoritmo de Base',
                value: 'SQLCipher AES-256 (Page-level)',
              ),
              const Divider(height: 16),
              _buildSecurityItem(
                label: 'Derivación de Clave',
                value: 'Argon2id (OWASP Mobile Standard)',
              ),
              const Divider(height: 16),
              _buildSecurityItem(
                label: 'Almacén de Hardware',
                value: _hasBiometrics
                    ? 'Android KeyStore / Biometría activa'
                    : 'Clave cifrada por frase maestra',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _buildSectionTitle('Respaldo de Acceso'),
        const SizedBox(height: 8),
        MnCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.key, color: theme.colorScheme.primary),
            title: const Text('Frase de Recuperación (12 palabras)'),
            subtitle: const Text(
              'Revelá tu clave mnemónica BIP-39 para respaldarla en papel.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _mostrarFraseRecuperacion,
          ),
        ),
        const SizedBox(height: 20),

        _buildSectionTitle('Acciones de Sesión'),
        const SizedBox(height: 8),
        MnCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.lock_clock, color: Colors.orange),
            title: const Text('Bloquear Bóveda ahora'),
            subtitle: const Text(
              'Cierra la sesión y requiere biometría o clave para volver a entrar.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.exit_to_app),
            onTap: () {
              widget.onLockVault?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityItem({required String label, required String value}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    );
  }

  // ==========================================================================
  // Pestaña 4: Respaldos y Datos
  // ==========================================================================

  Widget _buildBackupsTab() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        _buildSectionTitle('Copias de Seguridad Cifradas'),
        const SizedBox(height: 8),
        MnCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.enhanced_encryption, color: theme.colorScheme.primary),
                title: const Text('Crear Backup Cifrado (.mnbackup)'),
                subtitle: const Text(
                  'Snapshot completo protegido con contraseña o frase BIP-39.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _loading ? null : _crearBackupCifrado,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.settings_backup_restore, color: Colors.deepOrange),
                title: const Text('Restaurar Backup Cifrado'),
                subtitle: const Text(
                  'Recuperá tus transacciones, cuentas, presupuestos y metas.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _loading ? null : _restaurarBackupCifrado,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _buildSectionTitle('Exportación Abierta'),
        const SizedBox(height: 8),
        MnCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.table_chart_outlined, color: Colors.blue),
                title: const Text('Exportar movimientos (CSV)'),
                subtitle: const Text(
                  'Compatible con Excel, Google Sheets y LibreOffice.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.share, size: 20),
                onTap: _loading ? null : _exportarCsv,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.data_object, color: Colors.green),
                title: const Text('Exportar datos completos (JSON)'),
                subtitle: const Text(
                  'Estructura relacional completa en texto plano.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.share, size: 20),
                onTap: _loading ? null : _exportarJson,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.model_training, color: Colors.purple),
                title: const Text('Exportar datos de entrenamiento (JSONL)'),
                subtitle: const Text(
                  'Dataset de correcciones para reentrenar Tiny Cactus Needle 3.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.share, size: 20),
                onTap: _loading ? null : _exportarJsonlTraining,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _buildSectionTitle('Información del Sistema'),
        const SizedBox(height: 8),
        MnCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.psychology, color: Colors.teal),
                  SizedBox(width: 8),
                  Text(
                    'MoneyNeedle v0.1.0',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• Modelo IA: Tiny Cactus Needle 3 (on-device, 100% offline)\n'
                '• Persistencia: SQLCipher Relacional con WAL mode\n'
                '• Protocolo de Backup: Autocontenido MNBK v1 (AES-256-GCM)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes y Perfil'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'Perfil', icon: Icon(Icons.person_outline, size: 20)),
            Tab(text: 'General', icon: Icon(Icons.tune, size: 20)),
            Tab(text: 'Seguridad', icon: Icon(Icons.security, size: 20)),
            Tab(text: 'Respaldos', icon: Icon(Icons.backup_outlined, size: 20)),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildProfileTab(),
              _buildGeneralTab(),
              _buildSecurityTab(),
              _buildBackupsTab(),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Procesando datos...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
