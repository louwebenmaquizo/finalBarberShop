import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
import '../config/shop_info.dart';
import 'catalog_service.dart';
import 'dashboard_service.dart';
import 'employee_service.dart';
import 'supabase_service_helpers.dart';

/// A single chat message — either from the user or the AI assistant.
class AiMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime? createdAt;

  const AiMessage({
    required this.role,
    required this.content,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'created_at': createdAt?.toIso8601String(),
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      role: (json['role'] ?? 'assistant').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal()
          : null,
    );
  }
}

/// Represents a grouped chat session with its full message history
class AiChatSession {
  final String sessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiMessage> messages;

  AiChatSession({
    required this.sessionId,
    required this.createdAt,
    DateTime? updatedAt,
    required this.messages,
  }) : updatedAt = updatedAt ?? createdAt;

  String get previewTitle {
    for (final m in messages) {
      if (m.role == 'user' && m.content.trim().isNotEmpty) {
        final text = m.content.trim();
        return text.length > 50 ? '${text.substring(0, 47)}...' : text;
      }
    }
    return 'New conversation';
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory AiChatSession.fromJson(Map<String, dynamic> json) {
    final rawMsgs = json['messages'] as List? ?? [];
    return AiChatSession(
      sessionId: (json['session_id'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ??
              DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())?.toLocal() ??
              DateTime.now()
          : DateTime.now(),
      messages: rawMsgs.map((m) {
        try {
          return AiMessage.fromJson(Map<String, dynamic>.from(m as Map));
        } catch (_) {
          return null;
        }
      }).whereType<AiMessage>().toList(),
    );
  }
}

/// Offline-First, Cloud-Synced Storage for AI Chat Sessions.
/// Guarantees that chat history works 100% reliably with zero latency.
class AiHistoryStorage {
  static String get _currentUid {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid != null && uid.trim().isNotEmpty) {
      return uid.trim();
    }
    return 'guest';
  }

  static String get _storageKey => 'ai_chat_sessions_v4_$_currentUid';
  static String get _activeSessionKey => 'ai_active_session_id_v4_$_currentUid';
  static String get _deletedSessionsKey => 'ai_deleted_sessions_v4_$_currentUid';
  static String get _lastActivityKey => 'ai_last_activity_ts_v4_$_currentUid';
  static const Duration inactivityTimeout = Duration(minutes: 10);

  /// Records the latest interaction or activity timestamp
  static Future<void> recordActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Checks if 10+ minutes have elapsed since the user last interacted with the AI
  static Future<bool> hasInactivityExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getInt(_lastActivityKey);
      if (lastTs == null) return false;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastTs;
      return elapsed >= inactivityTimeout.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Save or update a session both locally (instant) and to Supabase (cloud sync)
  static Future<void> saveSession(AiChatSession session) async {
    await recordActivity();
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = await loadLocalSessions();

      final idx = sessions.indexWhere((s) => s.sessionId == session.sessionId);
      if (idx >= 0) {
        sessions[idx] = session;
      } else {
        sessions.insert(0, session);
      }

      final encoded = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
      await prefs.setString(_activeSessionKey, session.sessionId);

      // Unmark from deleted if re-created
      final deleted = prefs.getStringList(_deletedSessionsKey) ?? [];
      if (deleted.contains(session.sessionId)) {
        deleted.remove(session.sessionId);
        await prefs.setStringList(_deletedSessionsKey, deleted);
      }
    } catch (e) {
      debugPrint('DEBUG: Error saving local chat session: $e');
    }

    // Sync to Supabase in background
    _syncToSupabase(session);
  }

  /// Load all local sessions immediately (0 ms latency)
  static Future<List<AiChatSession>> loadLocalSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final list = <AiChatSession>[];
        for (final item in decoded) {
          try {
            list.add(AiChatSession.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return list;
      }
    } catch (_) {}
    return [];
  }

  /// Load all sessions: merges local storage with Supabase cloud history
  static Future<List<AiChatSession>> loadAllSessions() async {
    final local = await loadLocalSessions();
    final prefs = await SharedPreferences.getInstance();
    final deleted = (prefs.getStringList(_deletedSessionsKey) ?? []).toSet();

    // In parallel, try pulling from Supabase
    try {
      final cloud = await AiService.loadUserChatSessionsFromSupabase();
      for (final cs in cloud) {
        if (deleted.contains(cs.sessionId)) continue;
        final idx = local.indexWhere((s) => s.sessionId == cs.sessionId);
        if (idx < 0) {
          local.add(cs);
        } else if (cs.messages.length > local[idx].messages.length) {
          local[idx] = cs;
        }
      }
    } catch (_) {}

    local.removeWhere((s) => deleted.contains(s.sessionId));
    local.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return local;
  }

  /// Returns the current active session if it exists, has messages, and is within 10 mins of activity
  static Future<AiChatSession?> getActiveSession() async {
    try {
      final expired = await hasInactivityExpired();
      if (expired) {
        await clearActiveSession();
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final activeId = prefs.getString(_activeSessionKey);
      final all = await loadLocalSessions();
      if (activeId != null && activeId.isNotEmpty) {
        for (final s in all) {
          if (s.sessionId == activeId) return s;
        }
      }
      return all.isNotEmpty && all.first.messages.isNotEmpty ? all.first : null;
    } catch (_) {
      return null;
    }
  }

  /// Set the active session ID so it persists across screen reopens
  static Future<void> setActiveSessionId(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeSessionKey, sessionId);
    } catch (_) {}
  }

  /// Reset active session (for "+ New Chat")
  static Future<void> clearActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeSessionKey);
    } catch (_) {}
  }

  /// Delete a single chat session both locally and in Supabase
  static Future<void> deleteSession(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = await loadLocalSessions();
      sessions.removeWhere((s) => s.sessionId == sessionId);
      await prefs.setString(
          _storageKey, jsonEncode(sessions.map((s) => s.toJson()).toList()));

      final activeId = prefs.getString(_activeSessionKey);
      if (activeId == sessionId) {
        await prefs.remove(_activeSessionKey);
      }

      final deletedList = prefs.getStringList(_deletedSessionsKey) ?? [];
      if (!deletedList.contains(sessionId)) {
        deletedList.add(sessionId);
        await prefs.setStringList(_deletedSessionsKey, deletedList);
      }
    } catch (_) {}

    // Delete from Supabase ai_messages table
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client
            .from('ai_messages')
            .delete()
            .match({'session_id': sessionId, 'user_id': user.id});
      } else {
        await SupabaseConfig.client
            .from('ai_messages')
            .delete()
            .eq('session_id', sessionId);
      }
    } catch (e) {
      debugPrint('Error deleting session from Supabase ai_messages: $e');
    }
  }

  /// Clear all sessions both locally and in Supabase
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      await prefs.remove(_activeSessionKey);
      await prefs.setStringList(_deletedSessionsKey, []);
    } catch (_) {}

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client
            .from('ai_messages')
            .delete()
            .eq('user_id', user.id);
      }
    } catch (e) {
      debugPrint('Error clearing all sessions from Supabase ai_messages: $e');
    }
  }

  static Future<void> _syncToSupabase(AiChatSession session) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null || session.messages.isEmpty) return;

    try {
      final lastMsg = session.messages.last;
      await SupabaseConfig.client.from('ai_messages').insert({
        'user_id': user.id,
        'session_id': session.sessionId,
        'role': lastMsg.role,
        'content': lastMsg.content,
        'created_at':
            (lastMsg.createdAt ?? session.updatedAt).toIso8601String(),
      });
    } catch (_) {
      // Supabase sync failure is gracefully handled; local session is already secured!
    }
  }
}

/// Error from the `ai-chat` Edge Function. [status] is 0 for network errors.
class AiChatException implements Exception {
  const AiChatException(this.message, {this.status = 0});

  final String message;
  final int status;

  /// Network failures, missing deployments and server errors may fall back to
  /// a database-only answer. Auth, permission and rate-limit errors may not.
  bool get allowsLocalFallback =>
      status == 0 || status == 404 || status >= 500;

  @override
  String toString() => message;
}

/// Talks to the `ai-chat` Supabase Edge Function and persists
/// message history both locally and in the `ai_messages` table.
class AiService {
  AiService._();

