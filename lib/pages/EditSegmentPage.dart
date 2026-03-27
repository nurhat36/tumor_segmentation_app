import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'NiiVueMobileViewer.dart';
import 'package:http/http.dart' as http;


class EditSegmentPage extends StatefulWidget {
  final String? originalImageUrl;
  final ui.Image? originalMemoryImage;
  final String? maskImageUrl;          // Listeden gelirse maskeyi bulmak için
  final List<Offset> initialContour;
  final int maskId;
  final String token;

  final bool isNiftiMode;
  final String activeAxis;
  final String? niftiFilePath;
  final Map<String, int>? totalSlicesMap;
  final Map<String, int>? currentSliceMap;

  const EditSegmentPage({
    super.key,
    this.originalImageUrl,
    this.originalMemoryImage,
    this.maskImageUrl,
    required this.initialContour,
    required this.maskId,
    required this.token,

    this.isNiftiMode = false, // Varsayılan olarak normal resim kabul eder
    this.activeAxis = 'axial',
    this.niftiFilePath,
    this.totalSlicesMap,
    this.currentSliceMap,
  });

  @override
  State<EditSegmentPage> createState() => _EditSegmentPageState();
}

class _EditSegmentPageState extends State<EditSegmentPage> {
  ui.Image? _loadedImage;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  late List<Offset> editablePoints;
  final TransformationController _transformationController = TransformationController();

  List<List<Offset>> _history = [];
  int _historyIndex = 0;
  bool _isEditMode = false;
  int? _activePointIndex;
  double _currentScale = 1.0;

