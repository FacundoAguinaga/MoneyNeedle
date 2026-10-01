import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../rust/api.dart/api.dart';
import 'mn_modal_sheet.dart';

/// Modal de entrada rápida (Command Palette) para escribir o dictar gastos con IA.
class QuickAddModal extends StatefulWidget {
  final Function(String query, ProposalDto proposal) onProposalGenerated;

  const QuickAddModal({
    super.key,
    required this.onProposalGenerated,
  });

  static Future<void> show({
    required BuildContext context,
    required Function(String query, ProposalDto proposal) onProposalGenerated,
  }) {
    return MnModalSheet.show(
      context: context,
      title: 'Registrar movimiento',
      child: QuickAddModal(onProposalGenerated: onProposalGenerated),
    );
  }

  @override
  State<QuickAddModal> createState() => _QuickAddModalState();
}

class _QuickAddModalState extends State<QuickAddModal> {
  static const _stt = MethodChannel('moneyneedle/stt');
  final _controller = TextEditingController();
  bool _loading = false;
  bool _listening = false;

  final List<String> _suggestions = [
    'almuerzo 4500',
    'super 28500 coto',
    'sube 5000',
    'sueldo 350k',
    'pagué la luz 8500',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> _cactPath() async {
    final bytes = await rootBundle.load('assets/models/tuned2.cact');
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/tuned2.cact');
    if (!await f.exists()) {
      await f.writeAsBytes(bytes.buffer.asUint8List());
    }
    return f.path;
  }

  Future<void> _processText([String? directText]) async {
    final text = (directText ?? _controller.text).trim();
    if (text.isEmpty) return;

    setState(() => _loading = true);
    final fecha = DateTime.now().toIso8601String().substring(0, 10);

    try {
      ProposalDto proposal;
      try {
        final cact = await _cactPath();
        proposal = await proposeReal(
          query: text,
          fechaHoy: fecha,
          cactPath: cact,
        );
      } catch (_) {
        proposal = await proposeMocked(query: text, fechaHoy: fecha);
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onProposalGenerated(text, proposal);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude entender la frase: $e')),
      );
    }
  }

  Future<void> _listen() async {
    if (_listening) return;
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      if (!mounted) return;
      final permanent = status.isPermanentlyDenied;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(permanent
              ? 'Micrófono bloqueado. Activalo en los Ajustes del sistema.'
              : 'Se requiere permiso de micrófono para dictar.'),
          action: permanent
              ? const SnackBarAction(label: 'Ajustes', onPressed: openAppSettings)
              : null,
        ),
      );
      return;
    }

    setState(() => _listening = true);
    try {
      final text = await _stt.invokeMethod<String>('listen');
      if (text != null && text.trim().isNotEmpty && mounted) {
        _controller.text = text.trim();
        await _processText();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se detectó audio (${e.code}). Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Campo de entrada
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_loading,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _processText(),
          decoration: InputDecoration(
            hintText: 'Ej: gasté 5000 en súper...',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _listening ? Icons.graphic_eq : Icons.mic,
                    color: _listening ? Colors.red : theme.colorScheme.primary,
                  ),
                  tooltip: 'Dictar por voz',
                  onPressed: _loading ? null : _listen,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Sugerencias rápidas
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _suggestions.map((sug) {
            return ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(
                sug,
                style: theme.textTheme.labelSmall,
              ),
              onPressed: _loading ? null : () => _processText(sug),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Botón de procesamiento
        FilledButton.icon(
          onPressed: _loading ? null : () => _processText(),
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(_loading ? 'Analizando frase...' : 'Entender movimiento'),
        ),
      ],
    );
  }
}
