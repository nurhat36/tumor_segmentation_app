import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';



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
  String? maskImagePath;
  final String baseUrl = "http://10.0.2.2:8000";


  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile =
    await picker.pickImage(source: ImageSource.gallery); // Galeriden seç
    if (pickedFile != null) {
      setState(() {
        selectedImage = File(pickedFile.path);
        maskImagePath = null; // Yeni seçim yapıldığında eski sonucu temizle
      });
    }
  }

  Future<void> sendToSegmentAPI() async {
    if (selectedImage == null) return;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/segment'),
    );

    request.headers['Authorization'] = 'Bearer ${widget.token}';
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
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: selectedImage != null ? sendToSegmentAPI : null,
            color: selectedImage != null ? Colors.white : Colors.grey,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selectedImage != null)
              Column(
                children: [
                  const Text("Seçilen Görsel"),
                  Image.file(selectedImage!, height: 200),
                ],
              ),
            if (maskImagePath != null) ...[
              const SizedBox(height: 20),
              const Text("Segment Sonucu"),
              Image.network(maskImagePath!, height: 200),
            ],
          ],
        ),
      ),
    );
  }
}
