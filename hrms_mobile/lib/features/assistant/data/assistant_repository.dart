import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';

// Help chatbot (HrmsApi /api/assistant): answers from the questions and answers the company's
// admins wrote. No AI. Models mirror the API's camelCase JSON.

class BotAction {
  const BotAction({required this.key, required this.label});
  final String key;
  final String label;
  static BotAction? fromJson(dynamic j) =>
      j is Map<String, dynamic> ? BotAction(key: j['key'] as String? ?? '', label: j['label'] as String? ?? '') : null;
}

/// A file the AI offered: label and API path (relative to the API base, fetched with the login token).
class BotDownload {
  const BotDownload({required this.label, required this.path});
  final String label;
  final String path;
  static BotDownload? fromJson(dynamic j) => j is Map<String, dynamic> && j['path'] is String
      ? BotDownload(label: j['label'] as String? ?? 'Download', path: j['path'] as String)
      : null;
}

class BotAnswer {
  const BotAnswer({required this.id, required this.question, required this.answer, this.action, this.download});
  final int id;
  final String question;
  final String answer;
  final BotAction? action;
  final BotDownload? download;
  factory BotAnswer.fromJson(Map<String, dynamic> j) => BotAnswer(
        id: (j['id'] as num).toInt(),
        question: j['question'] as String? ?? '',
        answer: j['answer'] as String? ?? '',
        action: BotAction.fromJson(j['action']),
        download: BotDownload.fromJson(j['download']),
      );
}

class BotTopic {
  const BotTopic({required this.category, required this.items});
  final String category;
  final List<BotAnswer> items;
}

/// A note about AI answers for the top of the chat. Admins get 'error' (stopped, with the fix and a
/// link) or 'warning'; everyone else 'info' ("smart answers are paused…", no billing details).
class BotAiNotice {
  const BotAiNotice({required this.level, required this.message, this.link, this.linkLabel});
  final String level;
  final String message;
  final String? link;
  final String? linkLabel;

  static BotAiNotice? fromJson(dynamic j) => j is Map<String, dynamic>
      ? BotAiNotice(
          level: j['level'] as String? ?? 'info',
          message: j['message'] as String? ?? '',
          link: j['link'] as String?,
          linkLabel: j['linkLabel'] as String?,
        )
      : null;
}

class BotStart {
  const BotStart({required this.greeting, required this.topics, required this.canMessageSchool, this.ai = false,
      this.aiNotice});
  final String greeting;
  final List<BotTopic> topics;
  final bool canMessageSchool;
  /// AI answers are on for this company.
  final bool ai;
  /// Shown at the top of the chat while AI answers are stopped (e.g. no Anthropic credit).
  final BotAiNotice? aiNotice;

