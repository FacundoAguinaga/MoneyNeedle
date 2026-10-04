import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/mn_card.dart';

class AccountsTab extends StatefulWidget {
  final bool isStandalone;
  const AccountsTab({super.key, this.isStandalone = false});

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

  void _abrirTransferenciaModal() {
    if (_accounts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitás al menos 2 cuentas para realizar una transferencia.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _TransferSheet(accounts: _accounts, onTransferred: _cargarCuentas),
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
    final theme = Theme.of(context);
    final colors = context.mnColors;
    final netWorthByCurrency = <String, double>{};
    for (final a in _accounts) {
      netWorthByCurrency[a.currency] = (netWorthByCurrency[a.currency] ?? 0.0) + a.currentBalance;
    }

    return Scaffold(
      appBar: widget.isStandalone
          ? AppBar(
              title: const Text('Cuentas y Tarjetas'),
              elevation: 0,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarCuentas,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Tarjeta Hero de Patrimonio Total
                  MnCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patrimonio Total Consolidado',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (netWorthByCurrency.isEmpty)
                          const Text('\$0.00', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))
                        else
                          ...netWorthByCurrency.entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '${e.key} \$${e.value.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Transferir'),
                          onPressed: _accounts.length >= 2 ? _abrirTransferenciaModal : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nueva Cuenta'),
                          onPressed: _abrirCrearCuentaModal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tus Cuentas y Tarjetas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_accounts.length} activas',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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

                      if (isCard) {
                        final limit = acc.creditLimit ?? 0;
                        final used = acc.currentBalance.abs();
                        final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

                        return MnCard(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.credit_card_rounded, color: color, size: 22),
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
                                          'Tarjeta de crédito · ${acc.currency}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${acc.currency} \$${acc.currentBalance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: acc.currentBalance < 0 ? colors.expense : null,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
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
                              if (limit > 0) ...[
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Consumo: \$${used.toStringAsFixed(0)} / \$${limit.toStringAsFixed(0)}',
                                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                    Text(
                                      '${(ratio * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: ratio > 0.8 ? colors.expense : theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 6,
                                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      ratio > 0.8 ? colors.expense : theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (acc.closingDay != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Cierre: día ${acc.closingDay}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  if (acc.dueDay != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Vence: día ${acc.dueDay}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  const Spacer(),
                                  TextButton.icon(
                                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                                    label: const Text('Resumen y cuotas', style: TextStyle(fontSize: 12)),
                                    onPressed: () => _verResumenTarjeta(acc),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      return MnCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_getIconForType(acc.accountType), color: color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${_formatType(acc.accountType)} · ${acc.currency}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${acc.currency} \$${acc.currentBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: acc.currentBalance < 0 ? colors.expense : null,
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
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
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirCrearCuentaModal,
        tooltip: 'Nueva Cuenta',
        child: const Icon(Icons.add_rounded),
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

class _TransferSheet extends StatefulWidget {
  final List<AccountDto> accounts;
  final VoidCallback onTransferred;

  const _TransferSheet({required this.accounts, required this.onTransferred});

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late String _fromAccountId;
  late String _toAccountId;
  final _fromAmountCtrl = TextEditingController();
  final _toAmountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  ExchangeRateDto? _latestRate;
  bool _transferring = false;

  AccountDto get _fromAccount =>
      widget.accounts.firstWhere((a) => a.id == _fromAccountId);
  AccountDto get _toAccount =>
      widget.accounts.firstWhere((a) => a.id == _toAccountId);

  bool get _isMultiCurrency => _fromAccount.currency != _toAccount.currency;

  @override
  void initState() {
    super.initState();
    _fromAccountId = widget.accounts.first.id;
    _toAccountId = widget.accounts.length > 1 ? widget.accounts[1].id : widget.accounts.first.id;
    _consultarCotizacion();
  }

  Future<void> _consultarCotizacion() async {
    if (!_isMultiCurrency) {
      setState(() => _latestRate = null);
      return;
    }
    try {
      final dbPath = await VaultService.getDbPath();
      final rate = await getLatestExchangeRate(
        dbPath: dbPath,
        baseCurrency: _fromAccount.currency,
        quoteCurrency: _toAccount.currency,
      );
      if (mounted) {
        setState(() => _latestRate = rate);
      }
    } catch (_) {}
  }

  void _onFromAccountChanged(String? val) {
    if (val == null) return;
    setState(() {
      _fromAccountId = val;
      if (_toAccountId == val) {
        final other = widget.accounts.firstWhere((a) => a.id != val);
        _toAccountId = other.id;
      }
    });
    _consultarCotizacion();
  }

  void _onToAccountChanged(String? val) {
    if (val == null) return;
    setState(() {
      _toAccountId = val;
    });
    _consultarCotizacion();
  }

  void _aplicarCotizacionPrevia() {
    if (_latestRate == null) return;
    final fromAmount = double.tryParse(_fromAmountCtrl.text.trim());
    if (fromAmount != null && fromAmount > 0) {
      final to = fromAmount * _latestRate!.rate;
      _toAmountCtrl.text = to.toStringAsFixed(2);
      setState(() {});
    }
  }

  Future<void> _ejecutarTransferencia() async {
    if (_fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cuenta de origen y destino no pueden ser la misma')),
      );
      return;
    }

    final fromAmount = double.tryParse(_fromAmountCtrl.text.trim());
    if (fromAmount == null || fromAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto de origen mayor a 0')),
      );
      return;
    }

    double toAmount;
    if (_isMultiCurrency) {
      final parsedTo = double.tryParse(_toAmountCtrl.text.trim());
      if (parsedTo == null || parsedTo <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresá el monto de destino mayor a 0')),
        );
        return;
      }
      toAmount = parsedTo;
    } else {
      toAmount = fromAmount;
    }

    setState(() => _transferring = true);
    try {
      final dbPath = await VaultService.getDbPath();
      final notes = _notesCtrl.text.trim().isNotEmpty
          ? _notesCtrl.text.trim()
          : 'Transferencia ${_fromAccount.name} → ${_toAccount.name}';

      await createTransfer(
        dbPath: dbPath,
        fromAccountId: _fromAccountId,
        toAccountId: _toAccountId,
        fromAmount: fromAmount,
        toAmount: toAmount,
        notes: notes,
      );

      widget.onTransferred();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transferencia realizada con éxito')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _transferring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al transferir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromAmount = double.tryParse(_fromAmountCtrl.text.trim());
    final toAmount = double.tryParse(_toAmountCtrl.text.trim());

    String? implicitRateStr;
    if (_isMultiCurrency && fromAmount != null && toAmount != null && fromAmount > 0 && toAmount > 0) {
      if (fromAmount > toAmount) {
        final rate = fromAmount / toAmount;
        implicitRateStr = '1 ${_toAccount.currency} ≈ ${rate.toStringAsFixed(2)} ${_fromAccount.currency}';
      } else {
        final rate = toAmount / fromAmount;
        implicitRateStr = '1 ${_fromAccount.currency} ≈ ${rate.toStringAsFixed(2)} ${_toAccount.currency}';
      }
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
                'Transferir Fondos',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _fromAccountId,
            decoration: const InputDecoration(
              labelText: 'Cuenta de Origen (sale)',
              border: OutlineInputBorder(),
            ),
            items: widget.accounts
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${a.currency} \$${a.currentBalance.toStringAsFixed(2)})'),
                    ))
                .toList(),
            onChanged: _onFromAccountChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _toAccountId,
            decoration: const InputDecoration(
              labelText: 'Cuenta de Destino (entra)',
              border: OutlineInputBorder(),
            ),
            items: widget.accounts
                .where((a) => a.id != _fromAccountId)
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${a.currency} \$${a.currentBalance.toStringAsFixed(2)})'),
                    ))
                .toList(),
            onChanged: _onToAccountChanged,
          ),
          const SizedBox(height: 16),
          if (!_isMultiCurrency) ...[
            TextField(
              controller: _fromAmountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monto a transferir (${_fromAccount.currency})',
                hintText: 'Ej. 5000',
                border: const OutlineInputBorder(),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Sale (${_fromAccount.currency})',
                      hintText: 'Ej. 1200000',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: TextField(
                    controller: _toAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Entra (${_toAccount.currency})',
                      hintText: 'Ej. 1000',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (implicitRateStr != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.currency_exchange, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Cotización implícita: $implicitRateStr',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_latestRate != null) ...[
              const SizedBox(height: 6),
              ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text(
                  'Última cotización: 1 ${_fromAccount.currency} = ${_latestRate!.rate.toStringAsFixed(4)} ${_toAccount.currency}',
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: _aplicarCotizacionPrevia,
              ),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notas / Motivo (opcional)',
              hintText: 'Ej. Ahorro, Cambio de divisa, etc.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _transferring
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.swap_horiz),
              label: Text(_transferring ? 'Transfiriendo...' : 'Confirmar Transferencia'),
              onPressed: _transferring ? null : _ejecutarTransferencia,
            ),
          ),
        ],
      ),
    );
  }
}
