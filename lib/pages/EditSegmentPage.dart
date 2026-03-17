import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class EditSegmentPage extends StatefulWidget {
  final String? originalImageUrl;
  final ui.Image? originalMemoryImage;
  final String? maskImageUrl;          // Listeden gelirse maskeyi bulmak için
  final List<Offset> initialContour;
  final int maskId;
  final String token;

  const EditSegmentPage({
    super.key,
    this.originalImageUrl,
    this.originalMemoryImage,
    this.maskImageUrl,
    required this.initialContour,
    required this.maskId,
    required this.token,
  });

  @override
  State<EditSegmentPage> createState() => _EditSegmentPageState();
}

class _EditSegmentPageState extends State<EditSegmentPage> {
  ui.Image? _loadedImage;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  late List<Offset> editablePoints;
  final TransformationController _transformationController = TransformationController();

  List<List<Offset>> _history = [];
  int _historyIndex = 0;
  bool _isEditMode = false;
  int? _activePointIndex;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      // 1. Orijinal Arka Plan Resmini Yükle
      if (widget.originalMemoryImage != null) {
        _loadedImage = widget.originalMemoryImage;
      } else if (widget.originalImageUrl != null) {
        _loadedImage = await _fetchImage(widget.originalImageUrl!);
      }

      // 2. Noktaları (Konturları) Belirle
      if (widget.initialContour.isNotEmpty) {
        editablePoints = List.from(widget.initialContour);
      } else if (widget.maskImageUrl != null) {
        // Liste sayfasından gelmiş, maskeden noktaları bulmamız lazım!
        ui.Image maskImg = await _fetchImage(widget.maskImageUrl!);
        editablePoints = await _extractContourFromMask(maskImg);
      } else {
        editablePoints = [];
      }

