import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/catalog_service.dart';

/// Modal dialog to quickly add a new service category
Future<Map<String, dynamic>?> showAddCategoryDialog(
  BuildContext context, {
  Function(Map<String, dynamic>)? onCategoryCreated,
}) async {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSaving = false;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x1A5BBCFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.category,
                  color: Color(0xFF1E88E5), size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Add New Category',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create a category to group and organize your barber services.',
                style:
                    GoogleFonts.manrope(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Category Name *',
                  hintText: 'e.g. Haircuts, Beard Care, Facial Spa',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                style: GoogleFonts.manrope(),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please enter category name'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Brief summary of services in this category',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
                maxLines: 2,
                style: GoogleFonts.manrope(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: isSaving
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    final name = nameController.text.trim();
                    final desc = descriptionController.text.trim();

                    // Pre-check existing categories
                    try {
                      final existing = await CatalogService.getAllCategories();
                      if (existing.any((c) =>
                          (c['name'] ?? '').toString().trim().toLowerCase() ==
                          name.toLowerCase())) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'A category named "$name" already exists.'),
                              backgroundColor: Colors.orange[800],
                            ),
                          );
                        }
                        return;
                      }
                    } catch (_) {}

                    setState(() => isSaving = true);
                    final result = await CatalogService.createCategory(
                        name, desc.isEmpty ? null : desc);

                    if (result['success'] == true) {
                      final newCat = {
                        'category_id': result['data']?['category_id'] ?? '',
                        'name': name,
                        'description': desc,
                      };
                      if (onCategoryCreated != null) {
                        onCategoryCreated(newCat);
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, newCat);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Category "$name" created successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } else {
                      setState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result['message'] ??
                                'Failed to create category'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5BBCFF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    'Save Category',
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
          ),
        ],
      ),
    ),
  );
}

/// Manage all categories (view list, edit names, delete)
void showManageCategoriesDialog(BuildContext context,
    {VoidCallback? onChanged}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: CatalogService.getAllCategories(),
          builder: (context, snapshot) {
            final categories = snapshot.data ?? [];
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;

            return Container(
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Service Categories',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'Organize services into clear categories',
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Add New Category Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final created = await showAddCategoryDialog(context);
                        if (created != null) {
                          setSheetState(() {});
                          if (onChanged != null) onChanged();
                        }
                      },
                      icon: const Icon(Icons.add, color: Color(0xFF1E88E5)),
                      label: Text(
                        'Add New Category',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E88E5),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFF5BBCFF)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // List of Categories
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : categories.isEmpty
                            ? Center(
                                child: Text(
                                  'No categories found. Tap above to create one.',
                                  style: GoogleFonts.manrope(
                                      color: Colors.grey[500]),
                                ),
                              )
                            : ListView.separated(
                                itemCount: categories.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final cat = categories[index];
                                  final catId = cat['category_id'] ?? '';
                                  final name = cat['name'] ?? 'Unnamed';
                                  final count = cat['service_count'] ?? 0;
                                  final desc = cat['description'] ?? '';

                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0x1A5BBCFF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.category,
                                          color: Color(0xFF1E88E5), size: 20),
                                    ),
                                    title: Text(
                                      name,
                                      style: GoogleFonts.manrope(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    subtitle: Text(
                                      desc.isNotEmpty
                                          ? desc
                                          : '$count service(s) attached',
                                      style: GoogleFonts.manrope(
                                          fontSize: 12,
                                          color: Colors.grey[600]),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Edit Category
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              size: 18, color: Colors.black54),
                                          onPressed: () {
                                            _showEditCategoryDialog(
                                                context, cat, () {
                                              setSheetState(() {});
                                              if (onChanged != null)
                                                onChanged();
                                            });
                                          },
                                        ),
                                        // Delete Category
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18, color: Colors.red),
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text('Delete Category',
                                                    style: GoogleFonts.manrope(
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                content: Text(
                                                    'Are you sure you want to delete "$name"? Services under this category will become unassigned.',
                                                    style:
                                                        GoogleFonts.manrope()),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                      child:
                                                          const Text('Cancel')),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, true),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                            backgroundColor:
                                                                Colors.red),
                                                    child: const Text('Delete',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.white)),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              await CatalogService
                                                  .deleteCategory(catId);
                                              setSheetState(() {});
                                              if (onChanged != null)
                                                onChanged();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

void _showEditCategoryDialog(BuildContext context,
    Map<String, dynamic> category, VoidCallback onUpdated) {
  final nameController = TextEditingController(text: category['name']);
  final descController =
      TextEditingController(text: category['description'] ?? '');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Edit Category',
          style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Category Name',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descController,
            decoration: InputDecoration(
              labelText: 'Description',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final name = nameController.text.trim();
            final desc = descController.text.trim();

            if (name.isEmpty) return;

            // Check duplicate
            try {
              final existing = await CatalogService.getAllCategories();
              if (existing.any((c) =>
                  (c['name'] ?? '').toString().trim().toLowerCase() ==
                      name.toLowerCase() &&
                  c['category_id'] != category['category_id'])) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Another category named "$name" already exists.'),
                      backgroundColor: Colors.orange[800],
                    ),
                  );
                }
                return;
              }
            } catch (_) {}

            Navigator.pop(ctx);
            final result = await CatalogService.updateCategory(
              category['category_id'],
              name,
              desc.isEmpty ? null : desc,
            );
            if (result['success'] == true) {
              onUpdated();
            } else if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text(result['message'] ?? 'Failed to update category'),
                    backgroundColor: Colors.red),
              );
            }
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5BBCFF)),
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
