import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui; // Sahte resim oluşturmak için gerekli

// Kendi projenin dosya yoluna göre burayı kontrol et
import 'package:tumor_segmentation_app2/pages/EditSegmentPage.dart';

// ==========================================
// TEST İÇİN SAHTE (DUMMY) RESİM OLUŞTURUCU
// ==========================================
Future<ui.Image> createDummyImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 100x100 boyutlarında siyah sahte bir resim çiziyoruz
  canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = Colors.black);
  return await recorder.endRecording().toImage(100, 100);
}

void main() {
  testWidgets('EditSegmentPage arayüzü çökmeden yükleniyor mu?', (WidgetTester tester) async {
    // 1. Önce sayfanın hata vermemesi için sahte resmimizi üretiyoruz
    final dummyImage = await createDummyImage();

    // 2. Sayfayı sanal ekrana çizdir
    await tester.pumpWidget(
      MaterialApp(
        home: EditSegmentPage(
          originalMemoryImage: dummyImage, // Sahte resmi sayfaya verdik!
          initialContour: const [],
          maskId: 1,
          token: "dummy_token",
        ),
      ),
    );

    // 3. KRİTİK NOKTA: Yükleme ekranının (CircularProgressIndicator) bitmesini bekle!
    await tester.pumpAndSettle();

    // 4. Şimdi yazıları ve butonları arayabiliriz
    expect(find.text('🖐️ Gezinme Modu'), findsOneWidget);
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('Düzenle butonuna basınca Çizim Moduna geçiyor mu?', (WidgetTester tester) async {
    final dummyImage = await createDummyImage();

    await tester.pumpWidget(
      MaterialApp(
        home: EditSegmentPage(
          originalMemoryImage: dummyImage,
          initialContour: const [],
          maskId: 1,
          token: "dummy_token",
        ),
      ),
    );

    // Yükleme ekranını bekle
    await tester.pumpAndSettle();

    // Düzenle butonuna bas
    await tester.tap(find.text('Düzenle'));

    // Animasyonların ve State değişiminin tamamlanmasını bekle
    await tester.pumpAndSettle();

    // Arayüz değişti mi kontrol et
    expect(find.text('✏️ Çizim Modu'), findsOneWidget);
    expect(find.text('Bitir'), findsOneWidget);
    expect(find.byIcon(Icons.done), findsOneWidget);
  });
}