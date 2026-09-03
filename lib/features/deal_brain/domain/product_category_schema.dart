class ProductCategorySchema {
  const ProductCategorySchema({
    required this.id,
    required this.keywords,
    this.requiresQuantity = false,
    this.requiredFields = const <String>[],
    this.questions = const <String, String>{},
  });

  final String id;
  final List<String> keywords;
  final bool requiresQuantity;
  final List<String> requiredFields;
  final Map<String, String> questions;

  bool matches(String source) => keywords.any(source.contains);
}

class ProductCategorySchemas {
  const ProductCategorySchemas._();

  static const schemas = <ProductCategorySchema>[
    ProductCategorySchema(
      id: 'chicken',
      keywords: ['chicken', 'చికెన్'],
      requiresQuantity: true,
      requiredFields: ['freshness', 'cut', 'chickenPreference', 'fulfilment'],
      questions: {
        'quantity': 'How much chicken do you need?',
        'freshness': 'Do you want fresh/live-cut or chilled chicken?',
        'cut': 'How should the chicken be cut?',
        'chickenPreference': 'Any preference for skin, portion, liver or gizzard? You can also say no preference.',
        'fulfilment': 'Do you want pickup or delivery?',
      },
    ),
    ProductCategorySchema(
      id: 'fresh_food',
      keywords: [
        'mutton', 'మటన్', 'meat', 'fish', 'చేప', 'prawns', 'vegetable',
        'vegetables', 'కూరగాయ', 'fruit', 'fruits', 'పండ్లు',
      ],
      requiresQuantity: true,
      questions: {'quantity': 'How much do you need?'},
    ),
    ProductCategorySchema(
      id: 'grocery',
      keywords: [
        'rice', 'బియ్యం', 'dal', 'పప్పు', 'flour', 'atta', 'sugar', 'చక్కెర',
        'oil', 'milk', 'పాలు', 'grocery', 'groceries', 'కిరాణా',
      ],
      requiresQuantity: true,
      questions: {'quantity': 'How much do you need?'},
    ),
    ProductCategorySchema(
      id: 'wholesale_packaged_goods',
      keywords: [
        'masala', 'మసాలా', 'spice', 'spices', 'packet', 'packets', 'bag', 'bags',
        'carton', 'cartons', 'case', 'cases', 'wholesale', 'bulk',
      ],
      requiresQuantity: true,
      requiredFields: ['packSize'],
      questions: {
        'quantity': 'How many packs, bags, cartons or units do you need?',
        'packSize': 'What pack or bag size do you need?',
      },
    ),
    ProductCategorySchema(
      id: 'construction_material',
      keywords: [
        'cement', 'సిమెంట్', 'sand', 'steel', 'iron', 'bricks', 'tiles',
        'wood', 'timber', 'material',
      ],
      requiresQuantity: true,
      questions: {'quantity': 'How much material do you need?'},
    ),
    ProductCategorySchema(
      id: 'television',
      keywords: ['tv', 'television', 'smart tv', 'led tv', 'oled', 'qled'],
      requiredFields: ['size'],
      questions: {'size': 'What TV screen size do you prefer?'},
    ),
    ProductCategorySchema(
      id: 'mobile_phone',
      keywords: ['phone', 'mobile', 'smartphone', 'iphone', 'android phone'],
      questions: {
        'model': 'Any preferred brand or model?',
      },
    ),
    ProductCategorySchema(
      id: 'furniture',
      keywords: [
        'furniture', 'sofa', 'chair', 'table', 'bed', 'cot', 'wardrobe',
        'మంచం', 'సోఫా', 'కుర్చీ',
      ],
      requiredFields: ['size'],
      questions: {
        'size': 'What size or dimensions do you need?',
        'material': 'Any preferred material?',
      },
    ),
    ProductCategorySchema(
      id: 'home_appliance',
      keywords: [
        'refrigerator', 'fridge', 'washing machine', 'ac', 'air conditioner',
        'microwave', 'mixer', 'grinder', 'geyser', 'appliance',
      ],
      questions: {'model': 'Any preferred brand, capacity or model?'},
    ),
    ProductCategorySchema(
      id: 'vehicle',
      keywords: ['car', 'bike', 'scooter', 'vehicle', 'motorcycle'],
      requiredFields: ['condition'],
      questions: {'condition': 'Do you want new or used?'},
    ),
    ProductCategorySchema(
      id: 'fashion',
      keywords: ['shirt', 'dress', 'saree', 'shoe', 'shoes', 'clothing', 'fashion'],
      requiredFields: ['size'],
      questions: {'size': 'What size do you need?'},
    ),
  ];

  static const general = ProductCategorySchema(
    id: 'general',
    keywords: <String>[],
  );

  static ProductCategorySchema resolve(String source) {
    final normalized = source.toLowerCase();
    for (final schema in schemas) {
      if (schema.matches(normalized)) return schema;
    }
    return general;
  }
}
