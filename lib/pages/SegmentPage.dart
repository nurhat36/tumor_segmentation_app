import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

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
  ui.Image? maskImage;
  List<List<Offset>> maskContours = [];

  // UI durumları
  bool isLoading = false;
  bool isSegmenting = false;
  bool showMask = true;
  ShapeType selectedShape = ShapeType.rectangle;

  // Seçim
  Rect? selectionRectImage;

  // API endpoint
  static const String baseUrl = "http://10.0.2.2:8000";

  // ----- Görsel yükleme -----
  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      isLoading = true;
      selectedImage = File(picked.path);
      selectionRectImage = null;
      maskImage = null;
      maskContours.clear();
    });

    final bytes = await picked.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    setState(() {
      loadedImage = frame.image;
      isLoading = false;
    });
  }

  // ----- Maskeyi yükle ve konturları bul -----
  Future<void> loadMaskImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    setState(() {
      maskImage = frame.image;
      _findSimplifiedContour();
    });
  }

  // ----- Maskenin beyaz alanlarının konturlarını bul (Geliştirilmiş versiyon) -----
  void _findSimplifiedContour() async {
    maskContours.clear();

    if (maskImage == null) return;

    try {
      final byteData = await maskImage!.toByteData();
      if (byteData == null) return;

      final width = maskImage!.width;
      final height = maskImage!.height;
      final pixels = byteData.buffer.asUint8List();

      final edgePoints = <Offset>{};
      final visited = List.generate(width * height, (_) => false);

      // Beyaz piksel olup olmadığını kontrol eden yardımcı fonksiyon
      bool isWhite(int x, int y) {
        if (x < 0 || x >= width || y < 0 || y >= height) return false;
        final index = y * width + x;
        return pixels[index * 4] > 200;
      }

      // Basit bir kontur takibi algoritması ile bir yol oluştur
      Offset? startPoint;
      // Başlangıç noktasını bul
      for (int y = 0; y < height && startPoint == null; y++) {
        for (int x = 0; x < width && startPoint == null; x++) {
          if (isWhite(x, y)) {
            startPoint = Offset(x.toDouble(), y.toDouble());
          }
        }
      }

      if (startPoint == null) return;

      final currentPath = <Offset>[startPoint];
      Offset currentPoint = startPoint;
      int maxIterations = width * height * 2;
      int i = 0;

      // "Marching Squares" benzeri basit bir yol takibi
      while (i < maxIterations) {
        bool moved = false;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;

            final nextX = currentPoint.dx.round() + dx;
            final nextY = currentPoint.dy.round() + dy;
            final nextPoint = Offset(nextX.toDouble(), nextY.toDouble());

            // Beyaz bir komşu piksel ve henüz ziyaret edilmemiş mi?
            if (isWhite(nextX, nextY) && !visited[nextY * width + nextX]) {
              // Kenarda mı kontrol et
              bool isEdge = false;
              for (int ndy = -1; ndy <= 1; ndy++) {
                for (int ndx = -1; ndx <= 1; ndx++) {
                  if (ndx == 0 && ndy == 0) continue;
                  if (!isWhite(nextX + ndx, nextY + ndy)) {
                    isEdge = true;
                    break;
                  }
                }
                if (isEdge) break;
              }

              if (isEdge) {
                currentPoint = nextPoint;
                currentPath.add(currentPoint);
                visited[currentPoint.dy.round() * width + currentPoint.dx.round()] = true;
                moved = true;
                break;
              }
            }
          }
          if (moved) break;
        }
        if (!moved) break;
        i++;
      }

      // Konturu basitleştir - her N noktada bir nokta al
      final simplifiedContour = <Offset>[];
      final samplingRate = 20; // Bu değeri deneyerek istediğiniz sıklığı bulun
      for (int i = 0; i < currentPath.length; i += samplingRate) {
        simplifiedContour.add(currentPath[i]);
      }
      if (simplifiedContour.isNotEmpty && currentPath.isNotEmpty && !simplifiedContour.contains(currentPath.last)) {
        simplifiedContour.add(currentPath.last);
      }

      if (simplifiedContour.isNotEmpty) {
        maskContours = [simplifiedContour];
      }

      setState(() {});
    } catch (e) {
      print('Kontur bulma hatası: $e');
    }
  }

  // ----- Layout hesaplamaları -----
  ({double scale, Offset offset}) _fit(Size box) {
    final w = loadedImage!.width.toDouble();
    final h = loadedImage!.height.toDouble();
    final s = math.min(box.width / w, box.height / h);
    final dx = (box.width - w * s) / 2.0;
    final dy = (box.height - h * s) / 2.0;
    return (scale: s, offset: Offset(dx, dy));
  }

  Offset _canvasToImage(Offset canvasPos, double scale, Offset off) {
    return Offset((canvasPos.dx - off.dx) / scale, (canvasPos.dy - off.dy) / scale);
  }

  // ----- API'ye segment isteği gönder -----
  Future<void> _sendSegmentRequest() async {
    if (selectionRectImage == null || selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Önce bir alan seçin ve resim yükleyin.")),
      );
      return;
    }

    setState(() {
      isSegmenting = true;
      maskImage = null;
      maskContours.clear();
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment'));
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(await http.MultipartFile.fromPath('file', selectedImage!.path));

      // FLOAT değerleri string olarak gönder (FastAPI otomatik convert eder)
      request.fields.addAll({
        'x': selectionRectImage!.left.toString(),       // String -> float
        'y': selectionRectImage!.top.toString(),        // String -> float
        'width': selectionRectImage!.width.toString(),  // String -> float
        'height': selectionRectImage!.height.toString(),// String -> float
        'shape': selectedShape.toString().split('.').last, // String
      });


      var response = await request.send();
      final responseBody = await http.Response.fromStream(response);
      // İstekten önce parametreleri kontrol et
      print('Gönderilen parametreler:');
      print('x: ${selectionRectImage!.left}');
      print('y: ${selectionRectImage!.top}');
      print('width: ${selectionRectImage!.width}');
      print('height: ${selectionRectImage!.height}');
      print('shape: ${selectedShape.toString().split('.').last}');

// Response'u daha detaylı logla
      if (response.statusCode != 200) {
        print('API Hatası: ${response.statusCode}');
        print('Response: ${responseBody.body}');
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(responseBody.body);
        final maskUrl = responseData['mask_url'];

        final maskResponse = await http.get(Uri.parse('$baseUrl$maskUrl'));

        if (maskResponse.statusCode == 200) {
          await loadMaskImage(maskResponse.bodyBytes);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Segmentasyon başarılı!")),
          );
        }
      } else {
        // HTTP hata kodlarını kontrol et
        print('HTTP Hatası: ${response.statusCode}');
        print('Response Body: ${responseBody.body}');
      }
    } catch (e) {
      print('İstek Hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: $e")),
      );
    } finally {
      setState(() {
        isSegmenting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Segment İşlemi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: pickImage,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadedImage == null
          ? const Center(child: Text("Resim seçiniz"))
          : Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final fit = _fit(Size(constraints.maxWidth, constraints.maxHeight - 80));
              final imgW = loadedImage!.width.toDouble();
              final imgH = loadedImage!.height.toDouble();

              return Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onPanStart: (details) {
                        final pImg = _canvasToImage(details.localPosition, fit.scale, fit.offset);
                        if (pImg.dx < 0 || pImg.dy < 0 || pImg.dx > imgW || pImg.dy > imgH) return;
                        setState(() {
                          selectionRectImage = Rect.fromLTWH(pImg.dx, pImg.dy, 0, 0);
                          maskImage = null;
                          maskContours.clear();
                        });
                      },
                      onPanUpdate: (details) {
                        if (selectionRectImage == null) return;
                        final pImg = _canvasToImage(details.localPosition, fit.scale, fit.offset);
                        final x = pImg.dx.clamp(0.0, imgW);
                        final y = pImg.dy.clamp(0.0, imgH);
                        final left = selectionRectImage!.left;
                        final top = selectionRectImage!.top;
                        final w = (x - left);
                        final h = (y - top);
                        setState(() {
                          selectionRectImage = Rect.fromLTWH(
                            w >= 0 ? left : x,
                            h >= 0 ? top : y,
                            w.abs(),
                            h.abs(),
                          );
                        });
                      },
                      child: Stack(
                        children: [
                          // Orijinal resim
                          Positioned(
                            left: fit.offset.dx,
                            top: fit.offset.dy,
                            width: imgW * fit.scale,
                            height: imgH * fit.scale,
                            child: RawImage(
                              image: loadedImage,
                              fit: BoxFit.fill,
                            ),
                          ),

                          // Maskenin konturlarını çiz (SADECE KENARLAR)
                          if (maskContours.isNotEmpty && showMask)
                            Positioned(
                              left: fit.offset.dx,
                              top: fit.offset.dy,
                              width: imgW * fit.scale,
                              height: imgH * fit.scale,
                              child: CustomPaint(
                                painter: _MaskOutlinePainter(
                                  maskContours,
                                  fit.scale,
                                ),
                              ),
                            ),

                          // Seçim dikdörtgeni
                          if (selectionRectImage != null && maskImage == null)
                            Positioned(
                              left: fit.offset.dx + selectionRectImage!.left * fit.scale,
                              top: fit.offset.dy + selectionRectImage!.top * fit.scale,
                              width: selectionRectImage!.width * fit.scale,
                              height: selectionRectImage!.height * fit.scale,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.blue, width: 2),
                                  color: Colors.blue.withOpacity(0.25),
                                ),
                              ),
                            ),
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
                          icon: isSegmenting
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Icon(Icons.play_arrow, color: Colors.white),
                          onPressed: isSegmenting ? null : _sendSegmentRequest,
                        ),
                        IconButton(
                          icon: Icon(
                            showMask ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white,
                          ),
                          onPressed: () => setState(() => showMask = !showMask),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          if (isSegmenting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Segmentasyon yapılıyor...", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ----- SADECE KENAR ÇİZGİLERİ ve NOKTALARI çizen CustomPainter -----
class _MaskOutlinePainter extends CustomPainter {
  final List<List<Offset>> contours;
  final double scale;

  _MaskOutlinePainter(this.contours, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;

    // Çizgi paint - mavi sürekli çizgi
    final linePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Nokta paint - kırmızı dolgulu noktalar
    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..strokeWidth=0.1;


    // Köşe noktası paint - yeşil dış çizgili noktalar
    final cornerDotPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.1;

    for (final contour in contours) {
      if (contour.length < 2) continue;

      final path = Path();
      final scaledContour = contour.map((point) => point * scale).toList();

      // Sürekli çizgi çiz
      path.moveTo(scaledContour[0].dx, scaledContour[0].dy);
      for (int i = 1; i < scaledContour.length; i++) {
        path.lineTo(scaledContour[i].dx, scaledContour[i].dy);
      }

      // Çizgiyi kapat (opsiyonel)
      if (scaledContour.length > 2) {
        path.lineTo(scaledContour[0].dx, scaledContour[0].dy);
      }

      // Çizgiyi çiz
      canvas.drawPath(path, linePaint);

      // Köşe noktalarını çiz (her 5 noktada bir)
      for (int i = 0; i < scaledContour.length; i += 5) {
        if (i < scaledContour.length) {
          final point = scaledContour[i];

          // Kırmızı iç dolgu
          canvas.drawCircle(point, 6.0, dotPaint);
          // Yeşil dış çerçeve
          canvas.drawCircle(point, 6.0, cornerDotPaint);
        }
      }

      // Başlangıç ve bitiş noktalarını özel işaretle
      if (scaledContour.isNotEmpty) {
        final firstPoint = scaledContour[0];
        final lastPoint = scaledContour[scaledContour.length - 1];

        // Büyük kırmızı noktalar
        canvas.drawCircle(firstPoint, 8.0, dotPaint);
        canvas.drawCircle(lastPoint, 8.0, dotPaint);
        // Yeşil çerçeveler
        canvas.drawCircle(firstPoint, 8.0, cornerDotPaint);
        canvas.drawCircle(lastPoint, 8.0, cornerDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskOutlinePainter oldDelegate) {
    return oldDelegate.contours != contours || oldDelegate.scale != scale;
  }
}