      _history.add(List.from(editablePoints));

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Görüntü yüklenirken hata oluştu: $e";
        });
      }
    }
  }

  Future<ui.Image> _fetchImage(String url) async {
    final networkImage = NetworkImage(url);
    final completer = Completer<ui.Image>();
    networkImage.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
            (info, _) => completer.complete(info.image),
        onError: (err, stack) => completer.completeError(err),
      ),
    );
    return await completer.future;
  }

  // Siyah/Beyaz maskeden kırmızı/mavi noktaları bulma algoritması
  Future<List<Offset>> _extractContourFromMask(ui.Image maskImg) async {
    final byteData = await maskImg.toByteData();
    if (byteData == null) return [];
    final width = maskImg.width;
    final height = maskImg.height;
    final pixels = byteData.buffer.asUint8List();
    final visited = List.generate(width * height, (_) => false);

    bool isWhite(int x, int y) {
      if (x < 0 || x >= width || y < 0 || y >= height) return false;
      return pixels[(y * width + x) * 4] > 128;
    }

    Offset? startPoint;
    for (int y = 0; y < height && startPoint == null; y++) {
      for (int x = 0; x < width && startPoint == null; x++) {
        if (isWhite(x, y)) startPoint = Offset(x.toDouble(), y.toDouble());
      }
    }
    if (startPoint == null) return [];

    final currentPath = <Offset>[startPoint];
    Offset currentPoint = startPoint;
    int i = 0;
    while (i < width * height * 2) {
      bool moved = false;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = currentPoint.dx.round() + dx;
          final ny = currentPoint.dy.round() + dy;
          if (isWhite(nx, ny) && !visited[ny * width + nx]) {
            bool isEdge = false;
            for (int ndy = -1; ndy <= 1; ndy++) {
              for (int ndx = -1; ndx <= 1; ndx++) {
                if (ndx == 0 && ndy == 0) continue;
                if (!isWhite(nx + ndx, ny + ndy)) { isEdge = true; break; }
              }
              if (isEdge) break;
            }
            if (isEdge) {
              currentPoint = Offset(nx.toDouble(), ny.toDouble());
              currentPath.add(currentPoint);
              visited[ny * width + nx] = true;
              moved = true; break;
            }
          }
        }
        if (moved) break;
      }
      if (!moved) break;
      i++;
    }

    final simplified = <Offset>[];
    for (int k = 0; k < currentPath.length; k += 20) simplified.add(currentPath[k]);
    return simplified;
  }

  void _onTransformChanged() => setState(() => _currentScale = _transformationController.value.getMaxScaleOnAxis());

  void _recordHistory() {
    if (_historyIndex < _history.length - 1) _history = _history.sublist(0, _historyIndex + 1);
    _history.add(List.from(editablePoints));
    _historyIndex++;
    setState(() {});
  }

  void _undo() {
    if (_historyIndex > 0) setState(() { _historyIndex--; editablePoints = List.from(_history[_historyIndex]); });
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) setState(() { _historyIndex++; editablePoints = List.from(_history[_historyIndex]); });
  }

  // ========================================================
  // KAYDET: Noktalardan yeni Siyah/Beyaz maske üretip geri yollar
  // ========================================================
  Future<void> _saveEdit() async {
    if (_loadedImage == null) return;
    setState(() => _isSaving = true);

    final width = _loadedImage!.width.toDouble();
    final height = _loadedImage!.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Arka plan siyah
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.black);

    // İçi beyaz poligon
    if (editablePoints.isNotEmpty) {
      final path = Path()..moveTo(editablePoints[0].dx, editablePoints[0].dy);
      for (int i = 1; i < editablePoints.length; i++) {
        path.lineTo(editablePoints[i].dx, editablePoints[i].dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);
    }

    // Resmi PNG byte'larına çevir
    final newMaskImage = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final byteData = await newMaskImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // Hem noktaları hem de hazır siyah/beyaz PNG dosyasını geri gönderiyoruz!
    Navigator.pop(context, {
      'points': editablePoints,
      'maskBytes': pngBytes,
    });
  }

  int? _findNearestPoint(Offset localPosition, double baseScale) {
    double hitRadius = 40.0 / baseScale / _currentScale;
    double minDistance = hitRadius;
    int? closestIndex;
    final imagePos = localPosition / baseScale;
    for (int i = 0; i < editablePoints.length; i++) {
      final distance = (editablePoints[i] - imagePos).distance;
      if (distance < minDistance) { minDistance = distance; closestIndex = i; }
    }
    return closestIndex;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isSaving) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.blueAccent),
              const SizedBox(height: 20),
              Text(_isSaving ? "Maske Oluşturuluyor..." : "Görüntü İşleniyor...", style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _loadedImage == null) {
      return Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: const Text("Hata"), backgroundColor: Colors.red[900]), body: Center(child: Text(_errorMessage ?? "Hata", style: const TextStyle(color: Colors.white))));
    }

    final imgW = _loadedImage!.width.toDouble();
    final imgH = _loadedImage!.height.toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isEditMode ? "✏️ Çizim Modu" : "🖐️ Gezinme Modu"),
        backgroundColor: _isEditMode ? Colors.blueAccent[700] : Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _historyIndex > 0 ? _undo : null),
          IconButton(icon: const Icon(Icons.redo), onPressed: _historyIndex < _history.length - 1 ? _redo : null),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveEdit),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() { _isEditMode = !_isEditMode; _activePointIndex = null; }),
        backgroundColor: _isEditMode ? Colors.green : Colors.blue,
        icon: Icon(_isEditMode ? Icons.done : Icons.edit),
        label: Text(_isEditMode ? "Bitir" : "Düzenle"),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double baseScale = (constraints.maxWidth / imgW < constraints.maxHeight / imgH) ? constraints.maxWidth / imgW : constraints.maxHeight / imgH;
          return Center(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.1, maxScale: 20.0, panEnabled: !_isEditMode,
              child: SizedBox(
                width: imgW * baseScale, height: imgH * baseScale,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: _isEditMode ? (d) { final i = _findNearestPoint(d.localPosition, baseScale); if (i != null) setState(() => _activePointIndex = i); } : null,
                  onPanUpdate: (_isEditMode && _activePointIndex != null) ? (d) {
                    final delta = d.delta / baseScale / _currentScale;
                    setState(() => editablePoints[_activePointIndex!] = Offset((editablePoints[_activePointIndex!].dx + delta.dx).clamp(0.0, imgW), (editablePoints[_activePointIndex!].dy + delta.dy).clamp(0.0, imgH)));
                  } : null,
                  onPanEnd: _isEditMode ? (_) { if (_activePointIndex != null) { _recordHistory(); setState(() => _activePointIndex = null); } } : null,
                  onTapUp: _isEditMode ? (d) {
                    if (_findNearestPoint(d.localPosition, baseScale) == null) {
                      setState(() => editablePoints.add(Offset((d.localPosition / baseScale).dx.clamp(0.0, imgW), (d.localPosition / baseScale).dy.clamp(0.0, imgH))));
                      _recordHistory();
                    }
                  } : null,
                  onLongPressStart: _isEditMode ? (d) {
                    final i = _findNearestPoint(d.localPosition, baseScale);
                    if (i != null) { setState(() { editablePoints.removeAt(i); _activePointIndex = null; }); _recordHistory(); }
                  } : null,
                  child: Stack(
                    children: [
                      Positioned.fill(child: RawImage(image: _loadedImage, fit: BoxFit.contain)),
                      Positioned.fill(child: CustomPaint(painter: _InvariantPainter(points: editablePoints, baseScale: baseScale, zoomLevel: _currentScale, activeIndex: _activePointIndex, isEditMode: _isEditMode))),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InvariantPainter extends CustomPainter {
  final List<Offset> points;
  final double baseScale;
  final double zoomLevel;
  final int? activeIndex;
  final bool isEditMode;

  _InvariantPainter({required this.points, required this.baseScale, required this.zoomLevel, this.activeIndex, required this.isEditMode});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final stroke = 1.5 / baseScale / zoomLevel;
    final dotRadius = (isEditMode ? 3.0 : 1.5) / baseScale / zoomLevel;
    final activeRadius = 5.0 / baseScale / zoomLevel;

    final fillPaint = Paint()..color = isEditMode ? Colors.blue.withOpacity(0.20) : Colors.white.withOpacity(0.05)..style = PaintingStyle.fill;
    final linePaint = Paint()..color = isEditMode ? Colors.blueAccent : Colors.greenAccent..style = PaintingStyle.stroke..strokeWidth = stroke..isAntiAlias = true;
    final dotPaint = Paint()..color = Colors.redAccent..style = PaintingStyle.fill;
    final activeDotPaint = Paint()..color = Colors.amber..style = PaintingStyle.fill;

    final path = Path()..moveTo(points[0].dx * baseScale, points[0].dy * baseScale);
    for (int i = 1; i < points.length; i++) path.lineTo(points[i].dx * baseScale, points[i].dy * baseScale);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);

    if (isEditMode) {
      for (int i = 0; i < points.length; i++) {
        final point = points[i] * baseScale;
        canvas.drawCircle(point, (i == activeIndex) ? activeRadius : dotRadius, (i == activeIndex) ? activeDotPaint : dotPaint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _InvariantPainter old) => true;
}