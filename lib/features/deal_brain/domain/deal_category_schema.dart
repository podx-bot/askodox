import 'universal_deal.dart';

class DealCategorySchema {
  const DealCategorySchema({
    required this.category,
    required this.requiredFields,
    required this.resultKind,
  });

  final String category;
  final List<String> requiredFields;
  final String resultKind;
}

class DealCategorySchemas {
  static DealCategorySchema forDeal(UniversalDeal deal) {
    switch (deal.intent) {
      case DealIntent.needRide:
      case DealIntent.offerRide:
        return const DealCategorySchema(category: 'mobility', requiredFields: ['from', 'to', 'timing'], resultKind: 'ride');
      case DealIntent.needWorker:
      case DealIntent.seekWork:
        return const DealCategorySchema(category: 'jobs', requiredFields: ['skill', 'location'], resultKind: 'job');
      case DealIntent.needService:
      case DealIntent.offerService:
        return const DealCategorySchema(category: 'services', requiredFields: ['subject', 'location'], resultKind: 'service');
      case DealIntent.bookAppointment:
      case DealIntent.offerAppointment:
        return const DealCategorySchema(category: 'appointment', requiredFields: ['subject', 'location', 'timing'], resultKind: 'appointment');
      case DealIntent.sendParcel:
      case DealIntent.deliverParcel:
        return const DealCategorySchema(category: 'delivery', requiredFields: ['from', 'to', 'timing'], resultKind: 'delivery');
      case DealIntent.rent:
      case DealIntent.offerRental:
        return const DealCategorySchema(category: 'property', requiredFields: ['subject', 'location', 'timing'], resultKind: 'property');
      case DealIntent.buy:
      case DealIntent.sell:
        return DealCategorySchema(
          category: deal.category == 'food' ? 'food' : deal.category == 'property' ? 'property' : 'commerce',
          requiredFields: const ['subject'],
          resultKind: deal.category ?? 'product',
        );
      case DealIntent.other:
        return const DealCategorySchema(category: 'general', requiredFields: ['subject'], resultKind: 'general');
    }
  }
}
