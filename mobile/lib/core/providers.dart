import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'file_io.dart';
import 'models.dart';
import 'repository.dart';
import 'user_store.dart';

/// 공고 목록 캐시용. main()에서 override 한다.
final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

/// 내 정보 파일. main()에서 override 한다.
final userStoreProvider = Provider<UserStore>((_) => throw UnimplementedError());

final fileIoProvider = Provider<FileIo>((_) => PickerFileIo());

final repositoryProvider = Provider<NoticeRepository>(
    (ref) => NoticeRepository(AppConfig.dataBase, ref.read(prefsProvider)));

/// 공고 전체. 새로고침은 `ref.refresh(noticeDataProvider.future)`.
final noticeDataProvider =
    FutureProvider<NoticeData>((ref) => ref.read(repositoryProvider).load());

// ---- 내 정보: 파일 한 개 (user_store.dart) ----
class UserDataNotifier extends Notifier<UserData> {
  @override
  UserData build() => ref.read(userStoreProvider).data;

  /// 화면 상태를 먼저 바꾸고 파일에 쓴다. 쓰기에 실패하면 예외를 던져 화면이 알리게 한다.
  Future<void> _set(UserData next) async {
    state = next;
    await ref.read(userStoreProvider).save(next);
  }

  Future<void> saveSubscription(Subscription s) => _set(state.copyWith(subscription: s));

  Future<void> setOnboarded(bool v) => _set(state.copyWith(onboarded: v));

  Future<void> saveProfile(Map<String, dynamic> p) => _set(state.copyWith(profile: p));

  Future<void> toggleFavorite(String id) {
    final f = state.favorites;
    return _set(state.copyWith(favorites: f.contains(id) ? f.where((e) => e != id).toList() : [...f, id]));
  }

  /// 파일에서 가져온 내용으로 전부 바꾼다.
  Future<void> replaceAll(UserData d) => _set(d);

  /// 파일 내용으로 내보내기용 바이트.
  List<int> exportBytes() => ref.read(userStoreProvider).exportBytes();
}

final userDataProvider = NotifierProvider<UserDataNotifier, UserData>(UserDataNotifier.new);

final subscriptionProvider =
    Provider<Subscription>((ref) => ref.watch(userDataProvider).subscription);

final favoritesProvider = Provider<List<String>>((ref) => ref.watch(userDataProvider).favorites);

// ---- 목록 필터 ----
class FilterNotifier extends Notifier<NoticeFilter> {
  @override
  NoticeFilter build() => const NoticeFilter();
  void set(NoticeFilter f) => state = f;
}

final filterProvider = NotifierProvider<FilterNotifier, NoticeFilter>(FilterNotifier.new);

/// 필터를 적용한 목록. 데이터가 로딩/오류 중이면 그 상태를 그대로 전달한다.
final noticesProvider = Provider.autoDispose<AsyncValue<List<Notice>>>((ref) {
  final f = ref.watch(filterProvider);
  final mine = ref.watch(subscriptionProvider);
  return ref.watch(noticeDataProvider).whenData((d) => f.apply(d.items, mine));
});

/// 저장한 공고 본문. 접수 마감이 가까운 순, 마감일 없는 것은 뒤.
/// 목록에서 빠진 옛 공고는 건너뛴다.
final favoriteNoticesProvider = Provider.autoDispose<AsyncValue<List<Notice>>>((ref) {
  final ids = ref.watch(favoritesProvider).toSet();
  return ref.watch(noticeDataProvider).whenData((d) {
    final list = d.items.where((n) => ids.contains(n.id)).toList();
    list.sort((a, b) {
      if (a.applyEnd == null && b.applyEnd == null) return 0;
      if (a.applyEnd == null) return 1;
      if (b.applyEnd == null) return -1;
      return a.applyEnd!.compareTo(b.applyEnd!);
    });
    return list;
  });
});

// ---- 캘린더: 월별 접수 마감 ----
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final calendarProvider =
    Provider.autoDispose.family<AsyncValue<Map<String, List<Notice>>>, String>((ref, month) {
  return ref.watch(noticeDataProvider).whenData((d) {
    final out = <String, List<Notice>>{};
    for (final n in d.items) {
      final e = n.applyEnd;
      if (e == null || n.isResult) continue;
      if (dayKey(e).startsWith(month)) out.putIfAbsent(dayKey(e), () => []).add(n);
    }
    return out;
  });
});

// ---- 비교: 담은 공고(최대 3개) ----
class CompareSelection extends Notifier<List<Notice>> {
  static const max = 3;
  @override
  List<Notice> build() => const [];

  bool has(String id) => state.any((n) => n.id == id);

  /// 담기/빼기. 가득 찼으면 false 를 돌려주고 변경하지 않는다.
  bool toggle(Notice n) {
    if (has(n.id)) {
      state = state.where((e) => e.id != n.id).toList();
      return true;
    }
    if (state.length >= max) return false;
    state = [...state, n];
    return true;
  }

  void clear() => state = const [];
}

final compareSelectionProvider =
    NotifierProvider<CompareSelection, List<Notice>>(CompareSelection.new);
