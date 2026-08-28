import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/dashboard_service.dart';
import '../../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _dashboardData;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const Color blueColor = Color(0xB25BBCFF);
  static const Color pinkColor = Color(0xFFFBC0E6);
  static const Color darkBlue = Color(0xFF1E88E5);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final data = await DashboardService.getDashboardData();
      setState(() {
        _dashboardData = data;
        _isLoading = false;
      });
      _animController.forward(from: 0);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _getNextClient() async {
    final nextClient = _dashboardData?['next_client'] as Map<String, dynamic>?;
    if (nextClient != null && nextClient.isNotEmpty) return nextClient;

    try {
      final appointments = await ApiService.getAppointments();
      if (appointments.isEmpty) return null;
      final now = DateTime.now();
      Map<String, dynamic>? next;
      DateTime? nextDt;
      for (var a in appointments) {
        final status = (a['status'] ?? '').toString().toLowerCase();
        if (['canceled', 'cancelled', 'no-show', 'declined'].contains(status))
          continue;
        try {
          final dt =
              DateTime.parse(a['start_time'] ?? a['appointment_date'] ?? '');
          if (dt.isAfter(now) && (nextDt == null || dt.isBefore(nextDt))) {
            nextDt = dt;
            next = a;
          }
        } catch (_) {}
      }
      if (next != null && nextDt != null) {
        return {
          'customer_name':
              next['customer_name'] ?? next['full_name'] ?? 'Unknown',
          'date': _fmtDate(nextDt),
          'time': _fmtTime(nextDt),
          'service': next['service_name'] ?? 'N/A',
          'employee': next['employee_name'] ?? next['staff_name'] ?? 'N/A',
        };
      }
    } catch (_) {}
    return null;
  }

  String _fmtDate(DateTime d) {
    const m = [
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
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtTime(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final min = d.minute.toString().padLeft(2, '0');
    final p = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $p';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dashboardData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Failed to load dashboard',
                style: GoogleFonts.manrope(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: Text('Retry', style: GoogleFonts.manrope()),
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildStatsCards(),
              const SizedBox(height: 24),
              _buildAnalyticsSection(),
              const SizedBox(height: 24),
              _buildNextClientSection(),
              const SizedBox(height: 24),
              _buildRecentBookingsSection(),
              const SizedBox(height: 24),
              _buildTopBarbersSection(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final stats = _dashboardData?['stats'] as Map<String, dynamic>? ?? {};
    final pending = stats['pending_count'] ?? 0;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard',
                  style: GoogleFonts.manrope(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              Text('Overview & Analytics',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: Colors.grey[500])),
            ],
          ),
        ),
        if (pending > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.pending_actions,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text('$pending Pending',
                    style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final stats = _dashboardData?['stats'] as Map<String, dynamic>? ?? {};
    final todayBookings = stats['today_bookings'] ?? 0;
    final totalBookings = stats['total_bookings'] ?? 0;
    final totalBarbers = stats['total_barbers'] ?? 0;
    final revRaw = stats['revenue_today'] ?? 0;
    final revenueToday = (revRaw is num) ? revRaw.toDouble() : 0.0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _buildStatCard("Today's Bookings", todayBookings.toString(), blueColor,
            Icons.calendar_today),
        _buildStatCard('Total Bookings', totalBookings.toString(), pinkColor,
            Icons.book_online),
        _buildStatCard('Total Barbers', totalBarbers.toString(), pinkColor,
            Icons.content_cut),
        _buildStatCard('Revenue Today', '\$${revenueToday.toStringAsFixed(2)}',
            blueColor, Icons.attach_money),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: Colors.black87),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.manrope(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              Text(title,
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.6),
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSection() {
    final analytics =
        _dashboardData?['analytics'] as Map<String, dynamic>? ?? {};
    final rawDays = analytics['days'] as List<dynamic>? ?? [];
    final rawVals = analytics['values'] as List<dynamic>? ?? [];
    final days = rawDays.map((e) => e.toString()).toList();
    final vals = rawVals.map((e) => (e as num).toInt()).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Analytics',
                  style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: blueColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('Last 7 days',
                    style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: darkBlue)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildLegend(blueColor, 'Bookings'),
              const SizedBox(width: 16),
              _buildLegend(pinkColor, 'Highlights'),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 24),
              child: CustomPaint(
                painter: BarGraphPainter(vals, days, blueColor, pinkColor),
                child: Container(),
              ),
            ),
          ),
          // Total for the week
          if (vals.isNotEmpty) ...[
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeekStat(
                    'This Week',
                    vals.fold(0, (a, b) => a + b).toString(),
                    Icons.calendar_view_week),
                _buildWeekStat(
                    'Avg/Day',
                    (vals.fold(0, (a, b) => a + b) / math.max(vals.length, 1))
                        .toStringAsFixed(1),
                    Icons.show_chart),
                _buildWeekStat(
                    'Peak Day',
                    days.isNotEmpty && vals.isNotEmpty
                        ? days[vals.indexOf(vals.reduce(math.max))]
                        : '-',
                    Icons.trending_up),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildWeekStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: darkBlue),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        Text(label,
            style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildNextClientSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next Client',
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>?>(
          future: _getNextClient(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Container(
                height: 120,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1), blurRadius: 10)
                    ]),
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            final nc = snap.data;
            if (nc == null || nc.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1), blurRadius: 10)
                    ]),
                child: Row(
                  children: [
                    Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.calendar_today_outlined,
                            color: Colors.grey[400], size: 28)),
                    const SizedBox(width: 16),
                    Text('No upcoming appointments',
                        style: GoogleFonts.manrope(
                            color: Colors.grey[500], fontSize: 15)),
                  ],
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [const Color(0xFF1E88E5), const Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF1E88E5).withOpacity(0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.person,
                                color: Colors.white, size: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(nc['customer_name'] ?? 'Unknown',
                                style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white))),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(nc['status'] ?? 'Booked',
                                style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        _buildInfoChip(
                            Icons.calendar_today, nc['date'] ?? 'N/A'),
                        _buildInfoChip(Icons.access_time, nc['time'] ?? 'N/A'),
                        if (nc['service'] != null && nc['service'] != 'N/A')
                          _buildInfoChip(Icons.content_cut, nc['service']),
                        if (nc['employee'] != null && nc['employee'] != 'N/A')
                          _buildInfoChip(Icons.person_outline, nc['employee']),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.8)),
        const SizedBox(width: 5),
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 13, color: Colors.white.withOpacity(0.9))),
      ],
    );
  }

  Widget _buildRecentBookingsSection() {
    final bookings = (_dashboardData?['recent_bookings'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Recent Bookings',
                  style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const Spacer(),
              Text('${bookings.length} records',
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 16),
          if (bookings.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No bookings yet',
                    style: GoogleFonts.manrope(color: Colors.grey[400])),
              ),
            )
          else
            ...bookings.map((b) => _buildBookingRow(b)).toList(),
        ],
      ),
    );
  }

  Widget _buildBookingRow(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? 'booked').toString().toLowerCase();
    Color statusColor;
    if (status == 'completed')
      statusColor = Colors.green;
    else if (status == 'pending')
      statusColor = Colors.orange;
    else if (status == 'canceled' || status == 'cancelled')
      statusColor = Colors.red;
    else if (status == 'booked')
      statusColor = darkBlue;
    else
      statusColor = Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: blueColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Center(
                child: Text(
                    booking['time']?.toString().split(' ').first ?? '--',
                    style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: darkBlue),
                    textAlign: TextAlign.center)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(booking['customer'] ?? 'Unknown',
                            style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(status[0].toUpperCase() + status.substring(1),
                          style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(booking['service'] ?? 'N/A',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text(booking['schedule'] ?? '',
                            style: GoogleFonts.manrope(
                                fontSize: 11, color: Colors.grey[500]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Icon(Icons.person_outline,
                        size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text(booking['employee'] ?? '',
                            style: GoogleFonts.manrope(
                                fontSize: 11, color: Colors.grey[500]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarbersSection() {
    final barbers = (_dashboardData?['top_barbers'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    if (barbers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Top Barbers',
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: barbers.length,
            itemBuilder: (ctx, i) => _buildBarberCard(barbers[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final photo = barber['profile_photo']?.toString() ?? '';
    final appointments = barber['total_appointments'] ?? 0;

    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF1E88E5).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildBarberPhoto(photo)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(barber['name'] ?? 'Unknown',
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('$appointments jobs',
                          style: GoogleFonts.manrope(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.8))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarberPhoto(String photo) {
    if (photo.isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http')) {
        return Image.network(clean,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _barberPhotoFallback());
      }
      try {
        final b64 = clean.contains(',') ? clean.split(',').last : clean;
        final bytes =
            base64Decode(b64.replaceAll('\n', '').replaceAll('\r', ''));
        return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
      } catch (_) {}
    }
    return _barberPhotoFallback();
  }

  Widget _barberPhotoFallback() {
    return Container(
      color: Colors.white.withOpacity(0.15),
      child: const Center(
          child: Icon(Icons.person, size: 40, color: Colors.white)),
    );
  }
}

// Custom painter for bar graph
class BarGraphPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color blueColor;
  final Color pinkColor;

  BarGraphPainter(this.data, this.labels, this.blueColor, this.pinkColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || labels.isEmpty) return;

    final maxVal = data.isEmpty ? 1 : data.reduce(math.max);
    final effectiveMax = maxVal < 5 ? 5 : maxVal;

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    final textStyle =
        TextStyle(fontSize: 10, color: Colors.grey[500], fontFamily: 'Manrope');

    final graphH = size.height - 24.0;
    const gridLines = 5;
    final stepY = graphH / (gridLines - 1);

    // Draw grid & Y labels
    for (int i = 0; i < gridLines; i++) {
      final y = stepY * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final val =
          ((gridLines - 1 - i) * effectiveMax / (gridLines - 1)).round();
      final tp = TextPainter(
          text: TextSpan(text: val.toString(), style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(-30, y - tp.height / 2));
    }

    if (data.isEmpty) return;

    final stepX = size.width / labels.length;
    final barW = stepX * 0.55;

    // Draw bars
    for (int i = 0; i < data.length && i < labels.length; i++) {
      final x = stepX * i + stepX / 2;
      final norm = data[i] / effectiveMax;
      final barH = (norm * graphH).clamp(2.0, graphH);
      final barTop = graphH - barH;

      final barColor = i % 2 == 0 ? blueColor : pinkColor;
      final paint = Paint()
        ..color = barColor
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - barW / 2, barTop, barW, barH),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, paint);

      // Value label on top of bar
      if (data[i] > 0) {
        final valTp = TextPainter(
          text: TextSpan(
              text: data[i].toString(),
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey[600],
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        valTp.paint(
            canvas, Offset(x - valTp.width / 2, barTop - valTp.height - 2));
      }

      // X label
      final labelTp = TextPainter(
          text: TextSpan(text: labels[i], style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      labelTp.paint(canvas, Offset(x - labelTp.width / 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant BarGraphPainter old) =>
      old.data != data || old.labels != labels;
}
