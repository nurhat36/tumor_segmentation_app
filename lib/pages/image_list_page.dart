import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data'; // Uint8List için gerekli
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import 'EditSegmentPage.dart';
import 'SegmentPage.dart';

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
  late Future<List<dynamic>> filesFuture;

  final String baseUrl = "http://oncovisionai.com.tr/api";

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  void _refreshFiles() {
    setState(() {
      filesFuture = apiService.getPatientFiles(widget.token, widget.patientId);
    });
  }

  String normalizeUrl(dynamic value) {
    if (value == null) return "";
    final raw = value.toString().replaceAll("\\", "/");
    if (raw.startsWith("http")) return raw;
    final path = raw.startsWith("/") ? raw : "/$raw";
    return "http://oncovisionai.com.tr$path";
  }

  // ========================================================
  // DOSYAYI KOMPLE SİLME (Ana dosya ve maskeleri)
  // ========================================================
  Future<void> _confirmDeleteFile(int fileId, String filename) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Kalıcı Olarak Sil?", style: TextStyle(color: Colors.white)),
        content: Text(
          "'$filename' dosyası ve ona ait TÜM YAPAY ZEKA MASKELERİ tamamen silinecek. Onaylıyor musunuz?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("İptal", style: TextStyle(color: Colors.white54))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      try {
        await apiService.deleteFile(widget.token, fileId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dosya başarıyla silindi.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _refreshFiles();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Silme hatası: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // ========================================================
  // DÜZENLEME SAYFASINA GEÇİŞ (Arka plan + Maske mantığı)
  // ========================================================
  Future<void> _navigateToEdit(Map<String, dynamic> mask, Map<String, dynamic> fileData) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          originalImageUrl: normalizeUrl(fileData['file_path']), // Orijinal MR arka planda!
          maskImageUrl: normalizeUrl(mask['mask_url']),          // Noktalar maskeden bulunacak
          initialContour: const [],
          maskId: mask['id'],
          token: widget.token,
        ),
      ),
    );

    if (result != null) {
      final maskBytes = result['maskBytes'] as Uint8List;

      // Yeni üretilen Siyah/Beyaz resmi direkt veritabanına güncelle
      try {
        var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/segment/${mask['id']}'));
        request.headers['Authorization'] = 'Bearer ${widget.token}';
        request.files.add(http.MultipartFile.fromBytes('file', maskBytes, filename: 'updated_mask.png'));
        var response = await request.send();

        if (response.statusCode == 200) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Maske başarıyla güncellendi.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
          // Açık olan BottomSheet'i kapat ve listeyi yenile
          Navigator.pop(context);
          _refreshFiles();
        }
      } catch (e) {
        print("Güncelleme hatası: $e");
      }
    }
  }

  // ========================================================
  // MASKE GEÇMİŞİ PENCERESİ (Bottom Sheet)
  // ========================================================
  void _showMasksBottomSheet(Map<String, dynamic> fileData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[800]!))),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.greenAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text("Segmentasyon Geçmişi\n${fileData['filename']}",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: apiService.getMasksByFile(widget.token, fileData['id']),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (snapshot.hasError) return Center(child: Text("Hata: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text("Bu dosya için henüz bir analiz yapılmamış.", style: TextStyle(color: Colors.grey)));
                      }

                      final masks = snapshot.data!;
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: masks.length,
                        itemBuilder: (context, index) {
                          final mask = masks[index];
                          final isNifti = mask['filename'].toString().endsWith('.nii') || mask['filename'].toString().endsWith('.nii.gz');

                          return Card(
                            color: Colors.grey[850],
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: Icon(isNifti ? Icons.view_in_ar : Icons.image, color: Colors.blueAccent),
                              title: Text(mask['filename'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                              subtitle: Text("Tarih: ${mask['created_at'] ?? 'Bilinmiyor'}", style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // DÜZENLEME BUTONU
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.orangeAccent),
                                    onPressed: isNifti ? () {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("3D MR (NIfTI) dosyaları mobilde düzenlenemez, Web panelini kullanın.")));
                                    } : () {
                                      // DÜZELTİLDİ: Artık _navigateToEdit fonksiyonumuzu çağırıyoruz!
                                      _navigateToEdit(mask, fileData);
                                    },
                                  ),
                                  // SİLME BUTONU (Sadece o maskeyi siler)
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () async {
                                      try {
                                        await apiService.deleteMask(widget.token, mask['id']);
                                        if (!mounted) return;
                                        Navigator.pop(context);
                                        _refreshFiles();
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Maske silindi.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.black87));
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========================================================
  // ANA UI MİMARİSİ
  // ========================================================
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          title: Text("${widget.patientName} - Dosyalar", style: const TextStyle(fontSize: 18)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshFiles),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.blueAccent,
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.image), text: "2D Görüntüler (PNG)"),
              Tab(icon: Icon(Icons.view_in_ar), text: "3D MR (NIfTI)"),
            ],
          ),
        ),
        body: FutureBuilder<List<dynamic>>(
          future: filesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text("Hata: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_off, size: 60, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("Bu hastaya ait hiçbir dosya bulunamadı.", style: TextStyle(color: Colors.grey)),
                    ],
                  )
              );
            }

            final allFiles = snapshot.data!;
            final niftiFiles = allFiles.where((f) => f['filename'].toString().endsWith('.nii') || f['filename'].toString().endsWith('.nii.gz')).toList();
            final imageFiles = allFiles.where((f) => !f['filename'].toString().endsWith('.nii') && !f['filename'].toString().endsWith('.nii.gz')).toList();

            return TabBarView(
              children: [
                _buildFileList(imageFiles),
                _buildFileList(niftiFiles),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.blueAccent,
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => SegmentPage(token: widget.token, patientId: widget.patientId)))
                .then((_) => _refreshFiles());
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text("Yeni Analiz", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // ========================================================
  // LİSTE KART TASARIMI
  // ========================================================
  Widget _buildFileList(List<dynamic> files) {
    if (files.isEmpty) return const Center(child: Text("Bu kategoride dosya yok.", style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSegmented = file['status'] == 'segmented';

        return Card(
          color: Colors.grey[900],
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isSegmented ? Colors.green.withOpacity(0.5) : Colors.transparent, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showMasksBottomSheet(file),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSegmented ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSegmented ? Icons.check_circle : Icons.hourglass_empty,
                      color: isSegmented ? Colors.greenAccent : Colors.grey,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file['filename'],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isSegmented ? "Yapay Zeka Analizli" : "Ham Görüntü (İşlem Bekliyor)",
                          style: TextStyle(
                            color: isSegmented ? Colors.greenAccent : Colors.grey[500],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: "Tümünü Sil",
                    onPressed: () => _confirmDeleteFile(file['id'], file['filename']),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}