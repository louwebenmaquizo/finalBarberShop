import 'dart:async';
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
    with TickerProviderStateMixin {
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

  late final AnimationController _dotController;

  // Colour constants
  static const Color _c1 = Color(0xFF5BBCFF);
  static const Color _c2 = Color(0xFF9B8DFF);
  static const LinearGradient _grad = LinearGradient(
    colors: [_c1, _c2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
    '👥  How many barbers do we have?',
    '📅  Show today\'s appointments',
    '💰  What is today\'s revenue?',
    '📊  Show this month\'s stats',
    '➕  Add a new barber',
    '📋  List all services',
  ];

  @override
  void initState() {
    super.initState();
    _sessionId = _generateUuidV4();
    _dotController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    _loadUserInfo();
    _loadCatalogAndBarbers();
    _restoreActiveSession();
  }

  Future<void> _restoreActiveSession() async {
    try {
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
        CatalogService.getAllServices(),
        EmployeeService.getAllEmployees(),
      ]);
      if (mounted) {
        setState(() {
          _catalogServices = results[0];
          _availableBarbers = results[1].where((e) {
            final role = (e['role'] ?? '').toString().toLowerCase();
            return !role.contains('admin') && !role.contains('cashier');
          }).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
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
  List<Map<String, dynamic>> _findRecommendedServices(
    String text, {
    String? userPrompt,
  }) {
    if (_catalogServices.isEmpty) return [];
    final lower = text.toLowerCase();
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
      final isGeneralQuery = lower.contains('barber') ||
          lower.contains('staff') ||
          lower.contains('who works') ||
          lower.contains('stylist') ||
          lower.contains('our team') ||
          lower.contains('all barber') ||
          lower.contains('names of barber') ||
          lower.contains('list of barber');

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: _grad,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Assistant',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  _isAdmin
                      ? 'Admin mode · Powered by Gemini'
                      : 'Powered by Gemini 3.6',
                  style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 22, color: Colors.black87),
            tooltip: 'Chat History',
            onPressed: _showHistorySheet,
          ),
          if (_messages.isNotEmpty)
            TextButton.icon(
              onPressed: _startNewChat,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text('New', style: GoogleFonts.manrope(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: _c1),
            ),
        ],
      ),
    );
  }

  // ── Empty / welcome state ─────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final suggestions = _isAdmin ? _adminSuggestions : _customerSuggestions;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: _grad,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _c1.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            'Hi${_userName != null ? ", $_userName" : ""}! 👋',
            style: GoogleFonts.manrope(
                fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'How can I help you today?',
            style: GoogleFonts.manrope(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
    final recommendedServices = !isUser
        ? _findRecommendedServices(msg.content, userPrompt: previousUserPrompt)
        : <Map<String, dynamic>>[];
    final recommendedBarbers = !isUser
        ? _findRecommendedBarbers(msg.content, userPrompt: previousUserPrompt)
        : <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              top: 4,
              bottom: 4,
              left: isUser ? 60 : 0,
              right: isUser ? 0 : 60,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: isUser ? _grad : null,
              color: isUser ? null : Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              boxShadow: isUser
                  ? [
                      BoxShadow(
                        color: _c1.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              msg.content,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.45,
                color: isUser ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),

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
                      const Icon(Icons.content_cut, size: 13, color: Color(0xFF5BBCFF)),
                      const SizedBox(width: 5),
                      Text(
                        'Recommended Styles:',
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
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
                      const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF9B8DFF)),
                      const SizedBox(width: 5),
                      Text(
                        'Our Barbers & Stylists:',
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
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
        border: Border.all(color: const Color(0xFF5BBCFF).withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5BBCFF).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              price,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0288D1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '• $duration',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: Colors.grey[600],
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
          Divider(height: 1, color: Colors.grey[200]),

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
                        const Icon(Icons.remove_red_eye_outlined, size: 16, color: Color(0xFF5BBCFF)),
                        const SizedBox(width: 6),
                        Text(
                          'View Hairstyle',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF5BBCFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Container(height: 30, width: 1, color: Colors.grey[200]),

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
                        const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF9B8DFF)),
                        const SizedBox(width: 6),
                        Text(
                          'Book This',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF7E6BF5),
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
      color: const Color(0xFF5BBCFF).withValues(alpha: 0.2),
      child: const Icon(Icons.content_cut, color: Color(0xFF5BBCFF), size: 24),
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
                          backgroundColor: _c1,
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
          color: const Color(0xFF9B8DFF).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                // Profile Avatar with high-res photo or stylized gradient initials
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
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9B8DFF)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              role,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF7E6BF5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 12, color: Colors.amber.shade700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                skills,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  color: Colors.grey[600],
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
          Divider(height: 1, color: Colors.grey[200]),

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
                            size: 16, color: Color(0xFF5BBCFF)),
                        const SizedBox(width: 6),
                        Text(
                          'View Profile',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF5BBCFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Container(height: 30, width: 1, color: Colors.grey[200]),

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
                            size: 16, color: Color(0xFF9B8DFF)),
                        const SizedBox(width: 6),
                        Text(
                          'Book Barber',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF7E6BF5),
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
        gradient: _grad,
        borderRadius: BorderRadius.circular(size / 3.5),
        boxShadow: [
          BoxShadow(
            color: _c1.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isNotEmpty ? initials : '💈',
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
                        color: const Color(0xFF9B8DFF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Barber Profile',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF7E6BF5),
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
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: const Color(0xFF7E6BF5),
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
                          Icon(Icons.auto_awesome,
                              size: 16, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Specialties & Skills',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
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
                      backgroundColor: const Color(0xFF9B8DFF),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                style: GoogleFonts.manrope(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask me anything...',
                  hintStyle: GoogleFonts.manrope(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _send(_controller.text),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: _grad,
                borderRadius: BorderRadius.circular(23),
                boxShadow: [
                  BoxShadow(
                    color: _c1.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
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
      backgroundColor: const Color(0xFF9B8DFF),
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
                          color: const Color(0xFF5BBCFF),
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
                    color: const Color(0xFF5BBCFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$price • $duration',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0288D1),
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
                          color: isSel ? const Color(0xFF0288D1) : Colors.black87,
                        ),
                      ),
                      selected: isSel,
                      onSelected: (_) => setState(() => _selectedService = s),
                      selectedColor:
                          const Color(0xFF5BBCFF).withValues(alpha: 0.2),
                      backgroundColor: Colors.grey.shade100,
                      side: BorderSide(
                        color: isSel
                            ? const Color(0xFF5BBCFF)
                            : Colors.grey.shade300,
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
                            ? const Color(0xFF9B8DFF).withValues(alpha: 0.15)
                            : Colors.grey[100],
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7E6BF5)
                              : Colors.transparent,
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
                                  color: isSelected
                                      ? const Color(0xFF7E6BF5)
                                      : Colors.black87,
                                ),
                              ),
                              Text(
                                (barber['role'] ?? 'Barber').toString(),
                                style: GoogleFonts.manrope(
                                    fontSize: 10, color: Colors.grey[600]),
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
                          ? const Color(0xFF5BBCFF)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatTimeSlot(time),
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.black87,
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
                  backgroundColor: const Color(0xFF5BBCFF),
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

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF5BBCFF).withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: Colors.black87,
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
          offset: Offset(0, -5 * bounce),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class AiFloatingButton extends StatelessWidget {
  const AiFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AiChatScreen.open(context),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5BBCFF), Color(0xFF9B8DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5BBCFF).withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
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
                  color: const Color(0xFF5BBCFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded, color: Color(0xFF5BBCFF), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Chat History',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF5BBCFF)))
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
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Ask the AI a question or get haircut recommendations, and your conversations will be saved here automatically.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: Colors.grey[600],
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
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () => widget.onSelectSession(session),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[200]!),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF9B8DFF).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.forum_outlined, color: Color(0xFF7E6BF5), size: 18),
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
