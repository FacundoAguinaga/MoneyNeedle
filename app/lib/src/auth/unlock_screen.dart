import 'package:flutter/material.dart';
import '../rust/api.dart/api.dart';
import 'vault_service.dart';

class UnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const UnlockScreen({super.key, required this.onUnlocked});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  bool _authenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _desbloquearConBiometria();
    });
  }

  Future<void> _desbloquearConBiometria() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _errorMessage = null;
    });

    try {
      final masterKey = await VaultService.readMasterKeyBiometric();
      if (masterKey != null && masterKey.isNotEmpty) {
        final ok = await VaultService.unlockAndInitDb(masterKey);
        if (ok && mounted) {
          widget.onUnlocked();
          return;
        }
      }
      if (mounted) {
        setState(() {
          _authenticating = false;
          _errorMessage = 'No se pudo autenticar o la clave no está disponible.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authenticating = false;
          _errorMessage = 'Error biométrico: $e';
        });
      }
    }
  }

  Future<void> _mostrarDialogoRecuperacion() async {
    final payload = await VaultService.getRecoveryPayload();
    if (payload == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos de recuperación guardados en este dispositivo.')),
      );
      return;
    }

    if (!mounted) return;
    final controller = TextEditingController();
    var recovering = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Recuperar con 12 palabras'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ingresá tu frase de 12 palabras separadas por espacios:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'word1 word2 word3 ... word12',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: recovering ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: recovering
                      ? null
                      : () async {
                          final phrase = controller.text.trim();
                          if (phrase.split(RegExp(r'\s+')).length < 12) {
                            setDialogState(() {
                              dialogError = 'Deben ser exactamente 12 palabras.';
                            });
                            return;
                          }

                          setDialogState(() {
                            recovering = true;
                            dialogError = null;
                          });

                          try {
                            final masterKey = await recoverMasterKey(
                              wrappedRecoveryPayload: payload,
                              recoveryPhrase: phrase,
                            );

                            // Re-guardar en biometric_storage para las próximas veces
                            await VaultService.saveMasterKeyBiometric(masterKey);
                            await VaultService.unlockAndInitDb(masterKey);

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) widget.onUnlocked();
                          } catch (e) {
                            setDialogState(() {
                              recovering = false;
                              dialogError = 'Frase incorrecta o no válida ($e)';
                            });
                          }
                        },
                  child: recovering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Recuperar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline, size: 72, color: Colors.green),
              const SizedBox(height: 24),
              const Text(
                'MoneyNeedle Seguro',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tus finanzas están protegidas por hardware y cifrado SQLCipher.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              FilledButton.icon(
                onPressed: _authenticating ? null : _desbloquearConBiometria,
                icon: _authenticating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(_authenticating ? 'Autenticando...' : 'Desbloquear con Huella'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _mostrarDialogoRecuperacion,
                child: const Text('¿Problemas con tu huella? Recuperar con frase'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
