import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/company_store.dart';
import '../../../core/utils/formatters.dart';

// Timetable, profile photos and class stories (HrmsApi TimetableController,
// ProfilePhotosController, StoriesController).

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    v is List ? v.whereType<Map<String, dynamic>>().map(f).toList() : <T>[];

// ── Timetable ──

const weekDayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekDayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class TimetableLog {
  const TimetableLog({required this.note, required this.updatedByName});
  final String note;
  final String updatedByName;
}

class TimetableSlot {
  TimetableSlot({
    required this.id,
    required this.classId,
    required this.className,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.notes,
    this.teacherName,
    this.teacherEmployeeId,
    this.log,
    this.canWriteLog = false,
  });

  final int id;
  final int classId;
  final String className;
  /// 1 = Monday … 7 = Sunday.
  final int dayOfWeek;
  final String startTime; // "HH:mm"
  final String endTime;
  final String subject;
  final String? notes;
  final String? teacherName;
  /// The period's own teacher (null = the class teacher).
  final int? teacherEmployeeId;
  /// "What we covered" on the week's date (that weekday's periods only).
  TimetableLog? log;
  final bool canWriteLog;

  factory TimetableSlot.fromJson(Map<String, dynamic> j) {
    final log = j['log'] as Map<String, dynamic>?;
    return TimetableSlot(
      id: _i(j['id']),
      classId: _i(j['classId']),
      className: j['className'] as String? ?? '',
      dayOfWeek: _i(j['dayOfWeek']),
      startTime: j['startTime'] as String? ?? '',
      endTime: j['endTime'] as String? ?? '',
      subject: j['subject'] as String? ?? '',
      notes: _s(j['notes']),
      teacherName: _s(j['teacherName']),
      teacherEmployeeId: j['teacherEmployeeId'] == null ? null : _i(j['teacherEmployeeId']),
      log: log == null ? null : TimetableLog(note: log['note'] as String? ?? '', updatedByName: log['updatedByName'] as String? ?? ''),
      canWriteLog: j['canWriteLog'] == true,
    );
  }
}

class TimetableWeek {
  const TimetableWeek({required this.date, required this.dayOfWeek, required this.slots, this.classId, this.className});
  /// "yyyy-MM-dd" the notes belong to.
  final String date;
  final int dayOfWeek;
  final List<TimetableSlot> slots;
  final int? classId;
  final String? className;

  factory TimetableWeek.fromJson(Map<String, dynamic> j) => TimetableWeek(
        date: j['date'] as String? ?? '',
        dayOfWeek: _i(j['dayOfWeek']),
        slots: _list(j['slots'], TimetableSlot.fromJson),
        classId: (j['classId'] as num?)?.toInt(),
        className: _s(j['className']),
      );
}

// ── Stories ──

/// Daily record (admins): what was on the timetable on a date, with the teacher's note.
class RecordPeriod {
  const RecordPeriod({required this.slotId, required this.className, required this.startTime, required this.endTime,
      required this.subject, this.teacherName, this.note, this.noteBy});
  final int slotId;
  final String className;
  final String startTime;
  final String endTime;
  final String subject;
  final String? teacherName;
  final String? note;
  final String? noteBy;

  factory RecordPeriod.fromJson(Map<String, dynamic> j) => RecordPeriod(
        slotId: _i(j['slotId']),
        className: j['className'] as String? ?? '',
        startTime: j['startTime'] as String? ?? '',
        endTime: j['endTime'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        teacherName: _s(j['teacherName']),
        note: _s(j['note']),
        noteBy: _s(j['noteBy']),
      );
}

class RecordDay {
  const RecordDay({required this.date, required this.dayOfWeek, required this.periods});
  final String date;
  final int dayOfWeek;
  final List<RecordPeriod> periods;

  factory RecordDay.fromJson(Map<String, dynamic> j) => RecordDay(
        date: j['date'] as String? ?? '',
        dayOfWeek: _i(j['dayOfWeek']),
        periods: _list(j['periods'], RecordPeriod.fromJson),
      );
}

class TimetableRecord {
  const TimetableRecord({required this.today, required this.days, required this.periods, required this.written});
  final String today;
  final List<RecordDay> days;
  /// Periods up to today, and how many of them have a note.
  final int periods;
  final int written;

