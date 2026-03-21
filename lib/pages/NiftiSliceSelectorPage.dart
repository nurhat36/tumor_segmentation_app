import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'EditSegmentPage.dart'; // Sizin yazdığınız 2D düzenleme sayfası

class NiftiSliceSelectorPage extends StatefulWidget {
  final int fileId;
  final int maskId;
  final String token;
  final String filename;

  const NiftiSliceSelectorPage({
    super.key,
    required this.fileId,
    required this.maskId,
    required this.token,
    required this.filename,
  });

  @override
  State<NiftiSliceSelectorPage> createState() => _NiftiSliceSelectorPageState();
}

class _NiftiSliceSelectorPageState extends State<NiftiSliceSelectorPage> {
  int currentSlice = 0;       // Ekranda gerçekten yüklenen ve sunucudan istenen kesit
  double sliderValue = 0.0;   // Kullanıcı kaydırırken sadece görsel olarak değişen değer
  int totalSlices = 0;
  bool isLoading = true;
  bool isSaving = false;

  // Resmi güncellediğimizde önbelleği (cache) kırıp yeni resmi ekrana basmak için bir zaman damgası
  int refreshKey = DateTime.now().millisecondsSinceEpoch;

  // Backend API URL'nizi buraya yazın
  final String baseUrl = "http://oncovisionai.com.tr/api";

  @override
  void initState() {
    super.initState();
    _fetchTotalSlices();
  }

  // 1. ADIM: Backend'den bu NIfTI dosyasının kaç kesit (dilim) olduğunu öğreniyoruz
  Future<void> _fetchTotalSlices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/segment/nifti/${widget.maskId}/info'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          totalSlices = data['total_slices'] ?? 100;
          currentSlice = totalSlices ~/ 2;
          sliderValue = currentSlice.toDouble(); // Slider değerini de ortaya eşitle
          isLoading = false;
        });
      } else {
        throw Exception("Kesit bilgisi alınamadı");
      }
    } catch (e) {
      setState(() {
        totalSlices = 100;
        currentSlice = 50;
        sliderValue = 50.0;
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

  // Görüntü URL'lerini oluşturan yardımcı fonksiyonlar (Sadece currentSlice değişince tetiklenir)
  String get sliceImageUrl => "$baseUrl/segment/nifti/${widget.maskId}/slice/$currentSlice?type=image";
  String get sliceMaskUrl => "$baseUrl/segment/nifti/${widget.maskId}/slice/$currentSlice?type=mask&t=$refreshKey";

  // 2. ADIM: Kullanıcı "Düzenle"ye basınca sizin sayfanızı açıyoruz
  void _editCurrentSlice() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          originalImageUrl: sliceImageUrl, // O anki kesitin MR arka planı
          maskImageUrl: sliceMaskUrl,      // O anki kesitin Maskesi
          initialContour: const [],
          maskId: widget.maskId,
          token: widget.token,
        ),
      ),
    );

    // Sizin sayfanızdan 'maskBytes' (yeni çizilen Siyah/Beyaz PNG) gelirse...
    if (result != null && result['maskBytes'] != null) {
      final Uint8List newMaskBytes = result['maskBytes'];
      _updateNiftiSlice(newMaskBytes);
    }
  }

  // 3. ADIM: Sizin sayfanızdan gelen yeni PNG'yi NIfTI'nin içine kaydetmesi için Backend'e yolluyoruz
  Future<void> _updateNiftiSlice(Uint8List maskBytes) async {
    setState(() => isSaving = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment/nifti/${widget.maskId}/slice/$currentSlice/update'));
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(http.MultipartFile.fromBytes('file', maskBytes, filename: 'updated_slice_$currentSlice.png'));

      var response = await request.send();

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$currentSlice. Kesit Başarıyla Güncellendi!", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green));

        // Ekrana yeni maskeyi basmak için cache'i kırıyoruz
        setState(() {
          refreshKey = DateTime.now().millisecondsSinceEpoch;
        });
      } else {
        throw Exception("Sunucu Hatası: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Güncelleme hatası: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.filename), backgroundColor: Colors.grey[900]),
        body: const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("Kesit Seçici - ${widget.filename}", style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ÜST KISIM: GÖRÜNTÜ VE MASKENİN ÜST ÜSTE BİNMESİ
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Arka Plan (MR Kesiti)
                        Image.network(
                          sliceImageUrl,
                          headers: {'Authorization': 'Bearer ${widget.token}'},
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, err, stack) => const Text("Kesit yüklenemedi", style: TextStyle(color: Colors.white54)),
                        ),
                        // Yapay Zeka Maskesi (Yarı saydam)
                        Opacity(
                          opacity: 0.5,
                          child: Image.network(
                            sliceMaskUrl,
                            headers: {'Authorization': 'Bearer ${widget.token}'},
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) => const SizedBox(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ALT KISIM: KONTROL PANELİ (SLIDER VE DÜZENLE BUTONU)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // METİN sliderValue'ye göre anlık değişecek
                      Text(
                        "Kesit (Slice): ${sliderValue.toInt()} / ${totalSlices > 0 ? totalSlices - 1 : 0}",
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Slider(
                        value: sliderValue, // currentSlice YERİNE sliderValue KULLANILIYOR
                        min: 0,
                        max: (totalSlices > 0 ? totalSlices - 1 : 0).toDouble(),
                        divisions: totalSlices > 0 ? totalSlices : 1,
                        activeColor: Colors.blueAccent,
                        inactiveColor: Colors.grey[700],
                        onChanged: (val) {
                          // Parmağı kaydırırken SADECE çubuk hareket eder, sunucuya istek GİTMEZ!
                          setState(() {
                            sliderValue = val;
                          });
                        },
                        onChangeEnd: (val) {
                          // Kullanıcı parmağını ekrandan ÇEKTİĞİNDE sunucuya istek atılır!
                          setState(() {
                            currentSlice = val.toInt();
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: isSaving ? null : _editCurrentSlice,
                          icon: const Icon(Icons.edit, color: Colors.white),
                          label: const Text("Seçili Kesiti Düzenle", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent[700],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // KAYDEDİLİYOR YÜKLENME EKRANI
          if (isSaving)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 16),
                    Text("Değişiklikler NIfTI dosyasına yazılıyor...", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}