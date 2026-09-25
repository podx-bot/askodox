enum AskodoxHomeRequestKind {
  general,
  job,
  deliveryJob,
  staffing,
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
    if (q.isEmpty) {
      return AskodoxHomeRequestKind.general;
    }

    final hasJob = _has(q, const ['job', 'jobs', 'ఉద్యోగం', 'జాబ్', 'vacancy', 'computer operator']);
    final hasDelivery = _has(q, const ['delivery', 'courier', 'డెలివరీ']);
    if (hasJob && hasDelivery) {
      return AskodoxHomeRequestKind.deliveryJob;
    }
    if (hasJob) {
      return AskodoxHomeRequestKind.job;
    }

    // Universal AI canonicalizes employer-side worker requests with a staffing
    // marker before they reach this deterministic routing layer. Staffing must
    // win before generic delivery/courier detection so a shop asking for
    // delivery workers cannot reuse an active parcel session.
    if (_has(q, const [
      'need staff', 'need worker', 'need workers', 'hiring staff', 'hire staff',
      'staffing request',
    ])) {
      return AskodoxHomeRequestKind.staffing;
    }

    if (_has(q, const [
      'ac repair', 'repair', 'service provider', 'plumber', 'electrician',
      'mechanic', 'మెకానిక్', 'రిపేర్', 'సర్వీస్ కావాలి',
    ])) {
      return AskodoxHomeRequestKind.service;
    }

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
    ])) {
      return AskodoxHomeRequestKind.retail;
    }
    if (_has(q, const [
      'sell ', 'seller', 'buyer', 'book ', 'appointment', 'order ',
      'అమ్మాలి', 'బుక్ చేయాలి', 'ఆర్డర్',
    ])) {
      return AskodoxHomeRequestKind.transaction;
    }

    return AskodoxHomeRequestKind.general;
  }

  static bool isTransactional(String text) => kindOf(text) != AskodoxHomeRequestKind.general;

  /// A short reply that answers a pending detail question ("curry cut",
  /// "1 kg", "skinless", "delivery") rather than starting a new request or
  /// asking something else. Only meaningful while a deal is unfinished.
  static bool isShortDetailAnswer(String text) {
    final clean = text.trim();
    if (clean.isEmpty || clean.contains('?')) return false;
    final words = clean.split(RegExp(r'\s+'));
    final kind = kindOf(clean);
    // "delivery" / "home delivery" answers the pickup-or-delivery question;
    // it is not a new parcel request.
    final fulfilmentOnly = kind == AskodoxHomeRequestKind.parcel &&
        words.length <= 4 &&
        !_has(clean.toLowerCase(),
            const ['parcel', 'courier', 'send', 'పార్సెల్', 'పంపాలి']);
    if (kind != AskodoxHomeRequestKind.general && !fulfilmentOnly) return false;
    return words.length <= 8;
  }

  static bool shouldStartFresh(String? activeText, String incomingText) {
    final incoming = kindOf(incomingText);
    if (incoming == AskodoxHomeRequestKind.general) return false;
    if (activeText == null || activeText.trim().isEmpty) return true;
    final active = kindOf(activeText);
    return active != incoming;
  }

  static bool _has(String text, List<String> values) => values.any(text.contains);
}
