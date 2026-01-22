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

  // Zoom ve Pan kontrolcüsü
  final TransformationController _transformationController = TransformationController();

  // Slider değeri (0 - 100 arası)
  double _sliderValue = 0.0;

  // O anki zoom seviyesi (Varsayılan 1.0)
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    // Listeyi olduğu gibi al (SegmentPage'de zaten azalttık)
    editablePoints = List.from(widget.initialContour);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // Nokta konumunu güncelleme
  void _onDragUpdate(int index, Offset newPos, double width, double height) {
    setState(() {
      editablePoints[index] = Offset(
        newPos.dx.clamp(0.0, width),
        newPos.dy.clamp(0.0, height),
      );
      editablePoints = List.from(editablePoints);
    });
  }

  void _saveEdit() {
    Navigator.pop(context, editablePoints);
  }

  // Slider değiştiğinde çalışacak fonksiyon
  void _onSliderChanged(double value) {
    setState(() {
      _sliderValue = value;

      // 0-100 arasındaki değeri 1.0x ile 5.0x zoom arasına dönüştür
      // Formül: 1.0 + (value / 25) -> 100 değeri 5.0 zoom yapar.
      double newScale = 1.0 + (value / 25.0);

      // Zoom işlemini uygula (Matris ölçekleme)
      // Identity matrisini alıp scale ediyoruz.
      _transformationController.value = Matrix4.identity()..scale(newScale);
      _currentScale = newScale;
    });
  }

  @override
  Widget build(BuildContext context) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Alanı Düzenle"),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveEdit,
            tooltip: "Kaydet",
          ),
        ],
      ),
      body: Stack(
        children: [
          // --- 1. ZOOM YAPILABİLİR ALAN ---
          InteractiveViewer(
            transformationController: _transformationController,
            // Sınırların dışına taşmayı engellemek için false yapabilirsin
            constrained: false,
            boundaryMargin: const EdgeInsets.all(100), // Resim kenara gidince boşluk
            minScale: 1.0,
            maxScale: 5.0,
            // Kullanıcı parmakla pinch (kıstırma) yaparsa slider'ı güncellemek gerekir
            onInteractionUpdate: (details) {
              setState(() {
                // Matrisin X eksenindeki ölçeğini al
                _currentScale = _transformationController.value.getMaxScaleOnAxis();
                // Scale'i (1.0 - 5.0) tekrar Slider (0-100) değerine çevir
                _sliderValue = (_currentScale - 1.0) * 25.0;
                if (_sliderValue < 0) _sliderValue = 0;
                if (_sliderValue > 100) _sliderValue = 100;
              });
            },
            child: SizedBox(
              // InteractiveViewer içinde constrained: false olduğu için
              // İçeriğin boyutunu ekran boyutuna sabitlememiz lazım.
              // Ancak burada direkt resim boyutunu baz alacağız ve LayoutBuilder ile
              // ekran boyutuna oranlayacağız.
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: Center(
                child: AspectRatio(
                  aspectRatio: imgW / imgH,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double screenW = constraints.maxWidth;
                      final double screenH = constraints.maxHeight;

                      // Ekrana sığdırma oranı (Base Scale)
                      final double scaleX = screenW / imgW;
                      final double scaleY = screenH / imgH;
                      final double baseScale = (scaleX < scaleY) ? scaleX : scaleY;

                      return Stack(
                        children: [
                          // A. Resim
                          SizedBox(
                            width: screenW,
                            height: screenH,
                            child: RawImage(image: widget.image, fit: BoxFit.contain),
                          ),

                          // B. Çizgiler
                          SizedBox(
                            width: screenW,
                            height: screenH,
                            child: CustomPaint(
                              painter: _EditorLinePainter(editablePoints, baseScale),
                            ),
                          ),

                          // C. Noktalar
                          ...editablePoints.asMap().entries.map((entry) {
                            final i = entry.key;
                            final p = entry.value;

                            final double screenX = p.dx * baseScale;
                            final double screenY = p.dy * baseScale;

                            final bool isCorner = (i == 0 || i == editablePoints.length - 1);
                            final double visualDiameter = isCorner ? 16.0 : 12.0;

                            return Positioned(
                              left: screenX - 15,
                              top: screenY - 15,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  // HASSAS SÜRÜKLEME AYARI:
                                  // Parmağın hareketini (delta) hem ekran ölçeğine (baseScale)
                                  // hem de şu anki ZOOM oranına (_currentScale) bölüyoruz.
                                  // Böylece zoom yapınca nokta fırlayıp gitmiyor.
                                  final deltaX = details.delta.dx / (baseScale * _currentScale);
                                  final deltaY = details.delta.dy / (baseScale * _currentScale);

                                  _onDragUpdate(i, Offset(p.dx + deltaX, p.dy + deltaY), imgW, imgH);
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  color: Colors.transparent,
                                  child: Center(
                                    child: Container(
                                      width: visualDiameter,
                                      height: visualDiameter,
                                      decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.green,
                                            width: 2.0,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black54,
                                              blurRadius: 2,
                                              offset: Offset(0, 1),
                                            )
                                          ]
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // --- 2. ZOOM BAR (SLIDER) ---
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.grey[900]!.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 5))
                  ]
              ),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      value: _sliderValue,
                      min: 0,
                      max: 100,
                      activeColor: Colors.blueAccent,
                      inactiveColor: Colors.white24,
                      onChanged: _onSliderChanged,
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    "${_currentScale.toStringAsFixed(1)}x",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorLinePainter extends CustomPainter {
  final List<Offset> points;
  final double scale;
  _EditorLinePainter(this.points, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final linePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final scaledPoints = points.map((p) => p * scale).toList();
    path.moveTo(scaledPoints[0].dx, scaledPoints[0].dy);
    for (int i = 1; i < scaledPoints.length; i++) {
      path.lineTo(scaledPoints[i].dx, scaledPoints[i].dy);
    }
    // Alanı kapat
    if (scaledPoints.length > 2) {
      path.lineTo(scaledPoints[0].dx, scaledPoints[0].dy);
    }
    canvas.drawPath(path, linePaint);
  }
  @override
  bool shouldRepaint(covariant _EditorLinePainter oldDelegate) => true;
}