  factory TimetableRecord.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>? ?? const {};
    return TimetableRecord(
      today: j['today'] as String? ?? '',
      days: _list(j['days'], RecordDay.fromJson),
      periods: _i(s['periods']),
      written: _i(s['written']),
    );
  }
}

class StoryMedia {
  const StoryMedia({required this.id, required this.kind, required this.fileName, required this.contentType,
      required this.sizeBytes, required this.url, required this.downloadUrl});
  final int id;
  final String kind; // Photo | Video
  final String fileName;
  final String contentType;
  final int sizeBytes;
  /// Signed link relative to the API root (valid ~12 h): no login token needed.
  final String url;
  final String downloadUrl;

  bool get isVideo => kind == 'Video';

  factory StoryMedia.fromJson(Map<String, dynamic> j) => StoryMedia(
        id: _i(j['id']),
        kind: j['kind'] as String? ?? 'Photo',
        fileName: j['fileName'] as String? ?? 'file',
        contentType: j['contentType'] as String? ?? 'application/octet-stream',
        sizeBytes: _i(j['sizeBytes']),
        url: j['url'] as String? ?? '',
        downloadUrl: j['downloadUrl'] as String? ?? '',
      );
}

class Story {
  const Story({required this.id, this.classId, this.className, this.caption, required this.createdByName,
      required this.createdAt, this.publishedAt, required this.canEdit, required this.media});
  final int id;
  final int? classId;
  final String? className;
  final String? caption;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final bool canEdit;
  final List<StoryMedia> media;

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: _i(j['id']),
        classId: (j['classId'] as num?)?.toInt(),
        className: _s(j['className']),
        caption: _s(j['caption']),
        createdByName: j['createdByName'] as String? ?? '',
        createdAt: tryParseApiDate(j['createdAt'])?.toLocal() ?? DateTime.now(),
        publishedAt: tryParseApiDate(j['publishedAt'])?.toLocal(),
        canEdit: j['canEdit'] == true,
        media: _list(j['media'], StoryMedia.fromJson),
      );
}

class StoryAudience {
  const StoryAudience({required this.wholeSchool, required this.classes});
  final bool wholeSchool;
  final List<({int id, String name})> classes;
}

class SchoolExtrasRepository {
  SchoolExtrasRepository(this._dio, this._apiBase);
  final Dio _dio;
  final String _apiBase;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Full URL for a link the API returns relative to its root (story media).
  String mediaUrl(String relative) => '${_apiBase.endsWith('/') ? _apiBase : '$_apiBase/'}$relative';

