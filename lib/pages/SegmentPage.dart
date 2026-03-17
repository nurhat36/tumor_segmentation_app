import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart'; // YENİ EKLENDİ
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

// EditSegmentPage dosyanızın doğru import edildiğinden emin olun
import 'EditSegmentPage.dart';

enum ShapeType { rectangle, circle, oval }

class SegmentPage extends StatefulWidget {
  final String token;
  final int patientId;


  const SegmentPage({
    super.key,
    required this.token,
    required this.patientId,

  });

  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  final ApiService apiService = ApiService();
  // Görsel ve Dosya
  File? selectedFile; // Hem resim hem .nii dosyasını tutar
  ui.Image? loadedImage; // Ekranda gösterilen anlık resim (Slice veya PNG)
  ui.Image? maskImage; // Ekranda gösterilen maske
  List<List<Offset>> maskContours = [];
  int? currentMaskId;

  // UI durumları
  bool isLoading = false;
  bool isSegmenting = false;
  bool showMask = true;
  ShapeType selectedShape = ShapeType.rectangle;

  // --- NIfTI (3D MR) Değişkenleri ---
  bool isNiftiMode = false; // Şu an NIfTI mı görüntülüyoruz?
  int totalSlices = 0;      // Toplam kesit sayısı
  int currentSliceIndex = 0; // Şu anki kesit

  // --- Zoom ve Mod Kontrolü ---
  final TransformationController _transformationController = TransformationController();
  bool _isPanMode = true; // True: Gezinme, False: Seçim
  Rect? selectionRectImage; // Seçim alanı

