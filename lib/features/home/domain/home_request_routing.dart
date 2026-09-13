class AskodoxHomeRequestRouting {
  const AskodoxHomeRequestRouting._();

  static bool isTransactional(String text) {
    final q = text.toLowerCase().trim();
    if (q.isEmpty) return false;

    const signals = <String>[
      // Jobs / work opportunities.
      'job', 'jobs', 'ఉద్యోగం', 'జాబ్', 'vacancy', 'computer operator',
      // Services / repair.
      'ac repair', 'repair', 'service provider', 'plumber', 'electrician',
      'mechanic', 'మెకానిక్', 'రిపేర్', 'సర్వీస్ కావాలి',
      // Ride / delivery.
      'ride', 'carpool', 'driver', 'passenger', 'రైడ్',
      'parcel', 'delivery', 'courier', 'పార్సెల్', 'డెలివరీ',
      // Product / local buying.
      'buy ', 'buy\n', 'purchase', 'nearby seller', 'local seller',
      'కొనాలి', 'కొనుగోలు', 'చికెన్', 'కోడి', 'mutton', 'మటన్', 'meat',
      'mobile phone', 'మొబైల్',
      // Explicit transaction-side intent.
      'sell ', 'seller', 'buyer', 'book ', 'appointment', 'order ',
      'అమ్మాలి', 'బుక్ చేయాలి', 'ఆర్డర్',
    ];

    return signals.any(q.contains);
  }
}