  int _currentSliceIndex = 0;
  int _totalSlices = 0;
  String _activeAxis = 'axial';
  late Map<String, int> _currentSliceMap;
  late Map<String, int> _totalSlicesMap;
  static const String baseUrl = "http://oncovisionai.com.tr/api";

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {

      if (widget.isNiftiMode && widget.totalSlicesMap != null) {
        _activeAxis = widget.activeAxis;
        _totalSlicesMap = Map.from(widget.totalSlicesMap!);
        _currentSliceMap = Map.from(widget.currentSliceMap!);
        _totalSlices = _totalSlicesMap[_activeAxis]!;
        _currentSliceIndex = _currentSliceMap[_activeAxis]!;
      }

      // 1. Orijinal Arka Plan Resmini Yükle
      if (widget.originalMemoryImage != null) {
        _loadedImage = widget.originalMemoryImage;
      } else if (widget.originalImageUrl != null) {
        _loadedImage = await _fetchImage(widget.originalImageUrl!);
      }

      // 2. Noktaları (Konturları) Belirle
      if (widget.initialContour.isNotEmpty) {
        editablePoints = List.from(widget.initialContour);
      } else if (widget.maskImageUrl != null) {
        // Liste sayfasından gelmiş, maskeden noktaları bulmamız lazım!
        ui.Image maskImg = await _fetchImage(widget.maskImageUrl!);
        editablePoints = await _extractContourFromMask(maskImg);
      } else {
        editablePoints = [];
      }

      _history.add(List.from(editablePoints));

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Görüntü yüklenirken hata oluştu: $e";
        });
      }
    }
  }

  Future<ui.Image> _fetchImage(String url) async {
    final networkImage = NetworkImage(url);
    final completer = Completer<ui.Image>();
    networkImage.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
            (info, _) => completer.complete(info.image),
        onError: (err, stack) => completer.completeError(err),
      ),
    );
    return await completer.future;
  }

  // Siyah/Beyaz maskeden kırmızı/mavi noktaları bulma algoritması
  Future<List<Offset>> _extractContourFromMask(ui.Image maskImg) async {
    final byteData = await maskImg.toByteData();
    if (byteData == null) return [];
    final width = maskImg.width;
    final height = maskImg.height;
    final pixels = byteData.buffer.asUint8List();
    final visited = List.generate(width * height, (_) => false);

    bool isWhite(int x, int y) {
      if (x < 0 || x >= width || y < 0 || y >= height) return false;
      return pixels[(y * width + x) * 4] > 128;
    }

    Offset? startPoint;
    for (int y = 0; y < height && startPoint == null; y++) {
      for (int x = 0; x < width && startPoint == null; x++) {
        if (isWhite(x, y)) startPoint = Offset(x.toDouble(), y.toDouble());
      }
    }
    if (startPoint == null) return [];

    final currentPath = <Offset>[startPoint];
    Offset currentPoint = startPoint;
    int i = 0;
    while (i < width * height * 2) {
      bool moved = false;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = currentPoint.dx.round() + dx;
          final ny = currentPoint.dy.round() + dy;
          if (isWhite(nx, ny) && !visited[ny * width + nx]) {
            bool isEdge = false;
            for (int ndy = -1; ndy <= 1; ndy++) {
              for (int ndx = -1; ndx <= 1; ndx++) {
                if (ndx == 0 && ndy == 0) continue;
                if (!isWhite(nx + ndx, ny + ndy)) { isEdge = true; break; }
              }
              if (isEdge) break;
            }
            if (isEdge) {
              currentPoint = Offset(nx.toDouble(), ny.toDouble());
              currentPath.add(currentPoint);
              visited[ny * width + nx] = true;
              moved = true; break;
            }
          }
        }
        if (moved) break;
      }
      if (!moved) break;
      i++;
    }

    final simplified = <Offset>[];
    if (currentPath.isNotEmpty) {
      simplified.add(currentPath.first);
      Offset lastAdded = currentPath.first;

      for (int i = 1; i < currentPath.length; i++) {
        // İki nokta arasındaki mesafe 25 pikselden (veya 30) büyükse yeni nokta ekle
        if ((currentPath[i] - lastAdded).distance >= 25.0) {
          simplified.add(currentPath[i]);
          lastAdded = currentPath[i];
        }
      }
    }
    return simplified;
  }

  void _onTransformChanged() => setState(() => _currentScale = _transformationController.value.getMaxScaleOnAxis());

  void _recordHistory() {
    if (_historyIndex < _history.length - 1) _history = _history.sublist(0, _historyIndex + 1);
    _history.add(List.from(editablePoints));
    _historyIndex++;
    setState(() {});
  }

  void _undo() {
    if (_historyIndex > 0) setState(() { _historyIndex--; editablePoints = List.from(_history[_historyIndex]); });
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) setState(() { _historyIndex++; editablePoints = List.from(_history[_historyIndex]); });
  }

  // ========================================================
  // YENİ EKLENEN NIfTI FONKSİYONLARI
  // ========================================================
  Future<bool> _saveCurrentSliceSilently() async {
    if (!widget.isNiftiMode || widget.maskId == 0 || _loadedImage == null) return true;
    final width = _loadedImage!.width.toDouble();
    final height = _loadedImage!.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.black);

    if (editablePoints.isNotEmpty) {
      final path = Path()..moveTo(editablePoints[0].dx, editablePoints[0].dy);
      for (int i = 1; i < editablePoints.length; i++) path.lineTo(editablePoints[i].dx, editablePoints[i].dy);
      path.close();
      canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);
    }
    final newMaskImage = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final byteData = await newMaskImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/segment/nifti/${widget.maskId}/slice/$_currentSliceIndex/update?axis=$_activeAxis'));
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(http.MultipartFile.fromBytes('file', pngBytes, filename: 'slice_update.png'));
      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<void> _fetchSlice(int index, String axis) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalRes = await http.get(Uri.parse('$baseUrl/segment/nifti/${widget.maskId}/slice/$index?type=original&axis=$axis&t=$timestamp'), headers: {'Authorization': 'Bearer ${widget.token}'});
      final maskRes = await http.get(Uri.parse('$baseUrl/segment/nifti/${widget.maskId}/slice/$index?type=mask&axis=$axis&t=$timestamp'), headers: {'Authorization': 'Bearer ${widget.token}'});

      if (originalRes.statusCode == 200 && maskRes.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(originalRes.bodyBytes);
        final frame = await codec.getNextFrame();
        _loadedImage = frame.image;

        final maskCodec = await ui.instantiateImageCodec(maskRes.bodyBytes);
        final maskFrame = await maskCodec.getNextFrame();
        editablePoints = await _extractContourFromMask(maskFrame.image);
        _history = [List.from(editablePoints)];
        _historyIndex = 0; _activePointIndex = null;
      }
    } catch (e) { print(e); } finally { setState(() => _isLoading = false); }
  }

  void _changeSlice(int delta) async {
    int newSlice = _currentSliceIndex + delta;
    if (newSlice >= 0 && newSlice < _totalSlices) {
      setState(() => _isLoading = true);
      await _saveCurrentSliceSilently();
      _currentSliceIndex = newSlice;
      _currentSliceMap[_activeAxis] = newSlice;
      await _fetchSlice(newSlice, _activeAxis);
    }
  }

  void _changeAxis(String newAxis) async {
    if (_activeAxis == newAxis) return;
    setState(() => _isLoading = true);
    await _saveCurrentSliceSilently();
    _activeAxis = newAxis;
    _totalSlices = _totalSlicesMap[newAxis]!;
    _currentSliceIndex = _currentSliceMap[newAxis]!;
    await _fetchSlice(_currentSliceIndex, _activeAxis);
  }

  // ========================================================
  // YENİ: 3D ve EKSEN KONTROLLERİ
  // ========================================================
  void _open3DViewer() {
    if (widget.niftiFilePath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("3D Hacim", style: TextStyle(color: Colors.white)), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          backgroundColor: Colors.black,
          body: NiiVueMobileViewer(
            localFilePath: widget.niftiFilePath!,
            maskUrl: null,
            token: widget.token,
          ),
        ),
      ),
    );
  }

  Widget _buildAxisButton(String axis, String label) {
    bool isActive = _activeAxis == axis;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? Colors.blue : Colors.grey[800],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero
      ),
      onPressed: () => _changeAxis(axis), // Tıklandığında aktif olarak ekseni değiştirir
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }


  // ========================================================
  // KAYDET: Noktalardan yeni Siyah/Beyaz maske üretip geri yollar
  // ========================================================
  Future<void> _saveEdit() async {
    if (_loadedImage == null) return;
    setState(() => _isSaving = true);

    final width = _loadedImage!.width.toDouble();
    final height = _loadedImage!.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Arka plan siyah
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.black);

    // İçi beyaz poligon
    if (editablePoints.isNotEmpty) {
      final path = Path()..moveTo(editablePoints[0].dx, editablePoints[0].dy);
      for (int i = 1; i < editablePoints.length; i++) {
        path.lineTo(editablePoints[i].dx, editablePoints[i].dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);
    }

    // Resmi PNG byte'larına çevir
    final newMaskImage = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final byteData = await newMaskImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // Hem noktaları hem de hazır siyah/beyaz PNG dosyasını geri gönderiyoruz!
    // Hem noktaları hem de hazır siyah/beyaz PNG dosyasını geri gönderiyoruz!
    Navigator.pop(context, {
      'points': editablePoints,
      'maskBytes': pngBytes,
      'activeAxis': widget.isNiftiMode ? _activeAxis : null,
      'currentSliceMap': widget.isNiftiMode ? _currentSliceMap : null,
    });
  }

  int? _findNearestPoint(Offset localPosition, double baseScale) {
    double hitRadius = 40.0 / baseScale / _currentScale;
    double minDistance = hitRadius;
    int? closestIndex;
    final imagePos = localPosition / baseScale;
    for (int i = 0; i < editablePoints.length; i++) {
      final distance = (editablePoints[i] - imagePos).distance;
      if (distance < minDistance) { minDistance = distance; closestIndex = i; }
    }
    return closestIndex;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isSaving) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.blueAccent),
              const SizedBox(height: 20),
              Text(_isSaving ? "Maske Oluşturuluyor..." : "Görüntü İşleniyor...", style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _loadedImage == null) {
      return Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: const Text("Hata"), backgroundColor: Colors.red[900]), body: Center(child: Text(_errorMessage ?? "Hata", style: const TextStyle(color: Colors.white))));
    }

    final imgW = _loadedImage!.width.toDouble();
    final imgH = _loadedImage!.height.toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isEditMode ? "✏️ Çizim Modu" : "🖐️ Gezinme Modu"),
        backgroundColor: _isEditMode ? Colors.blueAccent[700] : Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _historyIndex > 0 ? _undo : null),
          IconButton(icon: const Icon(Icons.redo), onPressed: _historyIndex < _history.length - 1 ? _redo : null),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveEdit),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 30.0), // 30.0 değerini artırarak daha da yukarı alabilirsin
        child: FloatingActionButton.extended(
          onPressed: () => setState(() { _isEditMode = !_isEditMode; _activePointIndex = null; }),
          backgroundColor: _isEditMode ? Colors.green : Colors.blue,
          icon: Icon(_isEditMode ? Icons.done : Icons.edit),
          label: Text(_isEditMode ? "Bitir" : "Düzenle"),
        ),
      ),

      body: Column(
        children: [
          // --- YENİ EKLENEN ÜST BAR (Sadece NIfTI ise görünür) ---
          if (widget.isNiftiMode)
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
                      icon: const Icon(Icons.view_in_ar, size: 16),
                      label: const Text('3D Gör', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _open3DViewer,
                    ),
                  ],
                ),
              ),
            ),

          // --- MEVCUT GÖRÜNTÜ ALANI ---
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double baseScale = (constraints.maxWidth / imgW < constraints.maxHeight / imgH) ? constraints.maxWidth / imgW : constraints.maxHeight / imgH;
                return Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.1, maxScale: 20.0, panEnabled: !_isEditMode,
                    child: SizedBox(
                      width: imgW * baseScale, height: imgH * baseScale,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: _isEditMode ? (d) { final i = _findNearestPoint(d.localPosition, baseScale); if (i != null) setState(() => _activePointIndex = i); } : null,
                        onPanUpdate: (_isEditMode && _activePointIndex != null) ? (d) {
                          final delta = d.delta / baseScale / _currentScale;
                          setState(() => editablePoints[_activePointIndex!] = Offset((editablePoints[_activePointIndex!].dx + delta.dx).clamp(0.0, imgW), (editablePoints[_activePointIndex!].dy + delta.dy).clamp(0.0, imgH)));
                        } : null,
                        onPanEnd: _isEditMode ? (_) { if (_activePointIndex != null) { _recordHistory(); setState(() => _activePointIndex = null); } } : null,
                        onTapUp: _isEditMode ? (d) {
                          if (_findNearestPoint(d.localPosition, baseScale) == null) {
                            setState(() => editablePoints.add(Offset((d.localPosition / baseScale).dx.clamp(0.0, imgW), (d.localPosition / baseScale).dy.clamp(0.0, imgH))));
                            _recordHistory();
                          }
                        } : null,
                        onLongPressStart: _isEditMode ? (d) {
                          final i = _findNearestPoint(d.localPosition, baseScale);
                          if (i != null) { setState(() { editablePoints.removeAt(i); _activePointIndex = null; }); _recordHistory(); }
                        } : null,
                        child: Stack(
                          children: [
                            Positioned.fill(child: RawImage(image: _loadedImage, fit: BoxFit.contain)),
                            Positioned.fill(child: CustomPaint(painter: _InvariantPainter(points: editablePoints, baseScale: baseScale, zoomLevel: _currentScale, activeIndex: _activePointIndex, isEditMode: _isEditMode))),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // --- EKSİK OLAN ALT BAR BURASI (SLIDER VE OKLAR) ---
          if (widget.isNiftiMode && _totalSlices > 0)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Column(
                children: [
                  Text("Kesit: $_currentSliceIndex / ${_totalSlices - 1}", style: const TextStyle(color: Colors.white)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.orange, size: 20),
                        onPressed: () => _changeSlice(-1),
                      ),
                      Expanded(
                        child: Slider(
                          value: _currentSliceIndex.toDouble(),
                          min: 0,
                          max: (_totalSlices - 1).toDouble(),
                          activeColor: Colors.orange,
                          onChanged: (val) {
                            setState(() { _currentSliceIndex = val.toInt(); });
                          },
                          onChangeEnd: (val) async {
                            int newSlice = val.toInt();
                            setState(() => _isLoading = true);
                            await _saveCurrentSliceSilently(); // Slider bırakılınca kaydet
                            _currentSliceIndex = newSlice;
                            _currentSliceMap[_activeAxis] = newSlice;
                            await _fetchSlice(newSlice, _activeAxis); // Yeni resmi getir
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 20),
                        onPressed: () => _changeSlice(1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InvariantPainter extends CustomPainter {
  final List<Offset> points;
  final double baseScale;
  final double zoomLevel;
  final int? activeIndex;
  final bool isEditMode;

  _InvariantPainter({required this.points, required this.baseScale, required this.zoomLevel, this.activeIndex, required this.isEditMode});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    // SegmentPage ile birebir aynı görünecek sabit değerler:
    final stroke = 2.0; // SegmentPage'deki çizgi kalınlığı
    final dotRadius = 2.5; // SegmentPage'deki standart nokta büyüklüğü
    final activeRadius = 4.0; // Edit modunda seçili/tutulan nokta biraz daha büyük olsun

    final fillPaint = Paint()..color = isEditMode ? Colors.blue.withOpacity(0.20) : Colors.white.withOpacity(0.05)..style = PaintingStyle.fill;
    final linePaint = Paint()..color = isEditMode ? Colors.blueAccent : Colors.greenAccent..style = PaintingStyle.stroke..strokeWidth = stroke..isAntiAlias = true;
    final dotPaint = Paint()..color = Colors.redAccent..style = PaintingStyle.fill;
    final activeDotPaint = Paint()..color = Colors.amber..style = PaintingStyle.fill;

    final path = Path()..moveTo(points[0].dx * baseScale, points[0].dy * baseScale);
    for (int i = 1; i < points.length; i++) path.lineTo(points[i].dx * baseScale, points[i].dy * baseScale);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);

    if (isEditMode) {
      for (int i = 0; i < points.length; i++) {
        final point = points[i] * baseScale;
        canvas.drawCircle(point, (i == activeIndex) ? activeRadius : dotRadius, (i == activeIndex) ? activeDotPaint : dotPaint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _InvariantPainter old) => true;
}