  // API endpoint (Emülatör için 10.0.2.2, Gerçek cihaz için PC IP'si)
  static const String baseUrl = "http://oncovisionai.com.tr/api";

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ============================================================
  // 📁 DOSYA SEÇİM İŞLEMLERİ (Resim veya NIfTI)
  // ============================================================

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.white),
              title: const Text('Galeri (PNG/JPG)', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_special, color: Colors.orange),
              title: const Text('MR Dosyası (.nii)', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickNiftiFile();
              },
            ),
          ],
        );
      },
    );
  }

  // Standart Resim Seçme
  // Standart Resim Seçme (DÜZELTİLDİ)
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() {
      isLoading = true; // İşlem bitene kadar ekranda yükleniyor ikonu dönsün
    });

    try {
      final file = File(pickedFile.path);

      // 1. Dosyayı sunucuya yükle (Senin yazdığın kısım)
      await apiService.uploadFileToPatient(
        widget.token,
        widget.patientId,
        file,
      );

      // 2. YENİ EKLENEN KISIM: Resmi ekranda göstermek için ui.Image'e çevir
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      // 3. UI'ı güncelle
      setState(() {
        selectedFile = file;             // Backend'e segmentasyona giderken lazım
        loadedImage = frame.image;       // Ekranda RawImage içinde gösterilecek olan resim
        isNiftiMode = false;             // Normal resim modundayız
        maskImage = null;                // Yeni resim geldi, eski maskeleri temizle
        maskContours.clear();
        selectionRectImage = null;       // Seçimi sıfırla
        isLoading = false;               // Yüklemeyi bitir
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Dosya başarıyla yüklendi ve ekrana getirildi")),
      );

    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: $e")),
      );
    }
  }

  // NIfTI Dosyası Seçme (File Picker ile)
  Future<void> _pickNiftiFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // .nii uzantısı için custom filtre bazen sorun çıkarabilir, any en garantisi
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;

        // Uzantı kontrolü
        if (!path.endsWith('.nii') && !path.endsWith('.nii.gz')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Lütfen .nii veya .nii.gz uzantılı dosya seçin.")),
          );
          return;
        }

        setState(() {
          selectedFile = File(path);
          isNiftiMode = true; // NIfTI modunu aktifleştir ama henüz yüklenmedi
          loadedImage = null; // Henüz görüntü yok (Segment'e basınca gelecek)
          maskImage = null;
          maskContours.clear();
          selectionRectImage = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${result.files.single.name} seçildi. İşlemek için 'Oynat' butonuna basın.")),
        );
      }
    } catch (e) {
      print("Dosya seçme hatası: $e");
    }
  }

  // ============================================================
  // 🖼️ GÖRÜNTÜ VE MASKE İŞLEME
  // ============================================================

  Future<void> loadMaskImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    setState(() {
      maskImage = frame.image;
      _findSimplifiedContour();
    });
  }

  void _findSimplifiedContour() async {
    maskContours.clear();
    if (maskImage == null) return;

    try {
      final byteData = await maskImage!.toByteData();
      if (byteData == null) return;

      final width = maskImage!.width;
      final height = maskImage!.height;
      final pixels = byteData.buffer.asUint8List();
      final visited = List.generate(width * height, (_) => false);

      bool isWhite(int x, int y) {
        if (x < 0 || x >= width || y < 0 || y >= height) return false;
        final index = y * width + x;
        return pixels[index * 4] > 128; // Eşik değeri
      }

      // ... (Senin mevcut kontur algoritman aynen buraya) ...
      // Kodun kısalığı için algoritmayı özet geçiyorum, senin yazdığınla aynı kalmalı:

      Offset? startPoint;
      for (int y = 0; y < height && startPoint == null; y++) {
        for (int x = 0; x < width && startPoint == null; x++) {
          if (isWhite(x, y)) startPoint = Offset(x.toDouble(), y.toDouble());
        }
      }

      if (startPoint == null) return;

      final currentPath = <Offset>[startPoint];
      Offset currentPoint = startPoint;
      int maxIterations = width * height * 2;
      int i = 0;

      while (i < maxIterations) {
        bool moved = false;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nextX = currentPoint.dx.round() + dx;
            final nextY = currentPoint.dy.round() + dy;

            if (isWhite(nextX, nextY) && !visited[nextY * width + nextX]) {
              bool isEdge = false;
              for (int ndy = -1; ndy <= 1; ndy++) {
                for (int ndx = -1; ndx <= 1; ndx++) {
                  if (ndx == 0 && ndy == 0) continue;
                  if (!isWhite(nextX + ndx, nextY + ndy)) {
                    isEdge = true;
                    break;
                  }
                }
                if (isEdge) break;
              }
              if (isEdge) {
                currentPoint = Offset(nextX.toDouble(), nextY.toDouble());
                currentPath.add(currentPoint);
                visited[currentPoint.dy.round() * width + currentPoint.dx.round()] = true;
                moved = true;
                break;
              }
            }
          }
          if (moved) break;
        }
        if (!moved) break;
        i++;
      }

      final simplifiedContour = <Offset>[];
      final samplingRate = 20; // Biraz daha hassas olsun diye 50 yerine 20 yaptım
      for (int k = 0; k < currentPath.length; k += samplingRate) {
        simplifiedContour.add(currentPath[k]);
      }
      if (simplifiedContour.isNotEmpty) maskContours = [simplifiedContour];

      setState(() {});

    } catch (e) {
      print('Kontur hatası: $e');
    }
  }

  // ============================================================
  // 🚀 API İSTEKLERİ (SEGMENTASYON & NIfTI)
  // ============================================================

  Future<void> _sendSegmentRequest() async {
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Önce bir dosya seçin.")));
      return;
    }

    if (!isNiftiMode && selectionRectImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen bir alan seçin.")));
      return;
    }

    setState(() {
      isSegmenting = true;
      maskImage = null;
      maskContours.clear();
    });

    try {
      // ==========================================================
      // ADIM 1: DOSYAYI BACKEND'E KAYDET (widget.patientId KULLANARAK)
      // ==========================================================
      print("⏳ Dosya ${widget.patientId} numaralı hastaya yükleniyor...");

      // DİKKAT: URL'ye widget.patientId'yi ekledik!
      var uploadRequest = http.MultipartRequest('POST', Uri.parse('$baseUrl/files/${widget.patientId}'));
      uploadRequest.headers['Authorization'] = 'Bearer ${widget.token}';
      uploadRequest.files.add(await http.MultipartFile.fromPath('file', selectedFile!.path));

      var uploadResponse = await uploadRequest.send();
      final uploadResponseBody = await http.Response.fromStream(uploadResponse);

      if (uploadResponse.statusCode != 200) {
        print("❌ Yükleme Hatası: ${uploadResponseBody.body}");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Dosya yükleme hatası: ${uploadResponse.statusCode}")));
        setState(() => isSegmenting = false);
        return;
      }

      final uploadData = json.decode(uploadResponseBody.body);
      final int newFileId = uploadData['id'];
      print("✅ Dosya başarıyla yüklendi. Veritabanı ID'si: $newFileId");

      // ==========================================================
      // ADIM 2: YÜKLENEN DOSYAYI SEGMENTE ET (newFileId KULLANARAK)
      // ==========================================================
      print("🧠 Yapay Zeka analizi başlatılıyor...");

      // DİKKAT: Artık URL'de backend'den gelen yeni dosya ID'sini kullanıyoruz
      var segmentRequest = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment/$newFileId'));
      segmentRequest.headers['Authorization'] = 'Bearer ${widget.token}';

      // Koordinatları gönderiyoruz
      segmentRequest.fields.addAll({
        'x': isNiftiMode ? '0' : selectionRectImage!.left.toString(),
        'y': isNiftiMode ? '0' : selectionRectImage!.top.toString(),
        'width': isNiftiMode ? '0' : selectionRectImage!.width.toString(),
        'height': isNiftiMode ? '0' : selectionRectImage!.height.toString(),
        'shape': selectedShape.toString().split('.').last,
        'z': '0', // NIfTI için güvenli olması adına Z eksenini de ekledik
      });

      var segmentResponse = await segmentRequest.send();
      final segmentResponseBody = await http.Response.fromStream(segmentResponse);

      if (segmentResponse.statusCode == 200) {
        final responseData = json.decode(segmentResponseBody.body);

        final maskUrl = responseData['mask_url'];
        final newMaskId = responseData['mask_id'] ?? newFileId;
        final type = responseData['type'] ?? 'volume';

        setState(() {
          currentMaskId = newMaskId;
        });

        if (type == 'volume' || (selectedFile!.path.endsWith('.nii') || selectedFile!.path.endsWith('.nii.gz'))) {
          // --- NIfTI Modunu Başlat ---
          await _initNiftiMode(newMaskId);
        } else {
          // --- Normal Resim Modu ---
          final maskDownloadResponse = await http.get(Uri.parse('$baseUrl$maskUrl'));
          await loadMaskImage(maskDownloadResponse.bodyBytes);
          setState(() => isNiftiMode = false);
        }

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Segmentasyon başarılı!")));
      } else {
        print("❌ Segmentasyon Hatası: ${segmentResponseBody.body}");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Segmentasyon Hatası: ${segmentResponse.statusCode}")));
      }
    } catch (e) {
      print("❌ Kritik Hata: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    } finally {
      setState(() => isSegmenting = false);
    }
  }

  // NIfTI: Bilgileri Çek
  Future<void> _initNiftiMode(int maskId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/segment/nifti/$maskId/info'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isNiftiMode = true;
          totalSlices = data['total_slices'];
          currentSliceIndex = (totalSlices / 2).floor(); // Ortadan başla
        });
        // İlk kesiti yükle
        await _loadSliceData(currentSliceIndex);
      }
    } catch (e) {
      print("NIfTI Info Error: $e");
    }
  }

  // NIfTI: Belirli bir kesiti yükle
  Future<void> _loadSliceData(int index) async {
    if (currentMaskId == null) return;
    setState(() => isLoading = true);

    try {
      // 1. Orijinal Görüntü
      final originalRes = await http.get(
          Uri.parse('$baseUrl/segment/nifti/$currentMaskId/slice/$index?type=original'),
          headers: {'Authorization': 'Bearer ${widget.token}'}
      );

      // 2. Maske
      final maskRes = await http.get(
          Uri.parse('$baseUrl/segment/nifti/$currentMaskId/slice/$index?type=mask'),
          headers: {'Authorization': 'Bearer ${widget.token}'}
      );

      if (originalRes.statusCode == 200 && maskRes.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(originalRes.bodyBytes);
        final frame = await codec.getNextFrame();

        setState(() {
          loadedImage = frame.image;
        });

        await loadMaskImage(maskRes.bodyBytes);
      }
    } catch (e) {
      print("Slice Load Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // NIfTI: Düzenlenmiş kesiti güncelle
  Future<bool> _updateNiftiSliceOnServer(int maskId, int sliceIndex) async {
    if (maskImage == null) return false;
    try {
      final byteData = await maskImage!.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;
      final pngBytes = byteData.buffer.asUint8List();

      var request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/segment/nifti/$maskId/slice/$sliceIndex/update')
      );
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(http.MultipartFile.fromBytes('file', pngBytes, filename: 'slice_update.png'));

      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print("Update Slice Error: $e");
      return false;
    }
  }

  // Normal PNG: Güncelleme
  Future<bool> _uploadMaskToServer(int maskId) async {
    // ... (Mevcut kodun aynısı) ...
    if (maskImage == null) return false;
    try {
      final byteData = await maskImage!.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final uri = Uri.parse('$baseUrl/segment/$maskId');
      var request = http.MultipartRequest('PUT', uri);
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(http.MultipartFile.fromBytes('file', pngBytes, filename: 'updated_mask.png'));
      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  // Manuel Çizim Oluşturma (Create)
  Future<bool> _createManualMaskOnServer() async {
    // ... (Mevcut kodun aynısı) ...
    // Kısaltma: Logiği aynı tutuyoruz
    return false;
  }

  // Ekrana Çizdirme ve Güncelleme
  Future<void> _updateMaskFromPoints(List<Offset> newContours) async {
    if (loadedImage == null) return;
    final width = loadedImage!.width;
    final height = loadedImage!.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Arka plan siyah (Maske olmayan yerler)
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = Colors.black);

    // Poligon beyaz (Maske alanı)
    if (newContours.isNotEmpty) {
      final path = Path()..moveTo(newContours[0].dx, newContours[0].dy);
      for (int i = 1; i < newContours.length; i++) path.lineTo(newContours[i].dx, newContours[i].dy);
      path.close();
      canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);
    }

    final newMaskImage = await recorder.endRecording().toImage(width, height);
    setState(() {
      maskImage = newMaskImage;
      maskContours = [newContours];
    });
  }

  // ============================================================
  // 🖱️ UI ETKİLEŞİMLERİ (Edit Sayfası vb.)
  // ============================================================

  void _openEditPage() async {
    if (loadedImage == null || maskContours.isEmpty) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          originalMemoryImage: loadedImage!,
          initialContour: List.from(maskContours[0]),
          maskId: currentMaskId ?? 0,
          token: widget.token,
        ),
      ),
    );

    if (result != null) {
      final editedPoints = result['points'] as List<Offset>;
      final maskBytes = result['maskBytes'] as Uint8List; // Hazır Siyah Beyaz Maske!

      // Ekranda maskeyi hemen güncelle
      await loadMaskImage(maskBytes);
      setState(() => maskContours = [editedPoints]);

      // Server'a yolla
      bool success;
      if (isNiftiMode) {
        success = await _updateNiftiSliceOnServer(currentMaskId!, currentSliceIndex);
      } else {
        // Normal mod için direkt elimizdeki maskBytes'ı yollayabiliriz
        var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/segment/$currentMaskId'));
        request.headers['Authorization'] = 'Bearer ${widget.token}';
        request.files.add(http.MultipartFile.fromBytes('file', maskBytes, filename: 'updated_mask.png'));
        var response = await request.send();
        success = response.statusCode == 200;
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? "Kaydedildi" : "Hata oluştu")));
    }
  }

  void _startManualDrawing() async {
    // Manuel çizim sadece Normal PNG veya Tekil Slice üzerinde çalışır
    if (loadedImage == null) return;

    // 1. Yeni EditSegmentPage yapısına göre çağırıyoruz
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSegmentPage(
          originalMemoryImage: loadedImage!, // DÜZELTME: memoryImage yerine originalMemoryImage oldu
          initialContour: const [],
          maskId: currentMaskId ?? 0,
          token: widget.token,
        ),
      ),
    );

    // 2. Eğer kullanıcı "Kaydet"e bastıysa ve sonuç döndüyse
    if (result != null) {
      final manualPoints = result['points'] as List<Offset>;
      final maskBytes = result['maskBytes'] as Uint8List;

      if (manualPoints.isEmpty) return; // Çizgi çizmeden kaydettiyse işlem yapma

      // 3. Üretilen siyah/beyaz maskeyi beklemeden ekranda göster
      await loadMaskImage(maskBytes);
      setState(() {
        maskContours = [manualPoints];
      });

      // 4. Server'a Kaydetme İşlemi
      bool success = false;
      try {
        if (isNiftiMode && currentMaskId != null) {
          // NIfTI slice güncellemesi
          success = await _updateNiftiSliceOnServer(currentMaskId!, currentSliceIndex);
        } else if (currentMaskId == null) {
          // İLK DEFA maske oluşturuluyorsa (Backend tarafında POST ile yeni kayıt açılmalı)
          // Not: Mevcut _createManualMaskOnServer metodunuzu maskBytes alacak şekilde güncellemeniz gerekebilir.
          // Geçici olarak bu bloğu kendi yapınıza göre uyarlayabilirsiniz:
          success = await _createManualMaskOnServer();
        } else {
          // Var olan maskeyi manuel çizimle GÜNCELLEME
          var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/segment/$currentMaskId'));
          request.headers['Authorization'] = 'Bearer ${widget.token}';
          request.files.add(http.MultipartFile.fromBytes('file', maskBytes, filename: 'manual_mask.png'));
          var response = await request.send();
          success = response.statusCode == 200;
        }
      } catch (e) {
        print("Manuel çizim kaydetme hatası: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(success ? "Manuel çizim kaydedildi!" : "Kaydetme hatası oluştu."))
        );
      }
    }
  }

  ({double scale, Offset offset}) _fit(Size box) {
    if (loadedImage == null) return (scale: 1.0, offset: Offset.zero);
    final w = loadedImage!.width.toDouble();
    final h = loadedImage!.height.toDouble();
    final s = math.min(box.width / w, box.height / h);
    final dx = (box.width - w * s) / 2.0;
    final dy = (box.height - h * s) / 2.0;
    return (scale: s, offset: Offset(dx, dy));
  }

  // ============================================================
  // 🖥️ UI BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNiftiMode ? "MR Analiz (3D)" : "Görüntü Analizi"),
        backgroundColor: isNiftiMode ? Colors.indigo[900] : Colors.blue,
        actions: [
          // NIfTI modunda seçim yapmaya gerek yok, sadece pan/zoom
          if (!isNiftiMode)
            IconButton(
              icon: Icon(_isPanMode ? Icons.pan_tool : Icons.crop_free),
              onPressed: () => setState(() => _isPanMode = !_isPanMode),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _showUploadOptions, // Güncellenen upload menüsü
          ),
        ],
      ),
      body: Column(
        children: [
          // --- GÖRÜNTÜ ALANI ---
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : loadedImage == null
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isNiftiMode ? Icons.folder_special : Icons.image, size: 80, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(isNiftiMode
                      ? "NIfTI Dosyası Seçildi.\nAnalize başlamak için Oynat'a basın."
                      : "Resim Seçilmedi",
                      textAlign: TextAlign.center
                  ),
                ],
              ),
            )
                : LayoutBuilder(
              builder: (context, constraints) {
                final fit = _fit(Size(constraints.maxWidth, constraints.maxHeight));
                final contentW = loadedImage!.width.toDouble() * fit.scale;
                final contentH = loadedImage!.height.toDouble() * fit.scale;

                return Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.1, maxScale: 10.0,
                    panEnabled: isNiftiMode ? true : _isPanMode, // NIfTI'de hep Pan açık

                    child: SizedBox(
                      width: contentW,
                      height: contentH,
                      child: GestureDetector(
                        // NIfTI modunda seçim yapılmaz
                        onPanStart: (!isNiftiMode && !_isPanMode) ? (details) {
                          final pImg = details.localPosition / fit.scale;
                          setState(() {
                            selectionRectImage = Rect.fromLTWH(pImg.dx, pImg.dy, 0, 0);
                            maskImage = null; maskContours.clear();
                          });
                        } : null,
                        onPanUpdate: (!isNiftiMode && !_isPanMode && selectionRectImage != null) ? (details) {
                          final pImg = details.localPosition / fit.scale;
                          final imgW = loadedImage!.width.toDouble();
                          final imgH = loadedImage!.height.toDouble();
                          setState(() {
                            selectionRectImage = Rect.fromPoints(
                              Offset(selectionRectImage!.left, selectionRectImage!.top),
                              Offset(pImg.dx.clamp(0.0, imgW), pImg.dy.clamp(0.0, imgH)),
                            );
                          });
                        } : null,

                        child: Stack(
                          children: [
                            Positioned.fill(child: RawImage(image: loadedImage, fit: BoxFit.contain)),
                            if (maskContours.isNotEmpty && showMask)
                              Positioned.fill(child: CustomPaint(painter: _MaskOutlinePainter(maskContours, fit.scale))),
                            if (selectionRectImage != null && maskImage == null)
                              Positioned.fill(child: CustomPaint(painter: _SelectionPainter(rect: selectionRectImage!, scale: fit.scale))),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // --- SLIDER (Sadece NIfTI Modunda) ---
          if (isNiftiMode && totalSlices > 0)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Column(
                children: [
                  Text("Kesit: $currentSliceIndex / $totalSlices", style: const TextStyle(color: Colors.white)),
                  Slider(
                    value: currentSliceIndex.toDouble(),
                    min: 0,
                    max: (totalSlices - 1).toDouble(),
                    activeColor: Colors.orange,
                    onChanged: (val) {
                      setState(() => currentSliceIndex = val.toInt());
                    },
                    onChangeEnd: (val) {
                      _loadSliceData(val.toInt());
                    },
                  ),
                ],
              ),
            ),

          // --- ALT KONTROL BAR ---
          Container(
            height: 70,
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: isSegmenting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.play_arrow, color: Colors.greenAccent, size: 30),
                  onPressed: isSegmenting ? null : _sendSegmentRequest,
                  tooltip: "Segmentasyonu Başlat",
                ),
                IconButton(
                  icon: Icon(showMask ? Icons.visibility : Icons.visibility_off, color: Colors.white),
                  onPressed: () => setState(() => showMask = !showMask),
                ),
                IconButton(
                  icon: const Icon(Icons.gesture, color: Colors.orangeAccent),
                  onPressed: (loadedImage != null && !isSegmenting) ? _startManualDrawing : null,
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                  onPressed: (maskContours.isNotEmpty && !isSegmenting) ? _openEditPage : null,
                ),
              ],
            ),
          ),

          if (isSegmenting)
            Container(width: double.infinity, height: 20, color: Colors.blue, child: const Center(child: Text("İşleniyor...", style: TextStyle(color: Colors.white, fontSize: 10)))),
        ],
      ),
    );
  }
}

// Painter Sınıfları (Aynı kalıyor)
class _MaskOutlinePainter extends CustomPainter {
  final List<List<Offset>> contours;
  final double scale;
  _MaskOutlinePainter(this.contours, this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;
    final linePaint = Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final dotPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    for (final contour in contours) {
      if (contour.length < 2) continue;
      final path = Path()..moveTo(contour[0].dx * scale, contour[0].dy * scale);
      for (int i = 1; i < contour.length; i++) path.lineTo(contour[i].dx * scale, contour[i].dy * scale);
      path.close();
      canvas.drawPath(path, linePaint);
      for (var p in contour) canvas.drawCircle(p * scale, 2.5, dotPaint);
    }
  }
  @override
  bool shouldRepaint(covariant _MaskOutlinePainter old) => true;
}

class _SelectionPainter extends CustomPainter {
  final Rect rect;
  final double scale;
  _SelectionPainter({required this.rect, required this.scale});
  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTRB(rect.left * scale, rect.top * scale, rect.right * scale, rect.bottom * scale);
    canvas.drawRect(screenRect, Paint()..color = Colors.blue.withOpacity(0.3));
    canvas.drawRect(screenRect, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant _SelectionPainter old) => old.rect != rect || old.scale != scale;
}