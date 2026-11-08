import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/user_store.dart';
import 'subscription_editor.dart';

const privacyUrl = 'https://park-do-hwi.github.io/housing-alert/privacy.html';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Subscription? edited;
  bool busy = false;
  int editorKey = 0; // 파일에서 가져오면 편집 폼을 새로 그리기 위한 값

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final s = edited;
    if (s == null) return;
    setState(() => busy = true);
    try {
      await ref.read(userDataProvider.notifier).saveSubscription(s);
      if (mounted) setState(() => edited = null);
      _toast('저장했어요');
    } catch (e) {
      _toast('저장 실패: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => busy = true);
    try {
      final bytes = Uint8List.fromList(
        ref.read(userDataProvider.notifier).exportBytes(),
      );
      final ok = await ref.read(fileIoProvider).save(UserStore.fileName, bytes);
      _toast(ok ? '파일로 저장했어요' : '취소했어요');
    } catch (e) {
      _toast('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => busy = true);
    try {
      final bytes = await ref.read(fileIoProvider).pick();
      if (bytes == null) return;
      final UserData data;
      try {
        data = UserStore.decodeBytes(bytes);
      } on UserFileException catch (e) {
        _toast(e.message);
        return;
      }
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('파일에서 가져올까요?'),
          content: Text(
            '지금 설정과 저장한 공고 ${ref.read(favoritesProvider).length}개가 '
            '파일 내용(저장한 공고 ${data.favorites.length}개)으로 바뀌어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      await ref
          .read(userDataProvider.notifier)
          .replaceAll(data.copyWith(onboarded: true));
      if (mounted) {
        setState(() {
          edited = null;
          editorKey++;
        });
      }
      _toast('가져왔어요');
    } catch (e) {
      _toast('가져오기 실패: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(subscriptionProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 설정'),
        actions: [
          if (edited != null)
            TextButton(onPressed: busy ? null : _save, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('화면 테마', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('화이트'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('블랙'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.phone_android),
                label: Text('기기 설정'),
              ),
            ],
            selected: {ref.watch(themeModeProvider)},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('관심 조건', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            '정하지 않으면 모든 공고가 보여요. 고르면 목록과 알림이 그 조건에 맞춰져요.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          SubscriptionEditor(
            key: ValueKey(editorKey),
            initial: s,
            onChanged: (n) => setState(() => edited = n),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 8),
          Text('내 정보 파일', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            '관심 조건과 저장한 공고는 서버로 보내지 않고 이 기기의 파일(${UserStore.fileName}) 하나에만 저장돼요. '
            '폰을 바꾸거나 앱을 다시 설치하기 전에 파일로 내보내 두면 그대로 옮길 수 있어요.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _export,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('파일로 내보내기'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _import,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('파일에서 가져오기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            '청약레이더는 LH·SH·GH·한국부동산원(청약홈) 등 공공기관이 공개한 정보를 모아 보여 주는 민간 정보 서비스이며, '
            '해당 기관이 운영하거나 보증하는 공식 앱이 아니에요. '
            '공고 일정·분양가·공급 조건은 변경되거나 수집 시점에 따라 다를 수 있으니, 청약 신청과 계약 전에 반드시 각 기관의 원문 공고를 확인하세요. '
            '주변 실거래가는 국토교통부 공개 자료를 참고용으로 보여 주는 것이며 분양가를 보장하지 않아요. '
            '지도는 카카오맵을 사용해요.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/web', extra: privacyUrl),
            child: const Text('개인정보처리방침'),
          ),
        ],
      ),
    );
  }
}
