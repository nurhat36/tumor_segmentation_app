import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

enum ShapeType { rectangle, circle, oval }

class SegmentPage extends StatefulWidget {
  final String token;
  final int userId;

  const SegmentPage({
    Key? key,
    required this.token,
    required this.userId,
  }) : super(key: key);

  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  File? selectedImage;
  ui.Image? loadedImage;
  ui.Image? overlayImage;
  final String baseUrl = "http://10.0.2.2:8000";

  ShapeType selectedShape = ShapeType.rectangle;
  Rect? selectionRect;
  bool isLoading = false;
  bool showOverlay = true;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        isLoading = true;
        selectedImage = File(pickedFile.path);
        selectionRect = null;
        overlayImage = null;
      });

      final data = await pickedFile.readAsBytes();
      final image = await decodeImageFromList(data);
      setState(() {
        loadedImage = image;
        isLoading = false;
      });
    }
  }

  Map<String, double> _calculateScale(Size containerSize) {
    if (loadedImage == null) return {"scale": 1.0, "dx": 0, "dy": 0};

    double imgWidth = loadedImage!.width.toDouble();
    double imgHeight = loadedImage!.height.toDouble();
    double containerWidth = containerSize.width;
    double containerHeight = containerSize.height;

    double scale = 1.0;
    double dx = 0;
    double dy = 0;

    if (imgWidth / imgHeight > containerWidth / containerHeight) {
      scale = containerWidth / imgWidth;
      dy = (containerHeight - imgHeight * scale) / 2;
    } else {
      scale = containerHeight / imgHeight;
      dx = (containerWidth - imgWidth * scale) / 2;
    }

    return {
      "scale": scale,
      "dx": dx,
      "dy": dy,
    };
  }

  Future<ui.Image> loadNetworkImage(String path) async {
    final response = await http.get(Uri.parse(path));
    final bytes = response.bodyBytes;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<ui.Image> createSimpleOverlay(ui.Image originalImage, ui.Image mask) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    // Önce orijinal resmi çiz
    canvas.drawImage(originalImage, Offset.zero, paint);

    // Maskeyi çiz (yarı saydam kırmızı)
    paint.color = Colors.red.withOpacity(0.3);
    paint.blendMode = BlendMode.srcOver;
    canvas.drawImage(mask, Offset.zero, paint);

    // Yeşil kenar çizgisi - basit versiyon
    paint.color = Colors.green;
    paint.strokeWidth = 3;
    paint.style = PaintingStyle.stroke;

    // Maskenin dış çerçevesini çiz
    canvas.drawRect(
        Rect.fromPoints(
            Offset.zero,
            Offset(mask.width.toDouble(), mask.height.toDouble())
        ),
        paint
    );

    final picture = recorder.endRecording();
    return await picture.toImage(originalImage.width, originalImage.height);
  }

  Future<void> sendToSegmentAPI(Size containerSize) async {
    if (selectedImage == null || selectionRect == null || loadedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen bir resim seçin ve alan belirleyin")),
      );
      return;
    }

    var scaleData = _calculateScale(containerSize);
    double scale = scaleData["scale"]!;
    double dx = scaleData["dx"]!;
    double dy = scaleData["dy"]!;

    double x = (selectionRect!.left - dx) / scale;
    double y = (selectionRect!.top - dy) / scale;
    double width = selectionRect!.width / scale;
    double height = selectionRect!.height / scale;

    x = x.clamp(0, loadedImage!.width.toDouble());
    y = y.clamp(0, loadedImage!.height.toDouble());
    width = width.clamp(0, loadedImage!.width.toDouble() - x);
    height = height.clamp(0, loadedImage!.height.toDouble() - y);

    if (width <= 0 || height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Geçersiz seçim alanı.")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment'));
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.fields['shape'] = selectedShape.toString().split('.').last;
      request.fields['x'] = x.toString();
      request.fields['y'] = y.toString();
      request.fields['width'] = width.toString();
      request.fields['height'] = height.toString();
      request.files.add(await http.MultipartFile.fromPath('file', selectedImage!.path));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var jsonData = json.decode(responseData);
        String maskUrl = baseUrl + jsonData['mask_url'];
        print("Mask URL: $maskUrl");

        // Maskeyi yükle
        final mask = await loadNetworkImage(maskUrl);
        print("Mask yüklendi: ${mask.width}x${mask.height}");

        // Basit overlay oluştur
        try {
          final overlay = await createSimpleOverlay(loadedImage!, mask);
          print("Overlay oluşturuldu");

          setState(() {
            overlayImage = overlay;
          });
        } catch (e) {
          print("Overlay oluşturma hatası: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Overlay oluşturulamadı: $e")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Segment işlemi başarısız: ${response.statusCode}")),
        );
      }
    } catch (e) {
      print("API hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata oluştu: ${e.toString()}")),
      );
    } finally {
      setState(() {
        isLoading = false;
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
          if (overlayImage != null)
            IconButton(
              icon: Icon(
                showOverlay ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  showOverlay = !showOverlay;
                });
              },
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : selectedImage == null
          ? const Center(child: Text("Resim seçiniz"))
          : Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (details) {
                    final localPos = details.localPosition;
                    setState(() {
                      selectionRect = Rect.fromLTWH(
                          localPos.dx, localPos.dy, 0, 0);
                    });
                  },
                  onPanUpdate: (details) {
                    final localPos = details.localPosition;
                    setState(() {
                      final left = selectionRect!.left;
                      final top = selectionRect!.top;
                      final width = localPos.dx - left;
                      final height = localPos.dy - top;
                      selectionRect = Rect.fromLTWH(
                        width >= 0 ? left : localPos.dx,
                        height >= 0 ? top : localPos.dy,
                        width.abs(),
                        height.abs(),
                      );
                    });
                  },
                  child: Stack(
                    children: [
                      Center(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: loadedImage?.width.toDouble(),
                            height: loadedImage?.height.toDouble(),
                            child: showOverlay && overlayImage != null
                                ? RawImage(image: overlayImage)
                                : Image.file(selectedImage!),
                          ),
                        ),
                      ),
                      if (selectionRect != null)
                        Positioned(
                          left: selectionRect!.left,
                          top: selectionRect!.top,
                          child: Container(
                            width: selectionRect!.width,
                            height: selectionRect!.height,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue, width: 2),
                              color: Colors.blue.withOpacity(0.3),
                              borderRadius: selectedShape == ShapeType.rectangle
                                  ? null
                                  : BorderRadius.circular(selectionRect!.shortestSide),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            height: 80,
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(Icons.crop_square,
                      color: selectedShape == ShapeType.rectangle ? Colors.blue : Colors.white),
                  onPressed: () => setState(() => selectedShape = ShapeType.rectangle),
                ),
                IconButton(
                  icon: Icon(Icons.circle,
                      color: selectedShape == ShapeType.circle ? Colors.blue : Colors.white),
                  onPressed: () => setState(() => selectedShape = ShapeType.circle),
                ),
                IconButton(
                  icon: Icon(Icons.circle_outlined,
                      color: selectedShape == ShapeType.oval ? Colors.blue : Colors.white),
                  onPressed: () => setState(() => selectedShape = ShapeType.oval),
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  onPressed: () {
                    if (selectionRect != null) {
                      final size = MediaQuery.of(context).size;
                      sendToSegmentAPI(size);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}