  /// Sends the conversation to the `ai-chat` Edge Function and returns the
  /// reply. The Gemini key lives only on the server.
  static Future<String> sendMessage({
    required List<AiMessage> messages,
    required String sessionId,
    String userRole = 'customer',
  }) async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) {
      throw Exception('You must be logged in to use the AI assistant.');
    }

    final isAdmin = userRole == 'admin' || userRole == 'manager' || userRole == 'cashier';

    // Suggested questions are answered straight from the database (no AI),
    // so their answers are always exact.
    final quick = await quickAnswer(
      messages.isNotEmpty ? messages.last.content : '',
      userRole: userRole,
    );
    if (quick != null) return quick;

    if (isAdmin) {
      return _adminExecutiveGemini(messages, sessionId, session);
    }

    try {
      final result = await _invokeAiChat(messages);
      final reply = result['reply']?.toString().trim() ?? '';
      if (reply.isNotEmpty) return reply;
      throw const AiChatException('No response from the AI. Please try again.');
    } on AiChatException catch (e) {
      if (e.allowsLocalFallback) {
        final local = await _localCustomerFallback(messages);
        if (local != null) return local;
      }
      throw Exception(e.message);
    }
  }

  // ── Suggested questions (answered from live data, never by the AI) ────────

  /// Shown as tappable suggestions in the chat. Each is answered exactly by
  /// [quickAnswer]; typing the same question works too.
  static const customerQuickQuestions = [
    '💈  Who are the barbers?',
    '✂️  What services are available?',
    '💰  What are the cheapest services?',
    '🕐  How long does each service take?',
    '⭐  Which barber is best for fades?',
    '📅  What are your booking hours?',
  ];

  static const adminQuickQuestions = [
    "📅  Today's bookings",
    '⏳  Pending approvals',
    "💰  Today's revenue",
    '👥  List all barbers',
    '📋  List all services',
    '➕  Add Barber',
    '✂️  Add Service',
  ];

  static const _dataError =
      "I couldn't load the latest data right now. Please check your connection and try again.";

  static String _normalizeQuestion(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[’']"), '')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Returns an exact, data-backed answer for a suggested question, or null
  /// when [text] is not one of them (it then goes to the AI as usual).
  static Future<String?> quickAnswer(String text, {required String userRole}) async {
    final q = _normalizeQuestion(text);
    final isStaffSide = userRole == 'admin' || userRole == 'manager' || userRole == 'cashier';
    final canManage = userRole == 'admin' || userRole == 'manager';
    try {
      if (isStaffSide) {
        switch (q) {
          case 'todays bookings':
            return await _quickTodaysBookings();
          case 'pending approvals':
            return await _quickPendingApprovals();
          case 'todays revenue':
            return await _quickTodaysRevenue();
          case 'list all barbers':
            return await _quickBarbers(forAdmin: true);
          case 'list all services':
            return await _quickServices(forAdmin: true);
          case 'add barber':
            return canManage
                ? 'Fill in the new barber\'s details below. A login is created for them, and their temporary password is shown after saving.\n\n[ADMIN_FORM:ADD_BARBER]'
                : 'Only admins and managers can add barbers.';
          case 'add service':
            return canManage
                ? 'Fill in the new service\'s details below.\n\n[ADMIN_FORM:ADD_CATALOG]'
                : 'Only admins and managers can add services.';
        }
        return null;
      }
      switch (q) {
        case 'who are the barbers':
          return await _quickBarbers(forAdmin: false);
        case 'what services are available':
          return await _quickServices(forAdmin: false);
        case 'what are the cheapest services':
          return await _quickCheapest();
        case 'how long does each service take':
          return await _quickDurations();
        case 'which barber is best for fades':
          return await _quickFadeBarbers();
        case 'what are your booking hours':
          return '📅 **Booking hours**\n\n'
              '• ${ShopInfo.bookingHoursLabel}, in 30-minute slots.\n'
              '• You can book up to ${ShopInfo.maxDaysAhead} days ahead.\n'
              '• You can have up to ${ShopInfo.maxUpcomingBookings} upcoming bookings at a time.\n'
              '• New bookings show as "Pending Approval" until the shop confirms them.';
      }
      return null;
    } catch (_) {
      return _dataError;
    }
  }

  static Future<List<Map<String, dynamic>>> _activeServices() async {
    final rows = SupabaseServiceHelpers.asMapList(await SupabaseConfig.client
        .from(SupabaseConfig.serviceCatalogView)
        .select('name, price, duration_minutes, category_name, is_active')
        .order('name'));
    return rows.where((s) => s['is_active'] != false).toList();
  }

  static Future<List<Map<String, dynamic>>> _barberRows() async {
    final rows = SupabaseServiceHelpers.asMapList(await SupabaseConfig.client
        .from(SupabaseConfig.staffDirectoryView)
        .select('name, role, skills, is_active')
        .order('name'));
    // Only people who cut hair, never admin/cashier accounts.
    return rows.where((s) {
      final role = (s['role'] ?? '').toString().toLowerCase();
      return !role.contains('admin') && !role.contains('cashier');
    }).toList();
  }

  static String _barberLine(Map<String, dynamic> b) {
    final skills = (b['skills'] ?? '').toString().trim();
    return '• **${b['name']}** — ${b['role'] ?? 'Barber'}'
        '${skills.isNotEmpty ? ' (Specialties: $skills)' : ''}';
  }

  static String _serviceLine(Map<String, dynamic> s) =>
      '• **${s['name']}** — ${ShopInfo.formatPrice(s['price'])}, ${s['duration_minutes']} min';

  static Future<String> _quickBarbers({required bool forAdmin}) async {
    final all = await _barberRows();
    final active = all.where((b) => b['is_active'] != false).toList();
    if (active.isEmpty) {
      return forAdmin
          ? '👥 There are no active barbers yet. Use **Add Barber** to add one.'
          : '💈 No barbers are available for booking yet. Please check back soon.';
    }
    final inactive = all.length - active.length;
    return '👥 **${forAdmin ? 'Active barbers' : 'Our barbers'} (${active.length})**\n\n'
        '${active.map(_barberLine).join('\n')}'
        '${forAdmin && inactive > 0 ? '\n\n_Plus $inactive inactive barber${inactive == 1 ? '' : 's'} (see the Employee tab)._' : ''}';
  }

  static Future<String> _quickServices({required bool forAdmin}) async {
    final List<Map<String, dynamic>> all;
    if (forAdmin) {
      all = SupabaseServiceHelpers.asMapList(await SupabaseConfig.client
          .from(SupabaseConfig.serviceCatalogView)
          .select('name, price, duration_minutes, category_name, is_active')
          .order('name'));
    } else {
      all = await _activeServices();
    }
    final active = all.where((s) => s['is_active'] != false).toList();
    if (active.isEmpty) return '📋 There are no services in the catalog yet.';
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final s in active) {
      byCategory.putIfAbsent((s['category_name'] ?? 'Other').toString(), () => []).add(s);
    }
    final inactive = all.length - active.length;
    final sb = StringBuffer('📋 **Services (${active.length})**\n');
    for (final e in byCategory.entries) {
      sb.writeln('\n**${e.key}**');
      for (final s in e.value) {
        sb.writeln(_serviceLine(s));
      }
    }
    if (forAdmin && inactive > 0) {
      sb.writeln('\n_Plus $inactive inactive service${inactive == 1 ? '' : 's'} (hidden from customers)._');
    }
    return sb.toString().trim();
  }

  static Future<String> _quickCheapest() async {
    final services = await _activeServices();
    if (services.isEmpty) return '💰 There are no services in the catalog yet.';
    services.sort((a, b) => SupabaseServiceHelpers.asDouble(a['price'])
        .compareTo(SupabaseServiceHelpers.asDouble(b['price'])));
    final top = services.take(3).toList();
    return '💰 **Our most affordable services**\n\n${top.map(_serviceLine).join('\n')}';
  }

  static Future<String> _quickDurations() async {
    final services = await _activeServices();
    if (services.isEmpty) return '🕐 There are no services in the catalog yet.';
    services.sort((a, b) => SupabaseServiceHelpers.asInt(a['duration_minutes'])
        .compareTo(SupabaseServiceHelpers.asInt(b['duration_minutes'])));
    return '🕐 **How long each service takes**\n\n'
        '${services.map((s) => '• **${s['name']}** — ${s['duration_minutes']} min').join('\n')}';
  }

  static Future<String> _quickFadeBarbers() async {
    final barbers = (await _barberRows()).where((b) => b['is_active'] != false).toList();
    if (barbers.isEmpty) {
      return '💈 No barbers are available for booking yet. Please check back soon.';
    }
    final fade = barbers
        .where((b) => (b['skills'] ?? '').toString().toLowerCase().contains('fade'))
        .toList();
    if (fade.isEmpty) {
      return '⭐ None of our barbers list fades as a specialty yet, but all of them can be booked for a fade. Our barbers:\n\n'
          '${barbers.map(_barberLine).join('\n')}';
    }
    return '⭐ **Barbers who list fades as a specialty**\n\n${fade.map(_barberLine).join('\n')}';
  }

  static (String, String) _todayRangeUtc() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return (start.toUtc().toIso8601String(), end.toUtc().toIso8601String());
  }

  static String _apptLine(Map<String, dynamic> a) {
    final start = SupabaseServiceHelpers.parseDateTime(a['start_time']);
    final time = start != null ? SupabaseServiceHelpers.displayTime(start) : '--';
    return '• **$time** — ${a['customer_name'] ?? 'Customer'}: ${a['service_name'] ?? 'Service'}'
        ' with ${a['staff_name'] ?? 'unassigned'} (`${a['status']}`)';
  }

  static Future<String> _quickTodaysBookings() async {
    final (from, to) = _todayRangeUtc();
    final rows = SupabaseServiceHelpers.asMapList(await SupabaseConfig.client
        .from(SupabaseConfig.appointmentDetailsView)
        .select('start_time, status, customer_name, service_name, staff_name')
        .gte('start_time', from)
        .lt('start_time', to)
        .order('start_time'));
    const inactive = {'canceled', 'declined', 'no-show'};
    final active = rows.where((a) => !inactive.contains(a['status'])).toList();
    final dropped = rows.length - active.length;
    if (rows.isEmpty) return '📅 There are no bookings for today.';
    final sb = StringBuffer('📅 **Today\'s bookings: ${active.length}**');
    if (dropped > 0) sb.write(' _(plus $dropped canceled/declined/no-show)_');
    sb.writeln('\n');
    for (final a in active) {
      sb.writeln(_apptLine(a));
    }
    return sb.toString().trim();
  }

  static Future<String> _quickPendingApprovals() async {
    final rows = SupabaseServiceHelpers.asMapList(await SupabaseConfig.client
        .from(SupabaseConfig.appointmentDetailsView)
        .select('start_time, status, customer_name, service_name, staff_name')
        .eq('status', 'pending')
        .gte('start_time', DateTime.now().toUtc().toIso8601String())
        .order('start_time'));
    if (rows.isEmpty) return '⏳ There are no bookings waiting for approval.';
    final sb = StringBuffer('⏳ **Waiting for approval: ${rows.length}**\n\n');
    for (final a in rows) {
      final start = SupabaseServiceHelpers.parseDateTime(a['start_time']);
      final date = start != null ? SupabaseServiceHelpers.displayDate(start) : '';
      sb.writeln('${_apptLine(a)} on $date');
    }
    sb.write('\nApprove or decline them in the **Booking** tab.');
    return sb.toString().trim();
  }

  static Future<String> _quickTodaysRevenue() async {
    final (from, to) = _todayRangeUtc();
    final rows = SupabaseServiceHelpers.asMapList(await SupabaseConfig.client
        .from(SupabaseConfig.transactionDetailsView)
        .select('amount, tip_amount, payment_method, status')
        .eq('status', 'completed')
        .gte('created_at', from)
        .lt('created_at', to));
    if (rows.isEmpty) {
      return '💰 **Today\'s revenue: ${ShopInfo.formatPrice(0)}**\n\nNo payments have been recorded today.';
    }
    double services = 0, tips = 0;
    final byMethod = <String, double>{};
    for (final t in rows) {
      final amount = SupabaseServiceHelpers.asDouble(t['amount']);
      final tip = SupabaseServiceHelpers.asDouble(t['tip_amount']);
      services += amount;
      tips += tip;
      final method = (t['payment_method'] ?? 'other').toString();
      byMethod[method] = (byMethod[method] ?? 0) + amount + tip;
    }
    final sb = StringBuffer('💰 **Today\'s revenue: ${ShopInfo.formatPrice(services + tips)}**\n\n')
      ..writeln('• Services: ${ShopInfo.formatPrice(services)}')
      ..writeln('• Tips: ${ShopInfo.formatPrice(tips)}')
      ..writeln('• Payments recorded: ${rows.length}');
    for (final e in byMethod.entries) {
      sb.writeln('• ${e.key[0].toUpperCase()}${e.key.substring(1)}: ${ShopInfo.formatPrice(e.value)}');
    }
    return sb.toString().trim();
  }

  static const int _maxMessagesSent = 20;

  static Future<Map<String, dynamic>> _invokeAiChat(
    List<AiMessage> messages,
  ) async {
    final recent = messages.length > _maxMessagesSent
        ? messages.sublist(messages.length - _maxMessagesSent)
        : messages;
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'ai-chat',
        body: {
          'messages': recent
              .map((m) => {'role': m.role, 'content': m.content})
              .toList(),
        },
      );
      return SupabaseServiceHelpers.asMap(response.data);
    } on FunctionException catch (e) {
      throw AiChatException(
        SupabaseServiceHelpers.errorMessage(e),
        status: e.status,
      );
    } catch (_) {
      throw const AiChatException(
        'Could not reach the AI assistant. Check your connection and try again.',
      );
    }
  }

  /// Executive Admin AI Copilot: Queries database analytics and formats catalog/staff mutations.
  /// Executive Admin AI Copilot: Queries database analytics and formats catalog/staff mutations.
  static Future<String> _adminExecutiveGemini(
    List<AiMessage> messages,
    String sessionId,
    Session session,
  ) async {
    final lastQuery =
        messages.isNotEmpty ? messages.last.content.trim() : '';
    final lowerQuery = lastQuery.toLowerCase();

    // ── Pre-fetch real-time catalog, staff, and dashboard data for grounded RAG ──
    List<Map<String, dynamic>> services = [];
    List<Map<String, dynamic>> staff = [];
    Map<String, dynamic>? dashboardData;
    try {
      final res = await Future.wait([
        CatalogService.getAllServices(forceRefresh: true),
        EmployeeService.getAllEmployees(forceRefresh: true),
        DashboardService.getDashboardData(forceRefresh: true),
      ]);
      services = res[0] as List<Map<String, dynamic>>;
      staff = res[1] as List<Map<String, dynamic>>;
      dashboardData = res[2] as Map<String, dynamic>?;
    } catch (_) {}

    // ── 1. PROACTIVE INTENT CLASSIFIER (Zero-latency direct database answers) ──

    // Case A: Bookings & Appointments Intelligence (Recent, Multi-Temporal, All-Time)
    final isBookingsQuery = lowerQuery.contains('booking') ||
        lowerQuery.contains('booked') ||
        lowerQuery.contains('appointment') ||
        lowerQuery.contains('scheduled') ||
        lowerQuery.contains('client');

    // Case A1: Real-Time Recent Bookings ("is there any recent bookings right now?", "any new bookings?", "latest appointments")
    final isRecentBookingsQuery = (lowerQuery.contains('recent') ||
            lowerQuery.contains('latest') ||
            lowerQuery.contains('right now') ||
            lowerQuery.contains('new booking') ||
            lowerQuery.contains('upcoming') ||
            lowerQuery.contains('next client') ||
            lowerQuery.contains('who booked')) &&
        (isBookingsQuery || lowerQuery.contains('right now'));

    if (isRecentBookingsQuery) {
      return await _executeRecentBookingsReport(dashboardData: dashboardData);
    }

    // Case A2: Multi-Temporal Bookings Analytics (Days, Weeks, Months, Years, All-Time)
    if (isBookingsQuery) {
      // Check total / all-time
      final isAllTimeQuery = lowerQuery.contains('total') ||
          lowerQuery.contains('all time') ||
          lowerQuery.contains('all-time') ||
          lowerQuery.contains('overall') ||
          lowerQuery.contains('cumulative') ||
          lowerQuery.contains('how many bookings') ||
          lowerQuery.contains('how many appointments') ||
          lowerQuery == 'total bookings' ||
          lowerQuery == 'total appointments' ||
          lowerQuery == 'bookings';

      // Check weeks
      final weeksMatch = RegExp(r'\b(?:past|last|previous)\s+(\d+)\s+weeks?\b').firstMatch(lowerQuery);
      final isThisWeek = lowerQuery.contains('this week') || lowerQuery.contains('current week');
      final isPastWeek = lowerQuery.contains('past week') || lowerQuery.contains('last week') || lowerQuery.contains('previous week');

      // Check months
      final monthsMatch = RegExp(r'\b(?:past|last|previous)\s+(\d+)\s+months?\b').firstMatch(lowerQuery);
      final isThisMonth = lowerQuery.contains('this month') || lowerQuery.contains('current month');
      final isPastMonth = lowerQuery.contains('past month') || lowerQuery.contains('last month') || lowerQuery.contains('previous month');

      // Check years
      final yearsMatch = RegExp(r'\b(?:past|last|previous)\s+(\d+)\s+years?\b').firstMatch(lowerQuery);
      final isThisYear = lowerQuery.contains('this year') || lowerQuery.contains('current year');
      final isPastYear = lowerQuery.contains('past year') || lowerQuery.contains('last year') || lowerQuery.contains('previous year');

      // Check days
      final daysMatch = RegExp(r'\b(?:past|last|previous)\s+(\d+)\s+days?\b').firstMatch(lowerQuery);
      final isToday = lowerQuery.contains('today');
      final isYesterday = lowerQuery.contains('yesterday');

      final now = DateTime.now();

      if (isToday) {
        final start = DateTime(now.year, now.month, now.day);
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: start,
          timeframeLabel: "Today's",
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (isYesterday) {
        final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
        final end = DateTime(now.year, now.month, now.day);
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: start,
          endDate: end,
          timeframeLabel: "Yesterday's",
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (daysMatch != null) {
        final days = int.tryParse(daysMatch.group(1)!) ?? 3;
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: start,
          timeframeLabel: "Past $days Days",
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (isThisWeek) {
        final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: startOfWeek,
          timeframeLabel: "This Week's",
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (weeksMatch != null || isPastWeek) {
        final weeks = weeksMatch != null ? int.tryParse(weeksMatch.group(1)!) ?? 1 : 1;
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: weeks * 7));
        final label = weeks == 1 ? "Past Week's" : "Past $weeks Weeks";
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: start,
          timeframeLabel: label,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (isThisMonth) {
        final startOfMonth = DateTime(now.year, now.month, 1);
        final label = "This Month's (${_monthName(now.month)} ${now.year})";
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: startOfMonth,
          timeframeLabel: label,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (monthsMatch != null || isPastMonth) {
        final months = monthsMatch != null ? int.tryParse(monthsMatch.group(1)!) ?? 1 : 1;
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: months * 30));
        final label = months == 1 ? "Past Month's" : "Past $months Months";
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: start,
          timeframeLabel: label,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (isThisYear) {
        final startOfYear = DateTime(now.year, 1, 1);
        final label = "This Year's (${now.year})";
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: startOfYear,
          timeframeLabel: label,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (yearsMatch != null || isPastYear) {
        final years = yearsMatch != null ? int.tryParse(yearsMatch.group(1)!) ?? 1 : 1;
        final start = DateTime(now.year - years, now.month, now.day);
        final label = years == 1 ? "Past Year's" : "Past $years Years";
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: start,
          timeframeLabel: label,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (isAllTimeQuery) {
        final analytics = await _executeTemporalBookingsAnalytics(
          isAllTime: true,
          timeframeLabel: "All-Time Overall",
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      }
    }

    // Case B: Shop Financials / Revenue (e.g. "today's revenue", "how much revenue", "financial summary")
    final isRevenueQuery = lowerQuery.contains('revenue') ||
        lowerQuery.contains('sales') ||
        lowerQuery.contains('income') ||
        lowerQuery.contains('financial') ||
        (lowerQuery.contains('how much') && lowerQuery.contains('earn'));

    if (isRevenueQuery) {
      return await _formatFinancialReport();
    }

    // Case C: List / Show Catalog Services (e.g. "list all the catalog", "show catalog", "all services")
    final isCatalogQuery = (lowerQuery.contains('catalog') ||
            lowerQuery.contains('service') ||
            lowerQuery.contains('hairstyle') ||
            lowerQuery.contains('haircut')) &&
        (lowerQuery.contains('list') ||
            lowerQuery.contains('all') ||
            lowerQuery.contains('show') ||
            lowerQuery.contains('view') ||
            lowerQuery.contains('what are') ||
            lowerQuery.contains('provide') ||
            lowerQuery.contains('how many') ||
            lowerQuery == 'catalog' ||
            lowerQuery == 'services' ||
            lowerQuery == 'hairstyles');

    if (isCatalogQuery &&
        !lowerQuery.contains('add') &&
        !lowerQuery.contains('create') &&
        !lowerQuery.contains('remove') &&
        !lowerQuery.contains('delete')) {
      return _formatCatalogReport(services);
    }

    // Case D: List / Show Staff Members (e.g. "how many barbers", "list all barbers", "who works here")
    final isStaffQuery = (lowerQuery.contains('barber') ||
            lowerQuery.contains('staff') ||
            lowerQuery.contains('employee') ||
            lowerQuery.contains('stylist') ||
            lowerQuery.contains('team') ||
            lowerQuery.contains('who works')) &&
        (lowerQuery.contains('list') ||
            lowerQuery.contains('all') ||
            lowerQuery.contains('show') ||
            lowerQuery.contains('who') ||
            lowerQuery.contains('provide') ||
            lowerQuery.contains('how many') ||
            lowerQuery == 'barbers' ||
            lowerQuery == 'staff' ||
            lowerQuery == 'employees');

    if (isStaffQuery &&
        !lowerQuery.contains('add') &&
        !lowerQuery.contains('create') &&
        !lowerQuery.contains('hire')) {
      return _formatStaffReport(staff);
    }

    // Case E: Add Hairstyle / Catalog Service (Inquiry vs Action)
    final isCatalogIntent = (lowerQuery.contains('hairstyle') ||
            lowerQuery.contains('catalog') ||
            lowerQuery.contains('service') ||
            lowerQuery.contains('haircut')) &&
        (lowerQuery.contains('add') ||
            lowerQuery.contains('create'));

    if (isCatalogIntent) {
      final isCatalogInquiry = lowerQuery.startsWith('can we') ||
          lowerQuery.startsWith('can i') ||
          lowerQuery.startsWith('can you add') ||
          lowerQuery.startsWith('how to') ||
          lowerQuery.startsWith('how do') ||
          lowerQuery.startsWith('how can') ||
          lowerQuery.startsWith('is it possible') ||
          lowerQuery.startsWith('are we able') ||
          lowerQuery.startsWith('do you allow') ||
          (lowerQuery.endsWith('?') &&
              // A question without any number is an inquiry, not a request.
              !RegExp(r'[0-9]').hasMatch(lowerQuery));

      if (isCatalogInquiry) {
        return 'Yes, absolutely! You can add new hairstyles and services in two ways:\n\n'
            '1. **Directly in this Chat:** Use the form below or provide details like:\n'
            '   👉 *"Add a hairstyle to catalog: Low Fade for 80000đ, 30 mins"*\n\n'
            '2. **Via the Catalog Screen:** Go to the **Catalog** tab and tap the **+ Add Catalog** button.\n\n'
            '[ADMIN_FORM:ADD_CATALOG]';
      }

      final params = _parseLocalAddService(lastQuery);
      if (params != null) {
        return 'I have prepared the new catalog service for your review:\n\n'
            '[ADMIN_ACTION:CREATE_SERVICE:${jsonEncode(params)}]\n\n'
            'Please review the details in the action card above and tap **Confirm & Add to Catalog** to write it to the database.';
      } else {
        return 'Sure! Please fill in the hairstyle or service details in the form below:\n\n'
            '[ADMIN_FORM:ADD_CATALOG]';
      }
    }

    // Case F: Add Barber / Staff Member (Inquiry vs Action)
    final isStaffIntent = (lowerQuery.contains('barber') ||
            lowerQuery.contains('employee') ||
            lowerQuery.contains('staff') ||
            lowerQuery.contains('stylist')) &&
        (lowerQuery.contains('add') ||
            lowerQuery.contains('create') ||
            lowerQuery.contains('hire'));

    if (isStaffIntent) {
      final isStaffInquiry = lowerQuery.startsWith('can we') ||
          lowerQuery.startsWith('can i') ||
          lowerQuery.startsWith('can you add') ||
          lowerQuery.startsWith('how to') ||
          lowerQuery.startsWith('how do') ||
          lowerQuery.startsWith('how can') ||
          lowerQuery.startsWith('is it possible') ||
          lowerQuery.startsWith('are we able') ||
          lowerQuery.startsWith('do you allow') ||
          (lowerQuery.endsWith('?') &&
              !lowerQuery.contains('phone') &&
              !lowerQuery.contains('named') &&
              !lowerQuery.contains('called') &&
              !RegExp(r'\d{10,11}').hasMatch(lowerQuery));

      if (isStaffInquiry) {
        return 'Yes, absolutely! You can add new barbers and staff members in two ways:\n\n'
            '1. **Directly in this Chat:** Use the form below or tell me their details.\n'
            '   👉 *"Add a barber named Marco with phone 09123456789"*\n\n'
            '2. **Via the Employee Screen:** Go to the **Employee** tab and tap the **+ Add Staff** button.\n\n'
            '[ADMIN_FORM:ADD_BARBER]';
      }

      final params = _parseLocalAddStaff(lastQuery);
      if (params != null) {
        return 'I have prepared the new staff profile for your review:\n\n'
            '[ADMIN_ACTION:CREATE_STAFF:${jsonEncode(params)}]\n\n'
            'Please review the profile in the action card above and tap **Confirm & Add Staff** to create their account in the database.';
      } else {
        return 'Sure! Please fill in the barber details in the form below:\n\n'
            '[ADMIN_FORM:ADD_BARBER]';
      }
    }

    // ── 2. GEMINI (server-side via the ai-chat Edge Function) ──
    final Map<String, dynamic> result;
    try {
      result = await _invokeAiChat(messages);
    } on AiChatException catch (e) {
      throw Exception(e.message);
    }

    final call = SupabaseServiceHelpers.asMap(result['function_call']);
    if (call.isNotEmpty) {
      return _dispatchAdminTool(
        call['name']?.toString() ?? '',
        SupabaseServiceHelpers.asMap(call['args']),
        services: services,
        staff: staff,
        dashboardData: dashboardData,
      );
    }

    final reply = result['reply']?.toString().trim() ?? '';
    if (reply.isNotEmpty) return reply;
    throw Exception('No response from the AI. Please try again.');
  }

  /// Executes the tool Gemini chose, using data loaded with the admin's own
  /// permissions, and formats the answer locally.
  static Future<String> _dispatchAdminTool(
    String name,
    Map<String, dynamic> args, {
    required List<Map<String, dynamic>> services,
    required List<Map<String, dynamic>> staff,
    required Map<String, dynamic>? dashboardData,
  }) async {
    if (name == 'query_catalog_services') {
      return _formatCatalogReport(services);
    } else if (name == 'query_staff_members') {
      return _formatStaffReport(staff);
    } else if (name == 'query_recent_bookings') {
      return await _executeRecentBookingsReport(dashboardData: dashboardData);
    } else if (name == 'query_bookings_analytics') {
      final tf = (args['timeframe'] ?? '').toString().toLowerCase();
      final count = (args['count'] as num?)?.toInt() ?? (args['days_back'] as num?)?.toInt() ?? 3;
      final status = args['status']?.toString();
      final now = DateTime.now();

      if (tf == 'today' || (tf == 'days' && count == 0)) {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, now.month, now.day),
          timeframeLabel: "Today's",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'yesterday') {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
          endDate: DateTime(now.year, now.month, now.day),
          timeframeLabel: "Yesterday's",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'this_week') {
        final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: startOfWeek,
          timeframeLabel: "This Week's",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'weeks') {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, now.month, now.day).subtract(Duration(days: count * 7)),
          timeframeLabel: count == 1 ? "Past Week's" : "Past $count Weeks",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'this_month') {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, now.month, 1),
          timeframeLabel: "This Month's (${_monthName(now.month)} ${now.year})",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'months') {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, now.month, now.day).subtract(Duration(days: count * 30)),
          timeframeLabel: count == 1 ? "Past Month's" : "Past $count Months",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'this_year') {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, 1, 1),
          timeframeLabel: "This Year's (${now.year})",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'years') {
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year - count, now.month, now.day),
          timeframeLabel: count == 1 ? "Past Year's" : "Past $count Years",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else if (tf == 'all_time') {
        final analytics = await _executeTemporalBookingsAnalytics(
          isAllTime: true,
          timeframeLabel: "All-Time Overall",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      } else {
        final days = count > 0 ? count : 3;
        final analytics = await _executeTemporalBookingsAnalytics(
          startDate: DateTime(now.year, now.month, now.day).subtract(Duration(days: days)),
          timeframeLabel: "Past $days Days",
          statusFilter: status,
          dashboardData: dashboardData,
        );
        return _formatBookingsReport(analytics);
      }
    } else if (name == 'query_shop_financials') {
      return await _formatFinancialReport();
    } else if (name == 'propose_add_catalog_service') {
      final serviceName = args['name']?.toString().trim() ?? '';
      if (serviceName.isEmpty || _isInvalidEntityName(serviceName, isStaff: false)) {
        return 'Sure! Please fill in the hairstyle or service details in the form below:\n\n[ADMIN_FORM:ADD_CATALOG]';
      }
      final serviceJson = {
        'name': serviceName,
        'price': (args['price'] as num?)?.toDouble() ?? 250.0,
        'duration_minutes': (args['duration_minutes'] as num?)?.toInt() ?? 30,
        'category_name': args['category_name'] ?? 'Haircuts',
        'description': args['description'] ?? 'Professional haircut style',
      };
      return 'I have prepared the new catalog service for your review:\n\n'
          '[ADMIN_ACTION:CREATE_SERVICE:${jsonEncode(serviceJson)}]\n\n'
          'Please review the details in the action card above and tap **Confirm & Add to Catalog** to write it to the database.';
    } else if (name == 'propose_add_employee') {
      final staffName = args['name']?.toString().trim() ?? '';
      if (staffName.isEmpty || _isInvalidEntityName(staffName, isStaff: true)) {
        return 'Sure! Please fill in the barber details in the form below:\n\n[ADMIN_FORM:ADD_BARBER]';
      }
      final staffJson = {
        'name': staffName,
        'role': args['role'] ?? 'Barber',
        'phone': args['phone'] ?? '',
        'email': args['email'] ?? '',
        'specialties': args['specialties'] ?? 'General Barbering',
      };
      return 'I have prepared the new staff profile for your review:\n\n'
          '[ADMIN_ACTION:CREATE_STAFF:${jsonEncode(staffJson)}]\n\n'
          'Please review the profile in the action card above and tap **Confirm & Add Staff** to create their account in the database.';
    }
    return 'Sorry, I could not complete that request. Please rephrase and try again.';
  }

  /// Real-time Supabase analytics query across any temporal range (days, weeks, months, years, or all-time)
  static Future<Map<String, dynamic>> _executeTemporalBookingsAnalytics({
    DateTime? startDate,
    DateTime? endDate,
    required String timeframeLabel,
    bool isAllTime = false,
    String? statusFilter,
    Map<String, dynamic>? dashboardData,
  }) async {
    try {
      var query = SupabaseConfig.client
          .from(SupabaseConfig.appointmentDetailsView)
          .select();

      if (!isAllTime && startDate != null) {
        query = query.gte('start_time', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lt('start_time', endDate.toUtc().toIso8601String());
      }
      if (statusFilter != null && statusFilter.isNotEmpty && statusFilter.toLowerCase() != 'all') {
        query = query.eq('status', statusFilter.toLowerCase());
      }

      // PostgREST returns at most 1000 rows per request; page through all.
      const pageSize = 1000;
      final rows = <Map<String, dynamic>>[];
      for (var page = 0; page < 50; page++) {
        final data = await query
            .order('start_time', ascending: false)
            .range(page * pageSize, (page + 1) * pageSize - 1);
        final batch = SupabaseServiceHelpers.asMapList(data);
        rows.addAll(batch);
        if (batch.length < pageSize) break;
      }

      int total = rows.length;
      int completed = 0;
      int pending = 0;
      int inProgress = 0;
      int canceled = 0;
      double revenue = 0.0;
      final barberCounts = <String, int>{};
      final serviceCounts = <String, int>{};

      for (final r in rows) {
        final s = (r['status'] ?? '').toString().toLowerCase();
        if (s == 'completed') {
          completed++;
          revenue += SupabaseServiceHelpers.asDouble(r['total_amount'] ?? r['price'] ?? r['service_price']);
        } else if (s == 'pending' || s == 'confirmed' || s == 'booked') {
          pending++;
        } else if (s == 'in_progress' || s == 'checked-in' || s == 'in-service') {
          inProgress++;
        } else if (s == 'canceled' || s == 'cancelled' || s == 'declined' || s == 'no-show') {
          canceled++;
        }

        final bName = (r['employee_name'] ?? r['staff_name'] ?? '').toString().trim();
        if (bName.isNotEmpty && bName != 'null') {
          barberCounts[bName] = (barberCounts[bName] ?? 0) + 1;
        }

        final sName = (r['service_name'] ?? '').toString().trim();
        if (sName.isNotEmpty && sName != 'null') {
          serviceCounts[sName] = (serviceCounts[sName] ?? 0) + 1;
        }
      }

      // Cross-reference with dashboardData if view query returned 0 rows (e.g. view RLS vs RPC)
      if (total == 0 && dashboardData != null) {
        final stats = SupabaseServiceHelpers.asMap(dashboardData['stats']);
        if (isAllTime) {
          total = (stats['total_bookings'] as num?)?.toInt() ?? 0;
        } else if (timeframeLabel.contains("Today's")) {
          total = (stats['today_bookings'] as num?)?.toInt() ?? 0;
          revenue = SupabaseServiceHelpers.asDouble(stats['revenue_today']);
        }
      }

      return {
        'timeframe_label': timeframeLabel,
        'total_bookings': total,
        'completed': completed,
        'pending': pending,
        'in_progress': inProgress,
        'canceled': canceled,
        'revenue': revenue,
        'barbers': barberCounts,
        'services': serviceCounts,
        'recent_samples': rows.take(4).toList(),
      };
    } catch (e) {
      int total = 0;
      double revenue = 0.0;
      if (dashboardData != null) {
        final stats = SupabaseServiceHelpers.asMap(dashboardData['stats']);
        if (isAllTime) {
          total = (stats['total_bookings'] as num?)?.toInt() ?? 0;
        } else if (timeframeLabel.contains("Today's")) {
          total = (stats['today_bookings'] as num?)?.toInt() ?? 0;
          revenue = SupabaseServiceHelpers.asDouble(stats['revenue_today']);
        }
      }
      return {
        'timeframe_label': timeframeLabel,
        'total_bookings': total,
        'completed': 0,
        'pending': 0,
        'canceled': 0,
        'revenue': revenue,
        'barbers': <String, int>{},
        'services': <String, int>{},
        'recent_samples': <Map<String, dynamic>>[],
        'error': e.toString(),
      };
    }
  }

  /// Format structured database analytics into a clean, authoritative executive report
  static String _formatBookingsReport(Map<String, dynamic> data) {
    final timeframe = (data['timeframe_label'] ?? 'Bookings').toString();
    final total = (data['total_bookings'] as num?)?.toInt() ?? 0;
    final completed = (data['completed'] as num?)?.toInt() ?? 0;
    final pending = (data['pending'] as num?)?.toInt() ?? 0;
    final inProgress = (data['in_progress'] as num?)?.toInt() ?? 0;
    final canceled = (data['canceled'] as num?)?.toInt() ?? 0;
    final revenue = (data['revenue'] as num?)?.toDouble() ?? 0.0;
    final barbers = SupabaseServiceHelpers.asMap(data['barbers']);
    final services = SupabaseServiceHelpers.asMap(data['services']);
    final recentSamples = SupabaseServiceHelpers.asMapList(data['recent_samples']);

    final bList = barbers.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    final sList = services.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));

    final sb = StringBuffer();
    sb.writeln('📊 **$timeframe Bookings Overview**');
    sb.writeln('Here is the live report directly from the shop database:\n');
    sb.writeln('• **Total Bookings:** $total appointment${total == 1 ? '' : 's'}');
    sb.writeln('• **Completed:** $completed (est. ${ShopInfo.formatPrice(revenue)} at list price)');
    sb.writeln('• **Pending / Confirmed:** $pending');
    sb.writeln('• **In progress:** $inProgress');
    sb.writeln('• **Canceled / No-show:** $canceled\n');

    if (bList.isNotEmpty) {
      sb.writeln('👥 **Barber Workload Breakdown:**');
      for (final e in bList.take(4)) {
        sb.writeln('• **${e.key}:** ${e.value} appointment${e.value == 1 ? '' : 's'}');
      }
      sb.writeln();
    }

    if (sList.isNotEmpty) {
      sb.writeln('✂️ **Top Requested Services:**');
      for (final e in sList.take(4)) {
        sb.writeln('• **${e.key}:** ${e.value} booked');
      }
      sb.writeln();
    }

    if (recentSamples.isNotEmpty) {
      sb.writeln('📋 **Latest Appointments in this Period:**');
      for (final b in recentSamples.take(3)) {
        final cName = b['customer_name'] ?? b['full_name'] ?? 'Customer';
        final sName = b['service_name'] ?? 'Haircut';
        final barber = b['employee_name'] ?? b['staff_name'] ?? 'Staff';
        final status = (b['status'] ?? 'Booked').toString().toUpperCase();
        sb.writeln('• **$cName** — $sName with $barber (`$status`)');
      }
      sb.writeln();
    }

    if (total == 0) {
      sb.writeln('_Note: No appointments recorded in this timeframe in the database._');
    }

    return sb.toString().trim();
  }

  /// Real-time recent bookings inspector answering "Is there any recent bookings right now?"
  static Future<String> _executeRecentBookingsReport({Map<String, dynamic>? dashboardData}) async {
    List<Map<String, dynamic>> recentList = [];
    Map<String, dynamic>? nextClient;
    Map<String, dynamic> stats = {};

    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.appointmentDetailsView)
          .select()
          .order('start_time', ascending: false)
          .limit(6);
      recentList = SupabaseServiceHelpers.asMapList(data);
    } catch (_) {}

    try {
      dashboardData ??= await DashboardService.getDashboardData(forceRefresh: true);
      stats = SupabaseServiceHelpers.asMap(dashboardData?['stats']);
      nextClient = SupabaseServiceHelpers.asMap(dashboardData?['next_client']);

      if (recentList.isEmpty) {
        final dbRecent = SupabaseServiceHelpers.asMapList(dashboardData?['recent_bookings']);
        if (dbRecent.isNotEmpty) {
          recentList = dbRecent;
        }
      }
    } catch (_) {}

    final sb = StringBuffer();
    sb.writeln('📅 **Real-Time Booking Status (Live Database)**\n');

    if (recentList.isNotEmpty) {
      sb.writeln('**Yes!** Here are the recent bookings recorded in the system right now:\n');

      for (int i = 0; i < recentList.length && i < 5; i++) {
        final b = recentList[i];
        final cName = b['customer_name'] ?? b['customer'] ?? b['full_name'] ?? 'Customer';
        final sName = b['service_name'] ?? b['service'] ?? 'Haircut Service';
        final barber = b['staff_name'] ?? b['employee'] ?? b['employee_name'] ?? 'Assigned Staff';
        final price = b['price'] ?? b['service_price'] ?? b['total_amount'];
        final priceStr = price != null ? ShopInfo.formatPrice(price) : '';
        final status = (b['status'] ?? 'Confirmed').toString().toUpperCase();
        final rawTime = b['start_time'] ?? b['date'];
        final timeStr = _formatBookingTime(rawTime);

        sb.writeln('${i + 1}. **$cName** — $sName${priceStr.isNotEmpty ? ' ($priceStr)' : ''}');
        sb.writeln('   • **Barber:** $barber');
        sb.writeln('   • **Schedule:** $timeStr');
        sb.writeln('   • **Status:** `$status`\n');
      }

      if (nextClient != null && nextClient.isNotEmpty) {
        final nName = nextClient['customer_name'] ?? nextClient['full_name'] ?? 'Client';
        final nService = nextClient['service'] ?? nextClient['service_name'] ?? 'Haircut';
        final nBarber = nextClient['employee'] ?? nextClient['staff_name'] ?? 'Barber';
        final nTime = nextClient['time'] ?? nextClient['start_time'] ?? '';
        sb.writeln('👉 **Next Scheduled Client:** $nName for $nService with $nBarber ($nTime)');
      }
    } else {
      final todayCount = stats['today_bookings'] ?? 0;
      final totalCount = stats['total_bookings'] ?? 0;

      sb.writeln('**No.** There are currently no recent bookings recorded in the database right now.\n');
      sb.writeln('• **Today\'s Bookings:** $todayCount');
      sb.writeln('• **All-Time Total Bookings:** $totalCount');
      sb.writeln('\nThe system queried the database in real-time and found zero active or recent appointment records.');
    }

    return sb.toString().trim();
  }

  static String _formatBookingTime(dynamic rawTime) {
    if (rawTime == null) return 'N/A';
    try {
      final dt = DateTime.parse(rawTime.toString()).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final timeStr = '$hour:$minute $period';
      if (isToday) return 'Today at $timeStr';
      return '${_monthName(dt.month)} ${dt.day}, ${dt.year} at $timeStr';
    } catch (_) {
      return rawTime.toString();
    }
  }

  static String _monthName(int month) {
    const months = [
      '',
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
      'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month];
    return '';
  }

  /// Format real-time shop financials using dashboard RPC
  static Future<String> _formatFinancialReport() async {
    try {
      final dash = await DashboardService.getDashboardData(forceRefresh: true);
      final stats = SupabaseServiceHelpers.asMap(dash?['stats']);
      final todayBookings = stats['today_bookings'] ?? 0;
      final totalBookings = stats['total_bookings'] ?? 0;
      final todayRevenue = SupabaseServiceHelpers.asDouble(stats['revenue_today']);
      final recent = SupabaseServiceHelpers.asMapList(dash?['recent_bookings']);

      final sb = StringBuffer();
      sb.writeln('💰 **Shop Financial & Performance Summary**\n');
      sb.writeln('• **Today\'s Revenue:** ${ShopInfo.formatPrice(todayRevenue)}');
      sb.writeln('• **Today\'s Bookings:** $todayBookings');
      sb.writeln('• **All-Time Total Bookings:** $totalBookings\n');

      if (recent.isNotEmpty) {
        sb.writeln('📋 **Latest Bookings:**');
        for (final b in recent.take(4)) {
          final cName = b['customer_name'] ?? b['customer'] ?? b['full_name'] ?? 'Customer';
          final sName = b['service_name'] ?? b['service'] ?? 'Service';
          final price = b['price'] != null ? ' (${ShopInfo.formatPrice(b['price'])})' : '';
          sb.writeln('• $cName - $sName$price');
        }
      }
      return sb.toString().trim();
    } catch (e) {
      return '💰 **Shop Financial Overview**\nUnable to retrieve real-time financial stats: $e';
    }
  }

  /// Generates a comprehensive, 100% accurate database report of the entire shop catalog
  static String _formatCatalogReport(List<Map<String, dynamic>> services) {
    if (services.isEmpty) {
      return '📋 **Shop Catalog**\nThere are currently no services listed in the shop catalog.\n\n'
          'To add a service, prompt:\n*"Add a hairstyle to catalog: [Name] for [Price]đ, [Duration] mins"*';
    }

    // Group services by category
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final s in services) {
      final cat = (s['category_name'] ?? 'General Services').toString();
      byCategory.putIfAbsent(cat, () => []).add(s);
    }

    final sb = StringBuffer();
    sb.writeln('📋 **Official Shop Catalog (${services.length} Total Services)**\n');

    for (final entry in byCategory.entries) {
      sb.writeln('### ${entry.key}');
      for (final s in entry.value) {
        final name = s['name'] ?? 'Service';
        final price = ShopInfo.formatPrice(s['price'] ?? 0);
        final duration = s['duration_minutes'] != null ? '${s['duration_minutes']} min' : '30 min';
        final desc = (s['description'] != null && s['description'].toString().trim().isNotEmpty)
            ? ' — _${s['description'].toString().trim()}_'
            : '';
        final status = (s['is_active'] == 1 || s['is_active'] == true) ? '' : ' *(Inactive)*';
        sb.writeln('• **$name** ($price, $duration)$status$desc');
      }
      sb.writeln();
    }

    sb.writeln('💡 *Tip: You can say "Add a hairstyle to catalog: [Name] for [Price]đ" to add a new service.*');
    return sb.toString().trim();
  }

  /// Generates a comprehensive, 100% accurate database report of all staff and barbers
  static String _formatStaffReport(List<Map<String, dynamic>> staff) {
    if (staff.isEmpty) {
      return '👥 **Staff & Barber Directory**\nNo staff members are currently registered in the database.\n\n'
          'To add a barber, prompt:\n*"Add a barber named [Name] with phone [Phone]"*';
    }

    final sb = StringBuffer();
    sb.writeln('👥 **Official Staff & Barber Directory (${staff.length} Total Staff)**\n');

    for (final st in staff) {
      final name = st['name'] ?? 'Staff Member';
      final role = st['role'] ?? 'Barber';
      final phone = (st['phone'] != null && st['phone'].toString().isNotEmpty)
          ? ' • Phone: ${st['phone']}'
          : '';
      final email = (st['email'] != null && st['email'].toString().isNotEmpty)
          ? ' • Email: ${st['email']}'
          : '';
      final skills = (st['skills'] != null && st['skills'].toString().isNotEmpty)
          ? '\n  Specialties: ${st['skills']}'
          : '';

      sb.writeln('• **$name** — *$role*$phone$email$skills');
    }

    sb.writeln('\n💡 *Tip: You can say "Add a barber named [Name] with phone [Phone]" to register new staff.*');
    return sb.toString().trim();
  }

  /// Validates whether an extracted string is a legitimate entity name or merely a generic keyword/question.
  static bool _isInvalidEntityName(String name, {required bool isStaff}) {
    final lower = name.toLowerCase().trim();
    if (lower.length < 2) return true;

    // Check common question patterns or conversational phrases
    if (lower.startsWith('can ') ||
        lower.startsWith('how ') ||
        lower.startsWith('what ') ||
        lower.startsWith('is ') ||
        lower.startsWith('are ') ||
        lower.startsWith('could ') ||
        lower.startsWith('should ') ||
        lower.startsWith('would ') ||
        lower.startsWith('why ') ||
        lower.startsWith('who ') ||
        lower.startsWith('where ') ||
        lower.startsWith('when ') ||
        lower.startsWith('tell ') ||
        lower.startsWith('show ') ||
        lower.endsWith('?')) {
      return true;
    }

    const invalidStaffNames = {
      'barber',
      'barbers',
      'staff',
      'staffs',
      'employee',
      'employees',
      'stylist',
      'stylists',
      'team',
      'user',
      'users',
      'someone',
      'anyone',
      'person',
      'people',
      'new barber',
      'new staff',
      'new employee',
      'add barber',
      'add barbers',
      'add staff',
      'add employee',
      'create barber',
      'hire barber',
      'can we add barbers',
      'can we add barber',
      'can you add barber',
    };

    const invalidServiceNames = {
      'hairstyle',
      'hairstyles',
      'service',
      'services',
      'catalog',
      'catalogs',
      'haircut',
      'haircuts',
      'cut',
      'cuts',
      'item',
      'items',
      'new hairstyle',
      'new service',
      'new catalog',
      'add hairstyle',
      'add hairstyles',
      'add service',
      'add catalog',
      'can we add hairstyles',
      'can we add hairstyle',
      'custom haircut',
    };

    if (isStaff) {
      return invalidStaffNames.contains(lower) ||
          lower.startsWith('add ') ||
          lower.startsWith('create ') ||
          lower.startsWith('hire ');
    } else {
      return invalidServiceNames.contains(lower) ||
          lower.startsWith('add ') ||
          lower.startsWith('create ');
    }
  }

  static Map<String, dynamic>? _parseLocalAddService(String text) {
    try {
      var clean = text.replaceAll(
        RegExp(
          r'^(?:can\s+(?:you|we|i)\s+)?(?:please\s+)?(?:add|create)\s+(?:a\s+)?(?:new\s+)?(?:hairstyle|catalog|service|haircut)?s?(?:\s+to\s+catalog)?(?:\s*:\s*|\s+)',
          caseSensitive: false,
        ),
        '',
      ).trim();

      // Extract duration first (e.g. 30 mins, 45 minutes, 30 phút) so its
      // number is never mistaken for the price.
      int duration = 30;
      final durMatch = RegExp(r'(\d+)\s*(?:mins?|minutes?|phút)', caseSensitive: false)
          .firstMatch(clean);
      if (durMatch != null) {
        duration = int.tryParse(durMatch.group(1)!) ?? 30;
      }
      final priceSource = durMatch == null
          ? clean
          : clean.replaceRange(durMatch.start, durMatch.end, ' ');

      // Extract the price in VND: 80000, 80.000, 80,000, 80k, 80.000đ, 80000 VND.
      // No price given -> return null so the admin fills in the form instead
      // of the app guessing one.
      final priceMatch = RegExp(
        r'(\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?)\s*(k\b|nghìn|ngàn)?',
        caseSensitive: false,
      ).firstMatch(priceSource);
      if (priceMatch == null) return null;
      final price = priceMatch.group(2) != null
          ? (double.tryParse(priceMatch.group(1)!.replaceAll(',', '.')) ?? 0) * 1000
          : ShopInfo.parsePrice(priceMatch.group(1)!) ?? 0;
      if (price <= 0) return null;

      // Extract name: everything before the first price/duration keyword or number.
      var name = clean;
      final sepIdx = name.indexOf(RegExp(
        r'\b(?:for|price|priced|at|giá)\b|\d',
        caseSensitive: false,
      ));
      if (sepIdx > 0) {
        name = name.substring(0, sepIdx).trim();
      }
      name = name.replaceAll(RegExp(r'^(?:called|named)\s+', caseSensitive: false), '').trim();
      name = name.replaceAll(RegExp(r'[,\.\-:\?]+$'), '').trim();

      if (name.isEmpty || _isInvalidEntityName(name, isStaff: false)) {
        return null;
      }

      return {
        'name': name,
        'price': price,
        'duration_minutes': duration,
        'category_name': 'Haircuts',
        'description': 'Professional haircut style',
      };
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseLocalAddStaff(String text) {
    try {
      var clean = text.replaceAll(
        RegExp(
          r'^(?:can\s+(?:you|we|i)\s+)?(?:please\s+)?(?:add|create|hire|register)\s+(?:a\s+)?(?:new\s+)?(?:barber|employee|staff|stylist|team\s+member)?s?(?:\s*:\s*|\s+)',
          caseSensitive: false,
        ),
        '',
      ).trim();

      // Extract phone
      String phone = '';
      final phoneMatch = RegExp(r'(?:09|\+?639)\d{9}|\b\d{10,11}\b').firstMatch(clean);
      if (phoneMatch != null) {
        phone = phoneMatch.group(0)!;
      }

      // Extract email
      String email = '';
      final emailMatch = RegExp(r'[\w\.-]+@[\w\.-]+\.\w+').firstMatch(clean);
      if (emailMatch != null) {
        email = emailMatch.group(0)!;
      }

      // Extract name
      var name = clean;
      final sepIdx = name.indexOf(RegExp(r'\b(?:with|phone|mobile|contact|email|specialties|role|skills)\b', caseSensitive: false));
      if (sepIdx > 0) {
        name = name.substring(0, sepIdx).trim();
      }
      name = name.replaceAll(RegExp(r'^(?:called|named)\s+', caseSensitive: false), '').trim();
      name = name.replaceAll(RegExp(r'[,\.\-:\?]+$'), '').trim();

      if (name.isEmpty || _isInvalidEntityName(name, isStaff: true)) {
        return null;
      }

      return {
        'name': name,
        'role': 'Barber',
        'phone': phone,
        'email': email,
        'specialties': 'Classic Cuts, Styling',
      };
    } catch (_) {
      return null;
    }
  }

  /// Extracts the specific count requested by the user for a category
  /// (e.g. "provide 1 barber" -> 1, "give me 2 hairstyles" -> 2).
  /// Returns null if no specific count was requested (or if "all" was requested).
  static int? extractRequestedCount(
    String query, {
    required List<String> keywords,
  }) {
    final lower = query.toLowerCase();

    // If user explicitly asks for "all", "every", or "full", no cap
    if (lower.contains('all') || lower.contains('every') || lower.contains('full')) {
      return null;
    }

    final hasKeyword = keywords.any((k) => lower.contains(k));
    if (!hasKeyword) return null;

    const wordNumbers = {
      'one': 1,
      'a': 1,
      'an': 1,
      'single': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
    };

    final kwPattern = keywords.map(RegExp.escape).join('|');

    // 1. Direct digit before keyword: e.g. "1 hairstyle", "2 barbers", "3 cuts"
    final directDigit = RegExp(
        r'\b(\d+)\b(?:\s+(?:of\s+(?:the\s+)?|best\s+|clean\s+|popular\s+|top\s+)?){0,2}\s*(?:' +
            kwPattern +
            r')\b');
    final dMatch = directDigit.firstMatch(lower);
    if (dMatch != null) {
      final val = int.tryParse(dMatch.group(1)!);
      if (val != null && val > 0) return val;
    }

    // 2. Word number before keyword: e.g. "one barber", "two hairstyles"
    for (final entry in wordNumbers.entries) {
      final directWord = RegExp(r'\b' +
          entry.key +
          r'\b(?:\s+(?:of\s+(?:the\s+)?|best\s+|clean\s+|popular\s+|top\s+)?){0,2}\s*(?:' +
          kwPattern +
          r')\b');
      if (directWord.hasMatch(lower)) {
        return entry.value;
      }
    }

    // 3. Action verb + digit: e.g. "provide 1", "give me 2", "show 3"
    final verbDigit = RegExp(
        r'\b(?:provide|give(?:\s+me)?|show(?:\s+me)?|recommend|suggest|list|tell\s+me|display|pick)\s+(\d+)\b');
    final vMatch = verbDigit.firstMatch(lower);
    if (vMatch != null) {
      final val = int.tryParse(vMatch.group(1)!);
      if (val != null && val > 0) return val;
    }

    // 4. Action verb + word number: e.g. "provide one", "give me two"
    for (final entry in wordNumbers.entries) {
      final verbWord = RegExp(
          r'\b(?:provide|give(?:\s+me)?|show(?:\s+me)?|recommend|suggest|list|tell\s+me|display|pick)\s+' +
              entry.key +
              r'\b');
      if (verbWord.hasMatch(lower)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Answers simple barber/service questions straight from the database when
  /// the AI service is unreachable. Returns null when it can't help.
  static Future<String?> _localCustomerFallback(List<AiMessage> messages) async {
    List<dynamic> services = [];
    List<dynamic> staff = [];
    try {
      final res = await Future.wait([
        SupabaseConfig.client
            .from(SupabaseConfig.servicesTable)
            .select('name, price, duration_minutes, description')
            .eq('is_active', true)
            .order('name'),
        SupabaseConfig.client
            .from(SupabaseConfig.staffDirectoryView)
            .select('name, role, skills, phone, profile_photo')
            .eq('is_active', true)
            .order('name'),
      ]);
      services = SupabaseServiceHelpers.asMapList(res[0]);
      staff = SupabaseServiceHelpers.asMapList(res[1]);
    } catch (_) {
      return null;
    }

    // Smart Local Fallback: If all Gemini models are exhausted, answer directly from database
    final lastQuery =
        messages.isNotEmpty ? messages.last.content.toLowerCase() : '';
    final isBarberQuery = lastQuery.contains('barber') ||
        lastQuery.contains('staff') ||
        lastQuery.contains('who works') ||
        lastQuery.contains('team') ||
        lastQuery.contains('stylist') ||
        lastQuery.contains('names of barber');

    final barberCount = extractRequestedCount(
      lastQuery,
      keywords: ['barber', 'barbers', 'stylist', 'stylists', 'staff'],
    );
    final serviceCount = extractRequestedCount(
      lastQuery,
      keywords: [
        'hairstyle',
        'hairstyles',
        'haircut',
        'haircuts',
        'service',
        'services',
        'cut',
        'cuts'
      ],
    );

    if (isBarberQuery && staff.isNotEmpty) {
      var bListStaff = staff.where((st) {
        final role = (st['role'] ?? '').toString().toLowerCase();
        return !role.contains('admin') && !role.contains('cashier');
      }).toList();

      if (barberCount != null && barberCount > 0) {
        bListStaff = bListStaff.take(barberCount).toList();
      }

      final bList = bListStaff
          .map((st) =>
              '• **${st['name']}** — ${st['role']}${st['skills'] != null && st['skills'].toString().isNotEmpty ? ' (Specialties: ${st['skills']})' : ''}')
          .join('\n\n');

      final countIntro = barberCount != null && barberCount > 0
          ? (barberCount == 1 ? 'Here is 1 barber from' : 'Here are $barberCount barbers from')
          : 'Here are our talented barbers and stylists at';

      return "$countIntro Liem Barber Shop:\n\n$bList\n\nYou can view their profile and book directly using the ${barberCount == 1 ? 'card' : 'cards'} below!";
    }

    if (services.isNotEmpty) {
      var sList = services.toList();
      if (serviceCount != null && serviceCount > 0) {
        sList = sList.take(serviceCount).toList();
      }

      final bullets = sList
          .map((s) =>
              '• **${s['name']}** — ${ShopInfo.formatPrice(s['price'])} (${s['duration_minutes']} mins)${s['description'] != null && s['description'].toString().isNotEmpty ? '\n  _${s['description']}_' : ''}')
          .join('\n\n');

      final countIntro = serviceCount != null && serviceCount > 0
          ? (serviceCount == 1 ? 'Here is 1 hairstyle from' : 'Here are $serviceCount hairstyles from')
          : 'Here is our full list of available hairstyles and grooming services from';

      return "$countIntro our catalog:\n\n$bullets\n\nYou can click **\"View Hairstyle\"** or **\"Book This\"** below to schedule your appointment directly!";
    }

    return null;
  }

  /// Persist an individual message (e.g. appointment booking confirmation) to Supabase
  static Future<void> saveMessage({
    required String sessionId,
    required String role,
    required String content,
  }) async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) return;
    try {
      await SupabaseConfig.client.from('ai_messages').insert({
        'user_id': session.user.id,
        'session_id': sessionId,
        'role': role,
        'content': content,
      });
    } catch (_) {}
  }

  /// Load all messages for the given [sessionId] from Supabase (strictly scoped to current user)
  static Future<List<AiMessage>> loadSessionHistory(String sessionId) async {
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return [];

      final data = await SupabaseConfig.client
          .from('ai_messages')
          .select()
          .eq('session_id', sessionId)
          .eq('user_id', uid)
          .order('created_at', ascending: true);
      return SupabaseServiceHelpers.asMapList(data)
          .map(AiMessage.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Load grouped chat sessions from Supabase cloud
  static Future<List<AiChatSession>> loadUserChatSessionsFromSupabase(
      {int limit = 20}) async {
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return [];

      final data = await SupabaseConfig.client
          .from('ai_messages')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit * 30);

      final rows = SupabaseServiceHelpers.asMapList(data);
      final sessionMap = <String, List<AiMessage>>{};
      final sessionOrder = <String>[];
      final sessionDates = <String, DateTime>{};

      for (final row in rows) {
        final sid = (row['session_id'] ?? '').toString();
        if (sid.isEmpty) continue;
        if (!sessionMap.containsKey(sid)) {
          sessionMap[sid] = [];
          sessionOrder.add(sid);
          final ca = row['created_at'];
          if (ca != null) {
            sessionDates[sid] =
                DateTime.tryParse(ca.toString())?.toLocal() ?? DateTime.now();
          } else {
            sessionDates[sid] = DateTime.now();
          }
        }
        sessionMap[sid]!.add(AiMessage.fromJson(row));
      }

      return sessionOrder.take(limit).map((sid) {
        return AiChatSession(
          sessionId: sid,
          createdAt: sessionDates[sid] ?? DateTime.now(),
          messages: sessionMap[sid]!.reversed.toList(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
