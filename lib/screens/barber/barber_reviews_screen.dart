import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/api_config.dart';
import '../../services/supabase_service_helpers.dart';
import '../../services/theme_service.dart';

/// Ratings and comments customers left for the signed-in barber.
///
/// Row-level security only returns feedback for appointments assigned to
/// this barber, so no extra filtering is needed for privacy.
class BarberReviewsScreen extends StatefulWidget {
  const BarberReviewsScreen({super.key});

  @override
  State<BarberReviewsScreen> createState() => _BarberReviewsScreenState();
}

class _BarberReviewsScreenState extends State<BarberReviewsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final feedback = SupabaseServiceHelpers.asMapList(
        await SupabaseConfig.client
            .from(SupabaseConfig.feedbackTable)
            .select('appointment_id, rating, comments, created_at')
            .order('created_at', ascending: false),
      );

      final ids = feedback
          .map((f) => f['appointment_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final details = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final rows = SupabaseServiceHelpers.asMapList(
          await SupabaseConfig.client
              .from(SupabaseConfig.appointmentDetailsView)
              .select('appointment_id, customer_name, service_name, start_time')
              .inFilter('appointment_id', ids),
        );
        for (final r in rows) {
          details[r['appointment_id'].toString()] = r;
        }
      }

      if (!mounted) return;
      setState(() {
        _reviews = [
          for (final f in feedback)
            {...f, ...?details[f['appointment_id']?.toString()]},
        ];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseServiceHelpers.errorMessage(e);
        _isLoading = false;
      });
    }
  }

  double get _average => _reviews.isEmpty
      ? 0
      : _reviews
              .map((r) => SupabaseServiceHelpers.asInt(r['rating']))
              .reduce((a, b) => a + b) /
          _reviews.length;

  int _countFor(int stars) =>
      _reviews.where((r) => SupabaseServiceHelpers.asInt(r['rating']) == stars).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text('My Reviews',
            style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text('Could not load your reviews.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
          const SizedBox(height: 4),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_reviews.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.star_border_rounded, size: 56, color: Colors.amber),
          const SizedBox(height: 12),
          Text('No reviews yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context))),
          const SizedBox(height: 4),
          Text('Customers can rate you after a completed haircut.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(color: AppColors.textSecondary(context))),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummary(),
        const SizedBox(height: 16),
        for (final r in _reviews) _buildReviewCard(r),
      ],
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(_average.toStringAsFixed(1),
                  style: GoogleFonts.manrope(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context))),
              _buildStars(_average.round(), size: 18),
              const SizedBox(height: 4),
              Text('${_reviews.length} review${_reviews.length == 1 ? '' : 's'}',
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: AppColors.textSecondary(context))),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var stars = 5; stars >= 1; stars--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text('$stars',
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: AppColors.textSecondary(context))),
                        const SizedBox(width: 4),
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _countFor(stars) / _reviews.length,
                              minHeight: 6,
                              backgroundColor: AppColors.cardBorder(context),
                              valueColor: const AlwaysStoppedAnimation(Colors.amber),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 20,
                          child: Text('${_countFor(stars)}',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.manrope(
                                  fontSize: 12, color: AppColors.textSecondary(context))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> r) {
    final rating = SupabaseServiceHelpers.asInt(r['rating']);
    final comment = (r['comments'] ?? '').toString().trim();
    final when = SupabaseServiceHelpers.parseDateTime(r['start_time'] ?? r['created_at']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (r['customer_name'] ?? 'Customer').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context)),
                ),
              ),
              _buildStars(rating, size: 16),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              (r['service_name'] ?? 'Service').toString(),
              if (when != null) SupabaseServiceHelpers.displayDate(when),
            ].join(' • '),
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 8),
          Text(
            comment.isEmpty ? 'No written comment.' : '"$comment"',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontStyle: comment.isEmpty ? FontStyle.italic : FontStyle.normal,
              color: comment.isEmpty
                  ? AppColors.textSecondary(context)
                  : AppColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStars(int rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star_rounded : Icons.star_border_rounded,
              size: size, color: Colors.amber),
      ],
    );
  }
}
