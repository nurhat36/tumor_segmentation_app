import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// EditSegmentPage dosyanızın doğru import edildiğinden emin olun
import 'EditSegmentPage.dart';

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
  int? currentMaskId;

  // UI durumları
  bool isLoading = false;
  bool isSegmenting = false;
  bool showMask = true;
  ShapeType selectedShape = ShapeType.rectangle;

  // Seçim
  Rect? selectionRectImage;

  // API endpoint
  static const String baseUrl = "http://192.168.1.101:8000";

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

  // ----- Maskenin beyaz alanlarının konturlarını bul -----
  void _findSimplifiedContour() async {
    maskContours.clear();

    if (maskImage == null) return;

    try {
      final byteData = await maskImage!.toByteData();
      if (byteData == null) return;

      final width = maskImage!.width;
      final height = maskImage!.height;
      final pixels = byteData.buffer.asUint8List();

      final visited = List.generate(width * height, (_) => false);

      // Beyaz piksel olup olmadığını kontrol eden yardımcı fonksiyon
      bool isWhite(int x, int y) {
        if (x < 0 || x >= width || y < 0 || y >= height) return false;
        final index = y * width + x;
        return pixels[index * 4] > 200;
      }

      // Basit bir kontur takibi algoritması ile bir yol oluştur
      Offset? startPoint;
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

      while (i < maxIterations) {
        bool moved = false;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;

            final nextX = currentPoint.dx.round() + dx;
            final nextY = currentPoint.dy.round() + dy;
            final nextPoint = Offset(nextX.toDouble(), nextY.toDouble());

            if (isWhite(nextX, nextY) && !visited[nextY * width + nextX]) {
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

      final simplifiedContour = <Offset>[];
      final samplingRate = 50;
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

      request.fields.addAll({
        'x': selectionRectImage!.left.toString(),
        'y': selectionRectImage!.top.toString(),
        'width': selectionRectImage!.width.toString(),
        'height': selectionRectImage!.height.toString(),
        'shape': selectedShape.toString().split('.').last,
      });

      var response = await request.send();
      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final responseData = json.decode(responseBody.body);
        final maskUrl = responseData['mask_url'];
        final newMaskId = responseData['mask_id'];

        final maskResponse = await http.get(Uri.parse('$baseUrl$maskUrl'));

        if (maskResponse.statusCode == 200) {
          await loadMaskImage(maskResponse.bodyBytes);
          setState(() {
            currentMaskId = newMaskId; // ---> State güncelleniyor
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Segmentasyon başarılı!")),
          );
        }
      } else {
        print('HTTP Hatası: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata oluştu: ${response.statusCode}")),
        );
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



  Future<bool> _uploadMaskToServer(int maskId) async {
    if (maskImage == null) return false;

    try {
      // 1. ui.Image'ı PNG Byte verisine çeviriyoruz
      final byteData = await maskImage!.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;

      final pngBytes = byteData.buffer.asUint8List();

      // 2. İsteği Hazırla (Backend URL'ini buraya yaz)
      // Örnek: 'http://192.168.1.20:8000/segment/$maskId'
      final uri = Uri.parse('$baseUrl/segment/$maskId');

      var request = http.MultipartRequest('PUT', uri);

      // Eğer Token gerekiyorsa (Backend'de current_user var, muhtemelen gerekir):
      request.headers['Authorization'] = 'Bearer ${widget.token}';

      // 3. Dosyayı ekle (Backend'deki 'file' parametresiyle aynı isimde)
      var multipartFile = http.MultipartFile.fromBytes(
        'file',
        pngBytes,
        filename: 'updated_mask.png', // Uzantı önemli
      );

      request.files.add(multipartFile);

      // 4. Gönder ve sonucu bekle
      var response = await request.send();

      if (response.statusCode == 200) {
        print("Sunucuya başarıyla yüklendi.");
        return true;
      } else {
        print("Yükleme hatası: ${response.statusCode}");
        // Hata detayını görmek istersen:
        // final respStr = await response.stream.bytesToString();
        // print(respStr);
        return false;
      }
    } catch (e) {
      print("Bağlantı hatası: $e");
      return false;
    }
  }

  // ----- YENİ EKLENEN: Düzenleme sonrası maskeyi güncelle -----
  // (@override YOKTUR çünkü bu bizim yazdığımız özel bir fonksiyondur)
  Future<void> _updateMaskFromPoints(List<Offset> newContours) async {
    if (loadedImage == null) return;

    final width = loadedImage!.width;
    final height = loadedImage!.height;

    // 1. Bir Canvas açıp siyah zemin üzerine beyaz poligon çizeceğiz
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Arka planı siyah yap (Maske dışı)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.black,
    );

    if (newContours.isNotEmpty) {
      final path = Path();
      path.moveTo(newContours[0].dx, newContours[0].dy);
      for (int i = 1; i < newContours.length; i++) {
        path.lineTo(newContours[i].dx, newContours[i].dy);
      }
      path.close();

      // İçini beyaz doldur (Maske içi)
      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }

    // 2. Çizimi resme dönüştür
    final picture = recorder.endRecording();
    final newMaskImage = await picture.toImage(width, height);

    setState(() {
      maskImage = newMaskImage;
      // Tek bir konturumuz olduğu için listeyi güncelliyoruz
      maskContours = [newContours];
    });
  }

  // ----- YENİ EKLENEN: Düzenleme sayfasını aç -----
  // SegmentPage.dart içinde bu fonksiyonu güncelleyin:

  void _openEditPage() async {
    if (loadedImage == null || maskContours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Düzenlenecek bir maske yok.")),
      );
      return;
    }

    // --- DEĞİŞİKLİK BURADA: HİÇBİR FİLTRE YOK ---
    // Listeyi olduğu gibi, birebir kopyalayarak gönderiyoruz.
    // Segmentasyon sonucu neyse, düzenleme ekranı odur.
    final List<Offset> pointsToEdit = List.from(maskContours[0]);

    final List<Offset>? editedPoints = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          image: loadedImage!,
          initialContour: pointsToEdit,
          maskId: currentMaskId!,
          token: widget.token,
        ),
      ),
    );

    if (editedPoints != null && editedPoints.isNotEmpty) {
      // 1. Önce ekranı (lokal görüntüyü) güncelle
      await _updateMaskFromPoints(editedPoints);

      // 2. Güncellenen maskeyi sunucuya gönder (maskId'yi kendi değişkeninle değiştir)
      // Kullanıcıya bir "Yükleniyor..." göstergesi koymak iyi olabilir.
      bool success = await _uploadMaskToServer(currentMaskId!);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Maske güncellendi ve sunucuya kaydedildi!"),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Maske ekranda güncellendi fakat sunucuya atılamadı."),
            backgroundColor: Colors.red,
          ),
        );
      }
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

                        // --- DÜZENLEME BUTONU ---
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          tooltip: "Maskeyi Düzenle",
                          onPressed: (maskContours.isNotEmpty && !isSegmenting)
                              ? _openEditPage
                              : null,
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
// Bu sınıf artık temiz ve kendi içinde bağımsız
// SegmentPage.dart en altındaki class:

class _MaskOutlinePainter extends CustomPainter {
  final List<List<Offset>> contours;
  final double scale;

  _MaskOutlinePainter(this.contours, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;

    final linePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final cornerDotPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final contour in contours) {
      if (contour.length < 2) continue;

      final path = Path();
      final scaledContour = contour.map((point) => point * scale).toList();

      path.moveTo(scaledContour[0].dx, scaledContour[0].dy);
      for (int i = 1; i < scaledContour.length; i++) {
        path.lineTo(scaledContour[i].dx, scaledContour[i].dy);
      }
      if (scaledContour.length > 2) {
        path.lineTo(scaledContour[0].dx, scaledContour[0].dy);
      }
      canvas.drawPath(path, linePaint);

      // --- NOKTALARI ÇİZ ---
      // HİÇBİR NOKTAYI ATLAMIYORUZ (i++)
      for (int i = 0; i < scaledContour.length; i++) {
        final point = scaledContour[i];

        // Edit sayfasıyla tutarlı boyutlar (Çap ~10-12)
        canvas.drawCircle(point, 5.0, dotPaint);
        canvas.drawCircle(point, 5.0, cornerDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskOutlinePainter oldDelegate) {
    return oldDelegate.contours != contours || oldDelegate.scale != scale;
  }
}