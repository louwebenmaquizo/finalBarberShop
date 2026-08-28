import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void showNotificationsModal(BuildContext context, {bool isAdmin = false}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _NotificationsModalContent(isAdmin: isAdmin),
  );
}

class _NotificationsModalContent extends StatefulWidget {
  final bool isAdmin;
  const _NotificationsModalContent({this.isAdmin = false});

  @override
  State<_NotificationsModalContent> createState() =>
      _NotificationsModalContentState();
}

class _NotificationsModalContentState
    extends State<_NotificationsModalContent> {
  late List<Map<String, dynamic>> _notifications;

  @override
  void initState() {
    super.initState();
    if (widget.isAdmin) {
      _notifications = [
        {
          'id': 1,
          'title': 'New Appointment Booked',
          'body':
              'Archie Boiser booked "Classic Haircut" with Michael for tomorrow at 2:00 PM.',
          'time': '10 mins ago',
          'icon': Icons.calendar_today,
          'color': const Color(0xFF1E88E5),
          'read': false,
        },
        {
          'id': 2,
          'title': 'Inventory Alert',
          'body':
              'Hair Pomade Matte Finish is running low in stock (3 units left).',
          'time': '1 hour ago',
          'icon': Icons.inventory_2_outlined,
          'color': Colors.orange,
          'read': false,
        },
        {
          'id': 3,
          'title': 'Daily Summary',
          'body':
              'You completed 14 haircuts today generating ₱4,200 in revenue.',
          'time': 'Yesterday',
          'icon': Icons.insights,
          'color': Colors.green,
          'read': true,
        },
      ];
    } else {
      _notifications = [
        {
          'id': 1,
          'title': 'Appointment Confirmed! ✂️',
          'body':
              'Your appointment with David on Monday, 3:00 PM is confirmed.',
          'time': '15 mins ago',
          'icon': Icons.check_circle_outline,
          'color': Colors.green,
          'read': false,
        },
        {
          'id': 2,
          'title': 'Weekend Special 20% OFF! 🎉',
          'body':
              'Book any Beard Grooming or Hair Styling package this weekend and get 20% off.',
          'time': '3 hours ago',
          'icon': Icons.local_offer_outlined,
          'color': const Color(0xFF1E88E5),
          'read': false,
        },
        {
          'id': 3,
          'title': 'Reminder: Upcoming Haircut',
          'body': 'Don\'t forget your scheduled haircut today. See you soon!',
          'time': '1 day ago',
          'icon': Icons.alarm,
          'color': Colors.amber[800],
          'read': true,
        },
      ];
    }
  }

  void _markAllAsRead() {
    setState(() {
      for (var item in _notifications) {
        item['read'] = true;
      }
    });
  }

  void _clearAll() {
    setState(() {
      _notifications.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

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
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_notifications.any((n) => !n['read']))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_notifications.where((n) => !n['read']).length}',
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (_notifications.isNotEmpty)
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
          const Divider(height: 1),

          // Notification List
          Expanded(
            child: _notifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No notifications',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = _notifications[index];
                      final isRead = item['read'] as bool;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            item['read'] = true;
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isRead
                                ? Colors.grey[50]
                                : const Color(0x0F5BBCFF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isRead
                                  ? Colors.grey[200]!
                                  : const Color(0x335BBCFF),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (item['color'] as Color)
                                      .withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  item['icon'] as IconData,
                                  color: item['color'] as Color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['title'] as String,
                                            style: GoogleFonts.manrope(
                                              fontSize: 15,
                                              fontWeight: isRead
                                                  ? FontWeight.w600
                                                  : FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          item['time'] as String,
                                          style: GoogleFonts.manrope(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['body'] as String,
                                      style: GoogleFonts.manrope(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
