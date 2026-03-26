import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'EditSegmentPage.dart'; // Sizin yazdığınız 2D düzenleme sayfası
import 'NiiVueMobileViewer.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class NiftiSliceSelectorPage extends StatefulWidget {
  final int fileId;
  final int maskId;
  final String token;
  final String filename;

  final String? niftiFilePath;

  const NiftiSliceSelectorPage({
    super.key,
    required this.fileId,
    required this.maskId,
    required this.token,
    required this.filename,

    this.niftiFilePath,
  });

  @override
  State<NiftiSliceSelectorPage> createState() => _NiftiSliceSelectorPageState();
}

class _NiftiSliceSelectorPageState extends State<NiftiSliceSelectorPage> {
  int currentSlice = 0;       // Ekranda gerçekten yüklenen ve sunucudan istenen kesit
  double sliderValue = 0.0;   // Kullanıcı kaydırırken sadece görsel olarak değişen değer
  int totalSlices = 0;

  // --- YENİ EKLENEN EKSEN KONTROLLERİ ---
  String activeAxis = 'axial';
  Map<String, int> totalSlicesMap = {'axial': 0, 'coronal': 0, 'sagittal': 0};
  Map<String, int> currentSliceMap = {'axial': 0, 'coronal': 0, 'sagittal': 0};

  bool isLoading = true;
  bool isSaving = false;
  bool isDownloading3D = false;

  // Resmi güncellediğimizde önbelleği (cache) kırıp yeni resmi ekrana basmak için bir zaman damgası
  int refreshKey = DateTime.now().millisecondsSinceEpoch;

  // Backend API URL'nizi buraya yazın
  final String baseUrl = "http://oncovisionai.com.tr/api";

  @override
  void initState() {
    super.initState();
    _fetchTotalSlices();
  }

  // 1. ADIM: Backend'den kesit bilgilerini alıp State'teki haritaları dolduruyoruz
  Future<void> _fetchTotalSlices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/segment/nifti/${widget.maskId}/info'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          // --- DÜZELTME: Eğer API'den coronal/sagittal gelmezse çökmemesi için standart boyut 256 ata ---
          totalSlicesMap['axial'] = data['axial_slices'] ?? data['total_slices'] ?? 154;
          totalSlicesMap['coronal'] = data['coronal_slices'] ?? 256;
          totalSlicesMap['sagittal'] = data['sagittal_slices'] ?? 256;

          // Her eksen için başlangıçta ortadaki kesiti ayarla
          currentSliceMap['axial'] = totalSlicesMap['axial']! ~/ 2;
          currentSliceMap['coronal'] = totalSlicesMap['coronal']! ~/ 2;
          currentSliceMap['sagittal'] = totalSlicesMap['sagittal']! ~/ 2;

