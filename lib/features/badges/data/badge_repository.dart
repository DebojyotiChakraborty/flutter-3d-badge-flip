import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge_model.dart';
import 'sample_badges.dart';

/// Provides the list of all badges.
final badgeRepositoryProvider = Provider<List<AwardBadge>>((ref) {
  return sampleBadges;
});
