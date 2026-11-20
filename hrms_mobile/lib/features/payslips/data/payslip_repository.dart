import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'payslip_models.dart';

class PayslipRepository {
  PayslipRepository(this._dio);

  final Dio _dio;

  /// GET /api/selfservice/my-payslips (newest first)
  Future<List<Payslip>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('selfservice/my-payslips');
      return (res.data ?? const [])
          .map((e) => Payslip.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/selfservice/my-payslips/{id}
  Future<PayslipDetail> detail(int id) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('selfservice/my-payslips/$id');
      return PayslipDetail.fromJson(res.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/selfservice/my-payslips/{id}/download
  Future<PayslipPdf> downloadPdf(int id, {required String fallbackName}) async {
    try {
      final res = await _dio.get<List<int>>(
        'selfservice/my-payslips/$id/download',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final name = _fileNameFrom(res.headers.value('content-disposition'));
      return PayslipPdf(bytes: res.data ?? const [], fileName: name ?? fallbackName);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/selfservice/my-payslips/{id}/email. Returns the server's message.
  Future<String> emailPdf(int id) async {
    try {
      final res = await _dio
          .post<Map<String, dynamic>>('selfservice/my-payslips/$id/email');
      return res.data?['message'] as String? ??
          'The payslip has been sent to your email.';
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Reads `filename=` from a Content-Disposition header.
  static String? _fileNameFrom(String? header) {
    if (header == null) return null;
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(header);
    return match?.group(1);
  }
}

final payslipRepositoryProvider = Provider<PayslipRepository>(
    (ref) => PayslipRepository(ref.watch(dioProvider)));

final payslipsProvider = FutureProvider.autoDispose<List<Payslip>>(
    (ref) => ref.watch(payslipRepositoryProvider).list());

final payslipDetailProvider = FutureProvider.autoDispose
    .family<PayslipDetail, int>(
        (ref, id) => ref.watch(payslipRepositoryProvider).detail(id));
