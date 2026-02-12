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

  // --- YENİ: Zoom ve Mod Kontrolü ---
  final TransformationController _transformationController = TransformationController();
  // True: Gezinme Modu (Zoom/Pan), False: Seçim Modu (Dikdörtgen Çizme)
  bool _isPanMode = true;

  // Seçim
  Rect? selectionRectImage;

  // API endpoint
  static const String baseUrl = "http://10.0.2.2:8000";

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

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
      // Yeni resim gelince zoom'u sıfırla
      _transformationController.value = Matrix4.identity();
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

      bool isWhite(int x, int y) {
        if (x < 0 || x >= width || y < 0 || y >= height) return false;
        final index = y * width + x;
        return pixels[index * 4] > 200;
      }

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

  // ----- API İstekleri -----
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
            currentMaskId = newMaskId;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Segmentasyon başarılı!")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata oluştu: ${response.statusCode}")),
        );
      }
    } catch (e) {
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
      final byteData = await maskImage!.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;
      final pngBytes = byteData.buffer.asUint8List();

      final uri = Uri.parse('$baseUrl/segment/$maskId');
      var request = http.MultipartRequest('PUT', uri);
      request.headers['Authorization'] = 'Bearer ${widget.token}';

      var multipartFile = http.MultipartFile.fromBytes(
        'file',
        pngBytes,
        filename: 'updated_mask.png',
      );
      request.files.add(multipartFile);

      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print("Bağlantı hatası: $e");
      return false;
    }
  }

  Future<void> _updateMaskFromPoints(List<Offset> newContours) async {
    if (loadedImage == null) return;
    final width = loadedImage!.width;
    final height = loadedImage!.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
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
      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final newMaskImage = await picture.toImage(width, height);
    setState(() {
      maskImage = newMaskImage;
      maskContours = [newContours];
    });
  }

  void _openEditPage() async {
    if (loadedImage == null || maskContours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Düzenlenecek bir maske yok.")),
      );
      return;
    }
    final List<Offset> pointsToEdit = List.from(maskContours[0]);
    final List<Offset>? editedPoints = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          image: loadedImage!,
          initialContour: pointsToEdit,
          maskId: currentMaskId ?? 0,
          token: widget.token,
        ),
      ),
    );
    if (editedPoints != null && editedPoints.isNotEmpty) {
      await _updateMaskFromPoints(editedPoints);
      if (currentMaskId != null) {
        bool success = await _uploadMaskToServer(currentMaskId!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(success ? "Kaydedildi" : "Sunucuya yüklenemedi")),
          );
        }
      }
    }
  }
  Future<bool> _createManualMaskOnServer() async {
    if (maskImage == null || selectedImage == null) return false;

    try {
      final byteData = await maskImage!.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;
      final pngBytes = byteData.buffer.asUint8List();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/segment/manual'),
      );

      request.headers['Authorization'] = 'Bearer ${widget.token}';

      // Orijinal resim
      request.files.add(
        await http.MultipartFile.fromPath(
          'original_file',
          selectedImage!.path,
        ),
      );

      // Maske
      request.files.add(
        http.MultipartFile.fromBytes(
          'mask_file',
          pngBytes,
          filename: 'manual_mask.png',
        ),
      );

      var response = await request.send();
      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final data = json.decode(responseBody.body);
        currentMaskId = data["mask_id"];   // 🔥 ÇOK ÖNEMLİ
        return true;
      }

      return false;
    } catch (e) {
      print("Create error: $e");
      return false;
    }
  }


  void _startManualDrawing() async {
    if (loadedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen önce bir resim seçin.")),
      );
      return;
    }
    final List<Offset>? manualPoints = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          image: loadedImage!,
          initialContour: [],
          maskId: currentMaskId ?? 0,
          token: widget.token,
        ),
      ),
    );
    if (manualPoints != null && manualPoints.isNotEmpty) {
      await _updateMaskFromPoints(manualPoints);

      bool success;

      if (currentMaskId == null) {
        // 🔥 İlk kez kaydediliyor → CREATE
        success = await _createManualMaskOnServer();
      } else {
        // 🔥 Var olan maskeyi güncelle → UPDATE
        success = await _uploadMaskToServer(currentMaskId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? "Kaydedildi" : "Sunucuya yüklenemedi")),
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
          // MOD DEĞİŞTİRME BUTONU (Pan vs Select)
          IconButton(
            icon: Icon(_isPanMode ? Icons.pan_tool : Icons.crop_free),
            tooltip: _isPanMode ? "Gezinme Modu (Seçim Yapılamaz)" : "Seçim Modu (Kaydırma Yapılamaz)",
            style: IconButton.styleFrom(
              backgroundColor: _isPanMode ? Colors.grey[800] : Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _isPanMode = !_isPanMode;
              });
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_isPanMode ? "Gezinme Modu: Yakınlaştır ve Kaydır" : "Seçim Modu: Dikdörtgen Çiz"),
                duration: const Duration(seconds: 1),
              ));
            },
          ),
          const SizedBox(width: 8),
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
          : Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Resmi ekrana sığdıran temel oranlar
                final double screenW = constraints.maxWidth;
                final double screenH = constraints.maxHeight;
                final fit = _fit(Size(screenW, screenH));

                // InteractiveViewer içeriğinin boyutu
                final double contentW = loadedImage!.width.toDouble() * fit.scale;
                final double contentH = loadedImage!.height.toDouble() * fit.scale;

                return Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    boundaryMargin: const EdgeInsets.all(500),
                    minScale: 0.1,
                    maxScale: 10.0,
                    // Seçim modundaysak Pan (Kaydırma) kapalı olsun ki çizim yapabilelim
                    panEnabled: _isPanMode,
                    scaleEnabled: true, // Zoom her zaman açık olabilir (iki parmakla)

                    child: SizedBox(
                      width: contentW,
                      height: contentH,
                      child: GestureDetector(
                        // --- SEÇİM (DİKDÖRTGEN ÇİZME) ---
                        // Sadece _isPanMode FALSE ise (yani Seçim Modu açıksa) çalışır.
                        onPanStart: !_isPanMode ? (details) {
                          // Koordinatı InteractiveViewer'ın içindeki local'e göre alıyoruz.
                          // Resim zaten fit edildiği için, bu koordinatı scale'e bölüp
                          // orijinal resim koordinatını buluyoruz.
                          final pImg = details.localPosition / fit.scale;

                          setState(() {
                            // Yeni seçime başla
                            selectionRectImage = Rect.fromLTWH(pImg.dx, pImg.dy, 0, 0);
                            // Eski maskeyi temizle
                            maskImage = null;
                            maskContours.clear();
                          });
                        } : null,

                        onPanUpdate: (!_isPanMode && selectionRectImage != null) ? (details) {
                          final pImg = details.localPosition / fit.scale;
                          final imgW = loadedImage!.width.toDouble();
                          final imgH = loadedImage!.height.toDouble();

                          final startX = selectionRectImage!.left;
                          final startY = selectionRectImage!.top;

                          // Anlık konumu sınırla
                          final currentX = pImg.dx.clamp(0.0, imgW);
                          final currentY = pImg.dy.clamp(0.0, imgH);

                          setState(() {
                            // Dikdörtgeni güncelle (Ters çekilirse de düzgün olsun diye Rect.fromPoints)
                            selectionRectImage = Rect.fromPoints(
                              Offset(startX, startY),
                              Offset(currentX, currentY),
                            );
                          });
                        } : null,

                        child: Stack(
                          children: [
                            // 1. Resim
                            Positioned.fill(
                              child: RawImage(
                                image: loadedImage,
                                fit: BoxFit.contain,
                              ),
                            ),

                            // 2. Maske Çizimi
                            if (maskContours.isNotEmpty && showMask)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _MaskOutlinePainter(
                                    maskContours,
                                    fit.scale, // InteractiveViewer içinde olduğumuz için fit.scale yeterli
                                  ),
                                ),
                              ),

                            // 3. Seçim Dikdörtgeni (Mavi Kutu)
                            if (selectionRectImage != null && maskImage == null)
                            // CustomPaint kullanarak çiziyoruz ki Positioned hesaplamalarıyla uğraşmayalım
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _SelectionPainter(
                                    rect: selectionRectImage!,
                                    scale: fit.scale,
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
          ),

          // ALT BAR
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
                IconButton(
                  icon: const Icon(Icons.gesture, color: Colors.orangeAccent),
                  tooltip: "Kendin Çiz",
                  onPressed: (loadedImage != null && !isSegmenting)
                      ? _startManualDrawing
                      : null,
                ),
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

          if (isSegmenting)
            Container(
              height: 40,
              color: Colors.black54,
              child: const Center(
                child: Text("Segmentasyon yapılıyor...", style: TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Maske Ressamı ---
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
      ..strokeWidth = 2.5 / 1.0 // Zoom'a göre incelmesini isterseniz buraya transformation scale eklemelisiniz ama şu an sabit kalsın.
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

      // Resim koordinatını ekrana çevir (scale ile çarp)
      path.moveTo(contour[0].dx * scale, contour[0].dy * scale);
      for (int i = 1; i < contour.length; i++) {
        path.lineTo(contour[i].dx * scale, contour[i].dy * scale);
      }
      path.close();
      canvas.drawPath(path, linePaint);

      for (int i = 0; i < contour.length; i++) {
        final point = contour[i] * scale;
        canvas.drawCircle(point, 2.5, dotPaint);
        canvas.drawCircle(point, 2.5, cornerDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskOutlinePainter oldDelegate) {
    return true;
  }
}

// --- Seçim Dikdörtgeni Ressamı ---
// Positioned kullanmak yerine Painter kullandık çünkü InteractiveViewer içinde
// Positioned hesaplamak kaymalara neden olabilir.
class _SelectionPainter extends CustomPainter {
  final Rect rect;
  final double scale;

  _SelectionPainter({required this.rect, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Resim koordinatındaki Rect'i ekrana uyarlıyoruz
    final screenRect = Rect.fromLTRB(
      rect.left * scale,
      rect.top * scale,
      rect.right * scale,
      rect.bottom * scale,
    );

    canvas.drawRect(screenRect, paint);
    canvas.drawRect(screenRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) {
    return oldDelegate.rect != rect || oldDelegate.scale != scale;
  }
}