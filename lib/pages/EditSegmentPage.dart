import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class EditSegmentPage extends StatefulWidget {
  final ui.Image image;
  final List<Offset> initialContour;
  final int maskId;
  final String token;

  const EditSegmentPage({
    super.key,
    required this.image,
    required this.initialContour,
    required this.maskId,
    required this.token,
  });

  @override
  State<EditSegmentPage> createState() => _EditSegmentPageState();
}

class _EditSegmentPageState extends State<EditSegmentPage> {
  late List<Offset> editablePoints;
  final TransformationController _transformationController = TransformationController();

  // --- UNDO / REDO DEĞİŞKENLERİ ---
  // Tüm değişikliklerin tutulduğu liste listesi
  List<List<Offset>> _history = [];
  // Şu an hangi adımdayız?
  int _historyIndex = 0;

  bool _isEditMode = false;
  int? _activePointIndex;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    // Başlangıç listesini oluştur
    editablePoints = List.from(widget.initialContour);

    // İlk hali geçmişe ekle (Başlangıç noktası)
    _history.add(List.from(editablePoints));

    // Eğer manuel çizimse (boş liste), edit modunu aç
    if (widget.initialContour.isEmpty) {
      // _isEditMode = true; // İstersen direkt açabilirsin ama gezinme moduyla başlamak daha güvenli
    }

    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    setState(() {
      _currentScale = _transformationController.value.getMaxScaleOnAxis();
    });
  }

  // --- TARİHÇE YÖNETİMİ (Kritik Kısım) ---
  void _recordHistory() {
    // Eğer geçmişin ortasındaysak ve yeni işlem yaparsak, ilerideki (Redo) adımları silmeliyiz.
    if (_historyIndex < _history.length - 1) {
      _history = _history.sublist(0, _historyIndex + 1);
    }

    // Mevcut durumun kopyasını geçmişe ekle
    _history.add(List.from(editablePoints));
    _historyIndex++;
    setState(() {}); // Butonları güncellemek için
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        // Listeyi tamamen değiştiriyoruz (Deep Copy yaparak referansı kopar)
        editablePoints = List.from(_history[_historyIndex]);
      });
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        editablePoints = List.from(_history[_historyIndex]);
      });
    }
  }
  // ----------------------------------------

  void _saveEdit() {
    Navigator.pop(context, editablePoints);
  }

  int? _findNearestPoint(Offset localPosition, double baseScale) {
    double hitRadius = 40.0 / baseScale / _currentScale;
    double minDistance = hitRadius;
    int? closestIndex;

    final imagePos = localPosition / baseScale;

    for (int i = 0; i < editablePoints.length; i++) {
      final distance = (editablePoints[i] - imagePos).distance;
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  @override
  Widget build(BuildContext context) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();

    // Undo/Redo Aktiflik Durumu
    final canUndo = _historyIndex > 0;
    final canRedo = _historyIndex < _history.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isEditMode ? "✏️ Çizim Modu" : "🖐️ Gezinme Modu"),
        backgroundColor: _isEditMode ? Colors.blueAccent[700] : Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // GERİ AL (UNDO)
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Geri Al",
            onPressed: canUndo ? _undo : null, // Pasifse tıklanamaz
            color: canUndo ? Colors.white : Colors.white38,
          ),
          // İLERİ AL (REDO)
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: "İleri Al",
            onPressed: canRedo ? _redo : null,
            color: canRedo ? Colors.white : Colors.white38,
          ),
          // KAYDET
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveEdit,
            tooltip: "Kaydet",
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            _isEditMode = !_isEditMode;
            _activePointIndex = null;
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          if (_isEditMode) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Dokunarak ekle, basılı tutarak sil, sürükle."),
              duration: Duration(seconds: 2),
            ));
          }
        },
        backgroundColor: _isEditMode ? Colors.green : Colors.blue,
        icon: Icon(_isEditMode ? Icons.done : Icons.edit),
        label: Text(_isEditMode ? "Bitir" : "Düzenle"),
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenW = constraints.maxWidth;
          final double screenH = constraints.maxHeight;
          final double scaleX = screenW / imgW;
          final double scaleY = screenH / imgH;
          final double baseScale = (scaleX < scaleY) ? scaleX : scaleY;

          final double contentWidth = imgW * baseScale;
          final double contentHeight = imgH * baseScale;

          return Center(
            child: InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              minScale: 0.1,
              maxScale: 20.0,
              panEnabled: !_isEditMode,
              scaleEnabled: true,

              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,

                  // --- NOKTA SÜRÜKLEME ---
                  onPanStart: _isEditMode ? (details) {
                    final index = _findNearestPoint(details.localPosition, baseScale);
                    if (index != null) {
                      setState(() => _activePointIndex = index);
                    }
                  } : null,

                  onPanUpdate: (_isEditMode && _activePointIndex != null) ? (details) {
                    final delta = details.delta / baseScale / _currentScale;
                    setState(() {
                      Offset current = editablePoints[_activePointIndex!];
                      editablePoints[_activePointIndex!] = Offset(
                        (current.dx + delta.dx).clamp(0.0, imgW),
                        (current.dy + delta.dy).clamp(0.0, imgH),
                      );
                    });
                  } : null,

                  // SÜRÜKLEME BİTİNCE -> GEÇMİŞE KAYDET
                  onPanEnd: _isEditMode ? (_) {
                    if (_activePointIndex != null) {
                      _recordHistory(); // <-- Sürükleme bitince kaydet
                      setState(() => _activePointIndex = null);
                    }
                  } : null,

                  // --- NOKTA EKLEME (Tek Tık) ---
                  onTapUp: _isEditMode ? (details) {
                    if (_findNearestPoint(details.localPosition, baseScale) == null) {
                      final imagePos = details.localPosition / baseScale;
                      setState(() {
                        editablePoints.add(Offset(
                          imagePos.dx.clamp(0.0, imgW),
                          imagePos.dy.clamp(0.0, imgH),
                        ));
                      });
                      _recordHistory(); // <-- Ekleme bitince kaydet
                    }
                  } : null,

                  // --- NOKTA SİLME (Uzun Basma) ---
                  onLongPressStart: _isEditMode ? (details) {
                    final index = _findNearestPoint(details.localPosition, baseScale);
                    if (index != null) {
                      setState(() {
                        editablePoints.removeAt(index);
                        _activePointIndex = null;
                      });
                      _recordHistory(); // <-- Silme bitince kaydet

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Nokta silindi"), duration: Duration(milliseconds: 300)),
                      );
                    }
                  } : null,

                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RawImage(image: widget.image, fit: BoxFit.contain),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _InvariantPainter(
                            points: editablePoints,
                            baseScale: baseScale,
                            zoomLevel: _currentScale,
                            activeIndex: _activePointIndex,
                            isEditMode: _isEditMode,
                          ),
                        ),
                      ),
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

