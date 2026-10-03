// Every result/link type the backend returns keeps its link through the
// app's parser (UniversalMatch.fromJson) and gets a clickable card action
// (chatResultActionFor). Rows are shaped exactly like production
// /deals/discover rows (results probe 2026-10-03); nothing here is a fixed
// query or provider list.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

UniversalMatch _row(Map<String, Object?> json) => UniversalMatch.fromJson(json);

void main() {
  test('generic HTTPS web result: link kept, opens as a link', () {
    final m = _row({'id': 'online-0-smartcitycare.in', 'title': 'AC Repair Services', 'source': 'online',
        'match_source': 'online', 'destination_url': 'https://www.smartcitycare.in/air-conditioner/ac'});
    expect(m.destinationUrl, 'https://www.smartcitycare.in/air-conditioner/ac');
    expect(chatResultActionFor(m), ChatResultAction.openLink);
  });

  test('online shopping / product page: link + price + image kept', () {
    final m = _row({'id': 'online-1-reliancedigital.in', 'title': 'boAt earphones', 'source': 'online',
        'page_type': 'product_page', 'price': 999.0, 'price_verified': false,
        'image_url': 'https://imgs.search.brave.com/x', 'destination_url': 'https://www.reliancedigital.in/p/1'});
    expect(chatResultActionFor(m), ChatResultAction.openLink);
    expect(m.price, 999.0);
    expect(m.imageUrl, isNotNull);
  });

  test('affiliate / partner link: disclosure, app deep link and web fallback kept', () {
    final m = _row({'id': 'partner-product-7', 'title': 'Partner offer', 'source': 'online',
        'destination_url': 'https://partner.example/item?tag=x', 'deep_link': 'partner://item/7',
        'web_fallback_url': 'https://partner.example/item', 'affiliate': true, 'disclosure': 'Affiliate link'});
    expect(chatResultActionFor(m), ChatResultAction.openLink);
    expect(m.affiliate, isTrue);
    expect(m.disclosure, 'Affiliate link');
    expect(m.deepLink, 'partner://item/7');
    expect(m.webFallbackUrl, 'https://partner.example/item');
  });

  test('nearby business (Places): map link opens; registered ASKODOX listing sends a request', () {
    final shop = _row({'id': 'place-abc', 'title': 'Sri Sai AC Works', 'source': 'external',
        'match_source': 'external', 'destination_url': 'https://maps.google.com/?cid=1'});
    expect(chatResultActionFor(shop), ChatResultAction.openLink);
    final listing = _row({'id': '12', 'title': 'Vijayawada chicken biryani', 'source': 'local',
        'match_source': 'registered', 'segment': 'registered'});
    expect(chatResultActionFor(listing), ChatResultAction.sendRequest);
  });

  test('YouTube result: thumbnail, title, channel, embed for in-app playback', () {
    final data = jsonDecode(File('test/fixtures/production/discover_biryani_videos.json').readAsStringSync()) as Map;
    final videos = [
      for (final m in (data['matches'] as List).whereType<Map>())
        if (m['source'] == 'video') _row(Map<String, Object?>.from(m)),
    ];
    expect(videos, isNotEmpty);
    for (final v in videos) {
      expect(chatResultActionFor(v), ChatResultAction.watchVideo);
      expect(v.destinationUrl, startsWith('https://www.youtube.com/watch?v='));
      expect(v.imageUrl, startsWith('https://i.ytimg.com/'));
      expect(v.embedUrl, startsWith('https://www.youtube-nocookie.com/embed/'));
      expect(v.title, isNotEmpty);
      expect(v.sourceName, isNotEmpty);
    }
  });

  test('social video (Instagram / Facebook rows): plays as a video card with its link', () {
    final m = _row({'id': 'video-ig-1', 'title': 'Biryani reel', 'source': 'video', 'platform': 'instagram',
        'destination_url': 'https://www.instagram.com/reel/ABC/', 'source_name': 'foodie'});
    expect(chatResultActionFor(m), ChatResultAction.watchVideo);
    expect(m.destinationUrl, 'https://www.instagram.com/reel/ABC/');
  });

  test('the full production response keeps every link through parsing', () {
    for (final f in ['discover_biryani_videos.json', 'discover_ac_repair.json']) {
      final data = jsonDecode(File('test/fixtures/production/$f').readAsStringSync()) as Map;
      final raw = (data['matches'] as List).whereType<Map>().toList();
      final parsed = [for (final m in raw) _row(Map<String, Object?>.from(m))];
      final rawLinks = raw.where((m) => '${m['destination_url'] ?? ''}'.startsWith('https://')).length;
      final parsedLinks = parsed.where((m) => (m.destinationUrl ?? '').startsWith('https://')).length;
      expect(parsedLinks, rawLinks, reason: '$f: no link dropped by the parser');
      final results = AskodoxChatResults(matches: parsed, searched: true);
      expect(results.online.length + results.videos.length + results.local.length, parsed.length,
          reason: '$f: every row lands in a visible section');
    }
  });
}
