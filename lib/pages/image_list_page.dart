import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'SegmentPage.dart';


class ImageListPage extends StatefulWidget {
  final String token;
  final int userId;

  const ImageListPage({super.key, required this.token, required this.userId});

  @override
  State<ImageListPage> createState() => _ImageListPageState();
}

class _ImageListPageState extends State<ImageListPage> {
  final ApiService apiService = ApiService();
  late Future<List<dynamic>> imagesFuture;

  String? selectedImageUrl; // Tıklanan resmin tam yolu
  final String baseUrl = "http://10.0.2.2:8000";

  @override
  void initState() {
    super.initState();
    imagesFuture = apiService.getSegmentedImages(widget.token);
  }

  String formatImagePath(String path) {
    // \ karakterlerini / yap ve baseUrl ekle
    String fixedPath = path.replaceAll("\\", "/");
    return "$baseUrl$fixedPath";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Segmente Edilmiş Görseller")),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: imagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Hata: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Hiç görsel bulunamadı."));
                }

                final images = snapshot.data!;

                return GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final img = images[index];
                    String fullUrl = formatImagePath(img['mask_url']);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedImageUrl = fullUrl; // Tam URL’yi seç
                        });
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          fullUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image, size: 50),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (selectedImageUrl != null)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black87,
              width: double.infinity,
              child: Text(
                selectedImageUrl!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),

      // Sağ alt köşede + simgesi
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SegmentPage(
                token: widget.token,
                userId: widget.userId,
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),

    );
  }
}
