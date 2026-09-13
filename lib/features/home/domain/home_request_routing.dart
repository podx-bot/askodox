enum AskodoxHomeRequestKind {
  general,
  job,
  deliveryJob,
  service,
  ride,
  parcel,
  food,
  retail,
  transaction,
}

class AskodoxHomeRequestRouting {
  const AskodoxHomeRequestRouting._();

  static AskodoxHomeRequestKind kindOf(String text) {
    final q = text.toLowerCase().trim();
    if (q.isEmpty) return AskodoxHomeRequestKind.general;

    final hasJob = _has(q, const ['job', 'jobs', 'ఉద్యోగం', 'జాబ్', 'vacancy', 'computer operator']);
    final hasDelivery = _has(q, const ['delivery', 'courier', 'డెలివరీ']);
    if (hasJob && hasDelivery) return AskodoxHomeRequestKind.deliveryJob;
    if (hasJob) return AskodoxHomeRequestKind.job;

    if (_has(q, const [
      'ac repair', 'repair', 'service provider', 'plumber', 'electrician',
      'mechanic', 'మెకానిక్', 'రిపేర్', 'సర్వీస్ కావాలి',
    ])) return AskodoxHomeRequestKind.service;

    if (_has(q, const ['ride', 'carpool', 'driver', 'passenger', 'రైడ్'])) {
      return AskodoxHomeRequestKind.ride;
    }
    if (_has(q, const ['parcel', 'delivery', 'courier', 'పార్సెల్', 'డెలివరీ'])) {
      return AskodoxHomeRequestKind.parcel;
    }
    if (_has(q, const ['chicken', 'చికెన్', 'కోడి', 'mutton', 'మటన్', 'meat'])) {
      return AskodoxHomeRequestKind.food;
    }
    if (_has(q, const [
      'buy ', 'buy\n', 'purchase', 'nearby seller', 'local seller', 'కొనాలి',
      'కొనుగోలు', 'mobile phone', 'మొబైల్', 'tv', 'television', 'furniture', 'sofa',
    ])) return AskodoxHomeRequestKind.retail;
    if (_has(q, const [
      'sell ', 'seller', 'buyer', 'book ', 'appointment', 'order ',
      'అమ్మాలి', 'బుక్ చేయాలి', 'ఆర్డర్',
    ])) return AskodoxHomeRequestKind.transaction;

    return AskodoxHomeRequestKind.general;
  }

  static bool isTransactional(String text) => kindOf(text) != AskodoxHomeRequestKind.general;

  static bool shouldStartFresh(String? activeText, String incomingText) {
    final incoming = kindOf(incomingText);
    if (incoming == AskodoxHomeRequestKind.general) return false;
    if (activeText == null || activeText.trim().isEmpty) return true;
    final active = kindOf(activeText);
    return active != incoming;
  }

  static bool _has(String text, List<String> values) => values.any(text.contains);
}
