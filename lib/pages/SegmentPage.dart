import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;

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
  String? maskImagePath;
  final String baseUrl = "http://10.0.2.2:8000";

  ShapeType selectedShape = ShapeType.rectangle;
  Rect? selectionRect;
  bool isLoading = false;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        isLoading = true;
        selectedImage = File(pickedFile.path);
        selectionRect = null;
        maskImagePath = null;
      });

      // Orijinal resim boyutunu yükle
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

    // BoxFit.contain hesaplama
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

    // Ekran koordinatlarını orijinal resme çevir
    double x = (selectionRect!.left - dx) / scale;
    double y = (selectionRect!.top - dy) / scale;
    double width = selectionRect!.width / scale;
    double height = selectionRect!.height / scale;

    // Koordinatların resmin sınırlarını aşmasını engelle
    x = x.clamp(0, loadedImage!.width.toDouble());
    y = y.clamp(0, loadedImage!.height.toDouble());
    width = width.clamp(0, loadedImage!.width.toDouble() - x);
    height = height.clamp(0, loadedImage!.height.toDouble() - y);

    // Eğer width veya height 0 ise işlem yapma
    if (width <= 0 || height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Geçersiz seçim alanı")),
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
        setState(() {
          maskImagePath = maskUrl;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Segment işlemi başarısız: ${response.statusCode}")),
        );
      }
    } catch (e) {
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
                            child: Image.file(selectedImage!),
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
                              border: Border.all(
                                  color: Colors.blue, width: 2),
                              color: Colors.blue.withOpacity(0.3),
                              borderRadius: selectedShape ==
                                  ShapeType.rectangle
                                  ? null
                                  : BorderRadius.circular(
                                  selectionRect!.shortestSide),
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
                  icon: const Icon(Icons.crop_square,
                      color: Colors.white),
                  onPressed: () => setState(
                          () => selectedShape = ShapeType.rectangle),
                ),
                IconButton(
                  icon:
                  const Icon(Icons.circle, color: Colors.white),
                  onPressed: () =>
                      setState(() => selectedShape = ShapeType.circle),
                ),
                IconButton(
                  icon: const Icon(Icons.circle_outlined,
                      color: Colors.white),
                  onPressed: () =>
                      setState(() => selectedShape = ShapeType.oval),
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow,
                      color: Colors.white),
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
          if (maskImagePath != null)
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  const Text("Segment Sonucu"),
                  Expanded(
                    child: Image.network(
                      maskImagePath!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}