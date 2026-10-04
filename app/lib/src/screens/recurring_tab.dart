import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/mn_card.dart';

class RecurringTab extends StatefulWidget {
  final bool isStandalone;
  const RecurringTab({super.key, this.isStandalone = false});

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
    final theme = Theme.of(context);
    final colors = context.mnColors;

    final totalMonthly = _rules
        .where((r) =>
            r.transactionType.toLowerCase() != 'income' &&
            r.transactionType.toLowerCase() != 'ingreso')
        .fold<double>(0.0, (sum, r) => sum + r.amount);

    return Scaffold(
      appBar: widget.isStandalone
          ? AppBar(
              title: const Text('Suscripciones y Recurrentes'),
              elevation: 0,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarReglas,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Tarjeta Hero de Compromisos Fijos
                  MnCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Compromiso Fijo Periódico',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(Icons.autorenew_rounded, color: theme.colorScheme.primary, size: 20),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '\$${totalMonthly.toStringAsFixed(2)} / mes',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Suscripciones, servicios y cobros periódicos recurrentes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.tonalIcon(
                          icon: _processing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Procesar vencimientos ahora'),
                          onPressed: _processing ? null : _procesarVencimientos,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Suscripciones Activas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_rules.length} activas',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                      final itemColor = isGasto ? colors.expense : colors.income;

                      return MnCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: itemColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isGasto ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                color: itemColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${rule.currency} \$${rule.amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${rule.accountName} · ${_formatFreq(rule.frequency)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: rule.autoApply
                                    ? colors.income.withValues(alpha: 0.15)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                rule.autoApply ? 'Auto' : 'Manual',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: rule.autoApply
                                      ? colors.income
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              tooltip: 'Eliminar regla',
                              onPressed: () => _eliminarRegla(rule),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirCrearReglaModal,
        tooltip: 'Nueva Recurrente',
        child: const Icon(Icons.add_rounded),
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
