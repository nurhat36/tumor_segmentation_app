import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';    // ← YENİ
import 'package:flutter/gestures.dart';      // ← YENİ
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as p;

class NiiVueMobileViewer extends StatefulWidget {
  final String localFilePath;
  final String? maskUrl;
  final String token;
  final String viewMode;

  const NiiVueMobileViewer({
    super.key,
    required this.localFilePath,
    this.maskUrl,
    required this.token,
    required this.viewMode,
  });

  @override
  State<NiiVueMobileViewer> createState() => _NiiVueMobileViewerState();
}

class _NiiVueMobileViewerState extends State<NiiVueMobileViewer> {
  late final WebViewController _controller;
  HttpServer? _localServer;
  int _serverPort = 0;
  bool _isWebViewReady = false;
  String _statusMessage = "Hazırlanıyor...";

  @override
  void initState() {
    super.initState();
    _startLocalServerThenWebView();
  }

  @override
  void dispose() {
    _localServer?.close(force: true);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NiiVueMobileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.viewMode != widget.viewMode && _isWebViewReady) {
      _controller.runJavaScript("changeViewMode('${widget.viewMode}');");
    }

    if (oldWidget.localFilePath != widget.localFilePath && _isWebViewReady) {
      _loadNiftiFile();
    }
  }

  Future<void> _startLocalServerThenWebView() async {
    try {
      setState(() => _statusMessage = "Yerel sunucu başlatılıyor...");

      final file = File(widget.localFilePath);
      if (!await file.exists()) {
        setState(() => _statusMessage = "HATA: Dosya bulunamadı!");
        return;
      }

      final directory = file.parent;
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _serverPort = _localServer!.port;

      _localServer!.listen((HttpRequest request) async {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = 200;
          await request.response.close();
          return;
        }

        final requestedName = Uri.decodeComponent(request.uri.path.substring(1));
        final requestedFile = File('${directory.path}/$requestedName');

        if (await requestedFile.exists()) {
          if (requestedName.endsWith('.nii.gz')) {
            request.response.headers.contentType = ContentType('application', 'gzip');
          } else if (requestedName.endsWith('.nii')) {
            request.response.headers.contentType = ContentType('application', 'octet-stream');
          }
          await request.response.addStream(requestedFile.openRead());
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          request.response.write('Not Found');
          await request.response.close();
        }
      });

      _initWebView();

    } catch (e) {
      setState(() => _statusMessage = "Sunucu hatası: $e");
    }
  }

  void _initWebView() {
    setState(() => _statusMessage = "WebView yükleniyor...");

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          print("📨 JS → Flutter: ${message.message}");

          if (message.message == "READY") {
            _isWebViewReady = true;
            _loadNiftiFile();
          } else if (message.message == "LOADED") {
            setState(() => _statusMessage = "");
          } else if (message.message.startsWith("ERROR")) {
            setState(() => _statusMessage = message.message);
          }
        },
      )
      ..loadFlutterAsset('lib/assets/niivue.html');

    setState(() {});
  }

  void _loadNiftiFile() {
    if (!_isWebViewReady) return;

    final fileName = p.basename(widget.localFilePath);
    setState(() => _statusMessage = "MR dosyası yükleniyor...");

    _controller.runJavaScript("loadLocalData($_serverPort, '$fileName');");

    if (widget.maskUrl != null) {
      Future.delayed(const Duration(seconds: 2), () {
        _controller.runJavaScript("addMask('${widget.maskUrl}', '${widget.token}');");
      });
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      _controller.runJavaScript("changeViewMode('${widget.viewMode}');");
    });
  }

  // ═══════════════════════════════════════════════════
  // ★ BUILD - GestureRecognizers ile Scroll Desteği ★
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_serverPort == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.blueAccent),
            const SizedBox(height: 16),
            Text(_statusMessage, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // ─── ★ gestureRecognizers EKLENDİ ★ ───
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            // Tüm gesture'ları WebView'a gönder
            // (scroll, pan, zoom hepsi WebView içinde çalışsın)
            Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
          },
        ),

        if (_statusMessage.isNotEmpty)
          Positioned(
            bottom: 10, left: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}