class RfqSchema {
  const RfqSchema({required this.id, required this.fields});
  final String id;
  final List<String> fields;
}

class RfqSchemas {
  const RfqSchemas._();

  static const common = <String>[
    'price',
    'taxes',
    'deliveryLeadTime',
    'validity',
    'paymentTerms',
    'warrantyReturn',
    'notes',
  ];

  static const chickenBulk = RfqSchema(id: 'chicken_bulk', fields: <String>[
    'pricePerKg', 'quantity', 'cut', 'deliveryLeadTime', 'validity',
  ]);

  static const furniture = RfqSchema(id: 'furniture', fields: <String>[
    'material', 'dimensions', 'quantity', 'transport', 'installation', 'totalPrice',
  ]);

  static const service = RfqSchema(id: 'service', fields: <String>[
    'labourPrice', 'materialPrice', 'timeline', 'warranty', 'totalPrice',
  ]);

  static const wholesale = RfqSchema(id: 'wholesale', fields: <String>[
    'moq', 'unitPrice', 'taxes', 'freight', 'paymentTerms', 'deliveryLeadTime',
  ]);

  static const general = RfqSchema(id: 'general', fields: common);

  static RfqSchema resolve({required String category, String? productProfile, String? subject}) {
    final haystack = '${category.toLowerCase()} ${(productProfile ?? '').toLowerCase()} ${(subject ?? '').toLowerCase()}';
    if (haystack.contains('chicken')) return chickenBulk;
    if (haystack.contains('furniture') || haystack.contains('bed') || haystack.contains('sofa')) return furniture;
    if (haystack.contains('service') || haystack.contains('repair') || haystack.contains('electric')) return service;
    if (haystack.contains('wholesale') || haystack.contains('packaged_goods') || haystack.contains('masala')) return wholesale;
    return general;
  }
}
