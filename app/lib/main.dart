import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'src/rust/api.dart/api.dart';
import 'src/rust/api.dart/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MoneyNeedleApp());
}

class MoneyNeedleApp extends StatelessWidget {
  const MoneyNeedleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyNeedle',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const HomePage(),
    );
  }
}

class PendingProposal {
  final String texto;
  final String resumenIA;
  PendingProposal(this.texto, this.resumenIA);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _stt = MethodChannel('moneyneedle/stt');
  final _controller = TextEditingController();
  PendingProposal? _pending;
  final List<String> _movimientos = [];
  bool _escuchando = false;

  Future<void> _proponer() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    final fecha =
        DateTime.now().toIso8601String().substring(0, 10);
    try {
      // Engine real si el .cact está bunddeado; si no, mock.
      ProposalDto p;
      try {
        p = await proposeReal(
          query: texto,
          fechaHoy: fecha,
          cactPath: await _cactPath(),
        );
      } catch (_) {
        p = await proposeMocked(query: texto, fechaHoy: fecha);
      }
      setState(() {
        _pending = PendingProposal(
          texto,
          'IA propone: ${p.tipo} \$${p.monto.toStringAsFixed(0)} '
          '[${p.categoria}] grounded=${p.grounded ? "sí" : "NO"}',
        );
      });
    } catch (e) {
      setState(() {
        _pending = PendingProposal(texto, 'Error del core: $e');
      });
    }
  }

  /// Copia el asset a un archivo real (el engine necesita path, no bundle).
  /// Si no hay asset bunddeado, lanza y el llamador usa el mock.
  Future<String> _cactPath() async {
    final bytes = await rootBundle.load('assets/models/tuned2.cact');
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/tuned2.cact');
    if (!await f.exists()) {
      await f.writeAsBytes(bytes.buffer.asUint8List());
    }
    return f.path;
  }

  /// Voz → texto → propuesta. Pide permiso de mic si hace falta.
  Future<void> _escuchar() async {
    if (_escuchando) return;
    var permiso = await Permission.microphone.status;
    if (!permiso.isGranted) {
      permiso = await Permission.microphone.request();
    }
    if (!permiso.isGranted) {
      if (!mounted) return;
      final bloqueado = permiso.isPermanentlyDenied;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bloqueado
              ? 'Mic bloqueado: activalo en Ajustes → Apps → MoneyNeedle'
              : 'Sin micrófono no puedo escucharte'),
          action: bloqueado
              // ignore: prefer_const_constructors
              ? SnackBarAction(
                  label: 'Ajustes', onPressed: openAppSettings)
              : null,
        ),
      );
      return;
    }
    setState(() => _escuchando = true);
    try {
      final texto = await _stt.invokeMethod<String>('listen');
      if (texto != null && texto.trim().isNotEmpty && mounted) {
        _controller.text = texto.trim();
        await _proponer();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No te entendí (${e.code}). Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _escuchando = false);
    }
  }

  void _confirmar() {
    setState(() {
      _movimientos.add(_pending!.texto);
      _pending = null;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MoneyNeedle 🌵')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'gasté 5000 en súper...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _proponer(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(_escuchando ? Icons.graphic_eq : Icons.mic),
                  // STT nativo (offline-first) → texto → propuesta automática.
                  onPressed: _escuchar,
                ),
                const SizedBox(width: 4),
                FilledButton(onPressed: _proponer, child: const Text('OK')),
              ],
            ),
            if (_pending != null)
              Card(
                child: ListTile(
                  title: Text(_pending!.resumenIA),
                  subtitle: Text(_pending!.texto),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _pending = null),
                      ),
                      FilledButton(
                        onPressed: _confirmar,
                        child: const Text('Confirmar'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _movimientos.length,
                itemBuilder: (c, i) => ListTile(
                  leading: const Icon(Icons.receipt),
                  title: Text(_movimientos[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
