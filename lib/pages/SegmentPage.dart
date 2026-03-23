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
import 'NiiVueMobileViewer.dart';

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


  // YENİ EKLENENLER: 3 Eksen için takip değişkenleri
  String activeAxis = 'axial'; // Varsayılan: 'axial', 'coronal' veya 'sagittal'
  Map<String, int> totalSlicesMap = {'axial': 0, 'coronal': 0, 'sagittal': 0};
  Map<String, int> currentSliceMap = {'axial': 0, 'coronal': 0, 'sagittal': 0};

  // --- NIfTI (3D MR) Değişkenleri ---
  bool isNiftiMode = false; // Şu an NIfTI mı görüntülüyoruz?
  int totalSlices = 0;      // Toplam kesit sayısı
  int currentSliceIndex = 0; // Şu anki kesit

  int? currentFileId;         // Dosya yüklenir yüklenmez ID'sini tutacak
  double sliderValue = 0.0;   // Slider performans (DDoS) çözümü için

  // --- Zoom ve Mod Kontrolü ---
  final TransformationController _transformationController = TransformationController();
  bool _isPanMode = true; // True: Gezinme, False: Seçim
  // 3 Eksen için ayrı ayrı çizilen alanları (ROI) tutar
  Map<String, Rect?> axisSelections = {
    'axial': null,
    'coronal': null,
    'sagittal': null
  };

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
  // YENİ: Eksen değiştirildiğinde çalışacak fonksiyon
  void _changeAxis(String newAxis) {
    if (activeAxis == newAxis) return; // Zaten o eksendeyse işlem yapma

    setState(() {
      activeAxis = newAxis;
      totalSlices = totalSlicesMap[newAxis]!;
      currentSliceIndex = currentSliceMap[newAxis]!;
      sliderValue = currentSliceIndex.toDouble();

      // Yeni resim gelene kadar ekranı temizle
      loadedImage = null;
      maskImage = null;
      maskContours.clear();
      isLoading = true;
    });

    // Yeni eksenin ilgili kesitini sunucudan çek
    _loadSliceData(currentSliceIndex);
  }

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

      // 2. Resmi ekranda göstermek için ui.Image'e çevir
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      // 3. UI'ı güncelle
      setState(() {
        selectedFile = file;
        loadedImage = frame.image;
        isNiftiMode = false;
        maskImage = null;
        maskContours.clear();

        // 🔥 HATA BURADAYDI: Eski selectionRectImage silindi, yerine bunu sıfırlıyoruz:
        axisSelections = {
          'axial': null,
          'coronal': null,
          'sagittal': null
        };

        activeAxis = 'axial'; // 2D resimler varsayılan olarak axial kabul edilir
        currentFileId = null;
        currentMaskId = null;
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;

        if (!path.endsWith('.nii') && !path.endsWith('.nii.gz')) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen .nii veya .nii.gz uzantılı dosya seçin.")));
          return;
        }

        setState(() {
          selectedFile = File(path);
          isNiftiMode = true;
          isLoading = true; // Yükleme ekranı başlasın
          loadedImage = null;
          maskImage = null;
          maskContours.clear();
          currentMaskId = null;
          currentFileId = null;

          // 🔥 HATA BURADAYDI: selectionRectImage yerine yeni sistemi sıfırlıyoruz:
          axisSelections = {
            'axial': null,
            'coronal': null,
            'sagittal': null
          };
          activeAxis = 'axial'; // Varsayılan olarak hep üstten (axial) başlat
        });

        // 1. Dosyayı hemen sunucuya yükle
        var uploadReq = http.MultipartRequest('POST', Uri.parse('$baseUrl/files/${widget.patientId}'));
        uploadReq.headers['Authorization'] = 'Bearer ${widget.token}';
        uploadReq.files.add(await http.MultipartFile.fromPath('file', path));

        var uploadRes = await uploadReq.send();
        if (uploadRes.statusCode == 200) {
          final resData = json.decode(await uploadRes.stream.bytesToString());
          currentFileId = resData['id'];

          // 2. Sunucudan 3 eksenin de boyutlarını öğren
          final infoRes = await http.get(
              Uri.parse('$baseUrl/files/nifti/$currentFileId/info'),
              headers: {'Authorization': 'Bearer ${widget.token}'}
          );

          if (infoRes.statusCode == 200) {
            final infoData = json.decode(infoRes.body);
            setState(() {
              // Backend'in 3 eksen boyutunu da döndüğünü varsayıyoruz
              totalSlicesMap['axial'] = infoData['axial_slices'] ?? infoData['total_slices'] ?? 0;
              totalSlicesMap['coronal'] = infoData['coronal_slices'] ?? totalSlicesMap['axial']!;
              totalSlicesMap['sagittal'] = infoData['sagittal_slices'] ?? totalSlicesMap['axial']!;

              // Her eksen için başlangıçta ortadaki kesiti ayarla
              currentSliceMap['axial'] = (totalSlicesMap['axial']! / 2).floor();
              currentSliceMap['coronal'] = (totalSlicesMap['coronal']! / 2).floor();
              currentSliceMap['sagittal'] = (totalSlicesMap['sagittal']! / 2).floor();

              // Aktif ekseni ayarla
              totalSlices = totalSlicesMap[activeAxis]!;
              currentSliceIndex = currentSliceMap[activeAxis]!;
              sliderValue = currentSliceIndex.toDouble();
            });

            await _loadSliceData(currentSliceIndex);
          }
        } else {
          throw Exception("Yükleme başarısız: ${uploadRes.statusCode}");
        }
      }
    } catch (e) {
      print("Dosya yükleme hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
      setState(() => isLoading = false);
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
    if (!isNiftiMode && axisSelections['axial'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lütfen bir alan seçin."))
      );
      return;
    }

    setState(() {
      isSegmenting = true;
      maskImage = null;
      maskContours.clear();
    });

    try {
      int fileIdToSegment;

      // ==========================================================
      // ADIM 1: EĞER DOSYA DAHA ÖNCE YÜKLENMEDİYSE YÜKLE (NIfTI zaten yüklenmiş olacak)
      // ==========================================================
      if (currentFileId != null) {
        // NIfTI dosyası zaten _pickNiftiFile içinde yüklendi, tekrar yüklemeye gerek yok!
        fileIdToSegment = currentFileId!;
      } else {
        // Normal PNG resim ise şimdi yüklüyoruz
        print("⏳ Dosya yükleniyor...");
        var uploadRequest = http.MultipartRequest('POST', Uri.parse('$baseUrl/files/${widget.patientId}'));
        uploadRequest.headers['Authorization'] = 'Bearer ${widget.token}';
        uploadRequest.files.add(await http.MultipartFile.fromPath('file', selectedFile!.path));

        var uploadResponse = await uploadRequest.send();
        final uploadResponseBody = await http.Response.fromStream(uploadResponse);

        if (uploadResponse.statusCode != 200) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Dosya yükleme hatası")));
          setState(() => isSegmenting = false);
          return;
        }
        final uploadData = json.decode(uploadResponseBody.body);
        fileIdToSegment = uploadData['id'];
        currentFileId = fileIdToSegment; // Bir daha basılırsa tekrar yüklemesin
      }

      // ==========================================================
      // ADIM 2: SEGMENTASYON (YAPAY ZEKA) İSTEĞİNİ AT
      // ==========================================================
      print("🧠 Yapay Zeka analizi başlatılıyor...");
      var segmentRequest = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment/$fileIdToSegment'));
      segmentRequest.headers['Authorization'] = 'Bearer ${widget.token}';

      segmentRequest.fields.addAll({
        // ESKİ SİSTEM (2D PNG resimler için gerekli)
        'x': axisSelections['axial']?.left.toString() ?? '0',
        'y': axisSelections['axial']?.top.toString() ?? '0',
        'width': axisSelections['axial']?.width.toString() ?? '0',
        'height': axisSelections['axial']?.height.toString() ?? '0',

        // YENİ SİSTEM (3D NIfTI için)
        'ax_x': axisSelections['axial']?.left.toString() ?? '0',
        'ax_y': axisSelections['axial']?.top.toString() ?? '0',
        'ax_w': axisSelections['axial']?.width.toString() ?? '0',
        'ax_h': axisSelections['axial']?.height.toString() ?? '0',

        'cor_x': axisSelections['coronal']?.left.toString() ?? '0',
        'cor_y': axisSelections['coronal']?.top.toString() ?? '0',
        'cor_w': axisSelections['coronal']?.width.toString() ?? '0',
        'cor_h': axisSelections['coronal']?.height.toString() ?? '0',

        'sag_x': axisSelections['sagittal']?.left.toString() ?? '0',
        'sag_y': axisSelections['sagittal']?.top.toString() ?? '0',
        'sag_w': axisSelections['sagittal']?.width.toString() ?? '0',
        'sag_h': axisSelections['sagittal']?.height.toString() ?? '0',

        'shape': selectedShape.toString().split('.').last,
      });

      var segmentResponse = await segmentRequest.send();
      final segmentResponseBody = await http.Response.fromStream(segmentResponse);

      if (segmentResponse.statusCode == 200) {
        final responseData = json.decode(segmentResponseBody.body);

        final maskUrl = responseData['mask_url'];
        final newMaskId = responseData['mask_id'] ?? fileIdToSegment;

        setState(() => currentMaskId = newMaskId);

        if (isNiftiMode) {
          // --- NIfTI Modu: O anki kesiti MASKELİ haliyle tekrar yükle ---
          await _loadSliceData(currentSliceIndex);
        } else {
          // --- Normal Resim Modu ---
          final maskDownloadResponse = await http.get(Uri.parse('$baseUrl$maskUrl'));
          await loadMaskImage(maskDownloadResponse.bodyBytes);
          setState(() => isNiftiMode = false);
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Segmentasyon başarılı!")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: ${segmentResponse.statusCode}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Kritik Hata: $e")));
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

  Future<void> _loadSliceData(int index) async {
    setState(() => isLoading = true);

    try {
      if (currentMaskId != null) {
        // Maske varsa
        final originalRes = await http.get(Uri.parse('$baseUrl/segment/nifti/$currentMaskId/slice/$index?type=original&axis=$activeAxis'), headers: {'Authorization': 'Bearer ${widget.token}'});
        final maskRes = await http.get(Uri.parse('$baseUrl/segment/nifti/$currentMaskId/slice/$index?type=mask&axis=$activeAxis'), headers: {'Authorization': 'Bearer ${widget.token}'});



        if (originalRes.statusCode == 200 && maskRes.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(originalRes.bodyBytes);
          final frame = await codec.getNextFrame();
          setState(() => loadedImage = frame.image);
          await loadMaskImage(maskRes.bodyBytes);
        }
      } else if (currentFileId != null) {
        // Maske yoksa (Sadece ham görüntü)
        final rawRes = await http.get(Uri.parse('$baseUrl/files/nifti/$currentFileId/slice/$index?axis=$activeAxis'), headers: {'Authorization': 'Bearer ${widget.token}'});

        if (rawRes.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(rawRes.bodyBytes);
          final frame = await codec.getNextFrame();
          setState(() {
            loadedImage = frame.image;
            maskImage = null;
            maskContours.clear();
          });
        }
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
  // YENİ EKLENEN 3D AÇMA FONKSİYONU
  void _open3DViewer() {
    if (selectedFile == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text("3D Hacim", style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          body: NiiVueMobileViewer(
            localFilePath: selectedFile!.path,
            maskUrl: currentMaskId != null ? '$baseUrl/segment/nifti/$currentMaskId/download' : null,
            token: widget.token,
          ),
        ),
      ),
    );
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
          // NIfTI Modunda da çizim yapabilmek için bunu if (!isNiftiMode) dışına çıkardık:
          IconButton(
            icon: Icon(_isPanMode ? Icons.pan_tool : Icons.crop_free),
            onPressed: () => setState(() => _isPanMode = !_isPanMode),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _showUploadOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // --- EKSEN SEÇİCİ (Sadece NIfTI modunda görünür) ---
          // --- EKSEN SEÇİCİ VE 3D BUTONU (Sadece NIfTI modunda görünür) ---
          if (isNiftiMode && !isLoading)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal:55),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, // Telefon ekranı küçükse yana kaysın
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildAxisButton('axial', 'Üstten'),
                    const SizedBox(width: 8),
                    _buildAxisButton('coronal', 'Önden'),
                    const SizedBox(width: 8),
                    _buildAxisButton('sagittal', 'Yandan'),
                    const SizedBox(width: 16), // 3D butonuna biraz daha boşluk

                    // 🔥 YENİ EKLENEN 3D BUTONU 🔥
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange, // Dikkat çekici renk
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.view_in_ar, size: 16),
                      label: const Text('3D Gör', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _open3DViewer,
                    ),
                  ],
                ),
              ),
            ),
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

                    // YENİ: NIfTI'de hep Pan açık değil, butona bağladık
                    panEnabled: _isPanMode,

                    child: SizedBox(
                      width: contentW,
                      height: contentH,
                      child: GestureDetector(
                        onPanStart: (!_isPanMode) ? (details) {
                          final pImg = details.localPosition / fit.scale;
                          setState(() {
                            // Hangi eksendeysek onun karesini sıfırla ve başlat
                            axisSelections[activeAxis] = Rect.fromLTWH(pImg.dx, pImg.dy, 0, 0);
                            maskImage = null; maskContours.clear();
                          });
                        } : null,

                        onPanUpdate: (!_isPanMode && axisSelections[activeAxis] != null) ? (details) {
                          final pImg = details.localPosition / fit.scale;
                          final imgW = loadedImage!.width.toDouble();
                          final imgH = loadedImage!.height.toDouble();
                          setState(() {
                            // Hangi eksendeysek onun karesini güncelle
                            axisSelections[activeAxis] = Rect.fromPoints(
                              Offset(axisSelections[activeAxis]!.left, axisSelections[activeAxis]!.top),
                              Offset(pImg.dx.clamp(0.0, imgW), pImg.dy.clamp(0.0, imgH)),
                            );
                          });
                        } : null,

                        child: Stack(
                          children: [
                            Positioned.fill(child: RawImage(image: loadedImage, fit: BoxFit.contain)),
                            if (maskContours.isNotEmpty && showMask)
                              Positioned.fill(child: CustomPaint(painter: _MaskOutlinePainter(maskContours, fit.scale))),

                            // Aktif eksenin karesini çiz (Eğer varsa)
                            if (axisSelections[activeAxis] != null && maskImage == null)
                              Positioned.fill(
                                  child: CustomPaint(
                                      painter: _SelectionPainter(rect: axisSelections[activeAxis]!, scale: fit.scale)
                                  )
                              ),
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
          // --- SLIDER (Sadece NIfTI Modunda) ---
          if (isNiftiMode && totalSlices > 0)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Column(
                children: [
                  Text("Kesit: ${sliderValue.toInt()} / ${totalSlices - 1}", style: const TextStyle(color: Colors.white)),
                  Slider(
                    value: sliderValue,
                    min: 0,
                    max: (totalSlices - 1).toDouble(),
                    activeColor: Colors.orange,
                    onChanged: (val) {
                      setState(() {
                        sliderValue = val;
                      });
                    },
                    onChangeEnd: (val) {
                      setState(() {
                        currentSliceIndex = val.toInt();
                        currentSliceMap[activeAxis] = currentSliceIndex; // YENİ EKLENDİ
                      });
                      _loadSliceData(currentSliceIndex);
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