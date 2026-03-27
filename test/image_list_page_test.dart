import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Kendi ImageListPage dosyanızın yolunu import edin
import 'package:tumor_segmentation_app2/pages/image_list_page.dart';

void main() {
  testWidgets('ImageListPage arayüzü temel bileşenlerle yükleniyor mu?', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageListPage(
          token: "dummy_token",
          patientId: 1,
          patientName: "Kadir", // Sayfa başlığı için test verisi
        ),
      ),
    );

    // AppBar başlığı doğru formattı mı? ("Kadir - Dosyalar")
    expect(find.text('Kadir - Dosyalar'), findsOneWidget);

    // Sekmeler (Tabs) ekranda var mı?
    expect(find.text('2D Görüntüler (PNG)'), findsOneWidget);
    expect(find.text('3D MR (NIfTI)'), findsOneWidget);

    // Yeni analiz oluşturma butonu var mı?
    expect(find.text('Yeni Analiz'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}