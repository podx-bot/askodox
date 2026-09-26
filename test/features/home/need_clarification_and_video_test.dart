import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/need_clarification.dart';
import 'package:podx/features/home/presentation/video_viewer_screen.dart';

void main() {
  test('battery TV is ambiguous in English and Telugu; a clear phrasing is not', () {
    expect(askodoxClarificationFor('నాకు battery TV కావాలి')?.key, 'battery_tv');
    expect(askodoxClarificationFor('I want a battery tv')?.key, 'battery_tv');
    expect(askodoxClarificationFor('నాకు బ్యాటరీ టీవీ కావాలి')?.key, 'battery_tv');
    expect(askodoxClarificationFor('portable battery TV under 10000'), isNull);
    expect(askodoxClarificationFor('43 inch TV'), isNull);
    expect(askodoxClarificationFor('I need a wireless mouse'), isNull);
    expect(askodoxClarificationFor('I need a mouse')?.key, 'mouse');
  });

  test('a reply picks an option by number, label or keyword; nonsense picks none', () {
    final c = askodoxClarificationFor('battery tv')!;
    expect(askodoxResolveClarification(c, '2')!.subject, 'low power TV for inverter battery backup');
    expect(askodoxResolveClarification(c, 'Portable battery TV')!.subject, 'portable rechargeable battery TV');
    expect(askodoxResolveClarification(c, 'for the remote')!.subject, 'TV remote batteries');
    expect(askodoxResolveClarification(c, 'ఇన్వర్టర్ కోసం')!.subject, 'low power TV for inverter battery backup');
    expect(askodoxResolveClarification(c, 'hmm'), isNull);
  });

  test('video embed URLs stay inside ASKODOX', () {
    expect(askodoxVideoEmbedUri('https://www.youtube.com/watch?v=AbCdEf12345').toString(),
        'https://www.youtube-nocookie.com/embed/AbCdEf12345?autoplay=1&playsinline=1&rel=0');
    expect(askodoxVideoEmbedUri('https://youtu.be/AbCdEf12345').host, 'www.youtube-nocookie.com');
    expect(askodoxVideoEmbedUri('https://www.youtube.com/shorts/AbCdEf12345').path, '/embed/AbCdEf12345');
    expect(askodoxVideoEmbedUri('https://www.instagram.com/reel/xyz/').toString(),
        'https://www.instagram.com/reel/xyz/');
  });
}