  // ── Timetable ──
  Future<TimetableWeek> myTimetable(String date) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/timetable/mine', queryParameters: {'date': date});
        return TimetableWeek.fromJson(r.data!);
      });

  Future<TimetableWeek> childTimetable(int studentId, String date) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/timetable/child/$studentId', queryParameters: {'date': date});
        return TimetableWeek.fromJson(r.data!);
      });

  Future<TimetableLog?> saveLog(int slotId, String date, String note) => _call(() async {
        final r = await _dio.put<dynamic>('school/timetable/slots/$slotId/log', data: {'date': date, 'note': note});
        final d = r.data;
        return d is Map<String, dynamic>
            ? TimetableLog(note: d['note'] as String? ?? '', updatedByName: d['updatedByName'] as String? ?? '')
            : null;
      });

  // Class teachers set up their class's week (admins view it on the website)
  Future<TimetableWeek> classTimetable(int classId) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/timetable', queryParameters: {'classId': classId});
        return TimetableWeek.fromJson(r.data!);
      });

  Future<List<({int id, String name})>> timetableTeachers() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/timetable/teachers');
        return [
          for (final t in r.data ?? const [])
            (id: _i((t as Map<String, dynamic>)['id']), name: t['name'] as String? ?? ''),
        ];
      });

  /// Adds ([id] null) or updates a period. Times are "HH:mm".
  Future<void> saveSlot({int? id, required int classId, required int dayOfWeek, required String startTime,
          required String endTime, required String subject, int? teacherEmployeeId, String? notes}) =>
      _call(() async {
        final body = {
          'classId': classId, 'dayOfWeek': dayOfWeek, 'startTime': startTime, 'endTime': endTime,
          'subject': subject, 'teacherEmployeeId': teacherEmployeeId, 'notes': notes,
        };
        if (id == null) {
          await _dio.post<dynamic>('school/timetable/slots', data: body);
        } else {
          await _dio.put<dynamic>('school/timetable/slots/$id', data: body);
        }
      });

  Future<void> deleteSlot(int id) => _call(() => _dio.delete<dynamic>('school/timetable/slots/$id'));


  /// The daily record from..to ("yyyy-MM-dd", at most 31 days); classId null = every class (admins).
  Future<TimetableRecord> timetableRecord(int? classId, String from, String to) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/timetable/record',
            queryParameters: {'from': from, 'to': to, if (classId != null) 'classId': classId});
        return TimetableRecord.fromJson(r.data!);
      });
  Future<int> copyDay(int classId, int fromDay, List<int> toDays) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/timetable/copy',
            data: {'classId': classId, 'fromDay': fromDay, 'toDays': toDays});
        return _i(r.data?['copied']);
      });

  // ── Profile photos ──
  Future<Uint8List?> photo(String kind, int id, String version) => _call(() async {
        final r = await _dio.get<List<int>>('school/$kind/$id/photo',
            queryParameters: {'v': version}, options: Options(responseType: ResponseType.bytes));
        return r.data == null ? null : Uint8List.fromList(r.data!);
      });

  Future<String?> setPhoto(String kind, int id, Uint8List bytes, String fileName) => _call(() async {
        final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)});
        final r = await _dio.put<Map<String, dynamic>>('school/$kind/$id/photo', data: form);
        return _s(r.data?['photoUpdatedAt']);
      });

  Future<void> deletePhoto(String kind, int id) => _call(() => _dio.delete<void>('school/$kind/$id/photo'));

  // ── Stories ──
  Future<List<Story>> stories({int skip = 0, int take = 20}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/stories', queryParameters: {'skip': skip, 'take': take});
        return _list(r.data, Story.fromJson);
      });

  Future<StoryAudience> audience() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/stories/classes');
        final d = r.data ?? const {};
        return StoryAudience(
          wholeSchool: d['wholeSchool'] == true,
          classes: _list(d['classes'], (c) => (id: _i(c['id']), name: c['name'] as String? ?? '')),
        );
      });

  Future<int> createStory(int? classId, String? caption) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/stories', data: {'classId': classId, 'caption': caption});
        return _i(r.data?['id']);
      });

  Future<void> addMedia(int storyId, String path, String fileName, void Function(double) onProgress) => _call(() async {
        final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: fileName)});
        await _dio.post<void>('school/stories/$storyId/media',
            data: form,
            options: Options(sendTimeout: const Duration(minutes: 15), receiveTimeout: const Duration(minutes: 2)),
            onSendProgress: (sent, total) => total > 0 ? onProgress(sent / total) : null);
      });

  Future<int> publish(int storyId) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/stories/$storyId/publish');
        return _i(r.data?['sentTo']);
      });

  Future<void> deleteStory(int id) => _call(() => _dio.delete<void>('school/stories/$id'));

  /// Downloads a story file (signed link) into memory, e.g. to save or share it.
  Future<Uint8List> download(StoryMedia m, {void Function(double)? onProgress}) => _call(() async {
        final r = await _dio.get<List<int>>(mediaUrl(m.downloadUrl),
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 10)),
            onReceiveProgress: (got, total) => total > 0 && onProgress != null ? onProgress(got / total) : null);
        return Uint8List.fromList(r.data ?? const []);
      });
}

final schoolExtrasProvider =
    Provider<SchoolExtrasRepository>((ref) => SchoolExtrasRepository(ref.watch(dioProvider), ref.watch(apiBaseUrlProvider)));

/// Profile photo bytes of a child ('students') or parent ('parents'); null when there is none.
final profilePhotoProvider = FutureProvider.family<Uint8List?, ({String kind, int id, String? version})>((ref, k) async {
  if (k.version == null) return null;
  try {
    return await ref.watch(schoolExtrasProvider).photo(k.kind, k.id, k.version!);
  } catch (_) {
    return null;
  }
});

final storiesProvider = FutureProvider.autoDispose<List<Story>>((ref) => ref.watch(schoolExtrasProvider).stories(take: 30));
