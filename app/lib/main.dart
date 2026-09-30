import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
  final _controller = TextEditingController();
  PendingProposal? _pending;
  final List<String> _movimientos = [];

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
                  icon: const Icon(Icons.mic),
                  // TODO: STT local sherpa-onnx
                  onPressed: () {},
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
