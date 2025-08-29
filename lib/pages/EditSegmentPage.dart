import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class EditSegmentPage extends StatefulWidget {
  final ui.Image image;                     // Orijinal görsel
  final List<Offset> initialContour;        // Segment konturu
  final int maskId;                         // DB’deki mask ID’si
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
  late List<Offset> contourPoints;

  @override
  void initState() {
    super.initState();
    contourPoints = List.from(widget.initialContour); // Kopya al
  }

  void _onDragUpdate(int index, Offset newPos) {
    setState(() {
      contourPoints[index] = newPos;
    });
  }

  Future<void> _saveEdit() async {
    // Burada API çağrısı yapabilirsin (PUT /segment/{id}/replace gibi)
    // contourPoints listesini backend'e gönderebilirsin
    print("Kaydedilecek yeni noktalar: $contourPoints");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Değişiklikler kaydedildi!")),
    );
    Navigator.pop(context, contourPoints); // Geriye yeni noktaları gönder
  }

  @override
  Widget build(BuildContext context) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Segment Düzenleme"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveEdit,
          ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: imgW / imgH,
          child: Stack(
            children: [
              RawImage(image: widget.image, fit: BoxFit.contain),

              // Çizgi overlay
              CustomPaint(
                painter: _ContourPainter(contourPoints),
                size: Size(imgW, imgH),
              ),

              // Noktaları draggable yap
              ...contourPoints.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;

                return Positioned(
                  left: p.dx - 10,
                  top: p.dy - 10,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      _onDragUpdate(
                        i,
                        Offset(
                          (p.dx + details.delta.dx).clamp(0, imgW),
                          (p.dy + details.delta.dy).clamp(0, imgH),
                        ),
                      );
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        border: Border.all(color: Colors.white, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContourPainter extends CustomPainter {
  final List<Offset> points;

  _ContourPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ContourPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
