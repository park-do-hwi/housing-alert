import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 서버가 만든 notices.json 한 번 읽은 결과.
class NoticeData {
  const NoticeData({required this.items, this.generatedAt, this.stale = false});
  final List<Notice> items;
  final DateTime? generatedAt;

  /// true 면 네트워크에 실패해 기기에 저장해 둔 이전 데이터를 보여주는 중.
  final bool stale;
}

class NoticeLoadException implements Exception {
  NoticeLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 정적 JSON(`<baseUrl>/notices.json`)을 받아 오고, 성공하면 기기에 저장한다.
/// 받기에 실패하면 마지막으로 저장한 데이터를 돌려준다(오프라인 대응).
class NoticeRepository {
  NoticeRepository(this.baseUrl, this.prefs, [http.Client? client])
      : _c = client ?? http.Client();

  final String baseUrl;
  final SharedPreferences prefs;
  final http.Client _c;

  static const cacheKey = 'notices_cache_v1';

  Future<NoticeData> load() async {
    try {
      final r = await _c
          .get(Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/notices.json'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw NoticeLoadException('데이터 서버 오류 (${r.statusCode})');
      final body = utf8.decode(r.bodyBytes);
      final data = parse(body); // 파싱이 되는 것만 저장한다
      await prefs.setString(cacheKey, body);
      return data;
    } catch (e) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        try {
          final d = parse(cached);
          return NoticeData(items: d.items, generatedAt: d.generatedAt, stale: true);
        } catch (_) {/* 저장본이 깨졌으면 원래 오류를 던진다 */}
      }
      if (e is NoticeLoadException) rethrow;
      throw NoticeLoadException('공고 데이터를 불러오지 못했어요');
    }
  }

  static NoticeData parse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final items = (j['items'] as List)
        .map((e) => Notice.fromJson(e as Map<String, dynamic>))
        .toList();
    return NoticeData(items: items, generatedAt: DateTime.tryParse('${j['generated_at']}'));
  }
}
