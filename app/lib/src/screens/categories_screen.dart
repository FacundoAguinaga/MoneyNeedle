import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/vault_service.dart';
import '../rust/api.dart/api.dart';
import '../widgets/widgets.dart';

/// Pantalla para gestionar y personalizar categorías financieras.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String? _dbPath;
  List<CategoryDto> _categories = [];
  bool _loading = true;

  static const List<Map<String, dynamic>> _availableIcons = [
    {'name': 'fastfood', 'icon': Icons.fastfood, 'label': 'Comida'},
    {'name': 'directions_car', 'icon': Icons.directions_car, 'label': 'Transporte'},
    {'name': 'home', 'icon': Icons.home, 'label': 'Hogar'},
    {'name': 'local_hospital', 'icon': Icons.local_hospital, 'label': 'Salud'},
    {'name': 'school', 'icon': Icons.school, 'label': 'Educación'},
    {'name': 'sports_esports', 'icon': Icons.sports_esports, 'label': 'Ocio'},
    {'name': 'shopping_bag', 'icon': Icons.shopping_bag, 'label': 'Compras'},
    {'name': 'fitness_center', 'icon': Icons.fitness_center, 'label': 'Gimnasio'},
    {'name': 'flight', 'icon': Icons.flight, 'label': 'Viajes'},
    {'name': 'pets', 'icon': Icons.pets, 'label': 'Mascotas'},
    {'name': 'work', 'icon': Icons.work, 'label': 'Trabajo'},
    {'name': 'subscriptions', 'icon': Icons.subscriptions, 'label': 'Streaming'},
    {'name': 'build', 'icon': Icons.build, 'label': 'Reparaciones'},
    {'name': 'card_giftcard', 'icon': Icons.card_giftcard, 'label': 'Regalos'},
    {'name': 'savings', 'icon': Icons.savings, 'label': 'Ahorro'},
    {'name': 'receipt_long', 'icon': Icons.receipt_long, 'label': 'Impuestos'},
  ];

  static const List<String> _availableColors = [
    '#00695C', // Teal
    '#1976D2', // Azul
    '#388E3C', // Verde
    '#F57C00', // Naranja
    '#D32F2F', // Rojo
    '#7B1FA2', // Púrpura
    '#C2185B', // Rosa
    '#0097A7', // Cian
    '#5D4037', // Marrón
    '#455A64', // Gris azulado
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final path = await VaultService.getDbPath();
      final cats = await listCategories(dbPath: path);
      if (!mounted) return;
      setState(() {
        _dbPath = path;
        _categories = cats;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCategoryDialog({CategoryDto? categoryToEdit}) async {
    final isEditing = categoryToEdit != null;
    final nameCtrl = TextEditingController(text: categoryToEdit?.name ?? '');
    String selectedIcon = categoryToEdit?.icon ?? 'fastfood';
    String selectedColor = categoryToEdit?.color ?? '#00695C';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar categoría' : 'Nueva categoría'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: !isEditing,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la categoría',
                        hintText: 'Ej. Mascotas, Gimnasio, etc.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Ícono', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: GridView.builder(
                        gridDelegate: const RadialGridDelegate(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _availableIcons.length,
                        itemBuilder: (context, index) {
                          final item = _availableIcons[index];
                          final isSelected = item['name'] == selectedIcon;
                          return InkWell(
                            onTap: () => setDialogState(() => selectedIcon = item['name']),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                item['icon'] as IconData,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableColors.map((hex) {
                        final color = MnColorUtils.parseHex(hex);
                        final isSelected = hex == selectedColor;
                        return InkWell(
                          onTap: () => setDialogState(() => selectedColor = hex),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black87 : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 18, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    setState(() => _loading = true);

                    try {
                      if (isEditing) {
                        await updateCategory(
                          dbPath: _dbPath!,
                          categoryId: categoryToEdit.id,
                          name: name,
                          icon: selectedIcon,
                          color: selectedColor,
                        );
                      } else {
                        await createCategory(
                          dbPath: _dbPath!,
                          name: name,
                          icon: selectedIcon,
                          color: selectedColor,
                          parentId: null,
                        );
                      }
                      await _load();
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error guardando categoría: $e')),
                        );
                        setState(() => _loading = false);
                      }
                    }
                  },
                  child: Text(isEditing ? 'Guardar' : 'Crear'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _eliminarCategoria(CategoryDto cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar categoría?'),
        content: Text(
          'Se eliminará la categoría "${cat.name}". Las transacciones asociadas conservarán su registro histórico.',
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
      await deleteCategory(dbPath: _dbPath!, categoryId: cat.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Categoría "${cat.name}" eliminada')),
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

    final systemCats = _categories.where((c) => c.isSystem).toList();
    final customCats = _categories.where((c) => !c.isSystem).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías y Rubros'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (customCats.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      'TUS CATEGORÍAS PERSONALIZADAS',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: customCats.length,
                      separatorBuilder: (context, _) => Divider(
                        height: 1,
                        indent: 64,
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (context, index) {
                        final cat = customCats[index];
                        return ListTile(
                          leading: MnCategoryIcon(
                            category: cat.name,
                            colorHex: cat.color,
                            iconName: cat.icon,
                            radius: 20,
                          ),
                          title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _showCategoryDialog(categoryToEdit: cat),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                                onPressed: () => _eliminarCategoria(cat),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                  child: Text(
                    'CATEGORÍAS DEL SISTEMA',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: systemCats.length,
                    separatorBuilder: (context, _) => Divider(
                      height: 1,
                      indent: 64,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    itemBuilder: (context, index) {
                      final cat = systemCats[index];
                      return ListTile(
                        leading: MnCategoryIcon(
                          category: cat.name,
                          colorHex: cat.color,
                          iconName: cat.icon,
                          radius: 20,
                        ),
                        title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Sistema',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.selectionClick();
          _showCategoryDialog();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
      ),
    );
  }
}

class RadialGridDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  const RadialGridDelegate({
    required super.crossAxisCount,
    super.mainAxisSpacing = 0.0,
    super.crossAxisSpacing = 0.0,
    super.childAspectRatio = 1.0,
  });
}
