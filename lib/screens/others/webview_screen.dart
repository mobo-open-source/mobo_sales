import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebViewScreen({super.key, required this.url, required this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  int _loadingProgress = 0;
  Completer<void>? _refreshCompleter;

  @override
  void initState() {
    super.initState();
  }

  void _refresh() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _controller?.reload();
  }

  void _goBack() async {
    if (_controller != null && await _controller!.canGoBack()) {
      _controller!.goBack();
    } else {
      Navigator.pop(context);
    }
  }

  void _goForward() async {
    if (_controller != null && await _controller!.canGoForward()) {
      _controller!.goForward();
    }
  }

  Future<bool> _handleWillPop() async {
    if (_controller != null && await _controller!.canGoBack()) {
      _controller!.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[850] : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black,
          elevation: 0,
          leading: IconButton(
            onPressed: () async {
              if (_controller != null && await _controller!.canGoBack()) {
                _controller!.goBack();
              } else {
                if (mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(HugeIcons.strokeRoundedArrowLeft01, size: 20),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              onPressed: _goBack,
              icon: const Icon(HugeIcons.strokeRoundedArrowLeft02, size: 20),
              tooltip: 'Back',
            ),
            IconButton(
              onPressed: _goForward,
              icon: const Icon(HugeIcons.strokeRoundedArrowRight02, size: 20),
              tooltip: 'Forward',
            ),
          ],
        ),
        body: Column(
          children: [
            if (_errorMessage == null && _loadingProgress < 100)
              LinearProgressIndicator(
                value: _loadingProgress == 0 ? null : _loadingProgress / 100.0,
                minHeight: 3,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _refreshCompleter = Completer<void>();
                  _refresh();
                  try {
                    await _refreshCompleter!.future.timeout(
                      const Duration(seconds: 12),
                    );
                  } catch (_) {
                  } finally {
                    _refreshCompleter = null;
                  }
                },
                color: Theme.of(context).primaryColor,
                child: Stack(
                  children: [
                    if (_errorMessage != null)
                      _buildErrorWidget()
                    else
                      InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          useHybridComposition: true,
                          allowsBackForwardNavigationGestures: true,
                        ),
                        onWebViewCreated: (controller) {
                          _controller = controller;
                        },
                        onProgressChanged: (controller, progress) {
                          setState(() {
                            _loadingProgress = progress;
                          });
                        },
                        onLoadStart: (controller, url) {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                        },
                        onLoadStop: (controller, url) {
                          setState(() {
                            _isLoading = false;
                          });
                          _refreshCompleter?.complete();
                          _refreshCompleter = null;
                        },
                        onReceivedError: (controller, request, error) {
                          setState(() {
                            _isLoading = false;

                            if (error.type != WebResourceErrorType.CANCELLED) {
                              _errorMessage =
                                  'Failed to load page: ${error.description}';
                            }
                          });
                          _refreshCompleter?.completeError(error);
                          _refreshCompleter = null;
                        },
                        onReceivedHttpError: (controller, request, response) {
                          if ((response.statusCode ?? 0) >= 400) {
                            setState(() {
                              _isLoading = false;
                              _errorMessage =
                                  'HTTP Error: ${response.statusCode} - ${response.reasonPhrase}';
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedAlertCircle,
                  color: Colors.red,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Unable to Load Page',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'An error occurred while loading the page.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      HugeIcons.strokeRoundedArrowLeft01,
                      size: 16,
                    ),
                    label: Text(
                      'Go Back',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : Colors.black,
                      side: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
                    label: Text(
                      'Try Again',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
