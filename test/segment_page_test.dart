import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Kendi SegmentPage dosyanızın yolunu import edin
import 'package:tumor_segmentation_app2/pages/SegmentPage.dart';

void main() {
  testWidgets('SegmentPage arayüzü çökmeden yükleniyor mu?', (WidgetTester tester) async {

    // 1. Sayfayı sanal ekrana çizdir (Sanki uygulama açılmış gibi)
    await tester.pumpWidget(
      const MaterialApp(
        home: SegmentPage(
          token: "dummy_token",
          patientId: 1,
        ),
      ),
    );

    // 2. Sayfa yüklendiğinde "Görüntü Analizi" veya "MR Analiz (3D)" yazısı var mı?
    // Başlangıçta NIfTI modu kapalı olduğu için "Görüntü Analizi" yazmalı.
    expect(find.text('Görüntü Analizi'), findsOneWidget);

    // 3. Ekranda Upload (Yükle) butonu var mı kontrol et
    expect(find.byIcon(Icons.upload_file), findsOneWidget);

    // 4. Ekranda Play (Segmentasyonu başlat) butonu var mı?
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

  });

  testWidgets('Upload butonuna basınca menü açılıyor mu?', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SegmentPage(token: "dummy", patientId: 1),
      ),
    );

    // Upload butonunu bul ve tıkla
    await tester.tap(find.byIcon(Icons.upload_file));

    // Animasyonların bitmesini bekle
    await tester.pumpAndSettle();

    // Alt menü (BottomSheet) açılmış olmalı, içinde "Galeri" yazmalı
    expect(find.text('Galeri (PNG/JPG)'), findsOneWidget);
    expect(find.text('MR Dosyası (.nii)'), findsOneWidget);
  });
}