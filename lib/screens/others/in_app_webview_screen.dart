import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:provider/provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../widgets/connection_status_widget.dart';

class InAppWebViewScreen extends StatefulWidget {
  const InAppWebViewScreen({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<InAppWebViewScreen> createState() => _InAppWebViewScreenState();
}

class _InAppWebViewScreenState extends State<InAppWebViewScreen> {
  InAppWebViewController? _controller;
  int _progress = 0;
  String? _errorMessage;
  bool _forceDarkWebContent = false;
  bool _webViewReady = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connectivity = ConnectivityService.instance;
      if (!connectivity.isInitialized) {
        connectivity.initialize();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_forceDarkWebContent != isDark) {
      setState(() {
        _forceDarkWebContent = isDark;
      });
      if (_webViewReady) {
        _applyDarkModeIfNeeded();
      }
    }
  }

  void _reload() {
    setState(() {
      _errorMessage = null;
      _progress = 0;
    });
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.grey[900] : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          widget.title ?? 'Web Page',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),

        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        foregroundColor: isDark ? Colors.white : Theme.of(context).primaryColor,
      ),
      body: Consumer2<ConnectivityService, SessionService>(
        builder: (context, connectivityService, sessionService, child) {
          if (!connectivityService.isConnected ||
              !sessionService.hasValidSession) {
            return ConnectionStatusWidget(
              onRetry: () async {
                final ok = await connectivityService.checkConnectivityOnce();
                if (ok) {
                  _reload();
                }
              },
            );
          }

          return Column(
            children: [
              if (_errorMessage == null && _progress < 100)
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100.0,
                  minHeight: 3,
                ),
              Expanded(
                child: _errorMessage != null
                    ? _buildErrorState(context)
                    : InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          useHybridComposition: true,
                          allowsBackForwardNavigationGestures: true,
                        ),
                        onWebViewCreated: (controller) {
                          _controller = controller;
                          _webViewReady = true;
                        },
                        onProgressChanged: (controller, progress) {
                          setState(() => _progress = progress);
                        },
                        onLoadStart: (controller, url) {
                          setState(() {
                            _progress = 10;
                            _errorMessage = null;
                          });
                        },
                        onLoadStop: (controller, url) {
                          setState(() => _progress = 100);
                          _applyDarkModeIfNeeded();
                        },
                        onReceivedError: (controller, request, error) {
                          if (error.type == WebResourceErrorType.CANCELLED) {
                            return;
                          }
                          setState(() {
                            _errorMessage = error.description;
                          });
                        },
                        onReceivedHttpError: (controller, request, response) {
                          if ((response.statusCode ?? 0) >= 400) {
                            setState(() {
                              _errorMessage =
                                  'HTTP Error: ${response.statusCode} - ${response.reasonPhrase}';
                            });
                          }
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off,
              size: 56,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load the page',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: _reload, child: const Text('Retry')),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(widget.url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in browser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyDarkModeIfNeeded() async {
    if (_controller == null) return;

    if (!_forceDarkWebContent) {
      const remove = """
        (function(){
          try {
            var hint = document.getElementById('prefer-scheme-style');
            if (hint) { hint.remove(); }
            var metas = document.getElementsByTagName('meta');
            for (var i=0;i<metas.length;i++){
              var m = metas[i];
              if ((m.getAttribute('name')||'').toLowerCase()==='color-scheme'){
                
              }
            }
          } catch(e) {}
        })();
      """;
      try {
        await _controller!.evaluateJavascript(source: remove);
      } catch (_) {}
      return;
    }

    const js = """
      (function(){
        try {
          
          var style = document.getElementById('prefer-scheme-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'prefer-scheme-style';
            style.appendChild(document.createTextNode(':root{color-scheme:dark;}'));
            document.documentElement.appendChild(style);
          }
          
          var hasMeta = false;
          var metas = document.getElementsByTagName('meta');
          for (var i=0;i<metas.length;i++){
            var m = metas[i];
            if ((m.getAttribute('name')||'').toLowerCase()==='color-scheme'){
              hasMeta = true; break;
            }
          }
          if (!hasMeta){
            var meta = document.createElement('meta');
            meta.setAttribute('name','color-scheme');
            meta.setAttribute('content','dark light');
            document.getElementsByTagName('head')[0]?.appendChild(meta);
          }
        } catch (e) {}
      })();
    """;
    try {
      await _controller!.evaluateJavascript(source: js);
    } catch (_) {}
  }
}