  factory BotStart.fromJson(Map<String, dynamic> j) => BotStart(
        greeting: j['greeting'] as String? ?? 'Hi! How can I help?',
        topics: [
          for (final t in (j['topics'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            BotTopic(
              category: t['category'] as String? ?? '',
              items: [for (final i in (t['items'] as List<dynamic>? ?? const [])) BotAnswer.fromJson(i as Map<String, dynamic>)],
            ),
        ],
        canMessageSchool: j['canMessageSchool'] as bool? ?? false,
        ai: j['ai'] as bool? ?? false,
        aiNotice: BotAiNotice.fromJson(j['aiNotice']),
      );
}

typedef BotQuestionRef = ({int id, String question});

class BotAskResult {
  const BotAskResult({this.reply, this.answer, required this.related, required this.unanswered, this.source = 'faq',
      this.aiNotice});
  final String? reply;
  final BotAnswer? answer;
  final List<BotQuestionRef> related;
  final bool unanswered;
  /// Who answered: faq, ai or none.
  final String source;
  /// Set when the AI is stopped or just failed; this answer came from the list.
  final BotAiNotice? aiNotice;

  factory BotAskResult.fromJson(Map<String, dynamic> j) => BotAskResult(
        reply: j['reply'] as String?,
        answer: j['answer'] is Map<String, dynamic> ? BotAnswer.fromJson(j['answer'] as Map<String, dynamic>) : null,
        related: [
          for (final r in (j['related'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            (id: (r['id'] as num).toInt(), question: r['question'] as String? ?? ''),
        ],
        unanswered: j['unanswered'] as bool? ?? false,
        source: j['source'] as String? ?? 'faq',
        aiNotice: BotAiNotice.fromJson(j['aiNotice']),
      );
}

/// Admin: AI answers availability, switch and usage.
class BotAiStatus {
  const BotAiStatus({required this.configured, required this.enabled, required this.model, required this.dailyLimit,
      required this.todayQuestions, required this.monthQuestions, required this.monthAnswered,
      this.keySource, this.keyHint, this.keyUnreadable = false, this.problem, this.problemAt, this.problemCount = 0});
  /// Why the latest AI answers failed (e.g. no Anthropic credit), until one works again.
  final String? problem;
  /// When it last failed (UTC, ISO text).
  final String? problemAt;
  /// Questions in a row that failed.
  final int problemCount;
  /// A key is available (the company's own or the server's).
  final bool configured;
  /// 'company' (connected here), 'server', or null.
  final String? keySource;
  final String? keyHint;
  final bool keyUnreadable;
  final bool enabled;
  final String model;
  final int dailyLimit;
  final int todayQuestions;
  final int monthQuestions;
  final int monthAnswered;

  factory BotAiStatus.fromJson(Map<String, dynamic> j) {
    int n(String part, String k) => ((j[part] as Map<String, dynamic>?)?[k] as num?)?.toInt() ?? 0;
    final problem = j['problem'] as Map<String, dynamic>?;
    return BotAiStatus(
      problem: problem?['message'] as String?,
      problemAt: problem?['at'] as String?,
      problemCount: (problem?['failures'] as num?)?.toInt() ?? 0,
      configured: j['configured'] as bool? ?? false,
      keySource: j['keySource'] as String?,
      keyHint: j['keyHint'] as String?,
      keyUnreadable: j['keyUnreadable'] as bool? ?? false,
      enabled: j['enabled'] as bool? ?? false,
      model: j['model'] as String? ?? '',
      dailyLimit: (j['dailyLimitPerUser'] as num?)?.toInt() ?? 0,
      todayQuestions: n('today', 'questions'),
      monthQuestions: n('last30Days', 'questions'),
      monthAnswered: n('last30Days', 'answered'),
    );
  }
}

/// Admin: one question and answer.
class BotFaq {
  const BotFaq({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.keywords,
    required this.audience,
    this.action,
    required this.sortOrder,
    required this.isActive,
  });
  final int id;
  final String category;
  final String question;
  final String answer;
  final String? keywords;
  final String audience; // All | Parent | Employee
  final String? action;
  final int sortOrder;
  final bool isActive;

  factory BotFaq.fromJson(Map<String, dynamic> j) => BotFaq(
        id: (j['id'] as num).toInt(),
        category: j['category'] as String? ?? 'General',
        question: j['question'] as String? ?? '',
        answer: j['answer'] as String? ?? '',
        keywords: j['keywords'] as String?,
        audience: j['audience'] as String? ?? 'All',
        action: j['action'] as String?,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        isActive: j['isActive'] as bool? ?? true,
      );

  static String audienceLabel(String a) => switch (a) { 'Parent' => 'Parents', 'Employee' => 'Staff', _ => 'Everyone' };
}

class BotAdminList {
  const BotAdminList({required this.faqs, required this.actions, required this.schoolFeatures, required this.unansweredCount});
  final List<BotFaq> faqs;
  final List<({String key, String label, String audience})> actions;
  final bool schoolFeatures;
  final int unansweredCount;

  factory BotAdminList.fromJson(Map<String, dynamic> j) => BotAdminList(
        faqs: [for (final f in (j['faqs'] as List<dynamic>? ?? const [])) BotFaq.fromJson(f as Map<String, dynamic>)],
        actions: [
          for (final a in (j['actions'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            (key: a['key'] as String? ?? '', label: a['label'] as String? ?? '', audience: a['audience'] as String? ?? 'All'),
        ],
        schoolFeatures: j['schoolFeatures'] as bool? ?? false,
        unansweredCount: (j['unansweredCount'] as num?)?.toInt() ?? 0,
      );
}

class BotUnanswered {
  const BotUnanswered({required this.id, required this.text, required this.audience, required this.askedAt});
  final int id;
  final String text;
  final String audience;
  final DateTime askedAt;
  factory BotUnanswered.fromJson(Map<String, dynamic> j) => BotUnanswered(
        id: (j['id'] as num).toInt(),
        text: j['text'] as String? ?? '',
        audience: j['audience'] as String? ?? 'Employee',
        askedAt: tryParseApiDate(j['askedAt']) ?? DateTime.now(),
      );
}

class AssistantRepository {
  AssistantRepository(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<BotStart> start() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('assistant/start');
        return BotStart.fromJson(r.data!);
      });

  /// [history]: earlier turns of this chat as (fromUser, text), so the AI can follow up.
  Future<BotAskResult> ask(String text, {List<(bool, String)> history = const []}) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('assistant/ask',
            data: {
              'text': text,
              'history': [for (final h in history) {'fromUser': h.$1, 'text': h.$2}],
            },
            options: Options(receiveTimeout: const Duration(seconds: 75)));
        return BotAskResult.fromJson(r.data!);
      });

  /// Downloads a file the AI offered. Returns the bytes and the server's file name.
  Future<(List<int>, String)> download(String path) => _call(() async {
        final r = await _dio.get<List<int>>(path.startsWith('/') ? path.substring(1) : path,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 90)));
        final cd = r.headers.value('content-disposition') ?? '';
        // e.g. attachment; filename=Unpaid_fees.xlsx; filename*=UTF-8''Unpaid_fees.xlsx
        final m = RegExp(r'''filename=\"?([^";]+)\"?''', caseSensitive: false).firstMatch(cd);
        final name = m == null ? 'download' : Uri.decodeComponent(m.group(1)!);
        return (r.data ?? const <int>[], name);
      });

  // ── Admin ──

  Future<BotAiStatus> aiStatus() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('assistant/admin/ai');
        return BotAiStatus.fromJson(r.data!);
      });

  /// Connects the company's own Anthropic API key (tested by the server, stored encrypted).
  Future<void> connectKey(String apiKey) => _call(() => _dio.put<void>('assistant/admin/ai/key', data: {'apiKey': apiKey},
      options: Options(receiveTimeout: const Duration(seconds: 40))));

  Future<void> disconnectKey() => _call(() => _dio.delete<void>('assistant/admin/ai/key'));

  Future<void> setAi(bool enabled) => _call(() => _dio.put<void>('assistant/admin/ai', data: {'enabled': enabled}));

  Future<BotAdminList> adminList() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('assistant/admin/faqs');
        return BotAdminList.fromJson(r.data!);
      });

