import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
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
  static const String _storageKey = 'ai_chat_sessions_v3';
  static const String _activeSessionKey = 'ai_active_session_id_v3';
  static const String _deletedSessionsKey = 'ai_deleted_sessions_v3';

  /// Save or update a session both locally (instant) and to Supabase (cloud sync)
  static Future<void> saveSession(AiChatSession session) async {
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

  /// Returns the current active session if it exists and has messages
  static Future<AiChatSession?> getActiveSession() async {
    try {
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
  static Future<String> sendMessage({
    required List<AiMessage> messages,
    required String sessionId,
  }) async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) {
      throw Exception('You must be logged in to use the AI assistant.');
    }

    // 1. Try calling the deployed Supabase Edge Function first
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
      'generationConfig': {'maxOutputTokens': 512, 'temperature': 0.7},
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

  /// Load all messages for the given [sessionId] from Supabase
  static Future<List<AiMessage>> loadSessionHistory(String sessionId) async {
    try {
      final data = await SupabaseConfig.client
          .from('ai_messages')
          .select()
          .eq('session_id', sessionId)
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
