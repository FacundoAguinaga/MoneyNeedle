import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../services/notification_service.dart';
import 'categories_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onDataRestored;

  const SettingsScreen({super.key, this.onDataRestored});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _dbPath;
  bool _loading = false;
  bool _hasBiometrics = false;
  bool _reminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final path = await VaultService.getDbPath();
    final bioKey = await VaultService.readMasterKeyBiometric();
    final reminder = await NotificationService.instance.isReminderEnabled();
    if (mounted) {
      setState(() {
        _dbPath = path;
        _hasBiometrics = bioKey != null;
        _reminderEnabled = reminder;
      });
    }
  }

  // ==========================================================================
  // Acciones de Exportación
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

  // ==========================================================================
  // Crear Backup Cifrado (.mnbackup)
  // ==========================================================================

  Future<void> _mostrarModalCrearBackup() async {
    if (_dbPath == null) return;
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.enhanced_encryption, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Crear Backup Cifrado'),
            ],
          ),
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
                    labelText: 'Contraseña o Frase de Cifrado',
                    border: OutlineInputBorder(),
                    helperText: 'Mínimo 6 caracteres o tus 12 palabras',
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
              child: const Text('Generar Backup'),
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

  // ==========================================================================
  // Restaurar Backup Cifrado (.mnbackup)
  // ==========================================================================

  Future<void> _seleccionarYRestaurarBackup() async {
    if (_dbPath == null) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo leer la ruta del archivo seleccionado')),
          );
        }
        return;
      }

      if (!mounted) return;
      final passCtrl = TextEditingController();
      final formKey = GlobalKey<FormState>();

      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.settings_backup_restore, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('Restaurar Backup'),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Se restaurarán las transacciones, cuentas, presupuestos y metas. La base actual se respaldará físicamente de forma preventiva.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                      border: OutlineInputBorder(),
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
                style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
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
        builder: (ctx) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Restauración Exitosa'),
              ],
            ),
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
          );
        },
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

  // ==========================================================================
  // Bóveda Criptográfica y Frase
  // ==========================================================================

  Future<void> _mostrarInfoBoveda() async {
    final payload = await VaultService.getRecoveryPayload();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield, color: Colors.teal),
              SizedBox(width: 8),
              Text('Bóveda y Seguridad'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu base de datos está protegida localmente con SQLCipher (cifrado AES-256 página por página).',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    _hasBiometrics ? Icons.fingerprint : Icons.lock,
                    color: _hasBiometrics ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hasBiometrics
                          ? 'Desbloqueo biométrico activo por Keystore'
                          : 'Biometría no configurada o inactiva',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                payload != null
                    ? 'Payload de recuperación BIP-39 registrado en el dispositivo.'
                    : 'No se detectó payload de recuperación.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // Build UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes y Respaldos'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Sección 1: Seguridad
              _buildSectionHeader('Seguridad y Bóveda'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.security, color: Colors.teal),
                  title: const Text('Estado de la Bóveda'),
                  subtitle: Text(
                    _hasBiometrics
                        ? 'Cifrado SQLCipher + Biometría por hardware activo'
                        : 'SQLCipher activo',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.info_outline),
                  onTap: _mostrarInfoBoveda,
                ),
              ),

              // Sección 2: Backups Cifrados
              _buildSectionHeader('Copias de Seguridad Cifradas'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.enhanced_encryption, color: Colors.indigo),
                      title: const Text('Crear Backup Cifrado (.mnbackup)'),
                      subtitle: const Text(
                        'Generá un snapshot completo protegido con contraseña o frase BIP-39',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _loading ? null : _mostrarModalCrearBackup,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.settings_backup_restore, color: Colors.deepOrange),
                      title: const Text('Restaurar Backup Cifrado'),
                      subtitle: const Text(
                        'Seleccioná un archivo .mnbackup e ingresá su clave para restaurar',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _loading ? null : _seleccionarYRestaurarBackup,
                    ),
                  ],
                ),
              ),

              // Sección: Notificaciones y Hábitos
              _buildSectionHeader('Notificaciones y Hábitos'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 16),
                child: SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined, color: Colors.teal),
                  title: const Text('Recordatorio nocturno (21:00 hs)'),
                  subtitle: const Text(
                    'Te recuerda anotar tus gastos diarios para mantener la racha activa',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _reminderEnabled,
                  onChanged: (val) async {
                    setState(() => _reminderEnabled = val);
                    await NotificationService.instance.setReminderEnabled(val);
                  },
                ),
              ),

              // Sección: Personalización y Categorías
              _buildSectionHeader('Personalización'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.category_outlined, color: Colors.teal),
                  title: const Text('Categorías y Rubros'),
                  subtitle: const Text(
                    'Personalizá nombres, íconos y colores de tus consumos',
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

              // Sección 3: Exportación en Formatos Abiertos
              _buildSectionHeader('Exportación de Datos'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.table_chart_outlined, color: Colors.blue),
                      title: const Text('Exportar movimientos (CSV)'),
                      subtitle: const Text(
                        'Ideal para abrir en Excel, Google Sheets o LibreOffice',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.share),
                      onTap: _loading ? null : _exportarCsv,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.data_object, color: Colors.green),
                      title: const Text('Exportar datos completos (JSON)'),
                      subtitle: const Text(
                        'Estructura completa de cuentas, presupuestos y movimientos',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.share),
                      onTap: _loading ? null : _exportarJson,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.model_training, color: Colors.purple),
                      title: const Text('Exportar datos de entrenamiento (JSONL)'),
                      subtitle: const Text(
                        'Para reentrenar Cactus Needle 3 con correcciones de voz/texto',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.share),
                      onTap: _loading ? null : _exportarJsonlTraining,
                    ),
                  ],
                ),
              ),

              // Sección 4: Acerca de
              _buildSectionHeader('Acerca de MoneyNeedle'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.psychology,
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MoneyNeedle v0.1.0',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                'Finanzas Local-First con Needle 3',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '• Motor IA: Tiny Cactus Needle 3 (on-device, 100% offline)\n'
                        '• Motor de Persistencia: SQLCipher Relacional (AES-256)\n'
                        '• Derivación de Claves: Argon2id (OWASP mobile)\n'
                        '• Formato de Backups: Autocontenido MNBK v1 (AES-256-GCM)',
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black38,
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
