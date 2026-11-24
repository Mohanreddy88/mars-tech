import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

// School → Fees → Price lists (one per academic year) and Deposits — same as the website.

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;

const chargeKinds = {
  'OneTime': 'One-time (at registration)',
  'TwiceAYear': 'Twice a year',
  'Deposit': 'Refundable deposit (2nd month)',
};

class PriceSession {
  PriceSession({required this.sessionType, required this.offered, required this.start, required this.end,
      this.mealsIncluded, required this.monthlyFee, this.uponRegistration = 0, this.secondMonth = 0});
  final String sessionType;
  bool offered;
  String start;
  String end;
  String? mealsIncluded;
  double monthlyFee;
  final double uponRegistration;
  final double secondMonth;

  factory PriceSession.fromJson(Map<String, dynamic> j) => PriceSession(
        sessionType: j['sessionType'] as String? ?? '',
        offered: j['offered'] as bool? ?? true,
        start: j['start'] as String? ?? '08:00',
        end: j['end'] as String? ?? '16:30',
        mealsIncluded: _s(j['mealsIncluded']),
        monthlyFee: _d(j['monthlyFee']),
        uponRegistration: _d(j['uponRegistration']),
        secondMonth: _d(j['secondMonth']),
      );

  Map<String, dynamic> toJson() => {
        'sessionType': sessionType, 'offered': offered, 'start': start, 'end': end,
        'mealsIncluded': mealsIncluded, 'monthlyFee': monthlyFee,
      };
}

class PriceCharge {
  PriceCharge({required this.name, required this.kind, required this.amount, this.sessionType});
  String name;
  /// OneTime, TwiceAYear or Deposit.
  String kind;
  double amount;
  /// Only for this session; null = every child.
  String? sessionType;

  factory PriceCharge.fromJson(Map<String, dynamic> j) => PriceCharge(
        name: j['name'] as String? ?? '',
        kind: j['kind'] as String? ?? 'OneTime',
        amount: _d(j['amount']),
        sessionType: _s(j['sessionType']),
      );

  Map<String, dynamic> toJson() => {'name': name, 'kind': kind, 'amount': amount, 'sessionType': sessionType};
}

class PriceListRec {
  PriceListRec({required this.id, required this.name, required this.effectiveFrom, required this.twiceAYearMonths,
      this.terms, required this.current, required this.sessions, required this.charges});
  final int id;
  String name;
  /// yyyy-MM-dd
  String effectiveFrom;
  /// "1,7"
  String twiceAYearMonths;
  String? terms;
  final bool current;
  final List<PriceSession> sessions;
  final List<PriceCharge> charges;

  List<PriceSession> get offered => sessions.where((s) => s.offered).toList();

  factory PriceListRec.fromJson(Map<String, dynamic> j) => PriceListRec(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        effectiveFrom: (j['effectiveFrom'] as String? ?? '').substring(0, 10),
        twiceAYearMonths: j['twiceAYearMonths'] as String? ?? '',
        terms: _s(j['terms']),
        current: j['current'] == true,
        sessions: [for (final s in (j['sessions'] as List<dynamic>? ?? const [])) PriceSession.fromJson(s as Map<String, dynamic>)],
        charges: [for (final c in (j['charges'] as List<dynamic>? ?? const [])) PriceCharge.fromJson(c as Map<String, dynamic>)],
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'effectiveFrom': effectiveFrom, 'twiceAYearMonths': twiceAYearMonths, 'terms': terms,
        'sessions': [for (final s in sessions) s.toJson()],
        'charges': [for (final c in charges) c.toJson()],
      };
}

class DepositRec {
  const DepositRec({required this.id, required this.childName, this.className, required this.description,
      required this.amount, required this.status, this.note, this.invoiceNo, this.settledByName, required this.openInvoices});
  final int id;
  final String childName;
  final String? className;
  final String description;
  final double amount;
  /// Held, Refunded or Deducted.
  final String status;
  final String? note;
  final String? invoiceNo;
  final String? settledByName;
  final List<({int id, String invoiceNo, int year, int month, double balance})> openInvoices;

  bool get held => status == 'Held';

  factory DepositRec.fromJson(Map<String, dynamic> j) => DepositRec(
        id: (j['id'] as num).toInt(),
        childName: j['childName'] as String? ?? '',
        className: _s(j['className']),
        description: j['description'] as String? ?? 'Deposit',
        amount: _d(j['amount']),
        status: j['status'] as String? ?? 'Held',
        note: _s(j['note']),
        invoiceNo: _s(j['invoiceNo']),
        settledByName: _s(j['settledByName']),
        openInvoices: [
          for (final i in (j['openInvoices'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            (
              id: (i['id'] as num).toInt(),
              invoiceNo: i['invoiceNo'] as String? ?? '',
              year: (i['year'] as num?)?.toInt() ?? 0,
              month: (i['month'] as num?)?.toInt() ?? 0,
              balance: _d(i['balance'])
            ),
        ],
      );
}

class PriceListsRepository {
  PriceListsRepository(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<PriceListRec>> lists() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/fees/price-lists');
        return (r.data ?? const []).map((e) => PriceListRec.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<PriceListRec?> current() => _call(() async {
        final r = await _dio.get<dynamic>('school/fees/price-lists/current');
        return r.data is Map<String, dynamic> ? PriceListRec.fromJson(r.data as Map<String, dynamic>) : null;
      });

  Future<PriceListRec> create(String name, String effectiveFrom, int? copyFromId) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/fees/price-lists',
            data: {'name': name, 'effectiveFrom': effectiveFrom, 'copyFromId': copyFromId});
        return PriceListRec.fromJson(r.data!);
      });

  Future<PriceListRec> save(PriceListRec p) => _call(() async {
        final r = await _dio.put<Map<String, dynamic>>('school/fees/price-lists/${p.id}', data: p.toJson());
        return PriceListRec.fromJson(r.data!);
      });

  Future<void> delete(int id) => _call(() => _dio.delete<void>('school/fees/price-lists/$id'));

  Future<List<DepositRec>> deposits({bool all = false}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/fees/deposits', queryParameters: {if (all) 'status': 'all'});
        return (r.data ?? const []).map((e) => DepositRec.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// [how]: 'refund' or 'deduct' (from [invoiceId]).
  Future<void> settle(int id, String how, {int? invoiceId, String? note}) => _call(() =>
      _dio.post<void>('school/fees/deposits/$id/settle', data: {'how': how, 'invoiceId': invoiceId, 'note': note}));
}

final priceListsRepositoryProvider = Provider<PriceListsRepository>((ref) => PriceListsRepository(ref.watch(dioProvider)));
final priceListsProvider = FutureProvider.autoDispose<List<PriceListRec>>((ref) => ref.watch(priceListsRepositoryProvider).lists());
final currentPriceListProvider = FutureProvider.autoDispose<PriceListRec?>((ref) => ref.watch(priceListsRepositoryProvider).current());
