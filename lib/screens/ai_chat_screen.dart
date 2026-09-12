import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/api_config.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';
import '../services/auth_session_service.dart';
import '../services/catalog_service.dart';
import '../services/employee_service.dart';

// Modern Executive Brand Palette (Liem Barber & Store Operations)
const Color _primaryBlue = Color(0xFF5BBCFF); // App brand primary seed
const Color _primaryDeep = Color(0xFF1E88E5); // Rich royal blue
const Color _surfaceDark = Color(0xFF18181B); // Deep slate / Zinc 900
const Color _surfaceBorder = Color(0xFFE4E4E7); // Subtle hairline border / Zinc 200
const Color _surfaceLight = Color(0xFFF4F4F5); // Clean light neutral fill / Zinc 100
const Color _textPrimary = Color(0xFF18181B);
const Color _textSecondary = Color(0xFF71717A); // Neutral slate / Zinc 500
const Color _accentOnline = Color(0xFF10B981); // Emerald green for online badge
const LinearGradient _brandGradient = LinearGradient(
  colors: [Color(0xFF5BBCFF), Color(0xFF1E88E5)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Full-screen AI chat page with interactive Hairstyle Previews and Direct In-Chat Booking.
///
/// Entry point: [AiChatScreen.open(context)] from any screen.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiChatScreen()),
    );
  }

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<AiMessage> _messages = [];
  String _sessionId = '';
  bool _isLoading = false;
  String? _errorText;
  String? _userRole;
  String? _userName;
  String? _customerId;

  List<Map<String, dynamic>> _catalogServices = [];
  List<Map<String, dynamic>> _availableBarbers = [];
  List<Map<String, dynamic>> _catalogCategories = [];
  final Set<String> _confirmedActions = {};
  final Set<String> _submittingActions = {};

  late final AnimationController _dotController;


  static const _customerSuggestions = [
    '💈  Provide all names of barbers',
    '✂️  Suggest a clean haircut for me',
    '💈  What services are available?',
    '⭐  Which barber is best for fades?',
    '🕐  How long does a beard trim take?',
    '💰  What are the cheapest services?',
    '🎨  Best hairstyle for curly hair?',
  ];

  static const _adminSuggestions = [
    '📊  How many bookings in the past 3 days?',
    '📅  Show today\'s appointment schedule',
    '💰  What is today\'s revenue & stats?',
    '✂️  Add a hairstyle to catalog',
    '👥  Add a new barber to staff',
    '📋  List all catalog services',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AiHistoryStorage.recordActivity();
    _sessionId = _generateUuidV4();
    _dotController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    _loadUserInfo();
    _loadCatalogAndBarbers();
    _restoreActiveSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      AiHistoryStorage.recordActivity();
    } else if (state == AppLifecycleState.resumed) {
      _checkInactivityAndResetIfNeeded();
    }
  }

  Future<void> _checkInactivityAndResetIfNeeded() async {
    final expired = await AiHistoryStorage.hasInactivityExpired();
    if (expired && mounted) {
      await AiHistoryStorage.clearActiveSession();
      setState(() {
        _sessionId = _generateUuidV4();
        _messages.clear();
        _errorText = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'New conversation started after 10 minutes of inactivity.',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.white),
            ),
            backgroundColor: _surfaceDark,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _restoreActiveSession() async {
    try {
      final expired = await AiHistoryStorage.hasInactivityExpired();
      if (expired) {
        await AiHistoryStorage.clearActiveSession();
        return;
      }

      final active = await AiHistoryStorage.getActiveSession();
      if (active != null && active.messages.isNotEmpty && mounted) {
        setState(() {
          _sessionId = active.sessionId;
          _messages.clear();
          _messages.addAll(active.messages);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 150), () {
            _scrollToBottom();
          });
        });
      }
    } catch (_) {}
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // version 4
    values[8] = (values[8] & 0x3f) | 0x80; // variant
    return [
      values.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ].join('-');
  }

  Future<void> _loadUserInfo() async {
    try {
      final session = await AuthSessionService.getSession();
      if (session != null && mounted) {
        setState(() {
          _userRole = session['role']?.toString() ?? 'customer';
          _userName = session['full_name']?.toString() ??
              session['username']?.toString() ??
              'User';
          _customerId = session['customer_id']?.toString() ??
              session['id']?.toString();
        });

        if ((_customerId == null || _customerId!.isEmpty) &&
            session['user_id'] != null) {
          final cust = await ApiService.getCustomerByUserId(
              session['user_id'].toString());
          if (cust != null && cust['customer_id'] != null && mounted) {
            setState(() {
              _customerId = cust['customer_id'].toString();
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCatalogAndBarbers() async {
    try {
      final results = await Future.wait([
        CatalogService.getAllServices(forceRefresh: true),
        EmployeeService.getAllEmployees(forceRefresh: true),
        CatalogService.getAllCategories(forceRefresh: true),
      ]);
      if (mounted) {
        setState(() {
          _catalogServices = results[0];
          _availableBarbers = results[1].where((e) {
            final role = (e['role'] ?? '').toString().toLowerCase();
            return !role.contains('admin') && !role.contains('cashier');
          }).toList();
          _catalogCategories = results[2];
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AiHistoryStorage.recordActivity();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _dotController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    HapticFeedback.lightImpact();
    _controller.clear();
    final userMsg = AiMessage(
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
      _errorText = null;
    });
    _scrollToBottom();

    // Persist immediately so user message is never lost
    AiHistoryStorage.saveSession(
      AiChatSession(
        sessionId: _sessionId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: List.from(_messages),
      ),
    );

    try {
      final reply = await AiService.sendMessage(
        messages: _messages,
        sessionId: _sessionId,
        userRole: _userRole ?? 'customer',
      );
      if (!mounted) return;
      final aiMsg = AiMessage(
        role: 'assistant',
        content: reply,
        createdAt: DateTime.now(),
      );
      setState(() {
        _messages.add(aiMsg);
        _isLoading = false;
      });

      // Persist full exchange
      AiHistoryStorage.saveSession(
        AiChatSession(
          sessionId: _sessionId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: List.from(_messages),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      String cleanError = raw;
      if (raw.toLowerCase().contains('quota') ||
          raw.toLowerCase().contains('rate_limit') ||
          raw.toLowerCase().contains('429')) {
        cleanError =
            'AI capacity reached. Please wait a few seconds and try again.';
      }
      setState(() {
        _isLoading = false;
        _errorText = cleanError;
      });
    }
    _scrollToBottom();
  }

  void _startNewChat() {
    AiHistoryStorage.clearActiveSession();
    setState(() {
      _sessionId = _generateUuidV4();
      _messages.clear();
      _errorText = null;
    });
  }

  bool get _isAdmin =>
      _userRole == 'admin' || _userRole == 'manager' || _userRole == 'cashier';

  /// Extracts any matching services from the shop's catalog referenced in text
  /// Extracts any matching services from the shop's catalog referenced in text
  List<Map<String, dynamic>> _findRecommendedServices(
    String text, {
    String? userPrompt,
  }) {
    if (_catalogServices.isEmpty) return [];
    final lower = text.toLowerCase();
    final lowerPrompt = (userPrompt ?? '').toLowerCase();

    // If the user specifically asked for barbers/staff and did NOT ask for hairstyles/services, suppress services
    if (lowerPrompt.isNotEmpty) {
      final askedForBarbers = lowerPrompt.contains('barber') ||
          lowerPrompt.contains('stylist') ||
          lowerPrompt.contains('who works') ||
          lowerPrompt.contains('staff') ||
          lowerPrompt.contains('team') ||
          lowerPrompt.contains('who can cut');
      final askedForServices = lowerPrompt.contains('hairstyle') ||
          lowerPrompt.contains('haircut') ||
          lowerPrompt.contains('service') ||
          lowerPrompt.contains('cut') ||
          lowerPrompt.contains('style') ||
          lowerPrompt.contains('catalog');
      if (askedForBarbers && !askedForServices) {
        return [];
      }
    }

    final matched = <Map<String, dynamic>>[];
    for (final s in _catalogServices) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      if (name.isNotEmpty && lower.contains(name)) {
        matched.add(s);
      }
    }

    List<Map<String, dynamic>> resultList = matched;
    if (resultList.isEmpty) {
      final isGeneral = lower.contains('haircut') ||
          lower.contains('hairstyle') ||
          lower.contains('style') ||
          lower.contains('service');
      if (isGeneral) {
        resultList = List.from(_catalogServices);
      }
    }

    if (userPrompt != null && userPrompt.isNotEmpty && resultList.isNotEmpty) {
      final count = AiService.extractRequestedCount(
        userPrompt,
        keywords: [
          'hairstyle',
          'hairstyles',
          'haircut',
          'haircuts',
          'service',
          'services',
          'cut',
          'cuts',
          'style',
          'styles',
        ],
      );
      if (count != null && count > 0) {
        return resultList.take(count).toList();
      }
    }

    return resultList;
  }

  String _getServiceImage(Map<String, dynamic> service) {
    final img = (service['image_url'] ?? service['photo'] ?? '').toString();
    if (img.startsWith('http') || img.startsWith('assets/')) return img;
    final n = (service['name'] ?? '').toString().toLowerCase();
    final c = (service['category_name'] ?? '').toString().toLowerCase();
    if (n.contains('classic')) return 'assets/catalog/1.png';
    if (n.contains('fade') || n.contains('skin')) return 'assets/catalog/2.jpg';
    if (n.contains('kid') || n.contains('child')) return 'assets/catalog/3.jpg';
    if (n.contains('styling') || n.contains('style') || c.contains('styling')) {
      return 'assets/catalog/4.png';
    }
    if ((n.contains('beard') && !n.contains('haircut')) || c.contains('beard')) {
      return 'assets/catalog/5.jpg';
    }
    if (n.contains('beard') || n.contains('package')) {
      return 'assets/catalog/6.jpg';
    }
    return 'assets/catalog/1.png';
  }

  /// Extracts any matching barbers from the shop's staff referenced in text,
  /// or returns all available barbers if the message is a general query about barbers.
  /// Respects user-requested counts (e.g. "provide 1 barber" -> exactly 1 card).
  List<Map<String, dynamic>> _findRecommendedBarbers(
    String text, {
    String? userPrompt,
  }) {
    if (_availableBarbers.isEmpty) return [];
    final lower = text.toLowerCase();
    final lowerPrompt = (userPrompt ?? '').toLowerCase();

    // If the user specifically asked for hairstyles/services and NOT barbers, suppress barbers
    if (lowerPrompt.isNotEmpty) {
      final askedForServices = lowerPrompt.contains('hairstyle') ||
          lowerPrompt.contains('haircut') ||
          lowerPrompt.contains('service') ||
          lowerPrompt.contains('cut') ||
          lowerPrompt.contains('style') ||
          lowerPrompt.contains('price') ||
          lowerPrompt.contains('catalog');
      final askedForBarbers = lowerPrompt.contains('barber') ||
          lowerPrompt.contains('stylist') ||
          lowerPrompt.contains('who works') ||
          lowerPrompt.contains('staff') ||
          lowerPrompt.contains('team') ||
          lowerPrompt.contains('who can cut');
      if (askedForServices && !askedForBarbers) {
        return [];
      }
    }

    // Strip shop brand name so "Liem Barber Shop" doesn't falsely trigger general query
    final textWithoutShop = lower
        .replaceAll('liem barber shop', '')
        .replaceAll('liem barbershop', '')
        .replaceAll('barber shop', '')
        .replaceAll('barbershop', '');

    final matched = <Map<String, dynamic>>[];
    for (final b in _availableBarbers) {
      final name = (b['name'] ?? '').toString().toLowerCase();
      if (name.isNotEmpty && lower.contains(name)) {
        matched.add(b);
      }
    }

    List<Map<String, dynamic>> resultList = [];
    if (matched.isNotEmpty) {
      resultList = matched;
    } else {
      final isGeneralQuery = textWithoutShop.contains('barber') ||
          textWithoutShop.contains('staff') ||
          textWithoutShop.contains('who works') ||
          textWithoutShop.contains('stylist') ||
          textWithoutShop.contains('our team') ||
          textWithoutShop.contains('all barber') ||
          textWithoutShop.contains('names of barber') ||
          textWithoutShop.contains('list of barber');

      if (isGeneralQuery) {
        resultList = List.from(_availableBarbers);
      }
    }

    if (userPrompt != null && userPrompt.isNotEmpty && resultList.isNotEmpty) {
      final count = AiService.extractRequestedCount(
        userPrompt,
        keywords: ['barber', 'barbers', 'stylist', 'stylists', 'staff'],
      );
      if (count != null && count > 0) {
        return resultList.take(count).toList();
      }
    }

    return resultList;
  }

  String _getBarberPhotoUrl(Map<String, dynamic> barber) {
    final photo =
        (barber['profile_photo'] ?? barber['avatar'] ?? '').toString().trim();
    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      return photo;
    }
    if (photo.isNotEmpty) {
      const base = SupabaseConfig.url;
      return '$base/storage/v1/object/public/staff-avatars/$photo';
    }
    return '';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(),
            ),
            if (_errorText != null) _buildErrorBanner(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: _surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _surfaceDark),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 20,
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: _brandGradient,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryBlue.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              Positioned(
                bottom: -1,
                right: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _accentOnline,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isAdmin ? 'Executive AI Assistant' : 'Liem AI Concierge',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _surfaceDark,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _isAdmin
                      ? 'Liem Operations · Online'
                      : 'Liem Barber Shop · Online',
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    color: _textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 21, color: _surfaceDark),
            tooltip: 'Chat History',
            onPressed: _showHistorySheet,
            splashRadius: 20,
          ),
          if (_messages.isNotEmpty) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: _startNewChat,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: _surfaceBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 14, color: _surfaceDark),
                    const SizedBox(width: 4),
                    Text(
                      'New',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _surfaceDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Empty / welcome state ─────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final suggestions = _isAdmin ? _adminSuggestions : _customerSuggestions;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: _brandGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _primaryBlue.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Good day${_userName != null ? ", $_userName" : ""}',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _surfaceDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isAdmin
                ? 'Store operations, bookings analysis & database management'
                : 'How can we assist your grooming style today?',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: _textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: suggestions
                .map((s) => _SuggestionChip(label: s, onTap: () => _send(s)))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ── Message list ──────────────────────────────────────────────────────────
  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildTypingBubble();
        String? previousUserPrompt;
        if (_messages[index].role == 'assistant' && index > 0) {
          for (int k = index - 1; k >= 0; k--) {
            if (_messages[k].role == 'user') {
              previousUserPrompt = _messages[k].content;
              break;
            }
          }
        }
        return _buildBubble(_messages[index], previousUserPrompt: previousUserPrompt);
      },
    );
  }

  Widget _buildBubble(AiMessage msg, {String? previousUserPrompt}) {
    final isUser = msg.role == 'user';
    final hasAdminServiceAction =
        !isUser && msg.content.contains('[ADMIN_ACTION:CREATE_SERVICE:');
    final hasAdminStaffAction =
        !isUser && msg.content.contains('[ADMIN_ACTION:CREATE_STAFF:');

    var displayContent = msg.content;
    if (hasAdminServiceAction) {
      displayContent = displayContent
          .replaceAll(
              RegExp(r'\[ADMIN_ACTION:CREATE_SERVICE:[^\]]+\]'), '')
          .trim();
    }
    if (hasAdminStaffAction) {
      displayContent = displayContent
          .replaceAll(
              RegExp(r'\[ADMIN_ACTION:CREATE_STAFF:[^\]]+\]'), '')
          .trim();
    }
    if (displayContent.isEmpty) {
      displayContent = hasAdminServiceAction
          ? 'I have prepared the new catalog service for your review:'
          : 'I have prepared the new staff profile for your review:';
    }

    final recommendedServices = (!isUser &&
            !_isAdmin &&
            !hasAdminServiceAction &&
            !hasAdminStaffAction)
        ? _findRecommendedServices(msg.content, userPrompt: previousUserPrompt)
        : <Map<String, dynamic>>[];
    final recommendedBarbers = (!isUser &&
            !_isAdmin &&
            !hasAdminServiceAction &&
            !hasAdminStaffAction)
        ? _findRecommendedBarbers(msg.content, userPrompt: previousUserPrompt)
        : <Map<String, dynamic>>[];

    return TweenAnimationBuilder<double>(
      key: ValueKey('bubble_${msg.createdAt?.millisecondsSinceEpoch ?? msg.content.hashCode}_${msg.role}'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, anim, child) {
        return Opacity(
          opacity: anim,
          child: Transform.translate(
            offset: Offset(0, (1.0 - anim) * 8),
            child: child,
          ),
        );
      },
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              top: 5,
              bottom: 5,
              left: isUser ? 50 : 0,
              right: isUser ? 0 : 50,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser ? null : Colors.white,
              gradient: isUser ? _brandGradient : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser ? null : Border.all(color: _surfaceBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: isUser
                      ? _primaryBlue.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: isUser ? 8 : 4,
                  offset: isUser ? const Offset(0, 3) : const Offset(0, 2),
                ),
              ],
            ),
            child: isUser
                ? Text(
                    displayContent,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              size: 11.5,
                              color: _primaryDeep,
                            ),
                            const SizedBox(width: 4.5),
                            Text(
                              _isAdmin ? 'AI OPERATIONS' : 'LIEM AI CONCIERGE',
                              style: GoogleFonts.manrope(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: _primaryDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _FormattedMessageText(
                        text: displayContent,
                        baseStyle: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.5,
                          color: _textPrimary,
                        ),
                        boldColor: _surfaceDark,
                      ),
                    ],
                  ),
          ),
        ),

        // Admin interactive action cards
        if (hasAdminServiceAction)
          _buildAdminServiceActionCard(msg.content),
        if (hasAdminStaffAction)
          _buildAdminStaffActionCard(msg.content),

        // If this assistant message recommends haircut styles, render interactive cards!
        if (recommendedServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.content_cut_rounded, size: 13, color: _surfaceDark),
                      const SizedBox(width: 5),
                      Text(
                        'Recommended Styles:',
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _surfaceDark,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                ...recommendedServices.map(_buildServiceActionCard),
              ],
            ),
          ),

        // If this assistant message recommends or lists barbers, render interactive Barber Cards!
        if (recommendedBarbers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: _surfaceDark),
                      const SizedBox(width: 5),
                      Text(
                        'Our Barbers & Stylists:',
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _surfaceDark,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                ...recommendedBarbers.map(_buildBarberRecommendationCard),
              ],
            ),
          ),
      ],
      ),
    );
  }

  /// Interactive Card for each haircut suggested by the AI
  Widget _buildServiceActionCard(Map<String, dynamic> service) {
    final name = (service['name'] ?? 'Haircut').toString();
    final price = service['price'] != null ? '₱${service['price']}' : '';
    final duration = service['duration_minutes'] != null
        ? '${service['duration_minutes']} min'
        : '30 min';
    final imagePath = _getServiceImage(service);

    return Container(
      margin: const EdgeInsets.only(bottom: 8, right: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _surfaceBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row with image thumbnail and title
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imagePath.startsWith('http')
                      ? Image.network(
                          imagePath,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultThumbIcon(),
                        )
                      : Image.asset(
                          imagePath,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultThumbIcon(),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _surfaceDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: _surfaceLight,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _surfaceBorder),
                            ),
                            child: Text(
                              price,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _surfaceDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '• $duration',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Divider
          const Divider(height: 1, color: _surfaceBorder),

          // Action buttons: "View Hairstyle" and "Book Now"
          Row(
            children: [
              // View Hairstyle button
              Expanded(
                child: InkWell(
                  onTap: () => _showHairstylePreviewModal(service),
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.remove_red_eye_outlined, size: 15, color: _surfaceDark),
                        const SizedBox(width: 6),
                        Text(
                          'View Style',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _surfaceDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Container(height: 28, width: 1, color: _surfaceBorder),

              // Book Now button
              Expanded(
                child: InkWell(
                  onTap: () => _showInChatBookingModal(service: service),
                  borderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 15, color: _surfaceDark),
                        const SizedBox(width: 6),
                        Text(
                          'Book This',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _surfaceDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultThumbIcon() {
    return Container(
      width: 54,
      height: 54,
      color: _surfaceLight,
      child: const Icon(Icons.content_cut_rounded, color: _surfaceDark, size: 22),
    );
  }

  /// Opens a modal dialog previewing the selected hairstyle photo and description
  void _showHairstylePreviewModal(Map<String, dynamic> service) {
    final name = (service['name'] ?? 'Hairstyle').toString();
    final description = (service['description'] ?? 'A signature look from Liem Barber Shop.').toString();
    final price = service['price'] != null ? '₱${service['price']}' : '';
    final duration = service['duration_minutes'] != null ? '${service['duration_minutes']} minutes' : '30 minutes';
    final imagePath = _getServiceImage(service);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Large Hairstyle Photo
              Stack(
                children: [
                  imagePath.startsWith('http')
                      ? Image.network(imagePath, height: 220, width: double.infinity, fit: BoxFit.cover)
                      : Image.asset(imagePath, height: 220, width: double.infinity, fit: BoxFit.cover),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      radius: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$price  •  $duration',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Details section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Direct booking button inside the preview modal
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showInChatBookingModal(service: service);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _surfaceDark,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          'Book This Hairstyle Now',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Interactive Card for each Barber suggested by the AI, complete with Profile Photo and Action Buttons
  Widget _buildBarberRecommendationCard(Map<String, dynamic> barber) {
    final name = (barber['name'] ?? 'Barber').toString();
    final role = (barber['role'] ?? 'Barber').toString();
    final skills = (barber['skills'] ?? '').toString();
    final photoUrl = _getBarberPhotoUrl(barber);

    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _surfaceBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row with barber avatar and info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Profile Avatar with high-res photo or stylized initials
                _buildBarberAvatar(name, photoUrl, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _surfaceDark,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: _surfaceLight,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _surfaceBorder),
                            ),
                            child: Text(
                              role,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _surfaceDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.workspace_premium_outlined,
                                size: 13, color: _textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                skills,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Divider
          const Divider(height: 1, color: _surfaceBorder),

          // Action buttons: "View Profile" and "Book Barber"
          Row(
            children: [
              // View Profile
              Expanded(
                child: InkWell(
                  onTap: () => _showBarberProfileModal(barber),
                  borderRadius:
                      const BorderRadius.only(bottomLeft: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            size: 15, color: _surfaceDark),
                        const SizedBox(width: 6),
                        Text(
                          'View Profile',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _surfaceDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Container(height: 28, width: 1, color: _surfaceBorder),

              // Book with Barber
              Expanded(
                child: InkWell(
                  onTap: () => _showInChatBookingModal(barber: barber),
                  borderRadius:
                      const BorderRadius.only(bottomRight: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_month_rounded,
                            size: 15, color: _surfaceDark),
                        const SizedBox(width: 6),
                        Text(
                          'Book Barber',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _surfaceDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarberAvatar(String name, String photoUrl, {double size = 54}) {
    final initials = name
        .trim()
        .split(' ')
        .map((p) => p.isNotEmpty ? p[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 3.5),
        child: Image.network(
          photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitialsAvatar(initials, size),
        ),
      );
    }

    return _buildInitialsAvatar(initials, size);
  }

  Widget _buildInitialsAvatar(String initials, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(size / 3.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isNotEmpty ? initials : '✂️',
        style: GoogleFonts.manrope(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

  /// Opens a modal dialog previewing the selected Barber's profile and specialties
  void _showBarberProfileModal(Map<String, dynamic> barber) {
    final name = (barber['name'] ?? 'Barber').toString();
    final role = (barber['role'] ?? 'Professional Barber').toString();
    final skills =
        (barber['skills'] ?? 'Precision Fades, Classic Grooming').toString();
    final photoUrl = _getBarberPhotoUrl(barber);
    final phone = (barber['phone'] ?? '').toString();
    final email = (barber['email'] ?? '').toString();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _surfaceBorder),
                      ),
                      child: Text(
                        'Barber Profile',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _surfaceDark,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Large Avatar
                _buildBarberAvatar(name, photoUrl, size: 84),
                const SizedBox(height: 14),

                Text(
                  name,
                  style: GoogleFonts.manrope(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _surfaceDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // Specialties section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.workspace_premium_outlined,
                              size: 16, color: _surfaceDark),
                          const SizedBox(width: 6),
                          Text(
                            'Specialties & Skills',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _surfaceDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        skills,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                      if (phone.isNotEmpty || email.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Divider(height: 1, color: Colors.grey[200]),
                        const SizedBox(height: 10),
                        if (phone.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.phone_outlined,
                                  size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 6),
                              Text(phone,
                                  style: GoogleFonts.manrope(
                                      fontSize: 12.5,
                                      color: Colors.grey[600])),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Book with Barber button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showInChatBookingModal(barber: barber);
                    },
                    icon: const Icon(Icons.calendar_month_rounded,
                        size: 18, color: Colors.white),
                    label: Text(
                      'Book with $name',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _surfaceDark,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the In-Chat Quick Booking Sheet allowing direct appointment scheduling
  void _showInChatBookingModal({
    Map<String, dynamic>? service,
    Map<String, dynamic>? barber,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InChatBookingSheet(
        initialService: service,
        initialStaffId:
            barber != null ? (barber['staff_id'] ?? barber['id']) : null,
        customerId: _customerId,
        services: _catalogServices,
        barbers: _availableBarbers,
        onBookingComplete:
            (serviceName, barberName, dateFormatted, timeFormatted) {
          Navigator.pop(ctx);
          final confirmationText =
              '🎉 **Booking Confirmed!**\n\n'
              '✂️ **Service:** $serviceName\n'
              '💈 **Barber:** $barberName\n'
              '📅 **Date:** $dateFormatted\n'
              '⏰ **Time:** $timeFormatted\n\n'
              'Your appointment has been successfully scheduled! You can view and manage it anytime in your Appointments section.';
          setState(() {
            _messages.add(
              AiMessage(
                role: 'assistant',
                content: confirmationText,
              ),
            );
          });
          _scrollToBottom();
          AiService.saveMessage(
            sessionId: _sessionId,
            role: 'assistant',
            content: confirmationText,
          );
          AiHistoryStorage.saveSession(
            AiChatSession(
              sessionId: _sessionId,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              messages: List.from(_messages),
            ),
          );
        },
      ),
    );
  }

  /// Opens the Chat History modal to browse and restore past conversations
  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChatHistorySheet(
        onSelectSession: (session) async {
          Navigator.pop(ctx);
          await AiHistoryStorage.setActiveSessionId(session.sessionId);
          if (!mounted) return;

          setState(() {
            _sessionId = session.sessionId;
            _messages.clear();
            if (session.messages.isNotEmpty) {
              _messages.addAll(session.messages);
            }
            _errorText = null;
            _isLoading = session.messages.isEmpty;
          });
          if (session.messages.isNotEmpty) {
            _scrollToBottom();
          }

          // Fetch full remote history in case newer cloud messages exist
          try {
            final fullHistory =
                await AiService.loadSessionHistory(session.sessionId);
            if (mounted) {
              if (fullHistory.isNotEmpty &&
                  fullHistory.length >= _messages.length) {
                setState(() {
                  _messages.clear();
                  _messages.addAll(fullHistory);
                  _isLoading = false;
                });
                _scrollToBottom();
              } else {
                setState(() => _isLoading = false);
              }
            }
          } catch (_) {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        onDeleteSession: (deletedSessionId) {
          if (_sessionId == deletedSessionId) {
            _startNewChat();
          }
        },
        onClearAll: () {
          _startNewChat();
        },
      ),
    );
  }

  // ── Typing indicator ──────────────────────────────────────────────────────
  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: _surfaceBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: _primaryDeep,
            ),
            const SizedBox(width: 8),
            _AnimatedDot(controller: _dotController, delay: 0.0),
            const SizedBox(width: 4),
            _AnimatedDot(controller: _dotController, delay: 0.25),
            const SizedBox(width: 4),
            _AnimatedDot(controller: _dotController, delay: 0.5),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.red.shade700),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorText = null),
            child: Icon(Icons.close, size: 16, color: Colors.red.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Operational shortcuts for Admin Copilot
          if (_isAdmin)
            Container(
              height: 34,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildAdminQuickChip(
                    icon: Icons.analytics_outlined,
                    label: 'Past 3 Days Bookings',
                    onTap: () => _send('How many bookings in the past 3 days?'),
                  ),
                  _buildAdminQuickChip(
                    icon: Icons.calendar_today_outlined,
                    label: 'Today\'s Schedule',
                    onTap: () => _send('Show today\'s appointment schedule'),
                  ),
                  _buildAdminQuickChip(
                    icon: Icons.payments_outlined,
                    label: 'Revenue Summary',
                    onTap: () => _send('What is today\'s revenue & stats?'),
                  ),
                  _buildAdminQuickChip(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Add Hairstyle',
                    onTap: () {
                      _controller.text = 'Add a hairstyle to catalog: ';
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      _focusNode.requestFocus();
                    },
                  ),
                  _buildAdminQuickChip(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Add Barber',
                    onTap: () {
                      _controller.text = 'Add a barber named ';
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      _focusNode.requestFocus();
                    },
                  ),
                ],
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _surfaceLight,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _surfaceBorder, width: 1),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: _surfaceDark,
                    ),
                    decoration: InputDecoration(
                      hintText: _isAdmin
                          ? 'Ask bookings, revenue, or store tasks...'
                          : 'Ask anything about services & barbers...',
                      hintStyle: GoogleFonts.manrope(
                        color: _textSecondary,
                        fontSize: 13.5,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _send(_controller.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: _brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _primaryBlue.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminQuickChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 13, color: _surfaceDark),
        label: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: _surfaceDark,
          ),
        ),
        backgroundColor: _surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _surfaceBorder, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: onTap,
      ),
    );
  }

  Map<String, dynamic>? _extractAdminActionPayload(String content, String tag) {
    try {
      final startTag = '[$tag:';
      final startIdx = content.indexOf(startTag);
      if (startIdx == -1) return null;
      final jsonStart = startIdx + startTag.length;
      final jsonEnd = content.indexOf(']', jsonStart);
      if (jsonEnd == -1) return null;
      final jsonStr = content.substring(jsonStart, jsonEnd).trim();
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Widget _buildAdminServiceActionCard(String rawContent) {
    final data = _extractAdminActionPayload(rawContent, 'ADMIN_ACTION:CREATE_SERVICE');
    if (data == null) return const SizedBox.shrink();

    final name = (data['name'] ?? 'New Hairstyle').toString();
    final price = data['price'] != null ? '₱${data['price']}' : '₱250';
    final duration = data['duration_minutes'] != null ? '${data['duration_minutes']} min' : '30 min';
    final category = (data['category_name'] ?? 'Haircuts').toString();
    final description = (data['description'] ?? 'Professional haircut style').toString();

    final actionKey = 'service_${name}_${data['price']}';
    final isConfirmed = _confirmedActions.contains(actionKey);
    final isSubmitting = _submittingActions.contains(actionKey);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfirmed ? Colors.green.shade400 : _surfaceBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isConfirmed
                  ? Colors.green.shade50
                  : _surfaceLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  isConfirmed ? Icons.check_circle_rounded : Icons.inventory_2_outlined,
                  size: 16,
                  color: isConfirmed ? Colors.green.shade700 : _surfaceDark,
                ),
                const SizedBox(width: 8),
                Text(
                  isConfirmed ? 'SERVICE ADDED TO DATABASE' : 'PROPOSED CATALOG SERVICE',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isConfirmed ? Colors.green.shade800 : _surfaceDark,
                  ),
                ),
              ],
            ),
          ),

          // Body Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildParamBadge(Icons.payments_outlined, price, const Color(0xFF2E7D32)),
                    _buildParamBadge(Icons.timer_outlined, duration, Colors.black87),
                    _buildParamBadge(Icons.category_outlined, category, Colors.black87),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: GoogleFonts.manrope(fontSize: 12.5, color: Colors.grey[700]),
                  ),
                ],
                const SizedBox(height: 12),

                // Buttons or Confirmed State
                if (isConfirmed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '✓ Saved to Catalog. Visible to customers.',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () => _executeAddService(data, actionKey),
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(
                            isSubmitting ? 'Saving...' : 'Confirm & Add to Catalog',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
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

  Widget _buildAdminStaffActionCard(String rawContent) {
    final data = _extractAdminActionPayload(rawContent, 'ADMIN_ACTION:CREATE_STAFF');
    if (data == null) return const SizedBox.shrink();

    final name = (data['name'] ?? 'New Barber').toString();
    final role = (data['role'] ?? 'Barber').toString();
    final phone = (data['phone'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final specialties = (data['specialties'] ?? 'General Barbering').toString();

    final actionKey = 'staff_${name}_$phone';
    final isConfirmed = _confirmedActions.contains(actionKey);
    final isSubmitting = _submittingActions.contains(actionKey);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfirmed ? Colors.green.shade400 : _surfaceBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isConfirmed
                  ? Colors.green.shade50
                  : _surfaceLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  isConfirmed ? Icons.check_circle_rounded : Icons.person_add_alt_1_rounded,
                  size: 16,
                  color: isConfirmed ? Colors.green.shade700 : _surfaceDark,
                ),
                const SizedBox(width: 8),
                Text(
                  isConfirmed ? 'STAFF CREATED IN DATABASE' : 'PROPOSED STAFF PROFILE',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isConfirmed ? Colors.green.shade800 : _surfaceDark,
                  ),
                ),
              ],
            ),
          ),

          // Body Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildParamBadge(Icons.badge_outlined, role, _surfaceDark),
                    if (phone.isNotEmpty)
                      _buildParamBadge(Icons.phone_outlined, phone, Colors.black87),
                    if (email.isNotEmpty)
                      _buildParamBadge(Icons.email_outlined, email, Colors.black87),
                    _buildParamBadge(Icons.lock_outline_rounded, 'Pass: Barber@1234', Colors.grey.shade700),
                  ],
                ),
                if (specialties.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Skills: $specialties',
                    style: GoogleFonts.manrope(fontSize: 12.5, color: Colors.grey[700]),
                  ),
                ],
                const SizedBox(height: 12),

                // Buttons or Confirmed State
                if (isConfirmed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '✓ Staff Account Active (Default pass: Barber@1234)',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () => _executeAddStaff(data, actionKey),
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(
                            isSubmitting ? 'Creating...' : 'Confirm & Add Staff',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
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

  Widget _buildParamBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeAddService(Map<String, dynamic> data, String actionKey) async {
    setState(() {
      _submittingActions.add(actionKey);
    });

    try {
      String? categoryId;
      final catName = (data['category_name'] ?? 'Haircuts').toString().toLowerCase();
      for (final c in _catalogCategories) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        if (name.contains(catName) || catName.contains(name)) {
          categoryId = (c['category_id'] ?? c['id'])?.toString();
          break;
        }
      }
      if (categoryId == null && _catalogCategories.isNotEmpty) {
        categoryId = (_catalogCategories.first['category_id'] ?? _catalogCategories.first['id'])?.toString();
      }

      final servicePayload = {
        'name': data['name'],
        'price': (data['price'] as num?)?.toDouble() ?? 250.0,
        'duration_minutes': (data['duration_minutes'] as num?)?.toInt() ?? 30,
        'category_id': categoryId,
        'description': data['description'] ?? 'Professional haircut service',
        'is_active': 1,
      };

      final res = await CatalogService.createService(servicePayload);
      if (res['success'] == true) {
        if (!mounted) return;
        setState(() {
          _confirmedActions.add(actionKey);
          _submittingActions.remove(actionKey);
        });
        await _loadCatalogAndBarbers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Service "${data['name']}" added to catalog!'),
            backgroundColor: Colors.green[700],
          ),
        );
      } else {
        if (!mounted) return;
        setState(() {
          _submittingActions.remove(actionKey);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to add service.'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submittingActions.remove(actionKey);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _executeAddStaff(Map<String, dynamic> data, String actionKey) async {
    setState(() {
      _submittingActions.add(actionKey);
    });

    try {
      final staffPayload = {
        'name': data['name'],
        'role': data['role'] ?? 'Barber',
        'phone': data['phone'] ?? '',
        'email': data['email'] ?? '',
        'password': 'Barber@1234',
        'skills': data['specialties'] ?? 'General Barbering',
      };

      final res = await EmployeeService.createEmployee(staffPayload);
      if (res['success'] == true) {
        if (!mounted) return;
        setState(() {
          _confirmedActions.add(actionKey);
          _submittingActions.remove(actionKey);
        });
        await _loadCatalogAndBarbers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Staff member "${data['name']}" created! (Password: Barber@1234)'),
            backgroundColor: Colors.green[700],
          ),
        );
      } else {
        if (!mounted) return;
        setState(() {
          _submittingActions.remove(actionKey);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to add staff member.'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submittingActions.remove(actionKey);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IN-CHAT QUICK BOOKING MODAL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _InChatBookingSheet extends StatefulWidget {
  final Map<String, dynamic>? initialService;
  final String? initialStaffId;
  final String? customerId;
  final List<Map<String, dynamic>> services;
  final List<Map<String, dynamic>> barbers;
  final Function(String serviceName, String barberName, String dateFormatted, String timeFormatted) onBookingComplete;

  const _InChatBookingSheet({
    this.initialService,
    this.initialStaffId,
    required this.customerId,
    required this.services,
    required this.barbers,
    required this.onBookingComplete,
  });

  @override
  State<_InChatBookingSheet> createState() => _InChatBookingSheetState();
}

class _InChatBookingSheetState extends State<_InChatBookingSheet> {
  late Map<String, dynamic> _selectedService;
  String? _selectedStaffId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  bool _isSubmitting = false;
  String? _errorMessage;

  static final List<TimeOfDay> _slots = [
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 9, minute: 30),
    const TimeOfDay(hour: 10, minute: 0),
    const TimeOfDay(hour: 10, minute: 30),
    const TimeOfDay(hour: 11, minute: 0),
    const TimeOfDay(hour: 11, minute: 30),
    const TimeOfDay(hour: 13, minute: 0),
    const TimeOfDay(hour: 13, minute: 30),
    const TimeOfDay(hour: 14, minute: 0),
    const TimeOfDay(hour: 14, minute: 30),
    const TimeOfDay(hour: 15, minute: 0),
    const TimeOfDay(hour: 15, minute: 30),
    const TimeOfDay(hour: 16, minute: 0),
    const TimeOfDay(hour: 16, minute: 30),
    const TimeOfDay(hour: 17, minute: 0),
  ];

  @override
  void initState() {
    super.initState();
    _selectedService = widget.initialService ??
        (widget.services.isNotEmpty
            ? widget.services[0]
            : {'name': 'Classic Haircut', 'price': 250, 'duration_minutes': 30});

    if (widget.initialStaffId != null) {
      _selectedStaffId = widget.initialStaffId;
    } else if (widget.barbers.isNotEmpty) {
      _selectedStaffId =
          widget.barbers[0]['staff_id'] ?? widget.barbers[0]['id'];
    }
    _selectedTime = _slots[0];
  }

  Future<void> _confirmBooking() async {
    if (_selectedStaffId == null || _selectedTime == null) {
      setState(() => _errorMessage = 'Please select both a barber and a time slot.');
      return;
    }

    final custId = widget.customerId;
    if (custId == null || custId.isEmpty) {
      setState(() => _errorMessage = 'Unable to identify your customer account. Please log in.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final duration = _selectedService['duration_minutes'] as int? ?? 30;
      final startDt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      final endDt = startDt.add(Duration(minutes: duration));

      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';
      final endTimeStr =
          '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}:00';

      final appointmentData = {
        'customer_id': custId,
        'staff_id': _selectedStaffId,
        'service_id': _selectedService['service_id'] ?? _selectedService['id'],
        'start_time': '$dateStr $timeStr',
        'end_time': '$dateStr $endTimeStr',
      };

      final result = await ApiService.createAppointment(appointmentData);

      if (result != null && (result['appointment_id'] != null || result['id'] != null)) {
        final barber = widget.barbers.firstWhere(
          (b) => (b['staff_id'] ?? b['id']) == _selectedStaffId,
          orElse: () => {'name': 'Assigned Barber'},
        );
        final barberName = (barber['name'] ?? 'Barber').toString();
        final serviceName = (_selectedService['name'] ?? 'Service').toString();
        final dateFormatted = '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}';
        final timeFormatted = _formatTimeSlot(_selectedTime!);

        widget.onBookingComplete(serviceName, barberName, dateFormatted, timeFormatted);
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Could not complete booking. Please try another time slot.';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _formatTimeSlot(TimeOfDay t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  Widget _buildMiniAvatar(String name, dynamic rawPhoto) {
    final photoStr = (rawPhoto ?? '').toString().trim();
    String fullUrl = photoStr;
    if (photoStr.isNotEmpty && !photoStr.startsWith('http')) {
      fullUrl =
          '${SupabaseConfig.url}/storage/v1/object/public/staff-avatars/$photoStr';
    }

    if (fullUrl.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          fullUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsMini(name),
        ),
      );
    }
    return _initialsMini(name);
  }

  Widget _initialsMini(String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'B';
    return CircleAvatar(
      radius: 17,
      backgroundColor: _surfaceDark,
      child: Text(
        initial,
        style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceName = (_selectedService['name'] ?? 'Service').toString();
    final price = _selectedService['price'] != null ? '₱${_selectedService['price']}' : '';
    final duration = _selectedService['duration_minutes'] != null
        ? '${_selectedService['duration_minutes']} min'
        : '30 min';

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header: Selected Service info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct In-Chat Booking',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _surfaceDark,
                        ),
                      ),
                      Text(
                        serviceName,
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _surfaceBorder),
                  ),
                  child: Text(
                    '$price • $duration',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _surfaceDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Select Service chips (if multiple services exist)
            if (widget.services.length > 1) ...[
              Text(
                'Select Hairstyle / Service',
                style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.services.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final s = widget.services[i];
                    final isSel = (_selectedService['service_id'] ??
                            _selectedService['id']) ==
                        (s['service_id'] ?? s['id']);
                    return ChoiceChip(
                      label: Text(
                        '${s['name']} (₱${s['price']})',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Colors.white : _surfaceDark,
                        ),
                      ),
                      selected: isSel,
                      onSelected: (_) => setState(() => _selectedService = s),
                      selectedColor: _surfaceDark,
                      backgroundColor: _surfaceLight,
                      side: BorderSide(
                        color: isSel
                            ? _surfaceDark
                            : _surfaceBorder,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 1. Choose Barber
            Text(
              'Choose Barber',
              style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.barbers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final barber = widget.barbers[i];
                  final id = barber['staff_id'] ?? barber['id'];
                  final name = barber['name'] ?? 'Barber';
                  final isSelected = _selectedStaffId == id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedStaffId = id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _surfaceLight
                            : Colors.white,
                        border: Border.all(
                          color: isSelected
                              ? _surfaceDark
                              : _surfaceBorder,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _buildMiniAvatar(name,
                              barber['profile_photo'] ?? barber['avatar']),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _surfaceDark,
                                ),
                              ),
                              Text(
                                (barber['role'] ?? 'Barber').toString(),
                                style: GoogleFonts.manrope(
                                    fontSize: 10, color: _textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),

            // 2. Select Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Date',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(
                    '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 3. Select Time
            Text('Select Time Slot',
                style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _slots.map((time) {
                final isSelected = _selectedTime == time;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTime = time),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _surfaceDark
                          : _surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? _surfaceDark : _surfaceBorder,
                      ),
                    ),
                    child: Text(
                      _formatTimeSlot(time),
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : _surfaceDark,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.manrope(color: Colors.red, fontSize: 13),
                ),
              ),

            const SizedBox(height: 20),

            // Confirm Booking button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _surfaceDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Text(
                        'Confirm Appointment',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Suggestion Chip & Animated Dot
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Rich Formatted Message Text (Markdown renderer: bold, lists, headers)
// ─────────────────────────────────────────────────────────────────────────────

class _FormattedMessageText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final Color? boldColor;

  const _FormattedMessageText({
    required this.text,
    required this.baseStyle,
    this.boldColor,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      if (trimmed.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              trimmed.substring(4),
              style: baseStyle.copyWith(
                fontSize: (baseStyle.fontSize ?? 14) + 1.5,
                fontWeight: FontWeight.w700,
                color: boldColor ?? baseStyle.color,
              ),
            ),
          ),
        );
        continue;
      } else if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 5),
            child: Text(
              trimmed.substring(3),
              style: baseStyle.copyWith(
                fontSize: (baseStyle.fontSize ?? 14) + 2.5,
                fontWeight: FontWeight.w800,
                color: boldColor ?? baseStyle.color,
              ),
            ),
          ),
        );
        continue;
      }

      final isBullet = trimmed.startsWith('• ') ||
          trimmed.startsWith('- ') ||
          (trimmed.startsWith('* ') && !trimmed.startsWith('**'));
      if (isBullet) {
        final content = trimmed.substring(2);
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 6),
                  child: Text(
                    '•',
                    style: baseStyle.copyWith(
                      fontWeight: FontWeight.bold,
                      color: boldColor ?? baseStyle.color,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _buildInlineSpans(content, baseStyle, boldColor),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      final numMatch = RegExp(r'^(\d+)\.\s+(.*)').firstMatch(trimmed);
      if (numMatch != null) {
        final number = numMatch.group(1)!;
        final content = numMatch.group(2)!;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$number.',
                    style: baseStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: boldColor ?? baseStyle.color,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _buildInlineSpans(content, baseStyle, boldColor),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Text.rich(
            _buildInlineSpans(line, baseStyle, boldColor),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  static TextSpan _buildInlineSpans(
      String text, TextStyle baseStyle, Color? boldColor) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*([^*]+)\*\*|\*([^*]+)\*|`([^`]+)`)');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            color: boldColor ?? baseStyle.color,
          ),
        ));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
          text: match.group(3),
          style: baseStyle.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (match.group(4) != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.group(4)!,
              style: baseStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (baseStyle.fontSize ?? 14) * 0.9,
              ),
            ),
          ),
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return TextSpan(children: spans);
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: const Color(0xFF18181B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _AnimatedDot extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  const _AnimatedDot({required this.controller, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final raw = (controller.value - delay) % 1.0;
        final bounce = raw < 0.5 ? raw * 2 : (1.0 - raw) * 2;
        return Transform.translate(
          offset: Offset(0, -4 * bounce),
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: _primaryDeep,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class AiFloatingButton extends StatefulWidget {
  const AiFloatingButton({super.key});

  @override
  State<AiFloatingButton> createState() => _AiFloatingButtonState();
}

class _AiFloatingButtonState extends State<AiFloatingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () async {
          final expired = await AiHistoryStorage.hasInactivityExpired();
          if (expired) {
            await AiHistoryStorage.clearActiveSession();
          }
          if (context.mounted) {
            AiChatScreen.open(context);
          }
        },
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: _brandGradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _primaryBlue.withValues(alpha: 0.45),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT HISTORY MODAL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ChatHistorySheet extends StatefulWidget {
  final Function(AiChatSession session) onSelectSession;
  final Function(String deletedSessionId)? onDeleteSession;
  final VoidCallback? onClearAll;

  const _ChatHistorySheet({
    required this.onSelectSession,
    this.onDeleteSession,
    this.onClearAll,
  });

  @override
  State<_ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<_ChatHistorySheet> {
  List<AiChatSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final list = await AiHistoryStorage.loadAllSessions();
    if (mounted) {
      setState(() {
        _sessions = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSession(AiChatSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Chat?', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete this conversation? It will be deleted permanently from your local device and Supabase cloud.',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600]),
            child: Text('Delete', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final sid = session.sessionId;
      setState(() {
        _sessions.removeWhere((s) => s.sessionId == sid);
      });
      await AiHistoryStorage.deleteSession(sid);
      widget.onDeleteSession?.call(sid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat conversation deleted.', style: GoogleFonts.manrope()),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear All History?', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete all your past conversations both locally and in Supabase. This cannot be undone.',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600]),
            child: Text('Clear All', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _sessions.clear();
      });
      await AiHistoryStorage.clearAll();
      widget.onClearAll?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All chat history cleared.', style: GoogleFonts.manrope()),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _surfaceBorder),
                ),
                child: const Icon(Icons.history_rounded, color: _surfaceDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Chat History',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _surfaceDark,
                  ),
                ),
              ),
              if (_sessions.isNotEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: Text(
                    'Clear all',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: Colors.red[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sessions List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _surfaceDark, strokeWidth: 2))
                : _sessions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No Chat History Yet',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _surfaceDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your past conversations with the assistant will appear here.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _sessions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final session = _sessions[i];
                          final date = session.updatedAt;
                          final dateStr =
                              '${date.month}/${date.day}/${date.year} • ${date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour)}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () => widget.onSelectSession(session),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: _surfaceBorder),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: _surfaceLight,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: _surfaceBorder),
                                      ),
                                      child: const Icon(Icons.chat_bubble_outline_rounded, color: _surfaceDark, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            session.previewTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.manrope(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            dateStr,
                                            style: GoogleFonts.manrope(
                                              fontSize: 11.5,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${session.messages.length}',
                                        style: GoogleFonts.manrope(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.grey[400]),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteSession(session),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
