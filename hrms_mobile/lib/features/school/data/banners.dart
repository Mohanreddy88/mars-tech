import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'school_repository.dart';

// School → Banners: advert-style slides on the parent home. Same as the website.

/// Colour themes (same keys as the API and the website).
const bannerThemes = ['purple', 'blue', 'green', 'orange', 'pink', 'teal'];

/// Parent pages a banner button may open → their label in the admin form.
const bannerPages = {
  'fees': 'Fees',
  'messages': 'Messages',
  'new-message': 'Message the school (new message)',
  'announcements': 'Announcements',
  'account': 'My account',
};

/// A banner (GET school/banners for admins, school/banners/current for parents).
class SchoolBanner {
  SchoolBanner({
    required this.id,
    required this.title,
    this.text,
    this.buttonText,
    this.link,
    required this.theme,
    this.classId,
    this.className,
    this.startsOn,
    this.endsOn,
    this.isActive = true,
    this.imageVersion,
    this.status = 'Live',
  });

  final int id;
  final String title;
  final String? text;
  final String? buttonText;
  /// A key of [bannerPages] or an https:// address; null = no button.
  final String? link;
  final String theme;
  final int? classId;
  final String? className;
  /// yyyy-MM-dd or null.
  final String? startsOn;
  final String? endsOn;
  final bool isActive;
  /// Null = no picture.
  final int? imageVersion;
  /// 'Live', 'Scheduled', 'Ended' or 'Off' (admin list).
  final String status;

  bool get external => link?.startsWith('https://') ?? false;

  static String? _ymd(Object? v) => v is String && v.length >= 10 ? v.substring(0, 10) : null;

  factory SchoolBanner.fromJson(Map<String, dynamic> j) => SchoolBanner(
        id: j['id'] as int,
        title: j['title'] as String? ?? '',
        text: j['text'] as String?,
        buttonText: j['buttonText'] as String?,
        link: j['link'] as String?,
        theme: j['theme'] as String? ?? 'purple',
        classId: j['classId'] as int?,
        className: j['className'] as String?,
        startsOn: _ymd(j['startsOn']),
        endsOn: _ymd(j['endsOn']),
        isActive: j['isActive'] as bool? ?? true,
        imageVersion: j['imageVersion'] as int?,
        status: j['status'] as String? ?? 'Live',
      );
}

/// What the admin form sends.
class BannerSave {
  BannerSave({
    required this.title,
    this.text = '',
    this.buttonText = '',
    this.link = '',
    this.theme = 'purple',
    this.classId,
    this.startsOn,
    this.endsOn,
    this.isActive = true,
    this.image,
    this.removeImage = false,
  });

  String title, text, buttonText, link, theme;
  int? classId;
  String? startsOn, endsOn;
  bool isActive;
  PickedFile? image;
  bool removeImage;

  factory BannerSave.of(SchoolBanner b) => BannerSave(
        title: b.title,
        text: b.text ?? '',
        buttonText: b.buttonText ?? '',
        link: b.link ?? '',
        theme: b.theme,
        classId: b.classId,
        startsOn: b.startsOn,
        endsOn: b.endsOn,
        isActive: b.isActive,
      );
}

class BannersRepository {
  BannersRepository(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<SchoolBanner>> _list(String path) => _call(() async {
        final r = await _dio.get<List<dynamic>>(path);
        return (r.data ?? const []).map((e) => SchoolBanner.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// The parent's live banners.
  Future<List<SchoolBanner>> current() => _list('school/banners/current');

  /// Every banner (admins).
  Future<List<SchoolBanner>> all() => _list('school/banners');

  Future<Uint8List> image(int id, int version) => _call(() async {
        final r = await _dio.get<List<int>>('school/banners/$id/image',
            queryParameters: {'v': version}, options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data ?? const []);
      });

  Future<void> save(int? id, BannerSave b) => _call(() async {
        final form = FormData.fromMap({
          'title': b.title,
          'text': b.text,
          'buttonText': b.link.isEmpty ? '' : b.buttonText,
          'link': b.link,
          'theme': b.theme,
          if (b.classId != null) 'classId': b.classId,
          if (b.startsOn != null) 'startsOn': b.startsOn,
          if (b.endsOn != null) 'endsOn': b.endsOn,
          'isActive': b.isActive,
          'removeImage': b.removeImage,
          if (b.image != null) 'image': MultipartFile.fromBytes(b.image!.bytes, filename: b.image!.name),
        });
        if (id == null) {
          await _dio.post<void>('school/banners', data: form);
        } else {
          await _dio.put<void>('school/banners/$id', data: form);
        }
      });

  Future<void> move(int id, {required bool up}) =>
      _call(() => _dio.post<void>('school/banners/$id/move', queryParameters: {'up': up}));

  Future<void> delete(int id) => _call(() => _dio.delete<void>('school/banners/$id'));

  /// Adds the general school cards (a day of learning, play areas, meals, teachers) as banners to edit.
  Future<int> addSamples() => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/banners/samples');
        return (r.data?['added'] as int?) ?? 0;
      });
}

final bannersRepositoryProvider = Provider<BannersRepository>((ref) => BannersRepository(ref.watch(dioProvider)));

/// The parent home's banners (none on error, so the home just shows without them).
final currentBannersProvider = FutureProvider.autoDispose<List<SchoolBanner>>((ref) async {
  try {
    return await ref.watch(bannersRepositoryProvider).current();
  } catch (_) {
    return const [];
  }
});

final bannersProvider = FutureProvider.autoDispose<List<SchoolBanner>>((ref) => ref.watch(bannersRepositoryProvider).all());

/// A banner picture, kept for the session (a new picture has a new version).
final bannerImageProvider = FutureProvider.family<Uint8List, (int, int)>(
    (ref, key) => ref.watch(bannersRepositoryProvider).image(key.$1, key.$2));
