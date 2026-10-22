/// Load & space planner: does a set of boxes / bags fit a cargo space and a
/// weight limit? Deterministic, on-device. Volume fit is a necessary check,
/// not proof the load can be packed (shapes and gaps matter), and the payload
/// limit always comes from the user (vehicle papers / manufacturer), never a
/// guess from a photo.
library;

import 'dart:math' as math;

import 'construction_calculators.dart' show AskodoxCalcException;

class AskodoxLoadItem {
  const AskodoxLoadItem({
    required this.name,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.weightKg,
    this.quantity = 1,
  });

  final String name;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final double weightKg;
  final int quantity;

  double get unitVolumeM3 => lengthCm * widthCm * heightCm / 1e6;
  double get totalVolumeM3 => unitVolumeM3 * quantity;
  double get totalWeightKg => weightKg * quantity;
  List<double> get sortedDims => [lengthCm, widthCm, heightCm]..sort();
}

class AskodoxCargoSpace {
  const AskodoxCargoSpace({
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.payloadKg,
  });

  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final double payloadKg;

  double get volumeM3 => lengthCm * widthCm * heightCm / 1e6;
  List<double> get sortedDims => [lengthCm, widthCm, heightCm]..sort();
}

enum AskodoxLoadVerdict { fits, overWeight, overVolume, itemTooLarge, tight }

class AskodoxLoadPlan {
  const AskodoxLoadPlan({
    required this.verdicts,
    required this.totalVolumeM3,
    required this.totalWeightKg,
    required this.volumeUsedPercent,
    required this.weightUsedPercent,
    required this.loadingOrder,
    required this.oversizedItems,
  });

  final Set<AskodoxLoadVerdict> verdicts;
  final double totalVolumeM3;
  final double totalWeightKg;
  final double volumeUsedPercent;
  final double weightUsedPercent;

  /// Heaviest / largest first: load these at the bottom, toward the front.
  final List<String> loadingOrder;
  final List<String> oversizedItems;

  bool get fits => verdicts.contains(AskodoxLoadVerdict.fits) || verdicts.contains(AskodoxLoadVerdict.tight);
}

/// Above this share of the space, real packing usually fails even though
/// the volume adds up.
const double askodoxTightVolumePercent = 85;

AskodoxLoadPlan askodoxPlanLoad(List<AskodoxLoadItem> items, AskodoxCargoSpace space) {
  if (items.isEmpty) {
    throw const AskodoxCalcException('Add at least one item.', 'కనీసం ఒక వస్తువు చేర్చండి.');
  }
  for (final value in [space.lengthCm, space.widthCm, space.heightCm, space.payloadKg]) {
    if (value.isNaN || value <= 0) {
      throw const AskodoxCalcException('Cargo size and payload must be more than 0.',
          'కార్గో సైజు, బరువు పరిమితి 0 కంటే ఎక్కువ ఉండాలి.');
    }
  }
  for (final item in items) {
    final dims = [item.lengthCm, item.widthCm, item.heightCm];
    if (dims.any((d) => d.isNaN || d <= 0) || item.weightKg.isNaN || item.weightKg < 0 || item.quantity < 1) {
      throw AskodoxCalcException('Check the size, weight and quantity of "${item.name}".',
          '"${item.name}" సైజు, బరువు, సంఖ్య చూడండి.');
    }
  }
  final totalVolume = items.fold<double>(0, (sum, i) => sum + i.totalVolumeM3);
  final totalWeight = items.fold<double>(0, (sum, i) => sum + i.totalWeightKg);
  final volumePercent = totalVolume / space.volumeM3 * 100;
  final weightPercent = totalWeight / space.payloadKg * 100;

  // An item fits by itself only if its sorted dimensions fit the space's
  // sorted dimensions (any rotation of a box).
  final spaceDims = space.sortedDims;
  final oversized = <String>[
    for (final item in items)
      if (!List.generate(3, (i) => item.sortedDims[i] <= spaceDims[i]).every((ok) => ok)) item.name,
  ];

  final verdicts = <AskodoxLoadVerdict>{};
  if (oversized.isNotEmpty) verdicts.add(AskodoxLoadVerdict.itemTooLarge);
  if (totalWeight > space.payloadKg) verdicts.add(AskodoxLoadVerdict.overWeight);
  if (totalVolume > space.volumeM3) verdicts.add(AskodoxLoadVerdict.overVolume);
  if (verdicts.isEmpty) {
    verdicts.add(volumePercent > askodoxTightVolumePercent ? AskodoxLoadVerdict.tight : AskodoxLoadVerdict.fits);
  }

  final order = [...items]..sort((a, b) {
      final byWeight = b.weightKg.compareTo(a.weightKg);
      return byWeight != 0 ? byWeight : b.unitVolumeM3.compareTo(a.unitVolumeM3);
    });
  return AskodoxLoadPlan(
    verdicts: verdicts,
    totalVolumeM3: totalVolume,
    totalWeightKg: totalWeight,
    volumeUsedPercent: math.max(volumePercent, 0),
    weightUsedPercent: math.max(weightPercent, 0),
    loadingOrder: [for (final item in order) item.name],
    oversizedItems: oversized,
  );
}
