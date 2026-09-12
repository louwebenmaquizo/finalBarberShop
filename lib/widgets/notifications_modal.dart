import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';

/// Displays the real-time notifications sheet for Admins, Barbers, or Customers.
void showNotificationsModal(
  BuildContext context, {
  bool isAdmin = false,
  String? customerId,
  String? staffId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _NotificationsModalContent(
      isAdmin: isAdmin,
      customerId: customerId,
      staffId: staffId,
    ),
  );
}

class _NotificationsModalContent extends StatefulWidget {
  final bool isAdmin;
  final String? customerId;
  final String? staffId;

  const _NotificationsModalContent({
    this.isAdmin = false,
    this.customerId,
    this.staffId,
  });

  @override
  State<_NotificationsModalContent> createState() =>
      _NotificationsModalContentState();
}

class _NotificationsModalContentState
    extends State<_NotificationsModalContent> {
  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final items = await NotificationService.getNotifications(
      isAdmin: widget.isAdmin,
      customerId: widget.customerId,
      staffId: widget.staffId,
    );
    if (mounted) {
      setState(() {
        _notifications = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllAsRead() async {
    await NotificationService.markAllAsRead(_notifications);
    if (mounted) {
      setState(() {
        for (var item in _notifications) {
          item.isRead = true;
        }
      });
    }
  }

  Future<void> _clearAll() async {
    await NotificationService.clearAll(_notifications);
    if (mounted) {
      setState(() {
        _notifications.clear();
      });
    }
  }

  Future<void> _handleTapItem(AppNotification item) async {
    if (!item.isRead) {
      await NotificationService.markAsRead(item.id);
      if (mounted) {
        setState(() {
          item.isRead = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF18181B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (unreadCount > 0)
                      TextButton(
                        onPressed: _markAllAsRead,
                        child: Text(
                          'Mark Read',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: const Color(0xFF1E88E5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E4E7)),

          // Notification List / Loading / Empty
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF1E88E5),
                      strokeWidth: 2.5,
                    ),
                  )
                : _notifications.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F7FF),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFBAE6FD),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                  size: 32,
                                  color: Color(0xFF1E88E5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'You\'re All Caught Up!',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF18181B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'No new updates or scheduled alerts right now.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: const Color(0xFF71717A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        itemCount: _notifications.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _notifications[index];
                          final isRead = item.isRead;

                          return InkWell(
                            onTap: () => _handleTapItem(item),
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? const Color(0xFFFAFAFA)
                                    : const Color(0xFFF0F7FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isRead
                                      ? const Color(0xFFE4E4E7)
                                      : const Color(0xFFBAE6FD),
                                  width: isRead ? 1 : 1.2,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icon Badge
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: item.color.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      item.icon,
                                      color: item.color,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.title,
                                                style: GoogleFonts.manrope(
                                                  fontSize: 14.5,
                                                  fontWeight: isRead
                                                      ? FontWeight.w600
                                                      : FontWeight.bold,
                                                  color:
                                                      const Color(0xFF18181B),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              item.timeAgo,
                                              style: GoogleFonts.manrope(
                                                fontSize: 11.5,
                                                color: isRead
                                                    ? Colors.grey[500]
                                                    : const Color(0xFF1E88E5),
                                                fontWeight: isRead
                                                    ? FontWeight.normal
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.body,
                                          style: GoogleFonts.manrope(
                                            fontSize: 13,
                                            color: const Color(0xFF4B5563),
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Unread blue dot indicator
                                  if (!isRead) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 6),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1E88E5),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          if (_notifications.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined,
                      size: 18, color: Colors.grey),
                  label: Text(
                    'Clear all notifications',
                    style: GoogleFonts.manrope(
                        color: Colors.grey[700], fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
