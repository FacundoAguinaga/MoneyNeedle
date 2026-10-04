import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/widgets.dart';
import 'budgets_screen.dart';
import 'movement_detail_screen.dart';
import 'recurring_tab.dart';

class PendingProposal {
  final String texto;
  final ProposalDto propuesta;
  PendingProposal(this.texto, this.propuesta);
}

class HomeTab extends StatefulWidget {
  final VoidCallback? onViewAllMovements;

  const HomeTab({
    super.key,
    this.onViewAllMovements,
  });

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
  List<BudgetStatusDto> _budgets = [];
  List<RecurringRuleDto> _recurringRules = [];
  String _userName = 'Usuario';
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
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('mn_user_name') ?? 'Usuario';

      final summary = await getHomeSummary(dbPath: dbPath, currency: 'ARS');
      final streak = await getUsageStreak(dbPath: dbPath);
      final movs = await listMovements(dbPath: dbPath, limit: 5);
      final accs = await listAccounts(dbPath: dbPath);
      final cats = await listCategories(dbPath: dbPath);
      final insights = await getFinancialInsights(dbPath: dbPath, currency: 'ARS');

      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999).millisecondsSinceEpoch;
      final budgets = await listBudgetsStatus(
        dbPath: dbPath,
        startDateMs: startOfMonth,
        endDateMs: endOfMonth,
        currency: 'ARS',
      );
      final recurring = await listRecurringRules(dbPath: dbPath);

      if (!mounted) return;
      setState(() {
        _userName = name;
        _summary = summary;
        _streak = streak;
        _movimientos = movs;
        _accounts = accs;
        _categories = cats;
        _insights = insights;
        _budgets = budgets;
        _recurringRules = recurring;
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

  Widget _buildGreetingHeader(ThemeData theme) {
    final streak = _streak;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $_userName',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Resumen de tus finanzas',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                    size: 16,
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
    );
  }

  Widget _buildSummaryHero(ThemeData theme) {
    final colors = context.mnColors;
    final summary = _summary;

    if (summary == null) return const SizedBox.shrink();

    final currency = summary.currency;
    final totalBalance = summary.totalBalance;
    final expense = summary.monthlyExpense;
    final income = summary.monthlyIncome;
    final delta = summary.deltaExpensePct;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: MnCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo consolidado',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            MnAmountText(
              amount: totalBalance,
              currency: currency,
              colorize: false,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
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
                            Flexible(
                              child: Text(
                                'Ingresos mes',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_upward_rounded, size: 14, color: colors.expense),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Gastos mes',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (delta != null) ...[
                              const SizedBox(width: 4),
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
    );
  }

  Widget _buildBudgetSummaryCard(ThemeData theme) {
    if (_budgets.isEmpty) return const SizedBox.shrink();

    double totalBudget = 0;
    double totalSpent = 0;
    for (final b in _budgets) {
      totalBudget += b.budgetAmount;
      totalSpent += b.spentAmount;
    }

    if (totalBudget <= 0) return const SizedBox.shrink();

    final ratio = (totalSpent / totalBudget).clamp(0.0, 1.0);
    final ratioPct = (totalSpent / totalBudget) * 100;
    final isExceeded = totalSpent > totalBudget;
    final colors = context.mnColors;
    final barColor = isExceeded
        ? colors.expense
        : ratio > 0.8
            ? colors.warning
            : colors.income;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: MnCard(
        padding: const EdgeInsets.all(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BudgetsScreen()),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.pie_chart_outline, size: 16, color: barColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Presupuesto mensual',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${ratioPct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: barColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Gastaste ${MnAmountText.format(totalSpent, currency: 'ARS', includeDecimals: false)} de ${MnAmountText.format(totalBudget, currency: 'ARS', includeDecimals: false)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecurringNotice(ThemeData theme) {
    if (_recurringRules.isEmpty) return const SizedBox.shrink();

    final totalMonthly = _recurringRules
        .where((r) =>
            r.transactionType.toLowerCase() == 'gasto' ||
            r.transactionType.toLowerCase() == 'expense')
        .fold<double>(0.0, (sum, r) => sum + r.amount);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: MnCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RecurringTab(isStandalone: true),
            ),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.autorenew_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Compromisos fijos: ${MnAmountText.format(totalMonthly, currency: 'ARS', includeDecimals: false)} / mes (${_recurringRules.length} reglas)',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading && _movimientos.isEmpty && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            // Saludo personalizado con racha
            _buildGreetingHeader(theme),

            // Resumen Financiero Hero
            _buildSummaryHero(theme),

            // Resumen de Presupuesto (si hay límites fijados)
            _buildBudgetSummaryCard(theme),

            // Mini aviso de suscripciones fijas
            _buildRecurringNotice(theme),

            // 1 Insight destacado (el de mayor prioridad)
            if (_insights.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: InsightCard(insight: _insights.first),
              ),

            // Tarjeta de Propuesta Interactiva NLP (si está pendiente)
            if (_pending != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

            // Encabezado de Movimientos Recientes con link a todos
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Movimientos recientes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: const Text('Ver todos', style: TextStyle(fontSize: 12)),
                    onPressed: widget.onViewAllMovements,
                  ),
                ],
              ),
            ),

            // Preview de los últimos 5 movimientos
            if (_movimientos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: MnCard(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 36,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No hay movimientos recientes',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MnCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _movimientos.length,
                      separatorBuilder: (context, _) => Divider(
                        height: 1,
                        indent: 64,
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      itemBuilder: (context, index) {
                        final mov = _movimientos[index];
                        return Dismissible(
                          key: ValueKey('home_mov_${mov.id}'),
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
                                await _recargar();
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
