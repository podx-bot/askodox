import '../../deal_brain/domain/universal_deal.dart';

class UniversalMatchPresentation {
  const UniversalMatchPresentation({
    required this.resultKind,
    required this.partyLabel,
    required this.cardActionLabel,
    required this.questionChips,
    required this.confirmLabel,
    required this.supportsNegotiation,
    required this.supportsPayment,
    required this.supportsInvoice,
  });

  final String resultKind;
  final String partyLabel;
  final String cardActionLabel;
  final List<String> questionChips;
  final String confirmLabel;
  final bool supportsNegotiation;
  final bool supportsPayment;
  final bool supportsInvoice;
}

class UniversalMatchPresentationPolicy {
  static UniversalMatchPresentation forDeal(UniversalDeal deal) {
    switch (deal.intent) {
      case DealIntent.needService:
        return _service('provider', 'Ask provider', 'Confirm provider');
      case DealIntent.offerService:
        return _service('customer', 'Review customer', 'Accept customer');
      case DealIntent.needWorker:
        return _nonCommerce('worker opportunity', 'Ask employer', 'Apply');
      case DealIntent.seekWork:
        return _nonCommerce('job opportunity', 'Ask employer', 'Apply');
      case DealIntent.sendParcel:
        return _nonCommerce('delivery partner', 'Ask delivery partner', 'Choose partner');
      case DealIntent.deliverParcel:
        return _nonCommerce('delivery request', 'Review delivery request', 'Accept delivery');
      case DealIntent.needRide:
        return _nonCommerce('ride option', 'Ask driver', 'Choose ride');
      case DealIntent.offerRide:
        return _nonCommerce('passenger request', 'Review passenger', 'Accept passenger');
      case DealIntent.bookAppointment:
        return _service('appointment provider', 'Ask provider', 'Book appointment');
      case DealIntent.offerAppointment:
        return _service('appointment seeker', 'Review request', 'Accept appointment');
      case DealIntent.rent:
        return _nonCommerce('rental option', 'Ask owner', 'Choose rental');
      case DealIntent.offerRental:
        return _nonCommerce('rental request', 'Review renter', 'Accept rental');
      case DealIntent.sell:
        return _commerce(false);
      case DealIntent.buy:
      case DealIntent.other:
        return _commerce(deal.intent == DealIntent.buy);
    }
  }

  static UniversalMatchPresentation _commerce(bool buyer) => UniversalMatchPresentation(
        resultKind: buyer ? 'product' : 'buyer request',
        partyLabel: buyer ? 'seller' : 'buyer',
        cardActionLabel: buyer ? 'Ask seller' : 'Review buyer',
        questionChips: const ['Price', 'Availability', 'Delivery', 'Negotiate'],
        confirmLabel: buyer ? 'Confirm' : 'Accept request',
        supportsNegotiation: true,
        supportsPayment: buyer,
        supportsInvoice: buyer,
      );

  static UniversalMatchPresentation _service(String party, String action, String confirm) =>
      UniversalMatchPresentation(
        resultKind: 'service',
        partyLabel: party,
        cardActionLabel: action,
        questionChips: const ['Availability', 'Quote', 'Experience'],
        confirmLabel: confirm,
        supportsNegotiation: true,
        supportsPayment: false,
        supportsInvoice: false,
      );

  static UniversalMatchPresentation _nonCommerce(String kind, String action, String confirm) =>
      UniversalMatchPresentation(
        resultKind: kind,
        partyLabel: kind,
        cardActionLabel: action,
        questionChips: const ['Availability', 'Timing', 'Details'],
        confirmLabel: confirm,
        supportsNegotiation: false,
        supportsPayment: false,
        supportsInvoice: false,
      );
}
