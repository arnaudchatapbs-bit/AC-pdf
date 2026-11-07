import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Dépôt GitHub dont les Releases publient l'APK.
const String kUpdateRepo = 'arnaudchatapbs-bit/AC-pdf';

class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.apkUrl,
    required this.apkName,
    required this.size,
    required this.notes,
  });

  final String version;
  final String currentVersion;
  final String apkUrl;
  final String apkName;
  final int size;
  final String notes;
}

/// Vérification et installation des mises à jour publiées sur GitHub.
/// Seule fonction de l'app qui utilise Internet ; en l'absence de réseau,
/// elle échoue silencieusement.
class UpdateService {
  UpdateService._();

  static bool get supported => Platform.isAndroid;

  /// Compare deux versions « 1.2.3 ». Renvoie > 0 si [a] est plus récente.
  static int compareVersions(String a, String b) {
    List<int> parse(String v) => v
        .replaceFirst(RegExp(r'^v'), '')
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0)
        .toList();
    final pa = parse(a), pb = parse(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  /// Renvoie la mise à jour disponible, ou null (à jour, hors ligne, erreur).
  /// Avec [throwOnError], les erreurs réseau sont propagées (vérification manuelle).
  static Future<UpdateInfo?> check({bool throwOnError = false}) async {
    if (!supported) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final req = await client
          .getUrl(Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'))
          .timeout(const Duration(seconds: 10));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'ACpdf-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw HttpException('GitHub a répondu ${res.statusCode}');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      if (compareVersions(tag, current) <= 0) return null;
      final assets = (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      final apk = assets.where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk')).firstOrNull;
      if (apk == null) return null;
      return UpdateInfo(
        version: tag.replaceFirst(RegExp(r'^v'), ''),
        currentVersion: current,
        apkUrl: apk['browser_download_url'] as String,
        apkName: apk['name'] as String,
        size: (apk['size'] as num?)?.toInt() ?? 0,
        notes: (json['body'] as String?) ?? '',
      );
    } catch (e) {
      if (throwOnError) rethrow;
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Télécharge l'APK dans le cache privé de l'app. [onProgress] reçoit 0..1.
  static Future<File> download(UpdateInfo info, void Function(double) onProgress) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/${info.apkName}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(info.apkUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'ACpdf-app');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Téléchargement impossible (${res.statusCode})');
      final total = res.contentLength > 0 ? res.contentLength : info.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      if (total > 0 && received < total) throw const HttpException('Téléchargement incomplet');
      return file;
    } finally {
      client.close(force: true);
    }
  }

  /// Ouvre l'installeur Android (l'utilisateur confirme l'installation).
  static Future<String?> install(File apk) async {
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    return r.type == ResultType.done ? null : r.message;
  }
}
