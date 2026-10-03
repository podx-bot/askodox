import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/selling/domain/seller_catalogue.dart';

void main() {
  AskodoxUserRole? next(String text, AskodoxUserRole current, {AskodoxUserRole? fromIntent = AskodoxUserRole.buyer}) =>
      askodoxContextRole(spoken: askodoxDetectRole(text), fromIntent: fromIntent, current: current);

  test('a Seller stays Seller on product words, generic want/need and guessed buy intents', () {
    for (final text in [
      'fashion',
      'grocery',
      'ready-made grocery catalogue',
      'I want grocery items in my catalogue',
      'price list for online',
      'నాకు కిరాణా కేటలాగ్ కావాలి',
      'मुझे किराना कैटलॉग चाहिए',
      'products',
    ]) {
      expect(next(text, AskodoxUserRole.seller), AskodoxUserRole.seller, reason: text);
    }
  });

  test('only an explicit request to buy takes a Seller to Buyer', () {
    expect(next('I want to buy rice for my home', AskodoxUserRole.seller), AskodoxUserRole.buyer);
    expect(next('switch to buyer', AskodoxUserRole.seller), AskodoxUserRole.buyer);
    expect(next('బియ్యం కొనాలి', AskodoxUserRole.seller), AskodoxUserRole.buyer);
    expect(next('मुझे चावल खरीदना है', AskodoxUserRole.seller), AskodoxUserRole.buyer);
    expect(next('I repair ACs', AskodoxUserRole.seller), AskodoxUserRole.serviceProvider, reason: 'another stated role');
  });

  test('leaving a supply role is high impact (asked when ambiguous)', () {
    expect(askodoxRoleSwitchIsHighImpact(AskodoxUserRole.buyer, from: AskodoxUserRole.seller), isTrue);
    expect(askodoxRoleSwitchIsHighImpact(AskodoxUserRole.buyer, from: AskodoxUserRole.employer), isFalse);
  });

  test('Buyers keep the previous behaviour', () {
    expect(next('I want chicken', AskodoxUserRole.buyer), AskodoxUserRole.buyer);
    expect(next('I want to sell my TV', AskodoxUserRole.buyer, fromIntent: null), AskodoxUserRole.seller);
  });

  test('catalogue intent and short replies', () {
    expect(askodoxCatalogueTemplateFor('Do you have ready-made grocery catalogue?'), 'grocery');
    expect(askodoxCatalogueTemplateFor('కిరాణా కేటలాగ్'), 'grocery');
    expect(askodoxCatalogueTemplateFor('ready-made garments'), 'fashion');
    expect(askodoxCatalogueTemplateFor('సబ్జీ'), isNull);
    expect(askodoxWantsSellerCatalogue('Do you have ready-made grocery catalogue?', AskodoxUserRole.seller), isTrue);
    expect(askodoxWantsSellerCatalogue('fashion', AskodoxUserRole.seller), isTrue);
    expect(askodoxWantsSellerCatalogue('fashion', AskodoxUserRole.buyer), isFalse, reason: 'a buyer browsing fashion');
    expect(askodoxWantsSellerCatalogue('catalogue for my shop', AskodoxUserRole.buyer), isTrue);
    expect(askodoxWantsSellerCatalogue('I want to buy grocery', AskodoxUserRole.seller), isFalse);
    for (final all in ['all', 'All.', 'అన్నీ', 'सब', 'सभी']) {
      expect(askodoxCatalogueReply(all), AskodoxCatalogueReply.all, reason: all);
    }
    expect(askodoxCatalogueReply('సరే'), AskodoxCatalogueReply.yes);
    expect(askodoxCatalogueReply('rice 5 kg'), isNull);
  });
}
