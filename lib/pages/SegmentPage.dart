import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum ShapeType { rectangle, circle, oval }

class SegmentPage extends StatefulWidget {
  final String token;
  final int userId;

  const SegmentPage({
    super.key,
    required this.token,
    required this.userId,
  });

  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  // Görsel
  File? selectedImage;
  ui.Image? loadedImage;

  // UI durumları
  bool isLoading = false;
  bool editMode = false; // kırmızı noktalar aktif/pasif
  bool showOverlay = true;
  ShapeType selectedShape = ShapeType.rectangle;

  // Seçim / çokgen verileri (HEP "görüntü uzayı"nda saklanır!)
  Rect? selectionRectImage;           // ilk dikdörtgen seçim (image space)
  List<Offset> pointsImage = [];      // çokgen noktaları (image space)

  // ----- Yardımcı: görüntüyü yükle -----
  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      isLoading = true;
      selectedImage = File(picked.path);
      selectionRectImage = null;
      pointsImage.clear();
      editMode = false;
    });

    final bytes = await picked.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    setState(() {
      loadedImage = frame.image;
      isLoading = false;
    });
  }

  // ----- LayoutBuilder alanına göre ölçek/ofset -----
  // BoxFit.contain ile resmi sığdırmak için gereken scale & offset
  ({double scale, Offset offset}) _fit(Size box) {
    final w = loadedImage!.width.toDouble();
    final h = loadedImage!.height.toDouble();
    final s = math.min(box.width / w, box.height / h);
    final dx = (box.width - w * s) / 2.0;
    final dy = (box.height - h * s) / 2.0;
    return (scale: s, offset: Offset(dx, dy));
  }

  // Ekran (canvas) <-> Görüntü (image) koordinat dönüşümleri
  Offset _canvasToImage(Offset canvasPos, double scale, Offset off) {
    return Offset((canvasPos.dx - off.dx) / scale, (canvasPos.dy - off.dy) / scale);
  }

  Offset _imageToCanvas(Offset imgPos, double scale, Offset off) {
    return Offset(imgPos.dx * scale + off.dx, imgPos.dy * scale + off.dy);
  }

  // ----- İlk dikdörtgenden 12 noktalı oval çokgen üret -----
  List<Offset> _ovalPointsFromRect(Rect r, {int count = 12}) {
    final cx = r.center.dx;
    final cy = r.center.dy;
    final rx = r.width / 2.0;
    final ry = r.height / 2.0;
    final pts = <Offset>[];
    for (int i = 0; i < count; i++) {
      final t = (2 * math.pi) * (i / count);
      pts.add(Offset(cx + rx * math.cos(t), cy + ry * math.sin(t)));
    }
    return pts;
  }

  // ----- Segment (stub): dikdörtgeni çokgene çevir -----
  Future<void> _segmentFromSelection() async {
    if (selectionRectImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text("Önce bir alan seçin.")),

        const SnackBar(content: Text("Geçersiz seçim alanı")),

      );
      return;
    }
    setState(() {
      pointsImage = _ovalPointsFromRect(selectionRectImage!, count: 12);
      editMode = false; // önce göster, istenirse sonra düzenle
    });
  }

  // ----- Noktaların sürüklenmesi sırasında görüntü sınırına hapset -----
  Offset _clampToImage(Offset p) {
    final w = loadedImage!.width.toDouble();
    final h = loadedImage!.height.toDouble();
    final x = p.dx.clamp(0.0, w);
    final y = p.dy.clamp(0.0, h);
    return Offset(x, y);
  }

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Segment İşlemi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: pickImage,
            tooltip: "Resim seç",
          ),
          if (pointsImage.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: "Kaydet",
              onPressed: () {
                // Burada polygonu dosyaya/servise kaydetme eklenebilir
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Segmente edilen alan kaydedildi (örnek).")),
                );
              },
            ),
          if (pointsImage.isNotEmpty)
            IconButton(
              icon: Icon(editMode ? Icons.check : Icons.edit),
              tooltip: editMode ? "Düzenlemeyi bitir" : "Düzenle",
              onPressed: () => setState(() => editMode = !editMode),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadedImage == null
          ? const Center(child: Text("Üstteki yükle ikonuyla resim seçiniz"))
          : LayoutBuilder(
        builder: (context, constraints) {
          final fit = _fit(Size(constraints.maxWidth, constraints.maxHeight - 80)); // alt bar payı
          final imgW = loadedImage!.width.toDouble();
          final imgH = loadedImage!.height.toDouble();
          final drawW = imgW * fit.scale;
          final drawH = imgH * fit.scale;

          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  // İlk dikdörtgen seçimi (image space olarak tutulur)
                  onPanStart: (details) {
                    if (editMode) return; // editte dikdörtgenle işimiz yok
                    final pImg = _canvasToImage(details.localPosition, fit.scale, fit.offset);
                    if (pImg.dx < 0 || pImg.dy < 0 || pImg.dx > imgW || pImg.dy > imgH) return;
                    setState(() {
                      selectionRectImage = Rect.fromLTWH(pImg.dx, pImg.dy, 0, 0);
                      pointsImage.clear(); // yeni seçim, eski polygonu temizle
                    });
                  },
                  onPanUpdate: (details) {
                    if (editMode) return;
                    if (selectionRectImage == null) return;
                    final pImg = _canvasToImage(details.localPosition, fit.scale, fit.offset);
                    // clamp
                    final x = pImg.dx.clamp(0.0, imgW);
                    final y = pImg.dy.clamp(0.0, imgH);
                    final left = selectionRectImage!.left;
                    final top  = selectionRectImage!.top;
                    final w = (x - left);
                    final h = (y - top);
                    setState(() {
                      selectionRectImage = Rect.fromLTWH(
                        w >= 0 ? left : x,
                        h >= 0 ? top  : y,
                        w.abs(),
                        h.abs(),
                      );
                    });
                  },
                  child: Stack(
                    children: [
                      // Resim (BoxFit.contain ile elde edilen alan)
                      Positioned(
                        left: fit.offset.dx,
                        top: fit.offset.dy,
                        width: drawW,
                        height: drawH,
                        child: RawImage(image: loadedImage, fit: BoxFit.fill),
                      ),

                      // Seçim dikdörtgeni (yeşil hat İSTENMİYORSA bu kısmı kaldırabilirsin)
                      if (selectionRectImage != null && pointsImage.isEmpty)
                        Positioned(
                          left: fit.offset.dx + selectionRectImage!.left * fit.scale,
                          top:  fit.offset.dy + selectionRectImage!.top  * fit.scale,
                          width:  selectionRectImage!.width  * fit.scale,
                          height: selectionRectImage!.height * fit.scale,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue, width: 2),
                              color: Colors.blue.withOpacity(0.25),
                            ),
                          ),
                        ),

                      // Çokgen yeşil hat (her zaman image->canvas dönüşümüyle çizilir)
                      if (pointsImage.isNotEmpty && showOverlay)
                        Positioned(
                          left: fit.offset.dx,
                          top: fit.offset.dy,
                          width: drawW,
                          height: drawH,
                          child: CustomPaint(
                            painter: _PolygonPainter(
                              pointsImage,
                              fit.scale,
                            ),
                          ),
                        ),

                      // Düzenleme modunda kırmızı noktalar (canvas pozisyonunda)
                      if (editMode && pointsImage.isNotEmpty)
                        ...pointsImage.asMap().entries.map((e) {
                          final i = e.key;
                          final canvasPos = _imageToCanvas(e.value, fit.scale, fit.offset);
                          return Positioned(
                            left: canvasPos.dx - 10,
                            top:  canvasPos.dy - 10,
                            child: GestureDetector(
                              onPanUpdate: (d) {
                                setState(() {
                                  // delta canvas -> image
                                  final deltaImg = Offset(d.delta.dx / fit.scale, d.delta.dy / fit.scale);
                                  pointsImage[i] = _clampToImage(pointsImage[i] + deltaImg);
                                });
                              },
                              child: Container(
                                width: 20, height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),

              // Alt bar
              Container(
                height: 80,
                color: Colors.grey[900],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      tooltip: "Segment (seçili kutudan çokgen üret)",
                      onPressed: _segmentFromSelection,
                    ),
                    IconButton(
                      icon: Icon(showOverlay ? Icons.visibility : Icons.visibility_off, color: Colors.white),
                      tooltip: showOverlay ? "Örtüyü gizle" : "Örtüyü göster",
                      onPressed: () => setState(() => showOverlay = !showOverlay),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ----- Yeşil hat çizen CustomPainter -----
// points: image-space, painter içinde scale ile canvas'a taşınır.
class _PolygonPainter extends CustomPainter {
  final List<Offset> pointsImage;
  final double scale;

  _PolygonPainter(this.pointsImage, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (pointsImage.isEmpty) return;

    final path = Path();
    // image-space -> painter'ın local canvas space (0,0) zaten image'in sol-üstüne hizalı
    for (int i = 0; i < pointsImage.length; i++) {
      final p = pointsImage[i] * scale; // ölçekle
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PolygonPainter oldDelegate) {
    return oldDelegate.pointsImage != pointsImage || oldDelegate.scale != scale;
  }
}
