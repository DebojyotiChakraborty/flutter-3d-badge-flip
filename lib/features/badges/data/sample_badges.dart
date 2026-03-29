import '../../../core/theme/badge_colors.dart';
import '../models/badge_model.dart';

/// Sample badges matching the 5 available GLB assets in assets/badges/.
final List<AwardBadge> sampleBadges = [
  AwardBadge(
    id: '1',
    name: 'New Move Record',
    description:
        'You set a new personal record for calories burned in a single day. Keep pushing your limits!',
    glbAssetPath: 'assets/badges/award-1.glb',
    category: BadgeCategory.closeYourRings,
    accentColor: BadgeColors.pink,
    isEarned: true,
    dateEarned: DateTime(2025, 12, 15),
    metadata: {'calories': 343},
  ),
  AwardBadge(
    id: '2',
    name: 'Move Goal 200%',
    description:
        'You doubled your daily Move goal. Outstanding effort — you went above and beyond today!',
    glbAssetPath: 'assets/badges/award-2.glb',
    category: BadgeCategory.closeYourRings,
    accentColor: BadgeColors.orange,
    isEarned: true,
    dateEarned: DateTime(2025, 11, 28),
    metadata: {'percentage': 200},
  ),
  AwardBadge(
    id: '3',
    name: 'New All-Time Move Goal',
    description:
        'You hit a new all-time high for your Move goal. This is your best day yet!',
    glbAssetPath: 'assets/badges/award-3.glb',
    category: BadgeCategory.milestones,
    accentColor: BadgeColors.silver,
    isEarned: true,
    dateEarned: DateTime(2026, 1, 5),
    metadata: {'calories': 120},
  ),
  AwardBadge(
    id: '4',
    name: '100 Move Goals',
    description:
        'Close your Move ring 100 times. Every ring closed brings you one step closer to this milestone.',
    glbAssetPath: 'assets/badges/award-4.glb',
    category: BadgeCategory.milestones,
    accentColor: BadgeColors.green,
    isEarned: false,
    progress: 0.08,
    progressLabel: '8 of 100',
  ),
  AwardBadge(
    id: '5',
    name: 'Move Goal 300%',
    description:
        'Triple your daily Move goal in a single day. An extraordinary feat of dedication and endurance.',
    glbAssetPath: 'assets/badges/award-5.glb',
    category: BadgeCategory.closeYourRings,
    accentColor: BadgeColors.orange,
    isEarned: false,
    progress: 0.003,
    progressLabel: '1 of 360 kcal',
  ),
];
