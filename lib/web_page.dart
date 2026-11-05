import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'theme.dart';

/// Öppnar en sida inne i appen. På webben (förhandsvisning) öppnas en ny flik.
Future<void> openInApp(BuildContext context, String url, String title) async {
  if (kIsWeb) {
    await launchUrl(Uri.parse(url));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebPage(url: url, title: title)));
}

class WebPage extends StatefulWidget {
  final String url;
  final String title;
  const WebPage({super.key, required this.url, required this.title});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _c;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _c.canGoBack()) {
          await _c.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          actions: [
            IconButton(onPressed: () => _c.reload(), icon: const Icon(Icons.refresh_rounded)),
            IconButton(
              tooltip: 'Öppna i webbläsaren',
              onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_browser_rounded),
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, color: AppColors.accent, minHeight: 2),
                )
              : null,
        ),
        body: WebViewWidget(controller: _c),
      ),
    );
  }
}
