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

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      selectedImage = File(pickedFile.path);
      selectionRect = null;
      maskImagePath = null;

      // Load image for original dimensions
      final data = await pickedFile.readAsBytes();
      final image = await decodeImageFromList(data);
      setState(() {
        loadedImage = image;
      });
    }
  }

  Future<void> sendToSegmentAPI(BoxConstraints constraints) async {
    if (selectedImage == null || selectionRect == null || loadedImage == null) return;

    // Ekrandaki boyuta göre orijinal resme ölçekle
    double scaleX = loadedImage!.width / constraints.maxWidth;
    double scaleY = loadedImage!.height / constraints.maxHeight;

    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment'));
    request.headers['Authorization'] = 'Bearer ${widget.token}';
    request.fields['shape'] = selectedShape.toString().split('.').last;
    request.fields['x'] = (selectionRect!.left * scaleX).toInt().toString();
    request.fields['y'] = (selectionRect!.top * scaleY).toInt().toString();
    request.fields['width'] = (selectionRect!.width * scaleX).toInt().toString();
    request.fields['height'] = (selectionRect!.height * scaleY).toInt().toString();
    request.files.add(await http.MultipartFile.fromPath('file', selectedImage!.path));

    var response = await request.send();

    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
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
      body: selectedImage == null
          ? const Center(child: Text("Resim seçiniz"))
          : LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onPanStart: (details) {
                    final localPos = details.localPosition;
                    setState(() {
                      selectionRect = Rect.fromLTWH(localPos.dx, localPos.dy, 0, 0);
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
                      Image.file(
                        selectedImage!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                      if (selectionRect != null)
                        CustomPaint(
                          painter: SelectionPainter(selectionRect!, selectedShape),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 80,
                color: Colors.grey[900],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.crop_square, color: Colors.white),
                      onPressed: () => setState(() => selectedShape = ShapeType.rectangle),
                    ),
                    IconButton(
                      icon: const Icon(Icons.circle, color: Colors.white),
                      onPressed: () => setState(() => selectedShape = ShapeType.circle),
                    ),
                    IconButton(
                      icon: const Icon(Icons.circle_outlined, color: Colors.white),
                      onPressed: () => setState(() => selectedShape = ShapeType.oval),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      onPressed: (selectionRect != null)
                          ? () => sendToSegmentAPI(constraints)
                          : null,
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
                      Expanded(child: Image.network(maskImagePath!)),
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

class SelectionPainter extends CustomPainter {
  final Rect rect;
  final ShapeType shape;

  SelectionPainter(this.rect, this.shape);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    switch (shape) {
      case ShapeType.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case ShapeType.circle:
      case ShapeType.oval:
        canvas.drawOval(rect, paint);
        break;
    }

    final border = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    switch (shape) {
      case ShapeType.rectangle:
        canvas.drawRect(rect, border);
        break;
      case ShapeType.circle:
      case ShapeType.oval:
        canvas.drawOval(rect, border);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
