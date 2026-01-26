import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'EditSegmentPage.dart';
import 'SegmentPage.dart';
import 'dart:async';  // Completer için
import 'dart:ui' as ui;  // ui.Image için


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

  int? selectedImageId;       // seçilen resmin ID’si
  String? selectedImageUrl;   // seçilen resmin URL’i
  bool isDeleting = false;

  final String baseUrl = "http://10.0.2.2:8000";

  @override
  void initState() {
    super.initState();
    _refreshImages();
  }

  void _refreshImages() {
    setState(() {
      imagesFuture = apiService.getSegmentedImages(widget.token);
    });
    debugPrint("Yenileme isteği atıldı.");
  }

  String normalizeUrl(dynamic value) {
    final raw = (value ?? '').toString().replaceAll("\\", "/");
    if (raw.startsWith("http")) return raw;
    final path = raw.startsWith("/") ? raw : "/$raw";
    return "$baseUrl$path";
  }

  dynamic _extractId(Map<String, dynamic> img) {
    return img['id'] ?? img['mask_id'] ?? img['maskId'] ?? img['maskID'];
  }

  Future<void> _deleteSelected() async {
    if (selectedImageId == null) return;
    setState(() => isDeleting = true);
    try {
      debugPrint("Silinecek ID: $selectedImageId");
      await apiService.deleteSegmentedImage(widget.token, selectedImageId!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Resim silindi.")),
      );
      _refreshImages();
      setState(() {
        selectedImageId = null;
        selectedImageUrl = null;
      });
    } catch (e) {
      debugPrint("Silme hatası (UI): $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Silme hatası: $e")),
      );
    } finally {
      setState(() => isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Segmente Edilmiş Görseller"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshImages,
          ),
        ],
      ),
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
                  debugPrint("FutureBuilder hata: ${snapshot.error}");
                  return Center(child: Text("Hata: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  debugPrint("API boş liste döndü.");
                  return const Center(child: Text("Hiç görsel bulunamadı."));
                }

                final images = snapshot.data!;
                debugPrint("Toplam kayıt: ${images.length}");

                return GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final img = (images[index] as Map).cast<String, dynamic>();
                    final imageId = _extractId(img);
                    final fullUrl = normalizeUrl(
                        img['mask_url'] ?? img['maskUrl'] ?? img['url']);

                    if (imageId == null) {
                      debugPrint(
                          "Uyarı: Kayıtta ID alanı yok. Keys: ${img.keys.toList()}");
                    }
                    if ((img['mask_url'] ?? img['maskUrl'] ?? img['url']) ==
                        null) {
                      debugPrint(
                          "Uyarı: Kayıtta URL alanı yok. Keys: ${img.keys.toList()}");
                    }

                    final isSelected = selectedImageId == imageId;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedImageId = imageId;
                          selectedImageUrl = fullUrl;
                        });
                        debugPrint("Seçilen ID: $imageId");
                        debugPrint("Seçilen URL: $fullUrl");
                      },
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: isSelected
                                  ? Border.all(color: Colors.blue, width: 4)
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                fullUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image, size: 50),
                              ),
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.check,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Altta eylem barı
          if (selectedImageId != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              color: Colors.grey[900],
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Seçilen ID: $selectedImageId",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: isDeleting
                          ? null
                          : () async {
                        if (selectedImageUrl == null) return;

                        // Flutter'ın ui.Image tipine dönüştürmek için
                        final networkImage = NetworkImage(selectedImageUrl!);
                        final completer = Completer<ui.Image>();
                        networkImage.resolve(const ImageConfiguration()).addListener(
                          ImageStreamListener((info, _) {
                            completer.complete(info.image);
                          }),
                        );
                        final uiImage = await completer.future;

                        // Örnek: initialContour boş liste olabilir (henüz düzenleme yapılmadıysa)
                        final initialContour = <Offset>[];

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditSegmentPage(
                              image: uiImage,
                              initialContour: initialContour,
                              maskId: selectedImageId!,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text("Düzenle"),
                    ),

                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: isDeleting ? null : _deleteSelected,
                      icon: isDeleting
                          ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete),
                      label: Text(isDeleting ? "Siliniyor..." : "Sil"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: selectedImageId == null
          ? FloatingActionButton(
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
      )
          : null,
    );
  }
}
