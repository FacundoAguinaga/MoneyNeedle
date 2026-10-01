import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api.dart/api.dart';
import '../widgets/widgets.dart';
import 'vault_service.dart';

class OnboardingVaultScreen extends StatefulWidget {
  final VoidCallback onVaultReady;

  const OnboardingVaultScreen({super.key, required this.onVaultReady});

  @override
  State<OnboardingVaultScreen> createState() => _OnboardingVaultScreenState();
}

class _OnboardingVaultScreenState extends State<OnboardingVaultScreen> {
  VaultInitDto? _vault;
  bool _loading = true;
  bool _confirmed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generarVault();
  }

  Future<void> _generarVault() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await createVault();
      if (!mounted) return;
      setState(() {
        _vault = v;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error preparando seguridad: $e';
        _loading = false;
      });
    }
  }

  Future<void> _activarYContinuar() async {
    final v = _vault;
    if (v == null || !_confirmed) return;

    setState(() => _saving = true);
    try {
      await VaultService.saveRecoveryPayload(v.wrappedRecoveryPayload);
      await VaultService.saveMasterKeyBiometric(v.rawMasterKeyHex);
      await VaultService.unlockAndInitDb(v.rawMasterKeyHex);

      // Crear cuenta default "Billetera" si no existen cuentas aún
      try {
        final dbPath = await VaultService.getDbPath();
        final existing = await listAccounts(dbPath: dbPath);
        if (existing.isEmpty) {
          await createAccount(
            dbPath: dbPath,
            name: 'Billetera',
            accountType: 'wallet',
            currency: 'ARS',
            initialBalance: 0.0,
            color: '#00695C',
            icon: 'account_balance_wallet',
          );
        }
      } catch (_) {}

      if (!mounted) return;
      widget.onVaultReady();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al configurar acceso seguro: $e')),
      );
    }
  }

  void _copiarFrase() {
    if (_vault == null) return;
    Clipboard.setData(ClipboardData(text: _vault!.recoveryPhrase));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Frase de respaldo copiada al portapapeles'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparando tu espacio seguro...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _generarVault,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final palabras = _vault!.recoveryPhrase.split(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Protección y Respaldo'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tu frase de respaldo',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Si alguna vez cambiás de teléfono, estas 12 palabras te permiten recuperar todo tu historial financiero. Guardalas en un lugar seguro.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Grilla estilizada de 12 palabras
              Expanded(
                child: MnCard(
                  padding: const EdgeInsets.all(12),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: palabras.length,
                    itemBuilder: (context, index) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${index + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                palabras[index],
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Botón copiar
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _copiarFrase,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar palabras'),
                ),
              ),

              // Checkbox de confirmación
              CheckboxListTile(
                value: _confirmed,
                onChanged: (val) => setState(() => _confirmed = val ?? false),
                title: const Text(
                  'Anoté o guardé mis 12 palabras de respaldo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),

              // Botón de activación
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: (_confirmed && !_saving) ? _activarYContinuar : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(
                    _saving ? 'Configurando acceso...' : 'Activar seguridad y comenzar',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
