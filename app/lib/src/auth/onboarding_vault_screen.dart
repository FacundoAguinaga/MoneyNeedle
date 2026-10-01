import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api.dart/api.dart';
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
        _error = 'Error generando bóveda segura: $e';
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

      if (!mounted) return;
      widget.onVaultReady();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al configurar biometría: $e')),
      );
    }
  }

  void _copiarFrase() {
    if (_vault == null) return;
    Clipboard.setData(ClipboardData(text: _vault!.recoveryPhrase));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Frase de recuperación copiada al portapapeles')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generando bóveda criptográfica...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _generarVault,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final palabras = _vault!.recoveryPhrase.split(' ');

    return Scaffold(
      appBar: AppBar(title: const Text('Bóveda Cifrada')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tu frase de recuperación',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Anotá estas 12 palabras en un lugar seguro. Si cambiás de teléfono o se alteran tus datos biométricos, es la única manera de recuperar tus datos.',
                style: TextStyle(color: Colors.black87, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: palabras.length,
                    itemBuilder: (context, index) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}. ${palabras[index]}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _copiarFrase,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar'),
                ),
              ),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (val) => setState(() => _confirmed = val ?? false),
                title: const Text(
                  'Guardé mi frase de 12 palabras en un lugar seguro',
                  style: TextStyle(fontSize: 14),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_confirmed && !_saving) ? _activarYContinuar : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(_saving ? 'Configurando...' : 'Activar Biometría y Empezar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
