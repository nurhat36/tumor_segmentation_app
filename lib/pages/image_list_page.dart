import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ImageListPage extends StatefulWidget {
  final String token;
  final String userId;

  const ImageListPage({super.key, required this.token, required this.userId});

  @override
  State<ImageListPage> createState() => _ImageListPageState();
}

class _ImageListPageState extends State<ImageListPage> {
  final ApiService apiService = ApiService();
  late Future<List<dynamic>> imagesFuture;

  @override
  void initState() {
    super.initState();
    imagesFuture = apiService.getSegmentedImages(widget.token, widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Segmente Edilmiş Görseller")),
      body: FutureBuilder<List<dynamic>>(
        future: imagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Hata: ${snapshot.error}"));
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
              return Image.network(
                img['image_url'], // API’nin döndüğü URL
                fit: BoxFit.cover,
              );
            },
          );
        },
      ),
    );
  }
}
