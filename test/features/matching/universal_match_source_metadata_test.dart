import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

void main() {
  test('parses reusable source, media, location, availability and link metadata', () {
    final match = UniversalMatch.fromJson({
      'id': 'online-1',
      'title': 'Verified laptop',
      'source': 'online',
      'image_url': 'https://example.com/laptop.jpg',
      'location_label': 'Online delivery',
      'availability': 'In stock',
      'normal_url': 'https://merchant.example/laptop',
      'disclosure': 'Sponsored link',
    });

    expect(match.source, 'online');
    expect(match.imageUrl, 'https://example.com/laptop.jpg');
    expect(match.locationLabel, 'Online delivery');
    expect(match.availability, 'In stock');
    expect(match.destinationUrl, 'https://merchant.example/laptop');
    expect(match.disclosure, 'Sponsored link');
  });
}