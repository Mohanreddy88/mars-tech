import 'dart:convert';

import 'package:dio/dio.dart';

/// A user-presentable error from the HRMS API.
///
/// HrmsApi returns errors in two shapes:
///   * ExceptionMiddleware -> problem+json `{ title, status, detail }`
///   * Controllers         -> `{ message }`
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) return _fromDio(error);
    return ApiException('Something went wrong. Please try again.');
  }

  static ApiException _fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
            'The server took too long to respond. Please try again.');
      case DioExceptionType.connectionError:
        return ApiException(
            'Cannot reach the server. Check your internet connection.');
      default:
        break;
    }

    final status = error.response?.statusCode;
    final message = _extractMessage(error.response?.data);
    return ApiException(message ?? _fallbackFor(status), statusCode: status);
  }

  static String? _extractMessage(Object? data) {
    Object? body = data;
    if (body is String && body.isNotEmpty) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        return null;
      }
    }
    if (body is Map) {
      final value = body['detail'] ?? body['message'] ?? body['title'];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static String _fallbackFor(int? status) {
    switch (status) {
      case 400:
        return 'The request was invalid.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do this.';
      case 404:
        return 'The requested item was not found.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => message;
}
