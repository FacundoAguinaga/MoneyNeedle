import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  List<AccountDto> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarCuentas();
  }

  Future<void> _cargarCuentas() async {
    setState(() => _loading = true);
    try {
      final dbPath = await VaultService.getDbPath();
      final accs = await listAccounts(dbPath: dbPath);
      if (mounted) {
        setState(() {
          _accounts = accs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando cuentas: $e')),
        );
      }
    }
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
    } catch (_) {}
    return Colors.teal;
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'bank':
      case 'banco':
        return Icons.account_balance;
      case 'wallet':
      case 'billetera':
        return Icons.account_balance_wallet;
      case 'credit_card':
      case 'tarjeta':
        return Icons.credit_card;
      case 'investment':
      case 'inversion':
        return Icons.trending_up;
      case 'cash':
      case 'efectivo':
      default:
        return Icons.payments;
    }
  }

  String _formatType(String type) {
    switch (type.toLowerCase()) {
      case 'bank':
        return 'Cuenta bancaria';
      case 'wallet':
        return 'Billetera virtual';
      case 'credit_card':
        return 'Tarjeta de crédito';
      case 'investment':
        return 'Inversión';
      case 'cash':
      default:
        return 'Efectivo';
    }
  }

  Future<void> _eliminarCuenta(AccountDto acc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text('¿Seguro que querés eliminar "${acc.name}"? Los movimientos históricos se conservarán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
      await deleteAccount(dbPath: dbPath, accountId: acc.id);
      await _cargarCuentas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cuenta "${acc.name}" eliminada')),
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

  void _abrirCrearCuentaModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _CrearCuentaSheet(onCreated: _cargarCuentas),
      ),
    );
  }

  void _verResumenTarjeta(AccountDto card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CardStatementSheet(card: card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final netWorthByCurrency = <String, double>{};
    for (final a in _accounts) {
      netWorthByCurrency[a.currency] = (netWorthByCurrency[a.currency] ?? 0.0) + a.currentBalance;
    }

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarCuentas,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 1,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patrimonio Total',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 8),
                          if (netWorthByCurrency.isEmpty)
                            const Text('\$0.00', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
                          else
                            ...netWorthByCurrency.entries.map(
                              (e) => Text(
                                '${e.key} \$${e.value.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
                        'Tus Cuentas y Tarjetas',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${_accounts.length} activas',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('No hay cuentas creadas aún. Creá una para empezar.'),
                      ),
                    )
                  else
                    ..._accounts.map((acc) {
                      final color = _parseColor(acc.color);
                      final isCard = acc.accountType.toLowerCase() == 'credit_card';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: color.withAlpha(38),
                                    child: Icon(_getIconForType(acc.accountType), color: color),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          acc.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _formatType(acc.accountType),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${acc.currency} \$${acc.currentBalance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: acc.currentBalance < 0 ? Colors.red.shade700 : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'delete') _eliminarCuenta(acc);
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                            SizedBox(width: 8),
                                            Text('Eliminar', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isCard) ...[
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (acc.creditLimit != null)
                                      Text(
                                        'Límite: \$${acc.creditLimit!.toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (acc.closingDay != null)
                                      Text(
                                        'Cierre: día ${acc.closingDay}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (acc.dueDay != null)
                                      Text(
                                        'Vence: día ${acc.dueDay}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.receipt_long, size: 16),
                                    label: const Text('Ver cuotas y resumen'),
                                    onPressed: () => _verResumenTarjeta(acc),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCrearCuentaModal,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Cuenta'),
      ),
    );
  }
}

class _CrearCuentaSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CrearCuentaSheet({required this.onCreated});

  @override
  State<_CrearCuentaSheet> createState() => _CrearCuentaSheetState();
}

class _CrearCuentaSheetState extends State<_CrearCuentaSheet> {
  final _nameCtrl = TextEditingController();
  final _initialBalanceCtrl = TextEditingController(text: '0');
  final _creditLimitCtrl = TextEditingController();
  final _closingDayCtrl = TextEditingController();
  final _dueDayCtrl = TextEditingController();

  String _accountType = 'bank';
  String _currency = 'ARS';
  String _selectedColor = '#1976D2';

  final List<String> _colorOptions = [
    '#1976D2', // Azul
    '#388E3C', // Verde
    '#7B1FA2', // Púrpura
    '#F57C00', // Naranja
    '#00796B', // Teal
    '#D32F2F', // Rojo
    '#455A64', // Gris azulado
  ];

  bool _guardando = false;

  Future<void> _guardar() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un nombre para la cuenta')),
      );
      return;
    }

    final initialBalance = double.tryParse(_initialBalanceCtrl.text.trim()) ?? 0.0;
    double? creditLimit;
    int? closingDay;
    int? dueDay;

    if (_accountType == 'credit_card') {
      creditLimit = double.tryParse(_creditLimitCtrl.text.trim());
      closingDay = int.tryParse(_closingDayCtrl.text.trim());
      dueDay = int.tryParse(_dueDayCtrl.text.trim());
    }

    setState(() => _guardando = true);
    try {
      final dbPath = await VaultService.getDbPath();
      await createAccount(
        dbPath: dbPath,
        name: name,
        accountType: _accountType,
        currency: _currency,
        initialBalance: initialBalance,
        creditLimit: creditLimit,
        closingDay: closingDay,
        dueDay: dueDay,
        color: _selectedColor,
        icon: _accountType,
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear cuenta: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCard = _accountType == 'credit_card';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: minAxisSize(),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nueva Cuenta',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre de la cuenta',
              hintText: 'Ej. Banco Galicia, Visa Santander, Billetera',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _accountType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'bank', child: Text('Banco')),
                    DropdownMenuItem(value: 'wallet', child: Text('Billetera')),
                    DropdownMenuItem(value: 'credit_card', child: Text('Tarjeta de Crédito')),
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'investment', child: Text('Inversión')),
                  ],
                  onChanged: (val) => setState(() => _accountType = val ?? 'bank'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Moneda',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ARS', child: Text('ARS (\$)')),
                    DropdownMenuItem(value: 'USD', child: Text('USD (U\$D)')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                  ],
                  onChanged: (val) => setState(() => _currency = val ?? 'ARS'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _initialBalanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: isCard ? 'Saldo adeudado inicial' : 'Saldo inicial',
              border: const OutlineInputBorder(),
            ),
          ),
          if (isCard) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _creditLimitCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Límite de crédito',
                hintText: 'Ej. 500000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _closingDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Día de cierre',
                      hintText: 'Ej. 20',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _dueDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Día de vencimiento',
                      hintText: 'Ej. 5',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Text('Color identificador', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: _colorOptions.map((c) {
              final color = Color(int.parse('FF${c.replaceAll('#', '')}', radix: 16));
              final selected = _selectedColor == c;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = c),
                child: CircleAvatar(
                  backgroundColor: color,
                  radius: 18,
                  child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Crear Cuenta'),
            ),
          ),
        ],
      ),
    );
  }

  MainAxisSize minAxisSize() => MainAxisSize.min;
}

