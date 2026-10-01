import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../widgets/widgets.dart';
import 'movement_detail_screen.dart';

/// Pantalla de búsqueda multicriterio en el historial de transacciones.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String? _dbPath;
  List<AccountDto> _accounts = [];
  List<CategoryDto> _categories = [];
  List<MovementDto> _results = [];
  bool _loading = false;
  bool _hasSearched = false;

  // Filtros activos
  String? _selectedTipo; // null = Todos, 'gasto', 'ingreso', 'transferencia'
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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
      // Búsqueda inicial para mostrar transacciones recientes
      _ejecutarBusqueda();
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _ejecutarBusqueda();
    });
  }

  Future<void> _ejecutarBusqueda() async {
    if (_dbPath == null) return;
    setState(() => _loading = true);

    try {
      final queryText = _searchController.text.trim();
      final startMs = _selectedDateRange?.start.millisecondsSinceEpoch;
      final endMs = _selectedDateRange?.end.millisecondsSinceEpoch;

      final results = await searchMovements(
        dbPath: _dbPath!,
        query: queryText.isEmpty ? null : queryText,
        tipo: _selectedTipo,
        categoryId: _selectedCategoryId,
        accountId: _selectedAccountId,
        startDateMs: startMs,
        endDateMs: endMs,
        limit: 100,
        offset: 0,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _hasSearched = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasSearched = true;
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _ejecutarBusqueda();
    }
  }

  Future<void> _eliminarMovimiento(MovementDto mov) async {
    if (_dbPath == null) return;
    try {
      await deleteMovement(dbPath: _dbPath!, movementId: mov.id);
      await _ejecutarBusqueda();
      if (!mounted) return;

      final label = mov.descripcion.isNotEmpty ? mov.descripcion : mov.categoria;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Movimiento "$label" eliminado'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              try {
                await restoreMovement(dbPath: _dbPath!, movementId: mov.id);
                await _ejecutarBusqueda();
              } catch (_) {}
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar por nota, comercio o frase...',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _ejecutarBusqueda();
                    },
                  )
                : null,
          ),
          style: theme.textTheme.bodyLarge,
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          // Barra de Filtros horizontales
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Filtro Tipo
                PopupMenuButton<String?>(
                  initialValue: _selectedTipo,
                  onSelected: (val) {
                    setState(() => _selectedTipo = val);
                    _ejecutarBusqueda();
                  },
                  child: Chip(
                    avatar: Icon(
                      _selectedTipo == null ? Icons.filter_list : Icons.check,
                      size: 16,
                    ),
                    label: Text(
                      _selectedTipo == null
                          ? 'Tipo'
                          : _selectedTipo == 'gasto'
                              ? 'Gastos'
                              : _selectedTipo == 'ingreso'
                                  ? 'Ingresos'
                                  : 'Transferencias',
                    ),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Todos los tipos')),
                    const PopupMenuItem(value: 'gasto', child: Text('Solo Gastos')),
                    const PopupMenuItem(value: 'ingreso', child: Text('Solo Ingresos')),
                    const PopupMenuItem(value: 'transferencia', child: Text('Solo Transferencias')),
                  ],
                ),
                const SizedBox(width: 8),

                // Filtro Categoría
                if (_categories.isNotEmpty) ...[
                  PopupMenuButton<String?>(
                    initialValue: _selectedCategoryId,
                    onSelected: (val) {
                      setState(() => _selectedCategoryId = val);
                      _ejecutarBusqueda();
                    },
                    child: Chip(
                      avatar: Icon(
                        _selectedCategoryId == null ? Icons.category_outlined : Icons.check,
                        size: 16,
                      ),
                      label: Text(
                        _selectedCategoryId == null
                            ? 'Categoría'
                            : _categories
                                .where((c) => c.id == _selectedCategoryId)
                                .map((c) => c.name)
                                .firstOrNull ?? 'Categoría',
                      ),
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: null, child: Text('Todas las categorías')),
                      ..._categories.map(
                        (c) => PopupMenuItem(value: c.id, child: Text(c.name)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],

                // Filtro Cuenta
                if (_accounts.isNotEmpty) ...[
                  PopupMenuButton<String?>(
                    initialValue: _selectedAccountId,
                    onSelected: (val) {
                      setState(() => _selectedAccountId = val);
                      _ejecutarBusqueda();
                    },
                    child: Chip(
                      avatar: Icon(
                        _selectedAccountId == null ? Icons.account_balance_outlined : Icons.check,
                        size: 16,
                      ),
                      label: Text(
                        _selectedAccountId == null
                            ? 'Cuenta'
                            : _accounts
                                .where((a) => a.id == _selectedAccountId)
                                .map((a) => a.name)
                                .firstOrNull ?? 'Cuenta',
                      ),
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: null, child: Text('Todas las cuentas')),
                      ..._accounts.map(
                        (a) => PopupMenuItem(value: a.id, child: Text(a.name)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],

                // Filtro Rango de Fechas
                ActionChip(
                  avatar: Icon(
                    _selectedDateRange == null ? Icons.date_range_outlined : Icons.event_available,
                    size: 16,
                  ),
                  label: Text(
                    _selectedDateRange == null
                        ? 'Fecha'
                        : '${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month} - ${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}',
                  ),
                  onPressed: _pickDateRange,
                ),

                // Limpiar filtros activos si hay alguno
                if (_selectedTipo != null ||
                    _selectedCategoryId != null ||
                    _selectedAccountId != null ||
                    _selectedDateRange != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
                    tooltip: 'Limpiar filtros',
                    onPressed: () {
                      setState(() {
                        _selectedTipo = null;
                        _selectedCategoryId = null;
                        _selectedAccountId = null;
                        _selectedDateRange = null;
                      });
                      _ejecutarBusqueda();
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),

          // Resultados
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty && _hasSearched
                    ? const MnEmptyState(
                        icon: Icons.search_off_outlined,
                        title: 'Sin resultados',
                        message: 'No encontramos movimientos que coincidan con los filtros aplicados.',
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (context, _) => Divider(
                          height: 1,
                          indent: 64,
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (context, index) {
                          final mov = _results[index];
                          return Dismissible(
                            key: ValueKey('search_mov_${mov.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: theme.colorScheme.error,
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (_) {
                              HapticFeedback.heavyImpact();
                              _eliminarMovimiento(mov);
                            },
                            child: MovementListItem(
                              movement: mov,
                              onTap: () async {
                                final res = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MovementDetailScreen(movement: mov),
                                  ),
                                );
                                if (res == true) {
                                  await _ejecutarBusqueda();
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
