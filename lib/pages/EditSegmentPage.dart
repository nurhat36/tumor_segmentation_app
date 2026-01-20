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

  @override
  void initState() {
    super.initState();
    // Gelen listeyi olduğu gibi al (Filtreleme YOK)
    editablePoints = List.from(widget.initialContour);
  }

  void _onDragUpdate(int index, Offset newPos, double width, double height) {
    setState(() {
      editablePoints[index] = Offset(
        newPos.dx.clamp(0.0, width),
        newPos.dy.clamp(0.0, height),
      );
      // Repaint tetiklemesi için
      editablePoints = List.from(editablePoints);
    });
  }

  void _saveEdit() {
    Navigator.pop(context, editablePoints);
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
      body: Center(
        child: AspectRatio(
          aspectRatio: imgW / imgH,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double screenW = constraints.maxWidth;
              final double screenH = constraints.maxHeight;
              final double scaleX = screenW / imgW;
              final double scaleY = screenH / imgH;
              final double scale = (scaleX < scaleY) ? scaleX : scaleY;

              return Stack(
                children: [
                  // 1. Resim
                  SizedBox(
                    width: screenW,
                    height: screenH,
                    child: RawImage(image: widget.image, fit: BoxFit.contain),
                  ),

                  // 2. Çizgi (Tüm noktalar)
                  SizedBox(
                    width: screenW,
                    height: screenH,
                    child: CustomPaint(
                      painter: _EditorLinePainter(editablePoints, scale),
                    ),
                  ),

                  // 3. Noktalar (HER NOKTA İÇİN)
                  // Burada da filtreleme yapmıyoruz.
                  ...editablePoints.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;

                    final double screenX = p.dx * scale;
                    final double screenY = p.dy * scale;

                    return Positioned(
                      // Dokunma alanı geniş, nokta merkezde
                      left: screenX - 15,
                      top: screenY - 15,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          final deltaX = details.delta.dx / scale;
                          final deltaY = details.delta.dy / scale;
                          _onDragUpdate(i, Offset(p.dx + deltaX, p.dy + deltaY), imgW, imgH);
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          color: Colors.transparent,
                          child: Center(
                            child: Container(
                              // SegmentPage ile uyumlu görsel boyut (Çap 10-12)
                              width: 10.0,
                              height: 10.0,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.green,
                                  width: 1.5,
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
    path.close();
    canvas.drawPath(path, linePaint);
  }
  @override
  bool shouldRepaint(covariant _EditorLinePainter oldDelegate) => true;
}