class _CardStatementSheet extends StatefulWidget {
  final AccountDto card;
  const _CardStatementSheet({required this.card});

  @override
  State<_CardStatementSheet> createState() => _CardStatementSheetState();
}

class _CardStatementSheetState extends State<_CardStatementSheet> {
  late int _selectedYear;
  late int _selectedMonth;
  CardStatementDto? _statement;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    setState(() => _loading = true);
    try {
      final dbPath = await VaultService.getDbPath();
      final res = await getCardStatement(
        dbPath: dbPath,
        cardId: widget.card.id,
        cycleYear: _selectedYear,
        cycleMonth: _selectedMonth,
      );
      if (mounted) {
        setState(() {
          _statement = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando resumen: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Resumen: ${widget.card.name}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: () {
                  setState(() {
                    if (_selectedMonth == 1) {
                      _selectedMonth = 12;
                      _selectedYear -= 1;
                    } else {
                      _selectedMonth -= 1;
                    }
                  });
                  _cargarResumen();
                },
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Período $_selectedMonth/$_selectedYear',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () {
                  setState(() {
                    if (_selectedMonth == 12) {
                      _selectedMonth = 1;
                      _selectedYear += 1;
                    } else {
                      _selectedMonth += 1;
                    }
                  });
                  _cargarResumen();
                },
              ),
            ],
          ),
          const Divider(),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_statement == null || _statement!.items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No hay cuotas a liquidar en este período.'),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total a pagar del mes:', style: TextStyle(fontSize: 16)),
                  Text(
                    '${widget.card.currency} \$${_statement!.totalDue.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _statement!.items.length,
                itemBuilder: (ctx, i) {
                  final item = _statement!.items[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.description.isNotEmpty ? item.description : 'Compra'),
                    subtitle: Text('Cuota ${item.installmentNumber} de ${item.totalInstallments}'),
                    trailing: Text(
                      '${widget.card.currency} \$${item.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
