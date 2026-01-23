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
  // Bu değeri noktaların boyutunu ters orantılı ayarlamak için kullanacağız.
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
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
      // Noktanın resim dışına çıkmasını engelle (Clamp)
      editablePoints[index] = Offset(
        newPos.dx.clamp(0.0, width),
        newPos.dy.clamp(0.0, height),
      );
      // Listeyi güncelle ki UI tetiklensin
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
      // 1.0x ile 5.0x arası zoom
      double newScale = 1.0 + (value / 25.0);
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
        title: const Text("Hassas Alan Düzenleme"),
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
          // --- 1. ZOOM YAPILABİLİR ALAN (Senin Orijinal Yapın) ---
          InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(200), // Kenar boşluğu artırıldı rahat pan için
            minScale: 1.0,
            maxScale: 5.0,
            // Parmakla zoom yapınca slider'ı ve _currentScale'i güncelle
            onInteractionUpdate: (details) {
              setState(() {
                _currentScale = _transformationController.value.getMaxScaleOnAxis();
                _sliderValue = (_currentScale - 1.0) * 25.0;
                if (_sliderValue < 0) _sliderValue = 0;
                if (_sliderValue > 100) _sliderValue = 100;
              });
            },
            child: SizedBox(
              // Ekran boyutunu alıyoruz
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: Center(
                child: AspectRatio(
                  aspectRatio: imgW / imgH,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double screenW = constraints.maxWidth;
                      final double screenH = constraints.maxHeight;

                      // Resmi ekrana sığdırma oranı (Base Scale)
                      final double scaleX = screenW / imgW;
                      final double scaleY = screenH / imgH;
                      final double baseScale = (scaleX < scaleY) ? scaleX : scaleY;

                      return Stack(
                        clipBehavior: Clip.none, // Noktalar kenardan taşarsa kesilmesin
                        children: [
                          // A. Resim
                          SizedBox(
                            width: screenW,
                            height: screenH,
                            child: RawImage(image: widget.image, fit: BoxFit.contain),
                          ),

                          // B. Çizgiler (CustomPaint ile)
                          // Çizgi kalınlığını da zoom'a göre ayarlayalım ki çok kalınlaşmasın
                          SizedBox(
                            width: screenW,
                            height: screenH,
                            child: CustomPaint(
                              painter: _EditorLinePainter(
                                  points: editablePoints,
                                  scale: baseScale,
                                  // Zoom arttıkça çizgi incelsin
                                  strokeWidth: 2.5 / _currentScale
                              ),
                            ),
                          ),

                          // C. Noktalar (Widget olarak)
                          ...editablePoints.asMap().entries.map((entry) {
                            final i = entry.key;
                            final p = entry.value;

                            // Resim koordinatını ekran koordinatına çevir
                            final double screenX = p.dx * baseScale;
                            final double screenY = p.dy * baseScale;

                            // Başlangıç ve bitiş noktaları biraz daha belirgin olsun
                            final bool isCorner = (i == 0 || i == editablePoints.length - 1);
                            // Temel görsel boyut (zoomsuz hali)
                            final double baseDiameter = isCorner ? 16.0 : 12.0;

                            // Dokunma alanı boyutu (sabit kalacak)
                            const double touchAreaSize = 40.0;

                            return Positioned(
                              // Dokunma alanını merkeze al
                              left: screenX - (touchAreaSize / 2),
                              top: screenY - (touchAreaSize / 2),
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  // HASSAS SÜRÜKLEME HESABI (Senin kodundaki doğru mantık):
                                  // Parmağın hareketini (delta) hem ekran sığdırma ölçeğine (baseScale)
                                  // hem de şu anki ZOOM oranına (_currentScale) bölüyoruz.
                                  // Böylece 5x zoomdayken parmak 5cm kaysa bile nokta resim üzerinde azıcık kayar.
                                  final deltaX = details.delta.dx / (baseScale * _currentScale);
                                  final deltaY = details.delta.dy / (baseScale * _currentScale);

                                  _onDragUpdate(i, Offset(p.dx + deltaX, p.dy + deltaY), imgW, imgH);
                                },
                                child: Container(
                                  // Görünmez geniş dokunma alanı
                                  width: touchAreaSize,
                                  height: touchAreaSize,
                                  color: Colors.transparent,
                                  child: Center(
                                    // İŞTE KİLİT NOKTA BURASI: TERS ÖLÇEKLEME (Inverse Scaling)
                                    // InteractiveViewer büyüdükçe, biz bu widget'ı küçültüyoruz.
                                    child: Transform.scale(
                                      scale: 1.0 / _currentScale, // <--- BU SATIR ÖNEMLİ
                                      child: Container(
                                        // Görünür renkli nokta
                                        width: baseDiameter,
                                        height: baseDiameter,
                                        decoration: BoxDecoration(
                                            color: isCorner ? Colors.greenAccent : Colors.redAccent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
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

          // --- 2. ZOOM BAR (SLIDER) - Aynen korundu ---
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

// Çizgi çizen painter (Ufak bir güncellemeyle)
class _EditorLinePainter extends CustomPainter {
  final List<Offset> points;
  final double scale;
  final double strokeWidth; // Yeni parametre

  _EditorLinePainter({
    required this.points,
    required this.scale,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final linePaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth // Dinamik kalınlık
      ..strokeCap = StrokeCap.round;

    final path = Path();
    // Koordinatları ekran ölçeğine göre ayarla
    final scaledPoints = points.map((p) => p * scale).toList();

    path.moveTo(scaledPoints[0].dx, scaledPoints[0].dy);
    for (int i = 1; i < scaledPoints.length; i++) {
      path.lineTo(scaledPoints[i].dx, scaledPoints[i].dy);
    }
    if (scaledPoints.length > 2) {
      path.close(); // Yolu kapat
    }
    canvas.drawPath(path, linePaint);
  }
  @override
  bool shouldRepaint(covariant _EditorLinePainter oldDelegate) =>
      oldDelegate.points != points ||
          oldDelegate.scale != scale ||
          oldDelegate.strokeWidth != strokeWidth;
}