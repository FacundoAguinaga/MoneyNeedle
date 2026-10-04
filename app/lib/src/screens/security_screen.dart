import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/vault_service.dart';
import '../theme/mn_theme.dart';
import '../widgets/mn_card.dart';

class SecurityScreen extends StatefulWidget {
  final VoidCallback? onLockVault;

  const SecurityScreen({super.key, this.onLockVault});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _hasBiometrics = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final bioKey = await VaultService.readMasterKeyBiometric();
    if (mounted) {
      setState(() {
        _hasBiometrics = bioKey != null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad'),
      ),
      body: _buildSecurityTab(),
    );
  }

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
                  Icon(Icons.lock_outline, color: colors.income),
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
}
