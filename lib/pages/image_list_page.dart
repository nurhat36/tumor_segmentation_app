import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'EditSegmentPage.dart';
import 'SegmentPage.dart';
import 'dart:async';
import 'dart:ui' as ui;

class ImageListPage extends StatefulWidget {
  final String token;
  final int patientId;
  final String patientName;

  const ImageListPage({
    super.key,
    required this.token,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<ImageListPage> createState() => _ImageListPageState();
}

class _ImageListPageState extends State<ImageListPage> {
  final ApiService apiService = ApiService();
  late Future<List<dynamic>> imagesFuture;

  int? selectedImageId;
  String? selectedImageUrl;
  bool isDeleting = false;

  final String baseUrl = "http://oncovisionai.com.tr/api";

  @override
  void initState() {
    super.initState();
    _refreshImages();
  }

  void _refreshImages() {
    setState(() {
      imagesFuture =
          apiService.getImagesByPatient(widget.token, widget.patientId);
    });
  }

  String normalizeUrl(dynamic value) {
    final raw = (value ?? '').toString().replaceAll("\\", "/");
    if (raw.startsWith("http")) return raw;
    final path = raw.startsWith("/") ? raw : "/$raw";
    return "$baseUrl$path";
  }

  dynamic _extractId(Map<String, dynamic> img) {
    return img['id'] ?? img['mask_id'];
  }

  Future<void> _deleteSelected() async {
    if (selectedImageId == null) return;

    setState(() => isDeleting = true);

    try {
      await apiService.deleteMask(widget.token, selectedImageId!);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mask silindi.")),
      );

      _refreshImages();

      setState(() {
        selectedImageId = null;
        selectedImageUrl = null;
      });

    } catch (e) {
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
        title: Text("${widget.patientName} - Maskeler"),
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
                  return Center(child: Text("Hata: ${snapshot.error}"));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text("Bu hastaya ait maske bulunamadı."));
                }

                final images = snapshot.data!;

                return GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final img =
                    (images[index] as Map).cast<String, dynamic>();

                    final imageId = _extractId(img);
                    final fullUrl = normalizeUrl(img['mask_url']);
                    final isSelected = selectedImageId == imageId;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedImageId = imageId;
                          selectedImageUrl = fullUrl;
                        });
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

          if (selectedImageId != null)
            Container(
              padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                    ElevatedButton.icon(
                      onPressed: isDeleting
                          ? null
                          : () async {
                        if (selectedImageUrl == null) return;

                        final networkImage =
                        NetworkImage(selectedImageUrl!);

                        final completer =
                        Completer<ui.Image>();

                        networkImage
                            .resolve(const ImageConfiguration())
                            .addListener(
                          ImageStreamListener((info, _) {
                            completer.complete(info.image);
                          }),
                        );

                        final uiImage =
                        await completer.future;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditSegmentPage(
                                  image: uiImage,
                                  initialContour: const [],
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
                      onPressed:
                      isDeleting ? null : _deleteSelected,
                      icon: isDeleting
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                          : const Icon(Icons.delete),
                      label: Text(
                          isDeleting ? "Siliniyor..." : "Sil"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      floatingActionButton: selectedImageId == null
          ? FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SegmentPage(
                token: widget.token,
                patientId: widget.patientId,
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