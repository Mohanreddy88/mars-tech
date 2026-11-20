import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saving downloaded documents (payslip / attendance PDFs, leave documents)
/// and handing them to the phone's viewer or share sheet.
class FileOpener {
  FileOpener._();

  /// Writes [bytes] to the app's temporary folder.
  static Future<File> save(List<int> bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Opens the file in a viewer app; if none is installed, opens the share
  /// sheet instead (Drive, Files, email, ...).
  static Future<void> open(File file, {required String mimeType, String? subject}) async {
    final result = await OpenFilex.open(file.path, type: mimeType);
    if (result.type != ResultType.done) {
      await share(file, mimeType: mimeType, subject: subject);
    }
  }

  static Future<void> share(File file, {required String mimeType, String? subject}) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          subject: subject,
        ),
      );

  /// Content type from a file name's extension.
  static String mimeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }
}
