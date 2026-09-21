import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Short relative time such as "just now", "5 min ago", or "yesterday".
String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);
  if (difference.isNegative || difference.inSeconds < 45) return 'just now';
  if (difference.inMinutes < 60) {
    return '${math.max(1, difference.inMinutes)} min ago';
  }
  if (difference.inHours < 24) return '${difference.inHours} h ago';
  if (difference.inDays < 2) return 'yesterday';
  if (difference.inDays < 7) return '${difference.inDays} days ago';
  return DateFormat('d MMM').format(time);
}