  Future<void> save(int? id, Map<String, dynamic> body) => _call(() async {
        id == null
            ? await _dio.post<void>('assistant/admin/faqs', data: body)
            : await _dio.put<void>('assistant/admin/faqs/$id', data: body);
      });

  Future<void> delete(int id) => _call(() => _dio.delete<void>('assistant/admin/faqs/$id'));

  Future<int> addStarter() => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('assistant/admin/faqs/starter');
        return (r.data?['added'] as num?)?.toInt() ?? 0;
      });

  Future<List<BotUnanswered>> unanswered() => _call(() async {
        final r = await _dio.get<List<dynamic>>('assistant/admin/unanswered');
        return [for (final u in r.data ?? const []) BotUnanswered.fromJson(u as Map<String, dynamic>)];
      });

  Future<void> deleteUnanswered(int id) => _call(() => _dio.delete<void>('assistant/admin/unanswered/$id'));
}

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) => AssistantRepository(ref.watch(dioProvider)));

final botAdminProvider = FutureProvider.autoDispose<BotAdminList>((ref) => ref.watch(assistantRepositoryProvider).adminList());

final botAiStatusProvider =
    FutureProvider.autoDispose<BotAiStatus>((ref) => ref.watch(assistantRepositoryProvider).aiStatus());

final botUnansweredProvider =
    FutureProvider.autoDispose<List<BotUnanswered>>((ref) => ref.watch(assistantRepositoryProvider).unanswered());
