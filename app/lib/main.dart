import 'package:flutter/material.dart';

void main() => runApp(const MoneyNeedleApp());

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

  void _proponer() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    // TODO Fase 1: llamar a core Rust -> Needle 3 (.cact) y parsear tool_call real.
    // Hoy: mock para validar UX de confirmación.
    setState(() {
      _pending = PendingProposal(
        texto,
        'IA propone: gasto \$? en "otros" (mock, conectar Needle)',
      );
    });
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
