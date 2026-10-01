import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../widgets/widgets.dart';

class PendingProposal {
  final String texto;
  final ProposalDto propuesta;
  PendingProposal(this.texto, this.propuesta);
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  HomeSummaryDto? _summary;
  StreakDto? _streak;
  List<MovementDto> _movimientos = [];
  List<AccountDto> _accounts = [];
  List<CategoryDto> _categories = [];
  PendingProposal? _pending;
  bool _loading = true;
  bool _confirmando = false;

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

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _streak = streak;
        _movimientos = movs;
        _accounts = accs;
        _categories = cats;
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
          // Card principal de Saldo Total Consolidado
          MnCard(
            padding: const EdgeInsets.all(18),
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
                      ),
                    ),
                    if (streak != null && streak.currentStreak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔥 ', style: TextStyle(fontSize: 12)),
                            Text(
                              '${streak.currentStreak} días',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                MnAmountText(
                  amount: totalBalance,
                  currency: currency,
                  colorize: false,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Fila de Ingresos y Gastos del mes
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.arrow_downward, size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Ingresos mes',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.arrow_upward, size: 14, color: Colors.red),
                              const SizedBox(width: 4),
                              Text(
                                'Gastos mes',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (delta != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: delta > 0 ? Colors.red : Colors.green,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
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
                  ],
                ),
              ],
            ),
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
            // Resumen Financiero Compacto
            _buildSummaryHeader(),

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
              const MnSectionHeader(
                title: 'Movimientos recientes',
                subtitle: 'Historial cronológico consolidado',
              ),

            // Lista agrupada por fecha
            Expanded(
              child: GroupedMovementList(
                movements: _movimientos,
                onEmptyAction: _abrirQuickAdd,
                onItemDismissed: _eliminarMovimiento,
              ),
            ),
          ],
        ),
      ),
      // Opción A: FAB expandible para Command Palette
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirQuickAdd,
        icon: const Icon(Icons.add),
        label: const Text('Registrar'),
      ),
    );
  }
}
