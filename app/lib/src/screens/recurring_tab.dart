import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';

class RecurringTab extends StatefulWidget {
  const RecurringTab({super.key});

  @override
  State<RecurringTab> createState() => _RecurringTabState();
}

class _RecurringTabState extends State<RecurringTab> {
  List<RecurringRuleDto> _rules = [];
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _cargarReglas();
  }

  Future<void> _cargarReglas() async {
    setState(() => _loading = true);
    try {
      final dbPath = await VaultService.getDbPath();
      final rules = await listRecurringRules(dbPath: dbPath);
      if (mounted) {
        setState(() {
          _rules = rules;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar recurrentes: $e')),
        );
      }
    }
  }

  Future<void> _procesarVencimientos() async {
    setState(() => _processing = true);
    try {
      final dbPath = await VaultService.getDbPath();
      final count = await processRecurringRules(dbPath: dbPath);
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0
                ? 'Se aplicaron $count transacciones recurrentes pendientes.'
                : 'Todas las suscripciones están al día.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar: $e')),
        );
      }
    }
  }

  Future<void> _eliminarRegla(RecurringRuleDto rule) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar recurrente'),
        content: Text('¿Seguro que querés cancelar esta suscripción de \$${rule.amount.toStringAsFixed(2)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final dbPath = await VaultService.getDbPath();
      await deleteRecurringRule(dbPath: dbPath, ruleId: rule.id);
      await _cargarReglas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suscripción eliminada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  String _formatFreq(String freq) {
    switch (freq.toLowerCase()) {
      case 'daily':
        return 'Diario';
      case 'weekly':
        return 'Semanal';
      case 'yearly':
        return 'Anual';
      case 'monthly':
      default:
        return 'Mensual';
    }
  }

  void _abrirCrearReglaModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CrearReglaSheet(onCreated: _cargarReglas),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarReglas,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.autorenew, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Reglas Recurrentes',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Suscripciones y cobros fijos periódicos. Podés procesar los vencimientos pendientes manualmente o dejar que se apliquen en cada inicio de la app.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            icon: _processing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.play_arrow),
                            label: const Text('Procesar vencimientos ahora'),
                            onPressed: _processing ? null : _procesarVencimientos,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Suscripciones Activas',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${_rules.length} reglas',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_rules.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('No hay reglas recurrentes configuradas.'),
                      ),
                    )
                  else
                    ..._rules.map((rule) {
                      final isGasto = rule.transactionType.toLowerCase() == 'expense' ||
                          rule.transactionType.toLowerCase() == 'gasto';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isGasto ? Colors.red.shade100 : Colors.green.shade100,
                            child: Icon(
                              isGasto ? Icons.arrow_upward : Icons.arrow_downward,
                              color: isGasto ? Colors.red : Colors.green,
                            ),
                          ),
                          title: Text(
                            '${isGasto ? "Gasto" : "Ingreso"} ${rule.currency} \$${rule.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Cuenta: ${rule.accountName} · Frecuencia: ${_formatFreq(rule.frequency)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  rule.autoApply ? 'Auto' : 'Manual',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: rule.autoApply ? Colors.green.shade800 : Colors.grey.shade700,
                                  ),
                                ),
                                backgroundColor: rule.autoApply ? Colors.green.shade50 : Colors.grey.shade200,
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                onPressed: () => _eliminarRegla(rule),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCrearReglaModal,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Recurrente'),
      ),
    );
  }
}

class _CrearReglaSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CrearReglaSheet({required this.onCreated});

  @override
  State<_CrearReglaSheet> createState() => _CrearReglaSheetState();
}

class _CrearReglaSheetState extends State<_CrearReglaSheet> {
  final _amountCtrl = TextEditingController();
  List<AccountDto> _accounts = [];
  String? _selectedAccountId;
  String _transactionType = 'gasto';
  String _frequency = 'monthly';
  String _currency = 'ARS';
  bool _autoApply = true;
  bool _loading = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarCuentas();
  }

  Future<void> _cargarCuentas() async {
    try {
      final dbPath = await VaultService.getDbPath();
      final accs = await listAccounts(dbPath: dbPath);
      if (mounted) {
        setState(() {
          _accounts = accs;
          if (accs.isNotEmpty) {
            _selectedAccountId = accs.first.id;
            _currency = accs.first.currency;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _guardar() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido mayor a 0')),
      );
      return;
    }

    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una cuenta')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final dbPath = await VaultService.getDbPath();
      await createRecurringRule(
        dbPath: dbPath,
        accountId: _selectedAccountId!,
        transactionType: _transactionType,
        amount: amount,
        currency: _currency,
        frequency: _frequency,
        autoApply: _autoApply,
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear recurrente: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nueva Suscripción / Recurrente',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          if (_accounts.isEmpty)
            const Text('Debes crear al menos una cuenta antes de registrar un gasto recurrente.')
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedAccountId,
              decoration: const InputDecoration(
                labelText: 'Cuenta asociada',
                border: OutlineInputBorder(),
              ),
              items: _accounts
                  .map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (${a.currency})'),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  final acc = _accounts.firstWhere((a) => a.id == val);
                  setState(() {
                    _selectedAccountId = val;
                    _currency = acc.currency;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _transactionType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'gasto', child: Text('Gasto')),
                      DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
                    ],
                    onChanged: (val) => setState(() => _transactionType = val ?? 'gasto'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Diario')),
                      DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                      DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                      DropdownMenuItem(value: 'yearly', child: Text('Anual')),
                    ],
                    onChanged: (val) => setState(() => _frequency = val ?? 'monthly'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monto por período ($_currency)',
                hintText: 'Ej. 4500',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aplicar automáticamente'),
              subtitle: const Text('Registra la transacción al vencer sin confirmación manual'),
              value: _autoApply,
              onChanged: (val) => setState(() => _autoApply = val),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Crear Recurrente'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
