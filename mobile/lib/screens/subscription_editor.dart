import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/models.dart';

/// 관심 지역·유형·키워드 편집 폼. 온보딩과 설정 화면에서 공용으로 쓴다.
class SubscriptionEditor extends StatefulWidget {
  const SubscriptionEditor({super.key, required this.initial, required this.onChanged});
  final Subscription initial;
  final ValueChanged<Subscription> onChanged;

  @override
  State<SubscriptionEditor> createState() => _SubscriptionEditorState();
}

class _SubscriptionEditorState extends State<SubscriptionEditor> {
  late Subscription s = widget.initial;
  late final kw = TextEditingController(text: s.keywords.join(', '));
  late final ex = TextEditingController(text: s.excludeKeywords.join(', '));

  void _emit(Subscription n) {
    setState(() => s = n);
    widget.onChanged(n);
  }

  static List<String> _split(String v) =>
      v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  @override
  void dispose() {
    kw.dispose();
    ex.dispose();
    super.dispose();
  }

  Widget _chips(List<String> all, List<String> sel, ValueChanged<List<String>> on) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in all)
            FilterChip(
              label: Text(v),
              selected: sel.contains(v),
              onSelected: (on_) => on(on_ ? [...sel, v] : sel.where((e) => e != v).toList()),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final h = Theme.of(context).textTheme.titleMedium;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('관심 지역', style: h),
      const Text('선택하지 않으면 전국 공고를 받아요', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      _chips(sidoList, s.sido, (v) => _emit(s.copyWith(sido: v))),
      const SizedBox(height: 20),
      Text('공고 유형', style: h),
      const Text('선택하지 않으면 모든 유형을 받아요', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      _chips(categoryList, s.categories, (v) => _emit(s.copyWith(categories: v))),
      const SizedBox(height: 20),
      Text('포함할 키워드', style: h),
      const SizedBox(height: 8),
      TextField(
        controller: kw,
        decoration: const InputDecoration(hintText: '예: 신혼, 84㎡ (쉼표로 구분)', border: OutlineInputBorder()),
        onChanged: (v) => _emit(s.copyWith(keywords: _split(v))),
      ),
      const SizedBox(height: 16),
      Text('제외할 키워드', style: h),
      const SizedBox(height: 8),
      TextField(
        controller: ex,
        decoration: const InputDecoration(hintText: '예: 오피스텔', border: OutlineInputBorder()),
        onChanged: (v) => _emit(s.copyWith(excludeKeywords: _split(v))),
      ),
      const SizedBox(height: 20),
      Text('마감 임박 알림', style: h),
      const SizedBox(height: 8),
      _chips(const ['3', '2', '1', '0'], s.remindDays.map((e) => '$e').toList(), (v) {
        _emit(s.copyWith(remindDays: v.map(int.parse).toList()..sort((a, b) => b.compareTo(a))));
      }),
      const Text('접수 마감 N일 전 (0 = 마감 당일)', style: TextStyle(fontSize: 12)),
    ]);
  }
}
