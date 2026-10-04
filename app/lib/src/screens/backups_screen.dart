import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../widgets/mn_card.dart';

class BackupsScreen extends StatefulWidget {
  final VoidCallback? onDataRestored;
  const BackupsScreen({super.key, this.onDataRestored});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  String? _dbPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final path = await VaultService.getDbPath();
    if (mounted) setState(() => _dbPath = path);
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Respaldos y Datos'),
      ),
      body: Stack(
        children: [
          _buildBackupsTab(),
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
