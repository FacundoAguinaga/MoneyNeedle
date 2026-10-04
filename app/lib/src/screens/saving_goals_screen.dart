import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';

class SavingGoalsScreen extends StatefulWidget {
  const SavingGoalsScreen({super.key});

  @override
  State<SavingGoalsScreen> createState() => _SavingGoalsScreenState();
}

class _SavingGoalsScreenState extends State<SavingGoalsScreen> {
  String? _dbPath;
  bool _loading = true;
  String _currency = 'ARS';
  List<String> _availableCurrencies = ['ARS'];
  List<SavingGoalDto> _savingGoals = [];

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

  Future<void> _loadData() async {
    if (_dbPath == null) return;
    setState(() => _loading = true);

    try {
      final savingGoals = await listSavingGoals(dbPath: _dbPath!);

      if (!mounted) return;
      setState(() {
        _savingGoals = savingGoals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando metas de ahorro: $e')),
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

  Widget _buildCurrencySelector() {
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
      ],
    );
  }

  Widget _buildGoalsTab(ThemeData theme) {
    double totalSaved = 0;
    for (final g in _savingGoals) {
      if (g.currency == _currency) {
        totalSaved += g.currentAmount;
      }
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildCurrencySelector(),
          const SizedBox(height: 12),

          // Resumen de Ahorro en Metas
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
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.savings, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Acumulado en Metas',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatAmount(totalSaved),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: context.mnColors.income,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Botón para crear nueva meta
          FilledButton.icon(
            onPressed: () => _abrirModalNuevaMeta(),
            icon: const Icon(Icons.add),
            label: const Text('Crear Nueva Meta de Ahorro'),
          ),
          const SizedBox(height: 16),

          // Lista de metas
          if (_savingGoals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.flag_outlined, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      'No tenés metas de ahorro activas',
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
              itemCount: _savingGoals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final g = _savingGoals[i];
                final isCompleted = g.status == 'completed' || g.currentAmount >= g.targetAmount;
                final color = _parseColor(g.color);
                final remaining = (g.targetAmount - g.currentAmount).clamp(0.0, double.infinity);

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isCompleted
                          ? context.mnColors.income
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
                              radius: 18,
                              backgroundColor: color.withValues(alpha: 0.2),
                              child: Icon(_getCategoryIcon(g.icon), size: 20, color: color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Meta: ${_formatAmount(g.targetAmount)} ${g.currency}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCompleted)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: context.mnColors.income.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '¡Completada!',
                                  style: TextStyle(
                                    color: context.mnColors.income,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'delete') {
                                  _eliminarMeta(g.id);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Eliminar meta'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (g.progressPercentage / 100).clamp(0.0, 1.0),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              isCompleted ? context.mnColors.income : theme.colorScheme.primary,
                            ),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Ahorrado: ${_formatAmount(g.currentAmount)} (${g.progressPercentage.toStringAsFixed(1)}%)',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isCompleted ? '¡Meta alcanzada!' : 'Faltan: ${_formatAmount(remaining)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCompleted ? context.mnColors.income : theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _abrirModalAporte(g),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Aportar / Retirar Ahorro'),
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

  Future<void> _abrirModalNuevaMeta() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedIcon = 'flag';
    String selectedColor = '#2196F3';

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
                    'Nueva Meta de Ahorro',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Meta (ej. Vacaciones, Auto)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monto Objetivo ($_currency)',
                      border: const OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Selector de ícono rápido
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['flag', 'flight', 'home', 'directions_bus', 'shield'].map((iconKey) {
                      final selected = selectedIcon == iconKey;
                      return IconButton.filledTonal(
                        isSelected: selected,
                        onPressed: () => setModalState(() => selectedIcon = iconKey),
                        icon: Icon(_getCategoryIcon(iconKey)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final val = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                        if (name.isEmpty || val == null || val <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá nombre y monto objetivo válidos')),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          await createSavingGoal(
                            dbPath: _dbPath!,
                            name: name,
                            targetAmount: val,
                            currency: _currency,
                            color: selectedColor,
                            icon: selectedIcon,
                          );
                          await _loadData();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error creando meta: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Crear Meta'),
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

  Future<void> _abrirModalAporte(SavingGoalDto goal) async {
    final amountCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Aportar a ${goal.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Monto actual ahorrado: ${_formatAmount(goal.currentAmount)} ${goal.currency}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Monto a ingresar',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final val = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                if (val == null || val <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingresá un monto válido')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await contributeToSavingGoal(
                    dbPath: _dbPath!,
                    goalId: goal.id,
                    amount: val,
                  );
                  await _loadData();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error registrando aporte: $e')),
                    );
                  }
                }
              },
              child: const Text('Aportar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _eliminarMeta(String goalId) async {
    try {
      await deleteSavingGoal(dbPath: _dbPath!, goalId: goalId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meta de ahorro eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando meta: $e')),
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
        title: const Text('Metas de Ahorro'),
      ),
      body: _buildGoalsTab(Theme.of(context)),
    );
  }
}
