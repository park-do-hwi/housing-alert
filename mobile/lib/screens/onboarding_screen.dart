import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import 'subscription_editor.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  Subscription sub = const Subscription();
  bool saving = false;
  String? error;

  Future<void> _start() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final user = ref.read(userDataProvider.notifier);
      await user.saveSubscription(sub);
      await user.setOnboarded(true);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => error = '저장하지 못했어요. 다시 시도해 주세요.\n$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('어떤 공고를 받아볼까요?')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SubscriptionEditor(initial: sub, onChanged: (s) => sub = s),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : _start,
                child: saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('시작하기'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
