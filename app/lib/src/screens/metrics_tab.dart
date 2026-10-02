import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../theme/mn_theme.dart';
import '../widgets/mn_card.dart';

enum PeriodFilter {
  esteMes('Este mes'),
  mesAnterior('Mes anterior'),
  ultimos3Meses('Últimos 3m'),
  todoElAno('Año actual');

  final String label;
  const PeriodFilter(this.label);
}

class MetricsTab extends StatefulWidget {
  const MetricsTab({super.key});

  @override
  State<MetricsTab> createState() => _MetricsTabState();
}

class _MetricsTabState extends State<MetricsTab> {
  String? _dbPath;
  bool _loading = true;
  PeriodFilter _selectedPeriod = PeriodFilter.esteMes;
  String _currency = 'ARS';
  List<String> _availableCurrencies = ['ARS'];
  int _touchedPieIndex = -1;

  // Analítica
  CategoryReportDto? _categoryReport;
  FinancialKpisDto? _kpis;
  List<CashflowItemDto> _cashflow = [];
  List<InstallmentProjectionDto> _commitments = [];

  // Presupuestos y Metas (Fase 5)
  List<BudgetStatusDto> _budgets = [];
  List<SavingGoalDto> _savingGoals = [];
  List<CategoryDto> _categories = [];

  static const _monthNames = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  static const _fullMonthNames = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

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
      final catReport = await getCategorySpendingReport(
        dbPath: _dbPath!,
        startDateMs: startMs,
        endDateMs: endMs,
        currency: _currency,
      );

      final kpis = await getFinancialKpis(
        dbPath: _dbPath!,
        startDateMs: startMs,
        endDateMs: endMs,
        currency: _currency,
      );

      final cashflow = await getMonthlyCashflowHistory(
        dbPath: _dbPath!,
        currency: _currency,
        monthsLimit: 6,
      );

      final commitments = await getInstallmentCommitments(
        dbPath: _dbPath!,
        currency: _currency,
      );

      final budgets = await listBudgetsStatus(
        dbPath: _dbPath!,
        startDateMs: startMs,
        endDateMs: endMs,
        currency: _currency,
      );

      final savingGoals = await listSavingGoals(dbPath: _dbPath!);
      final categories = await listCategories(dbPath: _dbPath!);

