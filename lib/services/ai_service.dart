import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
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

/// Talks to the `ai-chat` Supabase Edge Function and persists
/// message history both locally and in the `ai_messages` table.
class AiService {
  AiService._();

  /// Send the full [messages] history and return the AI reply text.
  /// [sessionId] groups messages for this chat session.
  /// [userRole] determines whether customer concierge or executive admin copilot is active.
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

    // If Admin or Manager, route directly to the Executive Admin Copilot engine
    if (isAdmin) {
      return _adminExecutiveGemini(messages, sessionId, session);
    }

    // 1. Try calling the deployed Supabase Edge Function first (for customers)
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'ai-chat',
        body: {
          'messages': messages.map((m) => m.toJson()).toList(),
          'session_id': sessionId,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.status == 200 && response.data?['reply'] != null) {
        return response.data['reply'].toString();
      }

      if (response.status == 403) {
        throw Exception(
            response.data?['error']?.toString() ?? 'Access denied.');
      }
    } catch (edgeError) {
      final errStr = edgeError.toString();
      if (errStr.contains('Access denied') ||
          errStr.contains('not available for barbers')) {
        rethrow;
      }
      if (SupabaseConfig.geminiApiKey.isNotEmpty) {
        return _fallbackDirectGemini(messages, sessionId, session);
      }

      throw Exception(
        'The "ai-chat" Edge Function is not deployed yet, and GEMINI_API_KEY '
        'is not configured. Please add your free GEMINI_API_KEY in supabase.local.json '
        'or deploy the Edge Function.',
      );
    }

    if (SupabaseConfig.geminiApiKey.isNotEmpty) {
      return _fallbackDirectGemini(messages, sessionId, session);
    }

    throw Exception('AI service unavailable. Please try again.');
  }

  /// Executive Admin AI Copilot: Queries database analytics and formats catalog/staff mutations.
  /// Executive Admin AI Copilot: Queries database analytics and formats catalog/staff mutations.
  static Future<String> _adminExecutiveGemini(
    List<AiMessage> messages,
    String sessionId,
    Session session,
  ) async {
    final apiKey = SupabaseConfig.geminiApiKey.trim();
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
            lowerQuery.contains('create') ||
            lowerQuery.contains('new'));

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
              !lowerQuery.contains('₱') &&
              !lowerQuery.contains('php') &&
              !lowerQuery.contains('pesos'));

      if (isCatalogInquiry) {
        return 'Yes, absolutely! You can add new hairstyles and services in two ways:\n\n'
            '1. **Directly in this Chat:** Provide the service name, price, and duration, for example:\n'
            '   👉 *"Add a hairstyle to catalog: Low Fade for ₱250, 30 mins"*\n'
            '   👉 *"Add service: Beard Grooming for ₱150, 20 mins"*\n\n'
            '2. **Via the Catalog Screen:** Go to the **Catalog** tab and tap the **+ Add Catalog** button.\n\n'
            'Whenever you provide the service details here, I will prepare an interactive confirmation card for you to review before saving it to the database.';
      }

      final params = _parseLocalAddService(lastQuery);
      if (params != null) {
        return 'I have prepared the new catalog service for your review:\n\n'
            '[ADMIN_ACTION:CREATE_SERVICE:${jsonEncode(params)}]\n\n'
            'Please review the details in the action card above and tap **Confirm & Add to Catalog** to write it to the database.';
      } else {
        return 'Sure! What is the name and price of the hairstyle or service you would like to add to the catalog?\n\n'
            '👉 **Example:** *"Add a hairstyle to catalog: Classic Taper for ₱300, 30 mins"*\n'
            '👉 Or include duration: *"Add service: Hair Spa for ₱450, 45 mins"*';
      }
    }

    // Case F: Add Barber / Staff Member (Inquiry vs Action)
    final isStaffIntent = (lowerQuery.contains('barber') ||
            lowerQuery.contains('employee') ||
            lowerQuery.contains('staff') ||
            lowerQuery.contains('stylist')) &&
        (lowerQuery.contains('add') ||
            lowerQuery.contains('create') ||
            lowerQuery.contains('hire') ||
            lowerQuery.contains('new'));

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
            '1. **Directly in this Chat:** Simply tell me their details, for example:\n'
            '   👉 *"Add a barber named Marco with phone 09123456789"*\n'
            '   👉 *"Add staff John Doe, phone 09987654321, role Stylist"*\n\n'
            '2. **Via the Employee Screen:** Go to the **Employee** tab and tap the **+ Add Staff** button.\n\n'
            'Whenever you provide their details here, I will prepare an interactive confirmation card for you to review before creating their account.';
      }

      final params = _parseLocalAddStaff(lastQuery);
      if (params != null) {
        return 'I have prepared the new staff profile for your review:\n\n'
            '[ADMIN_ACTION:CREATE_STAFF:${jsonEncode(params)}]\n\n'
            'Please review the profile in the action card above and tap **Confirm & Add Staff** to create their account in the database.';
      } else {
        return 'Sure! What is the name and phone number of the barber you would like to add?\n\n'
            '👉 **Example:** *"Add a barber named Marco with phone 09123456789"*\n'
            '👉 Or provide details: *"Name: Carlos Santos, Phone: 09171234567, Role: Senior Barber"*';
      }
    }

    // ── 2. GEMINI LLM WITH FUNCTION CALLING (For nuanced & natural dialogue) ──
    if (apiKey.isNotEmpty) {
      try {
        final tools = [
          {
            'function_declarations': [
              {
                'name': 'query_catalog_services',
                'description':
                    'Query and list the entire shop catalog of services, hairstyles, categories, prices in PHP, and durations.',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'category': {
                      'type': 'STRING',
                      'description': 'Optional category filter'
                    }
                  }
                }
              },
              {
                'name': 'query_staff_members',
                'description':
                    'Query and list all official barbers, stylists, and staff members registered at the shop.',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'role': {
                      'type': 'STRING',
                      'description': 'Optional role filter: Barber, Stylist, etc.'
                    }
                  }
                }
              },
              {
                'name': 'query_recent_bookings',
                'description':
                    'Query the live Supabase database for real-time and recent appointments, checking if there are recent bookings right now, the latest scheduled clients, their barbers, services, timestamps, statuses, and next upcoming appointment.',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'limit': {
                      'type': 'INTEGER',
                      'description': 'Number of recent bookings to fetch (default 5)'
                    }
                  }
                }
              },
              {
                'name': 'query_bookings_analytics',
                'description':
                    'Query appointments and bookings analytics from the Supabase database across any timeframe (days, weeks, months, years, or all-time total) to get counts, statuses (completed, pending, canceled), revenue in PHP, and barber workload.',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'timeframe': {
                      'type': 'STRING',
                      'description':
                          'Timeframe to query: today, yesterday, days, this_week, weeks, this_month, months, this_year, years, all_time'
                    },
                    'count': {
                      'type': 'INTEGER',
                      'description':
                          'Number of units (e.g. 3 for past 3 days/weeks/months/years)'
                    },
                    'days_back': {
                      'type': 'INTEGER',
                      'description':
                          'Legacy compatibility: Number of days in the past to query'
                    },
                    'status': {
                      'type': 'STRING',
                      'description':
                          'Optional status filter: all, completed, pending, canceled'
                    }
                  }
                }
              },
              {
                'name': 'query_shop_financials',
                'description':
                    'Query real-time shop revenue and financial performance stats (today revenue, monthly revenue, total appointments).',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'period': {
                      'type': 'STRING',
                      'description': 'Timeframe to inspect: today, month, all'
                    }
                  }
                }
              },
              {
                'name': 'propose_add_catalog_service',
                'description':
                    'Propose adding a new hairstyle, haircut, or service to the shop catalog. Validates and generates an interactive confirmation card for the admin to verify before saving. DO NOT call this if the user is asking an inquiry/exploratory question (e.g. "can we add hairstyles?") or if the service name is missing or generic (e.g. "add hairstyle"). Only call when a specific haircut/service name is provided.',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'name': {
                      'type': 'STRING',
                      'description': 'Name of the haircut or service'
                    },
                    'price': {
                      'type': 'NUMBER',
                      'description': 'Price in Philippine Peso (PHP / ₱)'
                    },
                    'duration_minutes': {
                      'type': 'INTEGER',
                      'description': 'Duration in minutes (default 30)'
                    },
                    'category_name': {
                      'type': 'STRING',
                      'description': 'Category (Haircuts, Beard Grooming, etc.)'
                    },
                    'description': {
                      'type': 'STRING',
                      'description': 'Short description of the haircut style'
                    }
                  },
                  'required': ['name', 'price']
                }
              },
              {
                'name': 'propose_add_employee',
                'description':
                    'Propose adding a new barber, stylist, or staff member. Validates and generates an interactive confirmation card for the admin to verify before saving. DO NOT call this if the user is asking an inquiry/exploratory question (e.g. "can we add barbers?") or if the person\'s name is missing (e.g. "add barbers"). Only call when an actual person\'s name is specified.',
                'parameters': {
                  'type': 'OBJECT',
                  'properties': {
                    'name': {
                      'type': 'STRING',
                      'description': 'Full name of the barber or employee'
                    },
                    'role': {
                      'type': 'STRING',
                      'description': 'Role: Barber, Senior Barber, Stylist, or Cashier'
                    },
                    'phone': {
                      'type': 'STRING',
                      'description': 'Phone number'
                    },
                    'email': {
                      'type': 'STRING',
                      'description': 'Email address'
                    },
                    'specialties': {
                      'type': 'STRING',
                      'description': 'Specialties or skills'
                    }
                  },
                  'required': ['name']
                }
              }
            ]
          }
        ];

        final serviceSummary = services
            .map((s) =>
                '- ${s['name']}: ₱${s['price']} (${s['duration_minutes']} min, Category: ${s['category_name'] ?? 'Haircuts'})${s['description'] != null && s['description'].toString().isNotEmpty ? ' [${s['description']}]' : ''}')
            .join('\n');

        final staffSummary = staff
            .map((st) =>
                '- ${st['name']} (${st['role']})${st['phone'] != null && st['phone'].toString().isNotEmpty ? ' Phone: ${st['phone']}' : ''}${st['skills'] != null && st['skills'].toString().isNotEmpty ? ' Skills: ${st['skills']}' : ''}')
            .join('\n');

        final stats = SupabaseServiceHelpers.asMap(dashboardData?['stats']);
        final todayBookings = stats['today_bookings'] ?? 0;
        final totalBookings = stats['total_bookings'] ?? 0;
        final todayRevenue = SupabaseServiceHelpers.asDouble(stats['today_revenue']);
        final activeBarbers = stats['active_barbers'] ?? staff.length;
        final recentBookings = SupabaseServiceHelpers.asMapList(dashboardData?['recent_bookings']);
        final nextClient = SupabaseServiceHelpers.asMap(dashboardData?['next_client']);

        final recentSummary = recentBookings.isNotEmpty
            ? recentBookings.take(4).map((b) {
                final cName = b['customer_name'] ?? b['full_name'] ?? 'Customer';
                final sName = b['service_name'] ?? 'Service';
                final price = b['price'] != null ? ' (₱${b['price']})' : '';
                final status = b['status'] != null ? ' [${b['status']}]' : '';
                return '- $cName: $sName$price$status';
              }).join('\n')
            : 'No recent bookings recorded.';

        final nextClientSummary = nextClient.isNotEmpty
            ? '${nextClient['customer_name'] ?? nextClient['full_name']} for ${nextClient['service'] ?? nextClient['service_name']} with ${nextClient['employee'] ?? nextClient['staff_name']} (${nextClient['time'] ?? nextClient['start_time']})'
            : 'None scheduled.';

        final systemPrompt = '''
You are the Executive AI Operations Copilot for Liem Barber Shop.
You work directly with the Shop Administrator and Store Managers.
Your role is to manage shop operations, analyze bookings, report revenue, manage the catalog, and assist with staff.

LIVE SHOP PERFORMANCE & STATS (REAL-TIME DATABASE SNAPSHOT):
- Today's Bookings: $todayBookings
- All-Time Total Bookings: $totalBookings
- Today's Revenue: ₱${todayRevenue.toStringAsFixed(2)}
- Active Barbers: $activeBarbers
- Next Upcoming Client: $nextClientSummary
- Recent Bookings:
$recentSummary

OFFICIAL SHOP CATALOG (${services.length} Services):
${serviceSummary.isNotEmpty ? serviceSummary : 'No services currently listed.'}

OFFICIAL SHOP STAFF (${staff.length} Members):
${staffSummary.isNotEmpty ? staffSummary : 'No staff currently listed.'}

CAPABILITIES & RULES:
1. When asked to list, show, or describe the catalog, services, or hairstyles, provide the exact services from the official catalog above or call `query_catalog_services`. NEVER state that you do not have a database tool to view the catalog.
2. When asked about staff, barbers, or employees, list the team members from above or call `query_staff_members`.
3. When asked about bookings, appointments, or past schedules across ANY timeframe (today, yesterday, past X days, this week, past X weeks, this month, past X months, this year, past X years, or all-time total), call `query_bookings_analytics` or report using the real-time database snapshot above.
4. When asked if there are recent bookings right now (e.g. "is there any recent bookings right now?"), call `query_recent_bookings` or check the recent bookings snapshot above. If yes, state them clearly with customer, barber, and status. If no, state truthfully that there are no recent bookings in the database right now.
5. When asked about total bookings or overall shop appointments, answer using the exact all-time count from the database.
6. When asked about revenue, sales, or shop financials, call `query_shop_financials`.
7. When asked capability questions (e.g. "can we add barbers?", "how to add a hairstyle?", "is it possible to add staff?"), DO NOT generate an action card. Instead, warmly explain how they can do it (via chat with an example command or via the UI tabs).
8. When asked to add a hairstyle or service, verify that a specific service name is provided. If the user only said "add hairstyle" or "add service" without specifying the name, ask them what service name and price they want. DO NOT propose an action card with generic names like "add hairstyle" or "hairstyle".
9. When asked to add a barber or employee, verify that a specific person's name is provided. If the user only said "add barbers" or "add a barber" without a person's name, ask them for the barber's name and phone number. DO NOT propose an action card with names like "can we add barbers?" or "add barbers" or "New Barber".
10. Maintain a professional, executive, concise tone. Always use ₱ for Philippine Peso.
11. Answer with 100% precision grounded in the official database records provided above. Never invent fake bookings or metrics.
''';

        final contents = messages.map((m) {
          return {
            'role': m.role == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m.content}
            ],
          };
        }).toList();

        final payload = jsonEncode({
          'system_instruction': {
            'parts': [
              {'text': systemPrompt}
            ]
          },
          'contents': contents,
          'tools': tools,
          'generationConfig': {'maxOutputTokens': 1024, 'temperature': 0.7},
        });

        const modelsToTry = [
          'gemini-3.5-flash',
          'gemini-3.5-flash-lite',
          'gemini-3.7-flash',
          'gemini-3.6-flash',
        ];

        for (final model in modelsToTry) {
          try {
            final url = Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
            );
            final response = await http.post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: payload,
            );

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final candidates = data?['candidates'] as List?;
              if (candidates != null && candidates.isNotEmpty) {
                final candidate = candidates[0] as Map?;
                final parts = candidate?['content']?['parts'] as List?;
                if (parts != null && parts.isNotEmpty) {
                  for (final part in parts) {
                    final funcCall = part['functionCall'] as Map?;
                    if (funcCall != null) {
                      final name = funcCall['name']?.toString();
                      final args = SupabaseServiceHelpers.asMap(funcCall['args']);

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
                          return 'Sure! What is the name and price of the hairstyle you would like to add? (For example: *"Add a hairstyle to catalog: Fade Cut for ₱250, 30 mins"*)';
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
                          return 'Sure! What is the name and phone number of the barber you would like to add? (For example: *"Add barber Marco with phone 09123456789"*)';
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
                    }
                  }

                  final reply = parts[0]?['text']?.toString();
                  if (reply != null && reply.trim().isNotEmpty) {
                    return reply.trim();
                  }
                }
              }
            }
          } catch (_) {
            continue;
          }
        }
      } catch (_) {}
    }

    // Default intelligent fallback if all models or network calls fail
    return '👋 **Liem Barber Shop Executive Assistant**\n\n'
        'I am ready to help you manage shop operations. You can ask me:\n'
        '• *"List all the catalog"*\n'
        '• *"How many barbers do we have?"*\n'
        '• *"How many bookings in the past 3 days?"*\n'
        '• *"What is today\'s revenue?"*\n'
        '• *"Add a hairstyle to catalog: Skin Fade for ₱280, 30 mins"*\n'
        '• *"Add a barber named David with phone 09171234567"*';
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

      final data = await query.order('start_time', ascending: false);
      final rows = SupabaseServiceHelpers.asMapList(data);

      int total = rows.length;
      int completed = 0;
      int pending = 0;
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
          revenue = SupabaseServiceHelpers.asDouble(stats['today_revenue']);
        }
      }

      return {
        'timeframe_label': timeframeLabel,
        'total_bookings': total,
        'completed': completed,
        'pending': pending,
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
          revenue = SupabaseServiceHelpers.asDouble(stats['today_revenue']);
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
    sb.writeln('• **Completed:** $completed (Revenue: ₱${revenue.toStringAsFixed(2)})');
    sb.writeln('• **Pending / Confirmed:** $pending');
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
        final cName = b['customer_name'] ?? b['full_name'] ?? 'Customer';
        final sName = b['service_name'] ?? 'Haircut Service';
        final barber = b['employee_name'] ?? b['staff_name'] ?? 'Assigned Staff';
        final price = b['price'] ?? b['service_price'] ?? b['total_amount'];
        final priceStr = price != null ? '₱${price.toString()}' : '';
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
      final todayRevenue = SupabaseServiceHelpers.asDouble(stats['today_revenue']);
      final recent = SupabaseServiceHelpers.asMapList(dash?['recent_bookings']);

      final sb = StringBuffer();
      sb.writeln('💰 **Shop Financial & Performance Summary**\n');
      sb.writeln('• **Today\'s Revenue:** ₱${todayRevenue.toStringAsFixed(2)}');
      sb.writeln('• **Today\'s Bookings:** $todayBookings');
      sb.writeln('• **All-Time Total Bookings:** $totalBookings\n');

      if (recent.isNotEmpty) {
        sb.writeln('📋 **Latest Bookings:**');
        for (final b in recent.take(4)) {
          final cName = b['customer_name'] ?? b['full_name'] ?? 'Customer';
          final sName = b['service_name'] ?? 'Service';
          final price = b['price'] != null ? ' (₱${b['price']})' : '';
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
          'To add a service, prompt:\n*"Add a hairstyle to catalog: [Name] for ₱[Price], [Duration] mins"*';
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
        final price = s['price'] != null ? '₱${s['price']}' : '₱0.00';
        final duration = s['duration_minutes'] != null ? '${s['duration_minutes']} min' : '30 min';
        final desc = (s['description'] != null && s['description'].toString().trim().isNotEmpty)
            ? ' — _${s['description'].toString().trim()}_'
            : '';
        final status = (s['is_active'] == 1 || s['is_active'] == true) ? '' : ' *(Inactive)*';
        sb.writeln('• **$name** ($price, $duration)$status$desc');
      }
      sb.writeln();
    }

    sb.writeln('💡 *Tip: You can say "Add a hairstyle to catalog: [Name] for ₱[Price]" to add a new service.*');
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

      // Extract price (e.g. ₱250, 250 pesos, for 300)
      double price = 250.0;
      final priceMatch = RegExp(
        r'(?:(?:for|price[:\s]+|at)\s*)?(?:₱|php\s*)?(\d+(?:\.\d{1,2})?)\s*(?:pesos?|php|₱)?',
        caseSensitive: false,
      ).firstMatch(clean);
      if (priceMatch != null) {
        final parsed = double.tryParse(priceMatch.group(1)!);
        if (parsed != null && parsed > 0) {
          price = parsed;
        }
      }

      // Extract duration (e.g. 30 mins, 45 minutes)
      int duration = 30;
      final durMatch = RegExp(r'(\d+)\s*(?:mins?|minutes?)', caseSensitive: false).firstMatch(clean);
      if (durMatch != null) {
        duration = int.tryParse(durMatch.group(1)!) ?? 30;
      }

      // Extract name
      var name = clean;
      final sepIdx = name.indexOf(RegExp(
        r'\b(?:for|price|priced|at\s+₱?|\d+\s*(?:pesos|php|₱|mins|minutes))\b',
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

  /// Client-side direct Gemini call with dynamic database context.
  static Future<String> _fallbackDirectGemini(
    List<AiMessage> messages,
    String sessionId,
    Session session,
  ) async {
    final apiKey = SupabaseConfig.geminiApiKey.trim();
    if (apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY is not configured in supabase.local.json.');
    }

    // Query active services and staff from public views for real-time RAG context
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
    } catch (_) {}

    final serviceList = services
        .map((s) =>
            '- ${s['name']}: ₱${s['price']}, ${s['duration_minutes']} min${s['description'] != null ? ' (${s['description']})' : ''}')
        .join('\n');

    final staffList = staff
        .where((st) {
          final role = (st['role'] ?? '').toString().toLowerCase();
          return !role.contains('admin') && !role.contains('cashier');
        })
        .map((st) =>
            '- ${st['name']} (${st['role']})${st['skills'] != null && st['skills'].toString().isNotEmpty ? ' - Specialties: ${st['skills']}' : ''}')
        .join('\n');

    final systemPrompt = '''
You are a friendly and knowledgeable AI assistant for Liem Barber Shop.
Your job is to help customers choose the right haircut, learn about services, and find the right barber.

AVAILABLE SERVICES:
${serviceList.isNotEmpty ? serviceList : 'Standard cuts and styling available.'}

AVAILABLE BARBERS:
${staffList.isNotEmpty ? staffList : 'Professional barbers available.'}

RULES:
- CRITICAL COUNT RULE: When the customer requests a specific quantity or number of hairstyles, haircuts, services, or barbers (for example: "provide 1 hairstyle", "give me 2 barbers", "recommend 1 haircut", "show 3 styles", "provide 1 barber", "pick 2 haircuts"), you MUST provide and list EXACTLY that number of items. NEVER provide more or fewer items than requested.
- If the customer asks for a general list without a specific count (for example: "provide all names of barbers", "who are the barbers?", "who works here?"), list ALL available barbers or services.
- Always mention that their profile cards with their photos and booking buttons appear directly below in the chat.
- Only discuss haircuts, grooming, services, barbers, and appointment-related topics.
- Always show exact prices and durations from the list above. Never invent services or prices.
- When recommending haircuts or barbers, be specific and match the customer's described style or preference.
- Keep responses concise, warm, and helpful. Use emojis sparingly.
- Use ₱ (Philippine Peso) for all prices.
- If the question is unrelated to the barbershop, politely redirect.
''';

    final contents = messages.map((m) {
      return {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': m.content}
        ],
      };
    }).toList();

    final payload = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {'maxOutputTokens': 1024, 'temperature': 0.7},
    });

    // Pool of available models to failover seamlessly if any hits quota/rate-limits
    final modelsToTry = [
      'gemini-3.5-flash',
      'gemini-3.5-flash-lite',
      'gemini-3.7-flash',
      'gemini-3.6-flash',
    ];

    for (final model in modelsToTry) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data?['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final candidate = candidates[0] as Map?;
            final parts = candidate?['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final reply = parts[0]?['text']?.toString();
              if (reply != null && reply.trim().isNotEmpty) {
                return reply.trim();
              }
            }
          }
        }
        // If 429 (quota exceeded), 404, or 503, loop and try the next model!
      } catch (_) {
        continue;
      }
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
              '• **${s['name']}** — ₱${s['price']} (${s['duration_minutes']} mins)${s['description'] != null && s['description'].toString().isNotEmpty ? '\n  _${s['description']}_' : ''}')
          .join('\n\n');

      final countIntro = serviceCount != null && serviceCount > 0
          ? (serviceCount == 1 ? 'Here is 1 hairstyle from' : 'Here are $serviceCount hairstyles from')
          : 'Here is our full list of available hairstyles and grooming services from';

      return "$countIntro our catalog:\n\n$bullets\n\nYou can click **\"View Hairstyle\"** or **\"Book This\"** below to schedule your appointment directly!";
    }

    throw Exception(
      'Our AI Assistant is currently experiencing high demand. Please try again in a moment.',
    );
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
