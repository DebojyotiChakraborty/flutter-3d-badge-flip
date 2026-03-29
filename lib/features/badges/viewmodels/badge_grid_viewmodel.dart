import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/badge_repository.dart';
import '../models/badge_model.dart';

/// Provides the full list of badges for the grid.
final badgeListProvider = Provider<List<AwardBadge>>((ref) {
  return ref.watch(badgeRepositoryProvider);
});

/// Provides a single badge by ID.
/// Returns null if no badge matches.
final badgeByIdProvider = Provider.family<AwardBadge?, String>((ref, id) {
  final badges = ref.watch(badgeListProvider);
  try {
    return badges.firstWhere((b) => b.id == id);
  } catch (_) {
    return null;
  }
});
