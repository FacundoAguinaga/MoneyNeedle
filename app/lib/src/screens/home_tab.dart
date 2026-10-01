import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';

class PendingProposal {
  final String texto;
  final ProposalDto propuesta;
  PendingProposal(this.texto, this.propuesta);

  String get resumen =>
      '${propuesta.tipo.toUpperCase()} \$${propuesta.monto.toStringAsFixed(0)} ${propuesta.moneda} '
      '· Categ: ${propuesta.categoria} (grounded: ${propuesta.grounded ? "sí" : "no"})';
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _stt = MethodChannel('moneyneedle/stt');
  final _controller = TextEditingController();
  PendingProposal? _pending;
  List<MovementDto> _movimientos = [];
  List<AccountDto> _accounts = [];
  String? _selectedAccountId;
  int _selectedCuotas = 1;
  bool _escuchando = false;
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _recargar();
    _autoProcessRecurring();
  }

  Future<void> _autoProcessRecurring() async {
    try {
      final dbPath = await VaultService.getDbPath();
      await processRecurringRules(dbPath: dbPath);
    } catch (_) {}
  }

  Future<void> _recargar() async {
    try {
      final dbPath = await VaultService.getDbPath();
      final movs = await listMovements(dbPath: dbPath, limit: 50);
      final accs = await listAccounts(dbPath: dbPath);
      if (!mounted) return;
      setState(() {
        _movimientos = movs;
        _accounts = accs;
        if (_selectedAccountId == null && accs.isNotEmpty) {
          _selectedAccountId = accs.first.id;
        }
      });
    } catch (_) {}
  }

  Future<void> _proponer() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    try {
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
        _pending = PendingProposal(texto, p);
        _selectedCuotas = 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error del core: $e')),
      );
    }
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
              ? SnackBarAction(label: 'Ajustes', onPressed: openAppSettings)
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

  Future<void> _confirmar() async {
    final pend = _pending;
    if (pend == null) return;
    setState(() => _confirmando = true);

    try {
      final dbPath = await VaultService.getDbPath();
      final selectedAccount = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
      final isCard = selectedAccount?.accountType.toLowerCase() == 'credit_card';

      if (isCard && _selectedCuotas > 1) {
        final now = DateTime.now();
        await confirmCreditPurchase(
          dbPath: dbPath,
          cardAccountId: selectedAccount!.id,
          monto: pend.propuesta.monto,
          cuotas: _selectedCuotas,
          categoria: pend.propuesta.categoria,
          descripcion: pend.texto,
          startCycleYear: now.year,
          startCycleMonth: now.month,
        );
      } else {
        await confirmMovement(
          dbPath: dbPath,
          tipo: pend.propuesta.tipo,
          monto: pend.propuesta.monto,
          moneda: pend.propuesta.moneda,
          categoria: pend.propuesta.categoria,
          descripcion: pend.texto,
          fecha: pend.propuesta.fecha,
          frase: pend.texto,
          accountId: _selectedAccountId,
        );
      }

      _controller.clear();
      setState(() {
        _pending = null;
        _confirmando = false;
      });
      await _recargar();
    } catch (e) {
      if (mounted) {
        setState(() => _confirmando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedAccount = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    final isCard = selectedAccount?.accountType.toLowerCase() == 'credit_card';

    return Padding(
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
                onPressed: _escuchar,
              ),
              const SizedBox(width: 4),
              FilledButton(onPressed: _proponer, child: const Text('OK')),
            ],
          ),
          if (_pending != null) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _pending!.resumen,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => setState(() => _pending = null),
                        ),
                      ],
                    ),
                    Text(
                      '"${_pending!.texto}"',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedAccountId,
                            decoration: const InputDecoration(
                              labelText: 'Cuenta destino/origen',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: _accounts
                                .map((a) => DropdownMenuItem(
                                      value: a.id,
                                      child: Text('${a.name} (${a.currency})'),
                                    ))
                                .toList(),
                            onChanged: (val) => setState(() => _selectedAccountId = val),
                          ),
                        ),
                        if (isCard) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedCuotas,
                              decoration: const InputDecoration(
                                labelText: 'Cuotas',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('1 cuota')),
                                DropdownMenuItem(value: 3, child: Text('3 cuotas')),
                                DropdownMenuItem(value: 6, child: Text('6 cuotas')),
                                DropdownMenuItem(value: 12, child: Text('12 cuotas')),
                                DropdownMenuItem(value: 18, child: Text('18 cuotas')),
                                DropdownMenuItem(value: 24, child: Text('24 cuotas')),
                              ],
                              onChanged: (val) => setState(() => _selectedCuotas = val ?? 1),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isCard && _selectedCuotas > 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Total: \$${_pending!.propuesta.monto.toStringAsFixed(2)} en $_selectedCuotas cuotas de ~\$${(_pending!.propuesta.monto / _selectedCuotas).toStringAsFixed(2)} c/u',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: _confirmando
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check),
                        label: Text(_confirmando ? 'Guardando...' : 'Confirmar Movimiento'),
                        onPressed: _confirmando ? null : _confirmar,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _recargar,
              child: _movimientos.isEmpty
                  ? const Center(child: Text('No hay movimientos registrados todavía.'))
                  : ListView.builder(
                      itemCount: _movimientos.length,
                      itemBuilder: (c, i) {
                        final m = _movimientos[i];
                        final isTransfer = m.tipo.toLowerCase() == 'transferencia' || m.tipo.toLowerCase() == 'transfer';
                        final isGasto = m.tipo.toLowerCase() == 'gasto';

                        Widget leadingIcon;
                        if (isTransfer) {
                          leadingIcon = CircleAvatar(
                            backgroundColor: Colors.blue.shade50,
                            child: Icon(Icons.swap_horiz, color: Colors.blue.shade700),
                          );
                        } else {
                          leadingIcon = CircleAvatar(
                            backgroundColor: isGasto ? Colors.red.shade50 : Colors.green.shade50,
                            child: Icon(
                              isGasto ? Icons.arrow_upward : Icons.arrow_downward,
                              color: isGasto ? Colors.red : Colors.green,
                            ),
                          );
                        }

                        return ListTile(
                          leading: leadingIcon,
                          title: Text(
                            '${m.tipo.toUpperCase()} \$${m.monto.toStringAsFixed(0)} ${m.moneda}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            isTransfer
                                ? '${m.fecha}\n${m.descripcion}'
                                : '${m.categoria} · ${m.fecha}\n${m.descripcion}',
                          ),
                          isThreeLine: m.descripcion.isNotEmpty,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
