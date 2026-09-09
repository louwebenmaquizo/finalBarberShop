import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

class CatalogService {
  CatalogService._();

  static List<Map<String, dynamic>>? _cachedServices;
  static DateTime? _servicesCacheTime;
  static List<Map<String, dynamic>>? _cachedCategories;
  static DateTime? _categoriesCacheTime;
  static const Duration _cacheTtl = Duration(minutes: 2);

  static void invalidateCache() {
    _cachedServices = null;
    _servicesCacheTime = null;
    _cachedCategories = null;
    _categoriesCacheTime = null;
  }

  static Future<List<Map<String, dynamic>>> getAllServices({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedServices != null &&
        _servicesCacheTime != null &&
        DateTime.now().difference(_servicesCacheTime!) < _cacheTtl) {
      return _cachedServices!;
    }

    List<Map<String, dynamic>> rawList;
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.serviceCatalogView)
          .select()
          .order('name');
      final rows = SupabaseServiceHelpers.asMapList(data);
      rawList = await Future.wait(rows.map(_normalizeService));
    } catch (error) {
      if (!SupabaseServiceHelpers.isMissingDatabaseObject(error)) return [];
      try {
        final data = await SupabaseConfig.client
            .from(SupabaseConfig.servicesTable)
            .select()
            .order('name');
        rawList = await Future.wait(
          SupabaseServiceHelpers.asMapList(data).map(_normalizeService),
        );
      } catch (_) {
        return [];
      }
    }

    // Deduplicate services by unique ID and normalized name
    final seenIds = <String>{};
    final seenNames = <String>{};
    final uniqueServices = <Map<String, dynamic>>[];

    for (final s in rawList) {
      final id = (s['service_id'] ?? s['id'] ?? '').toString();
      final name = (s['name'] ?? '').toString().trim().toLowerCase();

      if (id.isNotEmpty && seenIds.contains(id)) continue;
      if (name.isNotEmpty && seenNames.contains(name)) continue;

      if (id.isNotEmpty) seenIds.add(id);
      if (name.isNotEmpty) seenNames.add(name);
      uniqueServices.add(s);
    }

    _cachedServices = uniqueServices;
    _servicesCacheTime = DateTime.now();

    return uniqueServices;
  }

  static Future<Map<String, dynamic>> _normalizeService(
    Map<String, dynamic> row,
  ) async {
    final service = Map<String, dynamic>.from(row);
    service['service_id'] = service['service_id'] ?? service['id'];
    service['category_id'] =
        service['category_id'] ?? service['service_category_id'];
    service['category_name'] = service['category_name'] ??
        SupabaseServiceHelpers.asMap(service['service_categories'])['name'];
    service['duration_minutes'] =
        SupabaseServiceHelpers.asInt(service['duration_minutes'], 30);
    service['price'] = SupabaseServiceHelpers.asDouble(service['price']);
    service['cost'] = service['cost'] == null
        ? null
        : SupabaseServiceHelpers.asDouble(service['cost']);
    service['is_active'] =
        SupabaseServiceHelpers.asBool(service['is_active']) ? 1 : 0;

    final image = await SupabaseStorageService.resolveReference(
      bucket: SupabaseConfig.serviceImagesBucket,
      value: service['image_url'] ?? service['photo'],
      isPublic: true,
    );
    service['image_url'] = image;
    service['photo'] = image;
    return service;
  }

  static Future<List<Map<String, dynamic>>> searchServices(String query) async {
    final services = await getAllServices();
    if (query.trim().isEmpty) return services;
    final needle = query.toLowerCase();
    return services.where((service) {
      return const ['name', 'description', 'category_name'].any(
        (field) =>
            (service[field] ?? '').toString().toLowerCase().contains(needle),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>?> getServiceById(String serviceId) async {
    // Check cached services first for instant lookup
    if (_cachedServices != null) {
      for (final s in _cachedServices!) {
        if ((s['service_id'] ?? s['id']) == serviceId) return s;
      }
    }

    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.serviceCatalogView)
          .select()
          .eq('service_id', serviceId)
          .maybeSingle();
      final row = SupabaseServiceHelpers.asMap(data);
      return row.isEmpty ? null : _normalizeService(row);
    } catch (error) {
      if (!SupabaseServiceHelpers.isMissingDatabaseObject(error)) return null;
      try {
        final data = await SupabaseConfig.client
            .from(SupabaseConfig.servicesTable)
            .select()
            .eq('id', serviceId)
            .maybeSingle();
        final row = SupabaseServiceHelpers.asMap(data);
        return row.isEmpty ? null : _normalizeService(row);
      } catch (_) {
        return null;
      }
    }
  }

  static Future<Map<String, dynamic>> createService(
    Map<String, dynamic> serviceData,
  ) async {
    try {
      final name = serviceData['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        return {
          'success': false,
          'message': 'Service name cannot be empty',
        };
      }

      // Check for duplicate service name
      final existingServices = await getAllServices();
      final duplicate = existingServices.any((s) =>
          (s['name'] ?? '').toString().trim().toLowerCase() ==
          name.toLowerCase());
      if (duplicate) {
        return {
          'success': false,
          'message': 'A service named "$name" already exists in the catalog.',
        };
      }

      final rawImage = serviceData['image_url'] ?? serviceData['photo'];
      final insert = _serviceMutationFields(serviceData)..remove('image_url');
      insert['name'] = name;

      final inserted = await SupabaseConfig.client
          .from(SupabaseConfig.servicesTable)
          .insert(insert)
          .select()
          .single();
      final row = SupabaseServiceHelpers.asMap(inserted);
      final serviceId = (row['id'] ?? '').toString();
      String? imageReference;
      String? warning;

      if (SupabaseStorageService.isDataImage(rawImage)) {
        try {
          imageReference = await SupabaseStorageService.uploadDataImage(
            bucket: SupabaseConfig.serviceImagesBucket,
            ownerId: serviceId,
            dataUri: rawImage.toString(),
          );
          if (imageReference != null) {
            await SupabaseConfig.client
                .from(SupabaseConfig.servicesTable)
                .update({'image_url': imageReference}).eq('id', serviceId);
          }
        } catch (error) {
          warning = 'Service was created, but its image could not be uploaded: '
              '${SupabaseServiceHelpers.errorMessage(error)}';
        }
      } else if (rawImage != null && rawImage.toString().isNotEmpty) {
        imageReference = rawImage.toString();
        await SupabaseConfig.client
            .from(SupabaseConfig.servicesTable)
            .update({'image_url': imageReference}).eq('id', serviceId);
      }

      invalidateCache();

      return {
        'success': true,
        'message': warning ?? 'Service created successfully',
        'data': {
          ...row,
          'service_id': serviceId,
          'image_url': imageReference,
        },
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> updateService(
    String serviceId,
    Map<String, dynamic> serviceData,
  ) async {
    try {
      final name = serviceData['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        // Check for duplicate name under a different service ID
        final existingServices = await getAllServices();
        final duplicate = existingServices.any((s) {
          final sId = (s['service_id'] ?? s['id'] ?? '').toString();
          final sName = (s['name'] ?? '').toString().trim().toLowerCase();
          return sId != serviceId && sName == name.toLowerCase();
        });
        if (duplicate) {
          return {
            'success': false,
            'message': 'Another service with the name "$name" already exists.',
          };
        }
      }

      final update = _serviceMutationFields(serviceData);
      final rawImage = update['image_url'];
      if (SupabaseStorageService.isDataImage(rawImage)) {
        update['image_url'] = await SupabaseStorageService.uploadDataImage(
          bucket: SupabaseConfig.serviceImagesBucket,
          ownerId: serviceId,
          dataUri: rawImage.toString(),
        );
      } else if (rawImage == '') {
        update['image_url'] = null;
      }

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.servicesTable)
          .update(update)
          .eq('id', serviceId)
          .select()
          .single();
      final row = SupabaseServiceHelpers.asMap(data);

      invalidateCache();

      return {
        'success': true,
        'message': 'Service updated successfully',
        'data': {...row, 'service_id': row['id'] ?? serviceId},
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Map<String, dynamic> _serviceMutationFields(
    Map<String, dynamic> source,
  ) {
    final result = <String, dynamic>{};
    for (final field in const [
      'name',
      'category_id',
      'duration_minutes',
      'price',
      'cost',
      'description',
      'image_url',
      'is_active',
    ]) {
      if (source.containsKey(field)) result[field] = source[field];
    }
    return result;
  }

  static Future<Map<String, dynamic>> deleteService(String serviceId) async {
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.servicesTable)
          .update({'is_active': false})
          .eq('id', serviceId)
          .select()
          .single();
      invalidateCache();
      return {
        'success': true,
        'message': 'Service deactivated successfully',
        'data': data,
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<List<Map<String, dynamic>>> getAllCategories({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedCategories != null &&
        _categoriesCacheTime != null &&
        DateTime.now().difference(_categoriesCacheTime!) < _cacheTtl) {
      return _cachedCategories!;
    }

    List<Map<String, dynamic>> rawCategories;
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.categoryCatalogView)
          .select()
          .order('name');
      rawCategories = SupabaseServiceHelpers.asMapList(data).map((row) {
        return {
          'category_id': row['category_id'] ?? row['id'] ?? '',
          'name': row['name'] ?? '',
          'description': row['description'],
          'service_count': SupabaseServiceHelpers.asInt(row['service_count']),
        };
      }).toList();
    } catch (error) {
      if (!SupabaseServiceHelpers.isMissingDatabaseObject(error)) return [];
      try {
        final data = await SupabaseConfig.client
            .from(SupabaseConfig.categoriesTable)
            .select()
            .order('name');
        rawCategories = SupabaseServiceHelpers.asMapList(data).map((row) {
          return {
            'category_id': row['id'] ?? '',
            'name': row['name'] ?? '',
            'description': row['description'],
            'service_count': 0,
          };
        }).toList();
      } catch (_) {
        return [];
      }
    }

    // Deduplicate categories by normalized name
    final seenNames = <String>{};
    final uniqueCategories = <Map<String, dynamic>>[];

    for (final c in rawCategories) {
      final name = (c['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty && seenNames.contains(name)) continue;
      if (name.isNotEmpty) seenNames.add(name);
      uniqueCategories.add(c);
    }

    _cachedCategories = uniqueCategories;
    _categoriesCacheTime = DateTime.now();

    return uniqueCategories;
  }

  static Future<Map<String, dynamic>> createCategory(
    String name,
    String? description,
  ) async {
    try {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) {
        return {
          'success': false,
          'message': 'Category name cannot be empty',
        };
      }

      final existingCategories = await getAllCategories();
      if (existingCategories.any((c) =>
          (c['name'] ?? '').toString().trim().toLowerCase() ==
          trimmedName.toLowerCase())) {
        return {
          'success': false,
          'message': 'Category "$trimmedName" already exists.',
        };
      }

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.categoriesTable)
          .insert({'name': trimmedName, 'description': description})
          .select()
          .single();
      final row = SupabaseServiceHelpers.asMap(data);

      invalidateCache();

      return {
        'success': true,
        'message': 'Category created successfully',
        'data': {...row, 'category_id': row['id']},
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> updateCategory(
    String categoryId,
    String name,
    String? description,
  ) async {
    try {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) {
        return {
          'success': false,
          'message': 'Category name cannot be empty',
        };
      }

      final existingCategories = await getAllCategories();
      final duplicate = existingCategories.any((c) {
        final cId = (c['category_id'] ?? c['id'] ?? '').toString();
        final cName = (c['name'] ?? '').toString().trim().toLowerCase();
        return cId != categoryId && cName == trimmedName.toLowerCase();
      });
      if (duplicate) {
        return {
          'success': false,
          'message': 'Category "$trimmedName" already exists.',
        };
      }

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.categoriesTable)
          .update({'name': trimmedName, 'description': description})
          .eq('id', categoryId)
          .select()
          .single();
      final row = SupabaseServiceHelpers.asMap(data);

      invalidateCache();

      return {
        'success': true,
        'message': 'Category updated successfully',
        'data': {...row, 'category_id': row['id'] ?? categoryId},
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> deleteCategory(
    String categoryId,
  ) async {
    try {
      await SupabaseConfig.client
          .from(SupabaseConfig.categoriesTable)
          .delete()
          .eq('id', categoryId);
      invalidateCache();
      return {
        'success': true,
        'message': 'Category deleted successfully',
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }
}
