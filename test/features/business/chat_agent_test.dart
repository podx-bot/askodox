import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/business/presentation/biz_chat.dart';

void main() {
  test('a role agent named in the chat is found; ordinary words are not (owner 2026-11-19)', () {
    expect(askodoxChatAgentOf('stock agent what is low?'), 'inventory');
    expect(askodoxChatAgentOf('స్టాక్ ఏజెంట్ ఏం తక్కువ ఉంది'), 'inventory');
    expect(askodoxChatAgentOf('ఫైనాన్స్ ఏజెంట్ ఈరోజు ఎంత వచ్చింది'), 'finance');
    expect(askodoxChatAgentOf('GST agent this month'), 'tax');
    expect(askodoxChatAgentOf('@sales follow ups'), 'sales');
    expect(askodoxChatAgentOf('I need a stock market tip'), isNull, reason: 'no agent word');
    expect(askodoxChatAgentOf('travel agent near me'), isNull, reason: 'not a shop role');
  });
}
