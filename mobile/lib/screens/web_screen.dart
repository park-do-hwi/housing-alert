import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 앱 안에서 기사·영상 페이지를 연다. 뒤로 가면 목록으로 돌아온다.
class WebScreen extends StatefulWidget {
  const WebScreen({super.key, required this.url, required this.title});
  final String url;
  final String title;
  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController c;
  int progress = 0;

  @override
  void initState() {
    super.initState();
    c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onProgress: (p) => setState(() => progress = p)))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: '공유',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(ShareParams(text: '${widget.title}\n${widget.url}\n- 청약레이더')),
          ),
        ],
        bottom: progress < 100
            ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: progress / 100))
            : null,
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await c.canGoBack()) {
            c.goBack();
          } else if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: WebViewWidget(controller: c),
      ),
    );
  }
}
