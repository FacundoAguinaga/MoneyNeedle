import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../widgets/widgets.dart';
import 'movement_detail_screen.dart';

/// Tab principal de movimientos que combina listado agrupado,
/// barra de búsqueda persistente, filtros multicriterio y paginación incremental.
class MovementsTab extends StatefulWidget {
  final VoidCallback? onQuickAdd;

  const MovementsTab({super.key, this.onQuickAdd});

  static final GlobalKey<MovementsTabState> movementsTabKey = GlobalKey<MovementsTabState>();

  @override
  State<MovementsTab> createState() => MovementsTabState();
}

class MovementsTabState extends State<MovementsTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  String? _dbPath;
  List<AccountDto> _accounts = [];
  List<CategoryDto> _categories = [];
  List<MovementDto> _movements = [];

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const int _pageSize = 50;
  int _currentOffset = 0;

  // Filtros activos
  String? _selectedTipo;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTimeRange? _selectedDateRange;

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _selectedTipo != null ||
      _selectedCategoryId != null ||
      _selectedAccountId != null ||
      _selectedDateRange != null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200 && !_loadingMore && _hasMore && !_initialLoading) {
      _loadMore();
    }
  }

  Future<void> _initData() async {
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
      await _ejecutarBusqueda(reset: true);
    } catch (_) {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _ejecutarBusqueda(reset: true);
    });
  }

  Future<void> recargar() async {
    await _ejecutarBusqueda(reset: true);
  }

  Future<void> _ejecutarBusqueda({required bool reset}) async {
    if (_dbPath == null) return;
    if (reset) {
      setState(() {
        _initialLoading = true;
        _currentOffset = 0;
        _hasMore = true;
      });
    }

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
        limit: _pageSize,
        offset: reset ? 0 : _currentOffset,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _movements = results;
          _currentOffset = results.length;
        } else {
          _movements.addAll(results);
          _currentOffset += results.length;
        }
        _hasMore = results.length == _pageSize;
        _initialLoading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _ejecutarBusqueda(reset: false);
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
      _ejecutarBusqueda(reset: true);
    }
  }

  Future<void> _eliminarMovimiento(MovementDto mov) async {
    if (_dbPath == null) return;
    try {
      await deleteMovement(dbPath: _dbPath!, movementId: mov.id);
      await _ejecutarBusqueda(reset: true);
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
                await _ejecutarBusqueda(reset: true);
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

  void _limpiarFiltros() {
    setState(() {
      _searchController.clear();
      _selectedTipo = null;
      _selectedCategoryId = null;
      _selectedAccountId = null;
      _selectedDateRange = null;
    });
    _ejecutarBusqueda(reset: true);
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SearchBar(
        controller: _searchController,
        hintText: 'Buscar por nota, comercio o frase...',
        hintStyle: WidgetStatePropertyAll(
          theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
        leading: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.search_rounded),
        ),
        trailing: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 20),
              onPressed: () {
                _searchController.clear();
                _ejecutarBusqueda(reset: true);
              },
            ),
        ],
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Filtro Tipo
          PopupMenuButton<String?>(
            initialValue: _selectedTipo,
            onSelected: (val) {
              setState(() => _selectedTipo = val);
              _ejecutarBusqueda(reset: true);
            },
            child: Chip(
              avatar: Icon(
                _selectedTipo == null ? Icons.filter_list_rounded : Icons.check_rounded,
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
                _ejecutarBusqueda(reset: true);
              },
              child: Chip(
                avatar: Icon(
                  _selectedCategoryId == null ? Icons.category_outlined : Icons.check_rounded,
                  size: 16,
                ),
                label: Text(
                  _selectedCategoryId == null
                      ? 'Categoría'
                      : _categories
                              .where((c) => c.id == _selectedCategoryId)
                              .map((c) => c.name)
                              .firstOrNull ??
                          'Categoría',
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
                _ejecutarBusqueda(reset: true);
              },
              child: Chip(
                avatar: Icon(
                  _selectedAccountId == null ? Icons.account_balance_outlined : Icons.check_rounded,
                  size: 16,
                ),
                label: Text(
                  _selectedAccountId == null
                      ? 'Cuenta'
                      : _accounts
                              .where((a) => a.id == _selectedAccountId)
                              .map((a) => a.name)
                              .firstOrNull ??
                          'Cuenta',
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
              _selectedDateRange == null ? Icons.date_range_outlined : Icons.event_available_rounded,
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
          if (_hasActiveFilters) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
              tooltip: 'Limpiar filtros',
              onPressed: _limpiarFiltros,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (!_hasMore && _movements.length >= _pageSize) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Fin de los movimientos (${_movements.length} en total)',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _ejecutarBusqueda(reset: true),
        child: Column(
          children: [
            _buildSearchBar(theme),
            _buildFilterChips(theme),
            const Divider(height: 1),
            Expanded(
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _movements.isEmpty
                      ? _hasActiveFilters
                          ? const MnEmptyState(
                              icon: Icons.search_off_outlined,
                              title: 'Sin resultados',
                              message:
                                  'No encontramos movimientos que coincidan con los filtros aplicados.',
                            )
                          : MnEmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'No hay movimientos',
                              message: 'Registrá tus ingresos y gastos para verlos acá agrupados.',
                              actionLabel: 'Registrar movimiento',
                              onAction: widget.onQuickAdd,
                            )
                      : GroupedMovementList(
                          movements: _movements,
                          controller: _scrollController,
                          footer: _buildFooter(),
                          onEmptyAction: widget.onQuickAdd,
                          onItemDismissed: _eliminarMovimiento,
                          onItemTap: (mov) async {
                            final res = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MovementDetailScreen(movement: mov),
                              ),
                            );
                            if (res == true) {
                              await _ejecutarBusqueda(reset: true);
                            }
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
