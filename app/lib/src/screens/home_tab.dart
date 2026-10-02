import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/vault_service.dart';
import '../providers/privacy_provider.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/widgets.dart';
import 'movement_detail_screen.dart';
import 'search_screen.dart';

class PendingProposal {
  final String texto;
  final ProposalDto propuesta;
  PendingProposal(this.texto, this.propuesta);
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  static final GlobalKey<HomeTabState> homeTabKey = GlobalKey<HomeTabState>();

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  HomeSummaryDto? _summary;
  StreakDto? _streak;
  List<MovementDto> _movimientos = [];
  List<AccountDto> _accounts = [];
  List<CategoryDto> _categories = [];
  List<FinancialInsightDto> _insights = [];
  PendingProposal? _pending;
  bool _loading = true;
  bool _confirmando = false;

  void abrirQuickAdd() {
    _abrirQuickAdd();
  }

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
      final summary = await getHomeSummary(dbPath: dbPath, currency: 'ARS');
      final streak = await getUsageStreak(dbPath: dbPath);
      final movs = await listMovements(dbPath: dbPath, limit: 50);
      final accs = await listAccounts(dbPath: dbPath);
      final cats = await listCategories(dbPath: dbPath);
      final insights = await getFinancialInsights(dbPath: dbPath, currency: 'ARS');

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _streak = streak;
        _movimientos = movs;
        _accounts = accs;
        _categories = cats;
        _insights = insights;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _abrirQuickAdd() {
    HapticFeedback.selectionClick();
    QuickAddModal.show(
      context: context,
      onProposalGenerated: (query, proposal) {
        setState(() {
          _pending = PendingProposal(query, proposal);
        });
      },
    );
  }

  Future<void> _eliminarMovimiento(MovementDto mov) async {
    try {
      final dbPath = await VaultService.getDbPath();
      await deleteMovement(dbPath: dbPath, movementId: mov.id);
      await _recargar();
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
                await restoreMovement(dbPath: dbPath, movementId: mov.id);
                await _recargar();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al restaurar: $e')),
                  );
                }
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
        _recargar();
      }
    }
  }

  Future<void> _confirmarPropuesta({
    required String tipo,
    required double monto,
    required String categoria,
    required String fecha,
    required String? accountId,
    required int cuotas,
  }) async {
    final pend = _pending;
    if (pend == null) return;
    setState(() => _confirmando = true);

    try {
      final dbPath = await VaultService.getDbPath();
      final selectedAccount =
          _accounts.where((a) => a.id == accountId).firstOrNull;
      final isCard = selectedAccount?.accountType.toLowerCase() == 'credit_card';

      if (isCard && cuotas > 1) {
        final now = DateTime.now();
        await confirmCreditPurchase(
          dbPath: dbPath,
          cardAccountId: selectedAccount!.id,
          monto: monto,
          cuotas: cuotas,
          categoria: categoria,
          descripcion: pend.texto,
          startCycleYear: now.year,
          startCycleMonth: now.month,
        );
      } else {
        await confirmMovement(
          dbPath: dbPath,
          tipo: tipo,
          monto: monto,
          moneda: selectedAccount?.currency ?? 'ARS',
          categoria: categoria,
          descripcion: pend.texto,
          fecha: fecha,
          frase: pend.texto,
          accountId: accountId,
        );
      }

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _pending = null;
        _confirmando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Movimiento registrado correctamente')),
      );
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

  Widget _buildSummaryHeader() {
    final theme = Theme.of(context);
    final colors = context.mnColors;
    final summary = _summary;
    final streak = _streak;

    if (summary == null) return const SizedBox.shrink();

    final currency = summary.currency;
    final totalBalance = summary.totalBalance;
    final expense = summary.monthlyExpense;
    final income = summary.monthlyIncome;
    final delta = summary.deltaExpensePct;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tarjeta Hero de Balance Consolidado
          MnCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Saldo consolidado',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (streak != null && streak.currentStreak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              color: Colors.orange,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${streak.currentStreak} días',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: MnAmountText(
                        amount: totalBalance,
                        currency: currency,
                        colorize: false,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: PrivacyController.instance,
                      builder: (context, isPrivate, _) {
                        return IconButton(
                          icon: Icon(
                            isPrivate ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: isPrivate ? 'Mostrar montos' : 'Ocultar montos',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            PrivacyController.instance.toggle();
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // Cajas de Ingresos y Gastos del Mes
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.income.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.income.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.arrow_downward_rounded, size: 14, color: colors.income),
                                const SizedBox(width: 4),
                                Text(
                                  'Ingresos mes',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            MnAmountText(
                              amount: income,
                              currency: currency,
                              colorize: true,
                              isIncome: true,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.expense.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.expense.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.arrow_upward_rounded, size: 14, color: colors.expense),
                                const SizedBox(width: 4),
                                Text(
                                  'Gastos mes',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (delta != null) ...[
                                  const Spacer(),
                                  Text(
                                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: delta > 0 ? colors.expense : colors.income,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            MnAmountText(
                              amount: expense,
                              currency: currency,
                              colorize: true,
                              isExpense: true,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Fila de Acciones Rápidas
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Registrar'),
                  onPressed: _abrirQuickAdd,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Buscar'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SearchScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _movimientos.isEmpty && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: Column(
          children: [
            // Resumen Financiero Hero
            _buildSummaryHeader(),

            // Carrusel de Insights Accionables
            if (_insights.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InsightsCarousel(insights: _insights),
              ),

            // Tarjeta de Propuesta Interactiva NLP (si está pendiente)
            if (_pending != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: NlpProposalCard(
                  rawPrompt: _pending!.texto,
                  proposal: _pending!.propuesta,
                  accounts: _accounts,
                  categories: _categories,
                  isConfirming: _confirmando,
                  onConfirm: _confirmarPropuesta,
                  onDiscard: () => setState(() => _pending = null),
                ),
              ),

            // Encabezado de Movimientos Recientes
            if (_movimientos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Movimientos recientes',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${_movimientos.length} registros',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            // Lista agrupada por fecha
            Expanded(
              child: GroupedMovementList(
                movements: _movimientos,
                onEmptyAction: _abrirQuickAdd,
                onItemDismissed: _eliminarMovimiento,
                onItemTap: (mov) async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MovementDetailScreen(movement: mov),
                    ),
                  );
                  if (res == true) {
                    await _recargar();
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirQuickAdd,
        tooltip: 'Registrar gasto o ingreso',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
