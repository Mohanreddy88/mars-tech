import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import 'audit_models.dart';

/// GET /api/audit (Admin only), newest first.
class AuditRepository {
  AuditRepository(this._dio);

  final Dio _dio;

  static const pageSize = 30;

  Future<AuditPage> page(AuditFilter filter, int page) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('audit', queryParameters: filter.query(page, pageSize));
      return AuditPage.fromJson(r.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final auditRepositoryProvider = Provider<AuditRepository>((ref) => AuditRepository(ref.watch(dioProvider)));
