import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/school/data/price_lists.dart';

void main() {
  test('a price list reads and writes back the same (Golden Montessori 2024)', () {
    final p = PriceListRec.fromJson({
      'id': 1, 'name': '2024', 'effectiveFrom': '2024-11-01', 'twiceAYearMonths': '1,7', 'terms': 'Collected monthly.', 'current': true,
      'sessions': [
        {'sessionType': 'Half day', 'offered': true, 'start': '08:00', 'end': '12:00', 'mealsIncluded': 'breakfast', 'monthlyFee': 930, 'uponRegistration': 1960, 'secondMonth': 1930},
        {'sessionType': 'Full day', 'offered': true, 'start': '07:30', 'end': '18:30', 'monthlyFee': 1450, 'uponRegistration': 2690, 'secondMonth': 2450},
        {'sessionType': 'Daycare', 'offered': false, 'start': '07:30', 'end': '18:30', 'monthlyFee': 0},
      ],
      'charges': [
        {'name': 'Registration', 'kind': 'OneTime', 'amount': 300, 'sessionType': null},
        {'name': 'Bedding', 'kind': 'OneTime', 'amount': 210, 'sessionType': 'Full day'},
        {'name': 'Deposit', 'kind': 'Deposit', 'amount': 1000, 'sessionType': null},
      ],
    });
    expect(p.offered.map((s) => s.sessionType), ['Half day', 'Full day']);
    expect(p.sessions.first.uponRegistration, 1960);
    expect(p.charges[1].sessionType, 'Full day');
    final back = p.toJson();
    expect((back['sessions'] as List).length, 3);
    expect((back['charges'] as List)[2], {'name': 'Deposit', 'kind': 'Deposit', 'amount': 1000.0, 'sessionType': null});
  });

  test('a held deposit lists the child\'s unpaid invoices', () {
    final d = DepositRec.fromJson({
      'id': 3, 'childName': 'Ali', 'description': 'Deposit', 'amount': 1000, 'status': 'Held',
      'openInvoices': [{'id': 9, 'invoiceNo': 'INV-202501-0001', 'year': 2025, 'month': 1, 'balance': 930}],
    });
    expect(d.held, isTrue);
    expect(d.openInvoices.single.invoiceNo, 'INV-202501-0001');
  });
}