      if (!mounted) return;
      setState(() {
        _categoryReport = catReport;
        _kpis = kpis;
        _cashflow = cashflow;
        _commitments = commitments;
        _budgets = budgets;
        _savingGoals = savingGoals;
        _categories = categories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando métricas: $e')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading && _kpis == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Sub-pestañas: Analítica, Presupuestos, Metas
          Container(
            color: theme.colorScheme.surface,
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.insights_rounded, size: 20), text: 'Analítica'),
                Tab(icon: Icon(Icons.account_balance_wallet_outlined, size: 20), text: 'Presupuestos'),
                Tab(icon: Icon(Icons.flag_outlined, size: 20), text: 'Metas'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAnalyticsTab(theme),
                _buildBudgetsTab(theme),
                _buildGoalsTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TAB 1: Analítica y Gráficos
  // ==========================================================================

  Widget _buildAnalyticsTab(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Selectores superiores: Moneda y Período
          _buildCurrencyAndPeriodSelectors(theme),
          const SizedBox(height: 12),

          // KPIs Clave
          if (_kpis != null) _buildKpiGrid(_kpis!, theme),
          const SizedBox(height: 16),

          // Sección 1: Desglose de Gastos por Categoría
          _buildCategoryCard(theme),
          const SizedBox(height: 16),

          // Sección 2: Flujo Mensual (Ingresos vs Gastos)
          _buildCashflowCard(theme),
          const SizedBox(height: 16),

          // Sección 3: Compromisos de Cuotas Futuras
          _buildInstallmentsCard(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
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

  Widget _buildKpiGrid(FinancialKpisDto k, ThemeData theme) {
    final colors = context.mnColors;
    final netColor = k.netSavings >= 0 ? colors.income : colors.expense;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                'Ingresos',
                _formatAmount(k.totalIncome),
                Icons.arrow_downward_rounded,
                colors.income,
                theme,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKpiCard(
                'Gastos',
                _formatAmount(k.totalExpense),
                Icons.arrow_upward_rounded,
                colors.expense,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                'Balance Neto',
                _formatAmount(k.netSavings),
                k.netSavings >= 0 ? Icons.savings_rounded : Icons.trending_down_rounded,
                netColor,
                theme,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKpiCard(
                'Tasa de Ahorro',
                '${k.savingsRate.toStringAsFixed(1)}%',
                Icons.pie_chart_rounded,
                theme.colorScheme.primary,
                theme,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return MnCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(ThemeData theme) {
    final items = _categoryReport?.items ?? [];
    final hasData = items.isNotEmpty && (_categoryReport?.totalAmount ?? 0) > 0;

    return MnCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gastos por Categoría',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (hasData)
                Text(
                  _formatAmount(_categoryReport!.totalAmount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.mnColors.expense,
                  ),
                ),
            ],
          ),
            const SizedBox(height: 16),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.pie_chart_outline, size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        'Sin gastos registrados en este período',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 180,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedPieIndex = -1;
                            return;
                          }
                          _touchedPieIndex =
                              pieTouchResponse.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: List.generate(items.length, (i) {
                      final item = items[i];
                      final isTouched = i == _touchedPieIndex;
                      final radius = isTouched ? 56.0 : 46.0;
                      final color = _parseColor(item.color);
                      return PieChartSectionData(
                        color: color,
                        value: item.totalAmount,
                        title: '${item.percentage.toStringAsFixed(0)}%',
                        radius: radius,
                        titleStyle: TextStyle(
                          fontSize: isTouched ? 14 : 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 2)
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final color = _parseColor(item.color);
                  final isTouched = i == _touchedPieIndex;

                  return Container(
                    decoration: BoxDecoration(
                      color: isTouched
                          ? theme.colorScheme.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withValues(alpha: 0.2),
                          child: Icon(_getCategoryIcon(item.icon), size: 18, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (item.percentage / 100).clamp(0.0, 1.0),
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(color),
                                  minHeight: 5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.percentage.toStringAsFixed(1)}% · ${item.transactionCount} mov.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatAmount(item.totalAmount),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );
    }

  Widget _buildCashflowCard(ThemeData theme) {
    final hasData = _cashflow.isNotEmpty;
    final colors = context.mnColors;

    return MnCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Flujo de Caja Mensual',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _buildLegendDot(colors.income, 'Ingresos'),
                  const SizedBox(width: 8),
                  _buildLegendDot(colors.expense, 'Gastos'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No hay suficientes datos mensuales',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 190,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxY(_cashflow),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = _cashflow[groupIndex];
                        final isIncome = rodIndex == 0;
                        final amount = isIncome ? item.incomeAmount : item.expenseAmount;
                        final title = isIncome ? 'Ingreso' : 'Gasto';
                        return BarTooltipItem(
                          '$title: ${_formatAmount(amount)}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _cashflow.length) {
                            return const SizedBox.shrink();
                          }
                          final item = _cashflow[idx];
                          final monthLabel = (item.month >= 1 && item.month <= 12)
                              ? _monthNames[item.month - 1]
                              : '${item.month}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              monthLabel,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _getGridInterval(_cashflow),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(_cashflow.length, (i) {
                    final item = _cashflow[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: item.incomeAmount,
                          color: colors.income,
                          width: 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: item.expenseAmount,
                          color: colors.expense,
                          width: 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _getMaxY(List<CashflowItemDto> list) {
    double m = 0;
    for (final it in list) {
      if (it.incomeAmount > m) m = it.incomeAmount;
      if (it.expenseAmount > m) m = it.expenseAmount;
    }
    return m == 0 ? 100 : m * 1.2;
  }

  double _getGridInterval(List<CashflowItemDto> list) {
    final max = _getMaxY(list);
    return max > 0 ? max / 4 : 25;
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildInstallmentsCard(ThemeData theme) {
    final hasData = _commitments.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Cuotas Pendientes a Vencer',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Compromiso de pagos futuros en tarjetas de crédito',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No tenés cuotas pendientes registradas',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _commitments.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, i) {
                  final c = _commitments[i];
                  final monthStr = (c.cycleMonth >= 1 && c.cycleMonth <= 12)
                      ? _fullMonthNames[c.cycleMonth - 1]
                      : 'Mes ${c.cycleMonth}';

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.calendar_month,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$monthStr ${c.cycleYear}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${c.count} ${c.count == 1 ? "cuota" : "cuotas"}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        _formatAmount(c.totalAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB 2: Presupuestos por Categoría (Fase 5)
  // ==========================================================================

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

  // ==========================================================================
  // TAB 3: Metas de Ahorro (Fase 5)
  // ==========================================================================

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
          _buildCurrencyAndPeriodSelectors(theme),
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
                            Text(
                              'Ahorrado: ${_formatAmount(g.currentAmount)} (${g.progressPercentage.toStringAsFixed(1)}%)',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            Text(
                              isCompleted ? '¡Meta alcanzada!' : 'Faltan: ${_formatAmount(remaining)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isCompleted ? context.mnColors.income : theme.colorScheme.onSurfaceVariant,
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
}
