import '../../catalog/domain/entities/product.dart';
import '../domain/product_discovery_repository.dart';
import '../domain/search_models.dart';

class MockProductDiscoveryRepository implements ProductDiscoveryRepository {
  const MockProductDiscoveryRepository();
  static const barcodes = {'89010001': 'avocado-box', '89010002': 'cold-brew', '89010003': 'wave-headphones', '89010004': 'pocket-charger', '89099999': 'coffee'};
  static const synonyms = {'earphones': 'headphones', 'shoes': 'sneakers', 'coffee maker': 'brewer', 'mobile charger': 'charger', 'plant pot': 'planter'};

  @override List<SmartMatch> matchText(String text, List<Product> catalog) {
    final query = text.trim().toLowerCase(); if (query.isEmpty) return const [];
    final normalized = synonyms[query] ?? query; final result = <SmartMatch>[];
    for (final p in catalog) {
      final name = p.name.toLowerCase(); final terms = '$name ${p.brand.name.toLowerCase()} ${p.tags.join(' ').toLowerCase()} ${p.categoryId} ${p.subcategoryId}';
      MatchKind? kind; double score = 0; String reason = '';
      if (synonyms[query] != null && terms.contains(normalized)) { kind = MatchKind.synonym; score = .86; reason = 'Common synonym'; }
      else if (name == normalized || p.tags.any((e) => e.toLowerCase() == normalized)) { kind = MatchKind.exact; score = .98; reason = 'Exact catalog match'; }
      else if (terms.contains(normalized)) { kind = name.contains(normalized) ? MatchKind.exact : MatchKind.brand; score = .9; reason = 'Name, brand or category match'; }
      else { final words = name.split(' '); if (words.any((w) => _distance(w, normalized) <= 2)) { kind = MatchKind.similarSpelling; score = .72; reason = 'Similar spelling'; } }
      if (kind != null) result.add(SmartMatch(product: p, kind: kind, confidence: MatchConfidence(score), reason: reason));
    }
    result.sort((a,b) => b.confidence.score.compareTo(a.confidence.score)); return result;
  }
  int _distance(String a, String b) { final d = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0)); for(var i=0;i<=a.length;i++) d[i][0]=i; for(var j=0;j<=b.length;j++) d[0][j]=j; for(var i=1;i<=a.length;i++) for(var j=1;j<=b.length;j++) d[i][j]=[d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+(a[i-1]==b[j-1]?0:1)].reduce((x,y)=>x<y?x:y); return d[a.length][b.length]; }
  @override BarcodeResult scanBarcode(Barcode barcode, List<Product> catalog) { if (!barcode.isValid) return const BarcodeResult(BarcodeMatchState.invalid, []); final key=barcodes[barcode.value]; final matches=catalog.where((p)=>p.id==key || (key=='coffee'&&p.tags.contains('coffee'))).toList(); return BarcodeResult(matches.isEmpty?BarcodeMatchState.notFound:matches.length==1?BarcodeMatchState.found:BarcodeMatchState.multipleMatches,matches); }
  @override OCRResult extractMockText(String source, List<Product> catalog) { const text='SoundCore Wave Wireless Headphones'; final matches=matchText('headphones',catalog); return OCRResult(extractedText:text,source:source,matches:matches); }
  @override List<SmartMatch> searchImage(ImageSearchRequest request,List<Product> catalog) => catalog.where((p)=>['wave-headphones','pocket-charger','street-sneakers'].contains(p.id)).map((p)=>SmartMatch(product:p,kind:MatchKind.related,confidence:MatchConfidence(p.id=='wave-headphones' ? .91 : .68),reason:'Mock visual similarity')).toList();
  @override List<SearchSuggestion> suggestions(List<String> recent) => [for(final value in recent.take(3)) SearchSuggestion(value,SuggestionSource.recent),const SearchSuggestion('Wave Wireless Headphones',SuggestionSource.trending),const SearchSuggestion('Classic Cold Brew',SuggestionSource.watchlist),const SearchSuggestion('Avocado Box',SuggestionSource.nearbyDemand),const SearchSuggestion('SoundCore',SuggestionSource.popularBrand)];
  @override List<RelatedProduct> related(Product product,List<Product> catalog) => catalog.where((p)=>p.id!=product.id&&(p.categoryId==product.categoryId||p.brand.id==product.brand.id)).take(4).map((p)=>RelatedProduct(p,p.brand.id==product.brand.id?RelatedProductType.alternatePackSize:p.price<product.price?RelatedProductType.betterOffer:RelatedProductType.alternateBrand)).toList();
}