// --- RESSAM (Değişiklik Yok - Aynı Kalıyor) ---
class _InvariantPainter extends CustomPainter {
  final List<Offset> points;
  final double baseScale;
  final double zoomLevel;
  final int? activeIndex;
  final bool isEditMode;

  _InvariantPainter({
    required this.points,
    required this.baseScale,
    required this.zoomLevel,
    this.activeIndex,
    required this.isEditMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final double stroke = 1.5 / baseScale / zoomLevel;
    final double dotRadius = (isEditMode ? 3.0 : 1.5) / baseScale / zoomLevel;
    final double activeRadius = 5.0 / baseScale / zoomLevel;

    final fillPaint = Paint()
      ..color = isEditMode
          ? Colors.blue.withOpacity(0.20)
          : Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = isEditMode ? Colors.blueAccent : Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final dotPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    final activeDotPaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;

    final path = Path();
    final start = points[0] * baseScale;
    path.moveTo(start.dx, start.dy);
    for (int i = 1; i < points.length; i++) {
      final p = points[i] * baseScale;
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);

    if (isEditMode) {
      for (int i = 0; i < points.length; i++) {
        final point = points[i] * baseScale;
        final bool isActive = (i == activeIndex);
        double r = isActive ? activeRadius : dotRadius;
        canvas.drawCircle(point, r, isActive ? activeDotPaint : dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InvariantPainter oldDelegate) {
    return true;
  }
}