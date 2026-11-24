import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/router/app_router.dart';
import 'package:hrms_mobile/features/school/data/banners.dart';
import 'package:hrms_mobile/features/school/presentation/banner_carousel.dart';

void main() {
  test('banners read from the API and their buttons open the right place', () {
    final b = SchoolBanner.fromJson({
      'id': 4, 'title': 'Holiday camp', 'text': '7–18 Dec', 'buttonText': 'Register',
      'link': 'https://forms.example.com/camp', 'theme': 'orange', 'imageVersion': 2,
      'startsOn': '2026-12-01T00:00:00', 'endsOn': null, 'isActive': true, 'status': 'Scheduled',
    });
    expect(b.external, isTrue);
    expect(b.startsOn, '2026-12-01');
    expect(b.imageVersion, 2);
    expect(bannerColors.keys, containsAll(bannerThemes), reason: 'every theme has colours');

    expect(bannerRoute('fees'), Routes.parentFees);
    expect(bannerRoute('account'), Routes.parentAccount);
    expect(bannerRoute(null), isNull);
    expect(bannerPages.keys, containsAll(['fees', 'messages', 'new-message', 'announcements', 'account']),
        reason: 'same page keys as the API (SchoolBanner.Pages)');
  });

  test('editing keeps the banner and switching off flips only isActive', () {
    final b = SchoolBanner(id: 1, title: 'Photo day', theme: 'pink', link: 'messages', buttonText: 'Ask us', classId: 3);
    final s = BannerSave.of(b)..isActive = false;
    expect([s.title, s.theme, s.link, s.buttonText, s.classId, s.isActive], ['Photo day', 'pink', 'messages', 'Ask us', 3, false]);
  });
}
