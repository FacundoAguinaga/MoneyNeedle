import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/widgets.dart';

/// Pantalla de detalle y edición completa de un movimiento financiero.
class MovementDetailScreen extends StatefulWidget {
  final MovementDto movement;

  const MovementDetailScreen({super.key, required this.movement});

  @override
  State<MovementDetailScreen> createState() => _MovementDetailScreenState();
}

class _MovementDetailScreenState extends State<MovementDetailScreen> {
  late MovementDto _movement;
  String? _dbPath;
  List<AccountDto> _accounts = [];
  List<CategoryDto> _categories = [];

  @override
  void initState() {
    super.initState();
    _movement = widget.movement;
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final path = await VaultService.getDbPath();
      final accs = await listAccounts(dbPath: path);
      final cats = await listCategories(dbPath: path);
      if (!mounted) return;
      setState(() {
        _dbPath = path;
        _accounts = accs;
        _categories = cats;
      });
    } catch (_) {}
  }

  Future<void> _eliminar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar movimiento?'),
        content: const Text(
          'El movimiento pasará a la papelera y se recalcularán los saldos y cuotas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true || _dbPath == null) return;

    try {
      HapticFeedback.heavyImpact();
      await deleteMovement(dbPath: _dbPath!, movementId: _movement.id);
      if (!mounted) return;
      Navigator.pop(context, true); // true = eliminado
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  Future<void> _editar() async {
    final amountCtrl = TextEditingController(text: _movement.monto.toStringAsFixed(2));
    final descCtrl = TextEditingController(text: _movement.descripcion);
    String selectedTipo = _movement.tipo.toLowerCase();
    String selectedCat = _movement.categoria;
    String? selectedAccId = _movement.accountId;
    String selectedDate = _movement.fecha;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Editar movimiento',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Monto
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Monto (${_movement.moneda})',
                        prefixText: '\$ ',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tipo
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'gasto', label: Text('Gasto')),
                        ButtonSegment(value: 'ingreso', label: Text('Ingreso')),
                        ButtonSegment(value: 'transferencia', label: Text('Transfer')),
                      ],
                      selected: {selectedTipo},
                      onSelectionChanged: (val) {
                        setModalState(() => selectedTipo = val.first);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Descripción / Nota
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descripción o nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Categoría
                    DropdownButtonFormField<String>(
                      initialValue: _categories.any((c) => c.name == selectedCat) ? selectedCat : null,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: _categories.map((c) {
                        return DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedCat = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Cuenta
                    DropdownButtonFormField<String?>(
                      initialValue: selectedAccId,
                      decoration: const InputDecoration(
                        labelText: 'Cuenta asociada',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin cuenta específica')),
                        ..._accounts.map((a) {
                          return DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.name} (${a.currency})'),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setModalState(() => selectedAccId = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Fecha
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
                      ),
                      title: Text('Fecha: $selectedDate'),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final currentDt = DateTime.tryParse(selectedDate) ?? DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: currentDt,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          final formatted = picked.toIso8601String().substring(0, 10);
                          setModalState(() => selectedDate = formatted);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: () async {
                        final newAmount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                        if (newAmount == null || newAmount <= 0) return;

                        if (_dbPath == null) return;
                        try {
                          await updateMovement(
                            dbPath: _dbPath!,
                            movementId: _movement.id,
                            tipo: selectedTipo,
                            monto: newAmount,
                            moneda: _movement.moneda,
                            categoria: selectedCat,
                            descripcion: descCtrl.text.trim(),
                            fecha: selectedDate,
                            accountId: selectedAccId,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al actualizar: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Guardar cambios'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (updated == true && _dbPath != null) {
      // Recargar movimiento
      final searchResult = await searchMovements(
        dbPath: _dbPath!,
        query: _movement.id,
        limit: 1,
        offset: 0,
      );
      if (searchResult.isNotEmpty && mounted) {
        setState(() {
          _movement = searchResult.first;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Movimiento actualizado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGasto = _movement.tipo.toLowerCase() == 'gasto' ||
        _movement.tipo.toLowerCase() == 'expense';
    final isIngreso = _movement.tipo.toLowerCase() == 'ingreso' ||
        _movement.tipo.toLowerCase() == 'income';
    final isTransfer = _movement.tipo.toLowerCase() == 'transferencia' ||
        _movement.tipo.toLowerCase() == 'transfer';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del movimiento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar movimiento',
            onPressed: _editar,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            tooltip: 'Eliminar',
            onPressed: _eliminar,
          ),
        ],
      ),
      body: _dbPath == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Tarjeta Principal de Monto
                MnCard(
                  padding: const EdgeInsets.all(24),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  child: Column(
                    children: [
                      MnCategoryIcon(
                        category: isTransfer ? 'transfer' : _movement.categoria,
                        iconName: isTransfer ? 'transfer' : null,
                        radius: 32,
                      ),
                      const SizedBox(height: 14),
                      MnAmountText(
                        amount: _movement.monto,
                        currency: _movement.moneda,
                        isExpense: isGasto,
                        isIncome: isIngreso,
                        isTransfer: isTransfer,
                        showSign: true,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isGasto
                                  ? context.mnColors.expense
                                  : isIngreso
                                      ? context.mnColors.income
                                      : context.mnColors.transfer)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _movement.tipo.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isGasto
                                ? context.mnColors.expense
                                : isIngreso
                                    ? context.mnColors.income
                                    : context.mnColors.transfer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tarjeta de Metadatos
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: const Text('Categoría'),
                        trailing: Text(
                          _movement.categoria.isNotEmpty ? _movement.categoria : 'Sin categoría',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.account_balance_outlined),
                        title: const Text('Cuenta'),
                        trailing: Text(
                          _movement.accountName ?? 'No especificada',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text('Fecha'),
                        trailing: Text(
                          _movement.fecha,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_movement.descripcion.isNotEmpty) ...[
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.notes_outlined),
                          title: const Text('Nota / Descripción'),
                          subtitle: Text(_movement.descripcion),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Botones de acción inferior
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _editar,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: _eliminar,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
