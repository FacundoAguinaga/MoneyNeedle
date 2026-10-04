import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';

enum PeriodFilter {
  esteMes('Este mes'),
  mesAnterior('Mes anterior'),
  ultimos3Meses('Últimos 3m'),
  todoElAno('Año actual');

  final String label;
  const PeriodFilter(this.label);
}

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  String? _dbPath;
  bool _loading = true;
  PeriodFilter _selectedPeriod = PeriodFilter.esteMes;
  String _currency = 'ARS';
  List<String> _availableCurrencies = ['ARS'];
  List<BudgetStatusDto> _budgets = [];
  List<CategoryDto> _categories = [];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final path = await VaultService.getDbPath();
    if (!mounted) return;
    setState(() => _dbPath = path);

    try {
      final accounts = await listAccounts(dbPath: path);
      final currencies = accounts.map((a) => a.currency).toSet().toList();
      if (currencies.isNotEmpty) {
        if (!currencies.contains(_currency)) {
          _currency = currencies.first;
        }
        _availableCurrencies = currencies;
      }
    } catch (_) {}

    await _loadData();
  }

  DateTimeRange _getDateRange(PeriodFilter period) {
    final now = DateTime.now();
    switch (period) {
      case PeriodFilter.esteMes:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case PeriodFilter.mesAnterior:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case PeriodFilter.ultimos3Meses:
        final start = DateTime(now.year, now.month - 2, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case PeriodFilter.todoElAno:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
    }
  }

  Future<void> _loadData() async {
    if (_dbPath == null) return;
    setState(() => _loading = true);

    final range = _getDateRange(_selectedPeriod);
    final startMs = range.start.millisecondsSinceEpoch;
    final endMs = range.end.millisecondsSinceEpoch;

    try {
      final budgets = await listBudgetsStatus(
        dbPath: _dbPath!,
        startDateMs: startMs,
        endDateMs: endMs,
        currency: _currency,
      );
      final categories = await listCategories(dbPath: _dbPath!);

      if (!mounted) return;
      setState(() {
        _budgets = budgets;
        _categories = categories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando presupuestos: $e')),
      );
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

  String _formatAmount(double amount) {
    final isNeg = amount < 0;
    final abs = amount.abs();
    final parts = abs.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];

    final buffer = StringBuffer();
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(integerPart[i]);
    }
    final sign = isNeg ? '-' : '';
    return '$sign\$ $buffer,$decimalPart';
  }

  IconData _getCategoryIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'shopping_cart':
      case 'supermercado':
        return Icons.shopping_cart;
      case 'directions_bus':
      case 'transporte':
        return Icons.directions_bus;
      case 'restaurant':
      case 'comida':
        return Icons.restaurant;
      case 'receipt':
      case 'receipt_long':
      case 'servicios':
        return Icons.receipt_long;
      case 'home':
      case 'hogar':
      case 'alquiler':
        return Icons.home;
      case 'local_hospital':
      case 'medical_services':
      case 'salud':
        return Icons.local_hospital;
      case 'school':
      case 'educacion':
        return Icons.school;
      case 'movie':
      case 'entretenimiento':
        return Icons.movie;
      case 'flight':
      case 'vacaciones':
        return Icons.flight;
      case 'shield':
      case 'emergencia':
        return Icons.shield;
      default:
        return Icons.category;
    }
  }

  Widget _buildCurrencyAndPeriodSelectors(ThemeData theme) {
    return Row(
      children: [
        DropdownButton<String>(
          value: _currency,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(12),
          items: _availableCurrencies
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(
                      c,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null && val != _currency) {
              setState(() => _currency = val);
              _loadData();
            }
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: PeriodFilter.values.map((p) {
                final selected = p == _selectedPeriod;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: selected,
                    label: Text(p.label),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedPeriod = p);
                      _loadData();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetsTab(ThemeData theme) {
    double totalBudget = 0;
    double totalSpent = 0;
    for (final b in _budgets) {
      totalBudget += b.budgetAmount;
      totalSpent += b.spentAmount;
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildCurrencyAndPeriodSelectors(theme),
          const SizedBox(height: 12),

          // Tarjeta de Resumen Presupuestario
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Presupuestado',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(totalBudget),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Consumido',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(totalSpent),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: totalSpent > totalBudget && totalBudget > 0
                                ? context.mnColors.expense
                                : context.mnColors.income,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Botón para definir presupuesto
          FilledButton.icon(
            onPressed: () => _abrirModalPresupuesto(),
            icon: const Icon(Icons.add),
            label: const Text('Fijar Límite por Categoría'),
          ),
          const SizedBox(height: 16),

          // Lista de presupuestos
          if (_budgets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      'No tenés límites fijados en este período',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _budgets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final b = _budgets[i];
                final color = _parseColor(b.categoryColor);

                // Determinar color de la barra
                Color barColor = context.mnColors.income;
                if (b.isOverBudget) {
                  barColor = context.mnColors.expense;
                } else if (b.isWarning) {
                  barColor = context.mnColors.warning;
                }

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: b.isOverBudget
                          ? context.mnColors.expense.withValues(alpha: 0.5)
                          : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: color.withValues(alpha: 0.2),
                              child: Icon(_getCategoryIcon(b.categoryIcon),
                                  size: 18, color: color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                b.categoryName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (b.isOverBudget)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: context.mnColors.expense.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Excedido',
                                  style: TextStyle(
                                    color: context.mnColors.expense,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if (b.isWarning)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: context.mnColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Cerca del límite',
                                  style: TextStyle(
                                    color: context.mnColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'delete') {
                                  _eliminarPresupuesto(b.id);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Eliminar presupuesto'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (b.spentPercentage / 100).clamp(0.0, 1.0),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(barColor),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Gastado: ${_formatAmount(b.spentAmount)} (${b.spentPercentage.toStringAsFixed(0)}%)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Tope: ${_formatAmount(b.budgetAmount)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          b.remainingAmount >= 0
                              ? 'Restan: ${_formatAmount(b.remainingAmount)}'
                              : 'Excedido por: ${_formatAmount(b.remainingAmount.abs())}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: b.remainingAmount >= 0 ? context.mnColors.income : context.mnColors.expense,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _abrirModalPresupuesto() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay categorías disponibles')),
      );
      return;
    }

    String selectedCatId = _categories.first.id;
    final amountCtrl = TextEditingController();
    int alertPercentage = 80;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fijar Presupuesto Mensual',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCatId,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(_getCategoryIcon(c.icon), size: 18, color: _parseColor(c.color)),
                            const SizedBox(width: 8),
                            Text(c.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedCatId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monto Límite Mensual ($_currency)',
                      border: const OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Alerta temprana al (%):'),
                      Text(
                        '$alertPercentage%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: alertPercentage.toDouble(),
                    min: 50,
                    max: 100,
                    divisions: 10,
                    label: '$alertPercentage%',
                    onChanged: (val) {
                      setModalState(() => alertPercentage = val.toInt());
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final val = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                        if (val == null || val <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá un monto válido mayor a 0')),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          await setCategoryBudget(
                            dbPath: _dbPath!,
                            categoryId: selectedCatId,
                            currency: _currency,
                            amount: val,
                            alertPercentage: alertPercentage,
                          );
                          await _loadData();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error guardando presupuesto: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Guardar Presupuesto'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _eliminarPresupuesto(String budgetId) async {
    try {
      await deleteBudget(dbPath: _dbPath!, budgetId: budgetId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presupuesto eliminado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando presupuesto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuestos'),
      ),
      body: _buildBudgetsTab(Theme.of(context)),
    );
  }
}
