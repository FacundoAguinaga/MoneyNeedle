import 'package:flutter/material.dart';
import '../rust/api.dart/api.dart';
import 'mn_card.dart';
import 'mn_category_icon.dart';

/// Tarjeta de propuesta interactiva con chips y campos editables pre-confirmación.
class NlpProposalCard extends StatefulWidget {
  final String rawPrompt;
  final ProposalDto proposal;
  final List<AccountDto> accounts;
  final List<CategoryDto> categories;
  final String? initialAccountId;
  final bool isConfirming;
  final Function({
    required String tipo,
    required double monto,
    required String categoria,
    required String fecha,
    required String? accountId,
    required int cuotas,
  }) onConfirm;
  final VoidCallback onDiscard;

  const NlpProposalCard({
    super.key,
    required this.rawPrompt,
    required this.proposal,
    required this.accounts,
    required this.categories,
    this.initialAccountId,
    this.isConfirming = false,
    required this.onConfirm,
    required this.onDiscard,
  });

  @override
  State<NlpProposalCard> createState() => _NlpProposalCardState();
}

class _NlpProposalCardState extends State<NlpProposalCard> {
  late TextEditingController _amountController;
  late String _tipo;
  late String _categoria;
  late String _fecha;
  late String? _accountId;
  int _cuotas = 1;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.proposal.monto > 0
          ? widget.proposal.monto.toStringAsFixed(0)
          : '',
    );
    _tipo = widget.proposal.tipo.toLowerCase() == 'ingreso' ? 'ingreso' : 'gasto';
    _categoria = widget.proposal.categoria;
    _fecha = widget.proposal.fecha.isNotEmpty
        ? widget.proposal.fecha
        : DateTime.now().toIso8601String().substring(0, 10);
    _accountId = widget.initialAccountId ??
        (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    DateTime initial = DateTime.tryParse(_fecha) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _fecha = picked.toIso8601String().substring(0, 10);
      });
    }
  }

  void _submit() {
    final parsed = double.tryParse(_amountController.text.replaceAll(',', '.')) ??
        widget.proposal.monto;
    if (parsed <= 0) return;

    widget.onConfirm(
      tipo: _tipo,
      monto: parsed,
      categoria: _categoria,
      fecha: _fecha,
      accountId: _accountId,
      cuotas: _cuotas,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedAccount =
        widget.accounts.where((a) => a.id == _accountId).firstOrNull;
    final isCard = selectedAccount?.accountType.toLowerCase() == 'credit_card';

    // Lista de categorías disponibles (las del sistema o las provistas)
    final catList = widget.categories.map((c) => c.name).toList();
    if (!catList.contains(_categoria)) {
      catList.add(_categoria);
    }

    return MnCard(
      padding: const EdgeInsets.all(16),
      borderColor: colorScheme.primary,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header con ícono, categoría y frase original
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MnCategoryIcon(category: _categoria, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.rawPrompt,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Propuesta de IA · Verificá los campos',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Descartar',
                onPressed: widget.onDiscard,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Fila de Chips Editables: Tipo, Categoría, Cuenta
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Tipo (Gasto / Ingreso)
              InputChip(
                avatar: Icon(
                  _tipo == 'gasto' ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: _tipo == 'gasto' ? Colors.red : Colors.green,
                ),
                label: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _tipo,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'gasto', child: Text('Gasto')),
                      DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _tipo = val);
                    },
                  ),
                ),
              ),

              // Categoría
              InputChip(
                avatar: const Icon(Icons.category_outlined, size: 16),
                label: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _categoria,
                    isDense: true,
                    items: catList.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _categoria = val);
                    },
                  ),
                ),
              ),

              // Cuenta
              if (widget.accounts.isNotEmpty)
                InputChip(
                  avatar: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                  label: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _accountId,
                      isDense: true,
                      items: widget.accounts.map((acc) {
                        return DropdownMenuItem(
                          value: acc.id,
                          child: Text('${acc.name} (${acc.currency})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _accountId = val);
                      },
                    ),
                  ),
                ),

              // Fecha
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 15),
                label: Text(_fecha),
                onPressed: _selectDate,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Campos: Monto y Cuotas
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Monto (${widget.proposal.moneda})',
                    prefixText: '\$ ',
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              if (isCard) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: _cuotas,
                    decoration: const InputDecoration(
                      labelText: 'Cuotas',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [1, 2, 3, 6, 9, 12, 18, 24].map((n) {
                      return DropdownMenuItem(
                        value: n,
                        child: Text(n == 1 ? '1 cuota' : '$n cuotas'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _cuotas = val);
                    },
                  ),
                ),
              ],
            ],
          ),

          // Advertencia de No Grounded
          if (!widget.proposal.grounded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El monto no apareció literal en tu frase. Verificá que sea correcto.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Botones de acción
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.isConfirming ? null : _submit,
                  icon: widget.isConfirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 20),
                  label: Text(
                    widget.isConfirming ? 'Confirmando...' : 'Confirmar movimiento',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: widget.onDiscard,
                child: const Text('Descartar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
