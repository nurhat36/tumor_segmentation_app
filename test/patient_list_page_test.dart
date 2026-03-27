import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Kendi PatientListPage dosyanızın yolunu import edin
import 'package:tumor_segmentation_app2/pages/patient_list_page.dart';

void main() {
  testWidgets('PatientListPage arayüzü çökmeden açılıyor mu?', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PatientListPage(token: "dummy_token"),
      ),
    );

    // Sayfa başlığı doğru mu?
    expect(find.text('Hastalar'), findsOneWidget);

    // Yenileme ikonu AppBar'da var mı?
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    // Sağ alttaki ekleme butonu var mı?
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('Ekle butonuna basınca Yeni Hasta Ekle dialogu açılıyor mu?', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PatientListPage(token: "dummy_token"),
      ),
    );

    // Ekle butonuna tıkla
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle(); // Animasyonun(popup) bitmesini bekle

    // Açılan pencerede "Yeni Hasta Ekle" ve "Hasta Adı" yazmalı
    expect(find.text('Yeni Hasta Ekle'), findsOneWidget);
    expect(find.text('Hasta Adı'), findsOneWidget);

    // Penceredeki İptal ve Ekle butonları görünür olmalı
    expect(find.text('İptal'), findsOneWidget);
    expect(find.text('Ekle'), findsOneWidget);
  });
}