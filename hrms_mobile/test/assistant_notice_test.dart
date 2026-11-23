import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/router/app_router.dart';
import 'package:hrms_mobile/features/assistant/data/assistant_repository.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';

void main() {
  test('the chat reads the "AI stopped" notice from start and ask', () {
    final s = BotStart.fromJson({
      'greeting': 'Hi',
      'topics': [],
      'ai': true,
      'aiNotice': {
        'level': 'error',
        'message': 'AI answers stopped: Your Anthropic credit has run out.',
        'link': 'https://console.anthropic.com/',
        'linkLabel': 'Open the Anthropic Console',
      },
    });
    expect(s.aiNotice!.level, 'error');
    expect(s.aiNotice!.link, 'https://console.anthropic.com/');

    final r = BotAskResult.fromJson({'reply': null, 'answer': null, 'related': [], 'unanswered': true, 'source': 'none',
        'aiNotice': {'level': 'info', 'message': 'Smart answers are paused for now.', 'link': null, 'linkLabel': null}});
    expect(r.aiNotice!.message, contains('paused'));
    expect(r.aiNotice!.link, isNull);

    expect(BotStart.fromJson({'greeting': 'Hi', 'topics': []}).aiNotice, isNull);
  });

  test('"AI answers stopped" notifications open the Chatbot page for admins only', () {
    Session session(String role) => Session(token: 't', username: 'u', role: role, expiresAt: DateTime.utc(2099));
    expect(Routes.fromWebLink(session('Admin'), '/master/chatbot'), Routes.chatbotAdmin);
    expect(Routes.fromWebLink(session('Parent'), '/master/chatbot'), isNull);
  });
}
