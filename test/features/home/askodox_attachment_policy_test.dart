import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';

void main() {
  test('attachment MIME type follows the selected file extension', () {
    expect(askodoxAttachmentMimeType('quote.pdf'), 'application/pdf');
    expect(askodoxAttachmentMimeType('catalog.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    expect(askodoxAttachmentMimeType('notes.unknown'),
        'application/octet-stream');
  });
}