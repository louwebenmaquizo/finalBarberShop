import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';

class SupabaseServiceHelpers {
  SupabaseServiceHelpers._();

  static SupabaseClient get client => SupabaseConfig.client;

  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> asMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map(asMap).where((row) => row.isNotEmpty).toList();
  }

  static String errorMessage(Object error) {
    if (error is AuthException) return error.message;
    if (error is PostgrestException) return error.message;
    if (error is StorageException) return error.message;
    if (error is FunctionException) {
      if (error.details is Map) {
        final detailsMap = error.details as Map;
        if (detailsMap.containsKey('error')) {
          return detailsMap['error'].toString();
        }
        if (detailsMap.containsKey('message')) {
          return detailsMap['message'].toString();
        }
      }
      if (error.reasonPhrase != null && error.reasonPhrase!.isNotEmpty) {
        return error.reasonPhrase!;
      }
    }

    final text = error.toString();
    if (text.contains('details: {error: ')) {
      final match = RegExp(r'details:\s*\{error:\s*([^}]+)\}').firstMatch(text);
      if (match != null) return match.group(1)?.trim() ?? text;
    }
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  static Map<String, dynamic> failure(Object error) => {
        'success': false,
        'message': errorMessage(error),
        'error': errorMessage(error),
      };

  static bool isMissingDatabaseObject(Object error) {
    if (error is! PostgrestException) return false;
    return const {
      '42P01', // undefined table/view
      '42883', // undefined function
      'PGRST200', // relationship not found
      'PGRST202', // function not found in schema cache
      'PGRST205', // table not found in schema cache
    }.contains(error.code);
  }

  static DateTime? parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    return parsed?.toLocal();
  }

  static String toUtcIso(dynamic value) {
    final parsed = parseDateTime(value);
    if (parsed == null) return value?.toString() ?? '';
    return parsed.toUtc().toIso8601String();
  }

  static String displayDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} '
        '${value.day.toString().padLeft(2, '0')}, ${value.year}';
  }

  static String displayLongDate(DateTime value) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  static String displayTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
            ? value.hour - 12
            : value.hour;
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')} $suffix';
  }

  static double asDouble(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int asInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool asBool(dynamic value, [bool fallback = true]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return fallback;
  }
}

class SupabaseStorageService {
  SupabaseStorageService._();

  static bool isDataImage(dynamic value) =>
      value is String && value.trim().startsWith('data:image/');

  static _DecodedImage? _decodeImage(String dataUri) {
    try {
      final trimmed = dataUri.trim();
      final comma = trimmed.indexOf(',');
      final header = comma >= 0 ? trimmed.substring(0, comma) : '';
      final encoded = comma >= 0 ? trimmed.substring(comma + 1) : trimmed;
      final mimeMatch = RegExp(r'data:(image/[^;]+)').firstMatch(header);
      final mime = mimeMatch?.group(1) ?? 'image/jpeg';
      if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
        return null;
      }
      final extension = switch (mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
      return _DecodedImage(
        bytes: Uint8List.fromList(base64Decode(encoded)),
        mimeType: mime,
        extension: extension,
      );
    } catch (_) {
      return null;
    }
  }

  /// Uploads a base64 data URI and returns the object path stored in the DB.
  static Future<String?> uploadDataImage({
    required String bucket,
    required String ownerId,
    required String dataUri,
  }) async {
    final decoded = _decodeImage(dataUri);
    if (decoded == null) {
      throw const FormatException('The selected image could not be decoded.');
    }

    final safeOwner = ownerId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = '$safeOwner/avatar_${DateTime.now().microsecondsSinceEpoch}.'
        '${decoded.extension}';

    await SupabaseConfig.client.storage.from(bucket).uploadBinary(
          path,
          decoded.bytes,
          fileOptions: FileOptions(
            contentType: decoded.mimeType,
            upsert: true,
          ),
        );
    return path;
  }

  static final Map<String, String> _urlCache = {};

  /// Turns a stored object path into a URL understood by the existing widgets.
  static Future<String?> resolveReference({
    required String bucket,
    required dynamic value,
    required bool isPublic,
    int signedUrlLifetimeSeconds = 3600,
  }) async {
    if (value == null) return null;
    final reference = value.toString().trim();
    if (reference.isEmpty) return null;
    if (reference.startsWith('http://') ||
        reference.startsWith('https://') ||
        reference.startsWith('data:image/') ||
        reference.startsWith('assets/')) {
      return reference;
    }

    final cacheKey = '$bucket:$reference:$isPublic';
    if (_urlCache.containsKey(cacheKey)) {
      return _urlCache[cacheKey];
    }

    try {
      final storage = SupabaseConfig.client.storage.from(bucket);
      final resolved = isPublic
          ? storage.getPublicUrl(reference)
          : await storage.createSignedUrl(reference, signedUrlLifetimeSeconds);
      if (resolved.isNotEmpty) {
        _urlCache[cacheKey] = resolved;
      }
      return resolved;
    } catch (_) {
      // Preserve legacy values so existing data can still use its fallback UI.
      return reference;
    }
  }
}

class _DecodedImage {
  const _DecodedImage({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;
}