          // Aktif eksene göre State'teki değişkenleri güncelle
          totalSlices = totalSlicesMap[activeAxis]!;
          currentSlice = currentSliceMap[activeAxis]!;
          sliderValue = currentSlice.toDouble();
          isLoading = false;
        });
      } else {
        throw Exception("Kesit bilgisi alınamadı");
      }
    } catch (e) {
      setState(() {
        // Hata durumunda varsayılan değerleri daha mantıklı sayılar yapalım
        totalSlicesMap = {'axial': 154, 'coronal': 256, 'sagittal': 256};
        currentSliceMap = {'axial': 77, 'coronal': 128, 'sagittal': 128};
        totalSlices = totalSlicesMap[activeAxis]!;
        currentSlice = currentSliceMap[activeAxis]!;
        sliderValue = currentSlice.toDouble();
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

  // Görüntü URL'lerini oluşturan yardımcı fonksiyonlar (Sadece currentSlice değişince tetiklenir)
  String get sliceImageUrl => "$baseUrl/segment/nifti/${widget.maskId}/slice/$currentSlice?type=image&axis=$activeAxis";
  String get sliceMaskUrl => "$baseUrl/segment/nifti/${widget.maskId}/slice/$currentSlice?type=mask&axis=$activeAxis&t=$refreshKey";

  void _changeAxis(String newAxis) {
    if (activeAxis == newAxis) return;
    setState(() {
      currentSliceMap[activeAxis] = currentSlice; // Eski ekseni kaydet
      activeAxis = newAxis;
      totalSlices = totalSlicesMap[newAxis]!;
      currentSlice = currentSliceMap[newAxis]!;
      sliderValue = currentSlice.toDouble();
    });
  }

  void _changeSlice(int delta) {
    int newSlice = currentSlice + delta;
    if (newSlice >= 0 && newSlice < totalSlices) {
      setState(() {
        currentSlice = newSlice;
        sliderValue = newSlice.toDouble();
        currentSliceMap[activeAxis] = newSlice;
      });
    }
  }

  void _open3DViewer() async {
    String fileUrl = (widget.niftiFilePath != null && widget.niftiFilePath!.isNotEmpty)
        ? widget.niftiFilePath!
        : "$baseUrl/files/download/${widget.fileId}";

    if (!fileUrl.startsWith('http')) {
      _navigateTo3DViewer(fileUrl);
      return;
    }

    setState(() => isDownloading3D = true);

    try {
      final directory = await getTemporaryDirectory();
      final safeFilename = widget.filename.replaceAll(RegExp(r'[^a-zA-Z0-9.\-]'), '_');
      final localPath = '${directory.path}/$safeFilename';
      final file = File(localPath);

      if (await file.exists() && await file.length() < 10000) {
        await file.delete();
      }

      if (!await file.exists()) {
        http.Response? finalResponse;

        // 1. İhtimal
        finalResponse = await http.get(Uri.parse(fileUrl), headers: {'Authorization': 'Bearer ${widget.token}'});

        // 2. İhtimal
        if (finalResponse.statusCode != 200) {
          finalResponse = await http.get(Uri.parse(fileUrl));
        }

        // 3. İhtimal
        if (finalResponse.statusCode == 404 && fileUrl.contains('/api/')) {
          String altUrl = fileUrl.replaceFirst('/api/', '/');
          finalResponse = await http.get(Uri.parse(altUrl));
        }

        // 4. İhtimal
        if (finalResponse.statusCode != 200) {
          finalResponse = await http.get(
              Uri.parse("$baseUrl/files/download/${widget.fileId}"),
              headers: {'Authorization': 'Bearer ${widget.token}'}
          );
        }

        if (finalResponse.statusCode == 200) {
          // --- HAYAT KURTARAN DÜZELTME BURADA ---
          // Ham (binary) veriyi .body ile zorla String'e çevirmiyoruz! Çökmeyi önler.
          // Sadece ilk 20 byte'ı güvenli bir şekilde alıp HTML olup olmadığına bakıyoruz.
          final firstBytes = finalResponse.bodyBytes.take(20).toList();
          final peekString = String.fromCharCodes(firstBytes).toLowerCase();

          if (peekString.contains('<!doc') || peekString.contains('<html')) {
            throw Exception("Sunucu dosya yerine web sayfası (HTML) döndürdü.");
          }

          // Her şey yolundaysa ham veriyi fiziksel dosyaya yaz!
          await file.writeAsBytes(finalResponse.bodyBytes);
        } else {
          throw Exception("Sunucu dosyayı bulamadı. Hata Kodu: ${finalResponse.statusCode}");
        }
      }

      setState(() => isDownloading3D = false);
      _navigateTo3DViewer(localPath);

    } catch (e) {
      setState(() => isDownloading3D = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("$e"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  void _navigateTo3DViewer(String localPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("3D Hacim", style: TextStyle(color: Colors.white)), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          backgroundColor: Colors.black,
          body: NiiVueMobileViewer(
            localFilePath: localPath,
            maskUrl: '$baseUrl/segment/nifti/${widget.maskId}/download',
            token: widget.token,
          ),
        ),
      ),
    );
  }


  Widget _buildAxisButton(String axis, String label) {
    bool isActive = activeAxis == axis;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.blue : Colors.grey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      onPressed: () => _changeAxis(axis),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }


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

          isNiftiMode: true,
          activeAxis: activeAxis,
          niftiFilePath: widget.niftiFilePath, // widget. ekledik
          totalSlicesMap: totalSlicesMap,
          currentSliceMap: currentSliceMap,
        ),
      ),
    );

    // Sizin sayfanızdan 'maskBytes' (yeni çizilen Siyah/Beyaz PNG) gelirse...
    if (result != null) {
      // Düzenleme sayfasında kesit/eksen değiştiyse buraya yansıt
      if (result['activeAxis'] != null && result['currentSliceMap'] != null) {
        setState(() {
          activeAxis = result['activeAxis'];
          currentSliceMap = Map<String, int>.from(result['currentSliceMap']);
          totalSlices = totalSlicesMap[activeAxis]!;
          currentSlice = currentSliceMap[activeAxis]!;
          sliderValue = currentSlice.toDouble();
        });
      }

      if (result['maskBytes'] != null) {
        _updateNiftiSlice(result['maskBytes']);
      }
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
              // --- YENİ EKLENEN ÜST BAR (EKSENLER VE 3D) ---
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildAxisButton('axial', 'Üstten'),
                      const SizedBox(width: 8),
                      _buildAxisButton('coronal', 'Önden'),
                      const SizedBox(width: 8),
                      _buildAxisButton('sagittal', 'Yandan'),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero),
                        icon: isDownloading3D
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.view_in_ar, size: 16),
                        label: Text(isDownloading3D ? 'İndiriliyor...' : '3D Gör', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: isDownloading3D ? null : _open3DViewer,
                      ),
                    ],
                  ),
                ),
              ),

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
                        "Kesit (Slice): $currentSlice / ${totalSlices > 0 ? totalSlices - 1 : 0}",
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 10),

                      // --- DÜZELTME: SLIDER VE YENİ EKLENEN OKLAR ---
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, color: Colors.blueAccent, size: 20),
                            onPressed: () => _changeSlice(-1),
                          ),
                          Expanded(
                            child: Slider(
                              value: sliderValue,
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
                                  currentSliceMap[activeAxis] = currentSlice; // Eksen haritasını günceller
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, color: Colors.blueAccent, size: 20),
                            onPressed: () => _changeSlice(1),
                          ),
                        ],
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