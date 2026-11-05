import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 사용자가 입력·저장한 모든 정보. 이 앱은 서버에 개인정보를 보내지 않고,
/// 아래 내용을 기기 안의 JSON 파일 한 개에만 저장한다.
class UserData {
  const UserData({
    this.subscription = const Subscription(),
    this.favorites = const [],
    this.onboarded = false,
    this.profile = const {},
  });

  final Subscription subscription; // 관심 지역·유형·키워드·마감 알림
  final List<String> favorites; // 저장한 공고 id
  final bool onboarded;

  /// 청약 자격·가점 계산에 쓸 내 정보 (무주택 기간, 부양가족 등). 해당 기능에서 채운다.
  final Map<String, dynamic> profile;

  UserData copyWith({
    Subscription? subscription,
    List<String>? favorites,
    bool? onboarded,
    Map<String, dynamic>? profile,
  }) =>
      UserData(
        subscription: subscription ?? this.subscription,
        favorites: favorites ?? this.favorites,
        onboarded: onboarded ?? this.onboarded,
        profile: profile ?? this.profile,
      );

  Map<String, dynamic> toJson() => {
        'subscription': subscription.toJson(),
        'favorites': favorites,
        'onboarded': onboarded,
        'profile': profile,
      };

  factory UserData.fromJson(Map<String, dynamic> j) => UserData(
        subscription: j['subscription'] is Map
            ? Subscription.fromJson((j['subscription'] as Map).cast<String, dynamic>())
            : const Subscription(),
        favorites: (j['favorites'] as List? ?? const []).map((e) => '$e').toList(),
        onboarded: j['onboarded'] == true,
        profile: (j['profile'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// 파일 형식이 맞지 않을 때. [message] 는 사용자에게 그대로 보여줘도 된다.
class UserFileException implements Exception {
  UserFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `housing_alert_user.json` 읽기/쓰기. 쓸 때는 임시 파일에 쓴 뒤 교체해서
/// 도중에 앱이 꺼져도 파일이 반쪽이 되지 않게 한다.
class UserStore {
  UserStore._(this.file, this.data);

  /// 파일 없이 메모리에만 두는 저장소. 화면 테스트용.
  UserStore.inMemory([this.data = const UserData()]) : file = null;

  static const fileName = 'housing_alert_user.json';
  static const appId = 'housing_alert';
  static const formatVersion = 1;

  final File? file;
  UserData data;

  static Future<UserStore> open({Directory? dir}) async {
    final d = dir ?? await getApplicationDocumentsDirectory();
    final f = File('${d.path}${Platform.pathSeparator}$fileName');
    var data = const UserData();
    if (await f.exists()) {
      try {
        data = decode(await f.readAsString());
      } catch (_) {
        // 깨진 파일은 지우지 않고 옆에 보관한 뒤 빈 상태로 시작한다.
        try {
          await f.rename('${f.path}.broken');
        } catch (_) {}
      }
    }
    return UserStore._(f, data);
  }

  Future<void> save(UserData next) async {
    data = next;
    final f = file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(encode(next), flush: true);
    await tmp.rename(f.path);
  }

  static String encode(UserData d) => const JsonEncoder.withIndent('  ').convert({
        'app': appId,
        'version': formatVersion,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        ...d.toJson(),
      });

  /// 파일에서 읽은 바이트를 [decode]로 넘긴다. UTF-8이 아니면 [UserFileException].
  static UserData decodeBytes(List<int> bytes) {
    try {
      return decode(utf8.decode(bytes));
    } on FormatException {
      throw UserFileException('올바른 JSON 파일이 아니에요');
    }
  }

  /// 파일 내용을 검사해서 [UserData]로 바꾼다. 이 앱의 파일이 아니면 [UserFileException].
  static UserData decode(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw UserFileException('올바른 JSON 파일이 아니에요');
    }
    if (j is! Map<String, dynamic> || j['app'] != appId) {
      throw UserFileException('이 앱에서 내보낸 파일이 아니에요');
    }
    final v = j['version'];
    if (v is! int || v > formatVersion) {
      throw UserFileException('더 새로운 버전의 앱에서 만든 파일이에요. 앱을 업데이트해 주세요');
    }
    return UserData.fromJson(j);
  }

  Uint8List exportBytes() => Uint8List.fromList(utf8.encode(encode(data)));
}
