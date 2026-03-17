import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

class ApiService {
  // DİKKAT: Eğer sunucunda SSL (HTTPS) yoksa ve direkt 8000 portuna atıyorsan:
  // "http://oncovisionai.com.tr:8000/api" yapmalısın.
  // SSL varsa "https://oncovisionai.com.tr/api" yapmalısın.
  final String baseUrl = "http://oncovisionai.com.tr/api";
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '636599479269-8f0sbt9dpchjfit9so8la30heiqc8ckl.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  // ==========================
  // GOOGLE LOGIN (Detaylı Loglu)
  // ==========================
  Future<String?> signInWithGoogle() async {


    try {
      // Önceki takılı kalmış oturumları temizle (Gerekirse açabilirsiniz)
      // await _googleSignIn.signOut();


      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {

        return null;
      }


      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final String? accessToken = googleAuth.accessToken;
      final String? idToken = googleAuth.idToken;



      if (accessToken != null) {
        return await _sendGoogleTokenToBackend(accessToken);
      } else {
        return null;
      }
    } catch (error, stackTrace) {

      return null;
    }
  }

  // Google Access Token'ı FastAPI backend'ine gönderme (Detaylı Loglu)
  Future<String?> _sendGoogleTokenToBackend(String token) async {
    final url = Uri.parse('$baseUrl/auth/google');



    final requestBody = jsonEncode({'token': token});


    try {

      final response = await http.post(
        url,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: requestBody,
      );



      if (response.statusCode == 200) {

        final responseData = jsonDecode(response.body);

        final String? backendAccessToken = responseData['access_token'];

        if (backendAccessToken != null) {

          return backendAccessToken;
        } else {
          return null;
        }

      } else if (response.statusCode == 422) {

        return null;
      } else if (response.statusCode == 400) {
        return null;
      } else {
        return null;
      }
    } catch (e, stackTrace) {

      return null;
    }
  }

  // Google çıkış işlemi
  Future<void> signOutGoogle() async {
    try {
      print('🟡 Google oturumu kapatılıyor...');
      await _googleSignIn.signOut();
      print('🟢 Google oturumu başarıyla kapatıldı.');
    } catch (e) {
      print('🔴 Google oturum kapatma hatası: $e');
    }
  }
  // ==========================
  // REGISTER
  // ==========================
  Future<bool> register(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/auth/register"), // Eğer hata devam ederse sonuna '/' ekle: "$baseUrl/auth/register/"
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      // 1. ADIM: Hatayı konsola yazdırarak neyin ters gittiğini görelim
      print("--- REGISTER LOG ---");
      print("Status Code: ${response.statusCode}");
      print("Response Body: ${response.body}");
      print("--------------------");

      // 2. ADIM: FastAPI kayıt işleminde 201 (Created) de dönebilir. İkisini de kabul et.
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        // 400 (Kullanıcı zaten var) veya 422 (Geçersiz veri) durumları buraya düşer
        return false;
      }
    } catch (e) {
      // Sunucuya hiç ulaşılamazsa (Örn: İnternet yok, bağlantı reddedildi)
      print("Kayıt İsteği Hatası: $e");
      return false;
    }
  }

  // ==========================
  // LOGIN (OAuth2 form)
  // ==========================
  Future<String?> login(String username, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/token"),
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: {
        "username": username,
        "password": password,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data["access_token"];
    }
    return null;
  }

  // ==========================
  // PATIENTS (HASTALAR)
  // ==========================
  Future<List<dynamic>> getPatients(String token) async {
    // DÜZELTME: FastAPI yönlendirme (redirect) yapıp token'ı düşürmesin diye sonuna '/' eklendi.
    final response = await http.get(
      Uri.parse('$baseUrl/patients/'),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Hastalar alınamadı: ${response.statusCode}");
    }
  }

  Future<Map<String, dynamic>> createPatient(String token, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/patients/'), // Sonunda '/' var
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
      body: jsonEncode({"name": name}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception("Hasta oluşturulamadı");
    }
  }

  Future<void> deletePatient(String token, int patientId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/patients/$patientId'),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Hasta silinemedi");
    }
  }

  // ==========================
  // FILES (DOSYALAR / RESİMLER)
  // ==========================
  Future<List<dynamic>> getImagesByPatient(String token, int patientId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/files/$patientId'), // React fileService.js ile eşlendi
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Bu hastaya ait dosyalar alınamadı");
    }
  }

  Future<Map<String, dynamic>?> uploadFileToPatient(String token, int patientId, File file) async {
    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/files/$patientId"),
    );

    request.headers["Authorization"] = "Bearer $token";
    request.files.add(await http.MultipartFile.fromPath("file", file.path));

    var response = await request.send();

    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      return json.decode(respStr);
    }
    return null;
  }

  // ==========================
  // AUTO SEGMENT (GÜNCELLENDİ)
  // ==========================
  Future<bool> autoSegment(String token, int fileId, {Map<String, dynamic>? roiCoords}) async {
    // DÜZELTME: Backend form-data ve koordinat bekliyor, düz POST değil MultipartRequest kullanılmalı.
    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/segment/$fileId"),
    );

    request.headers["Authorization"] = "Bearer $token";

    // React'taki ile aynı varsayılan koordinatları gönderiyoruz
    request.fields['x'] = roiCoords?['x']?.toString() ?? '0';
    request.fields['y'] = roiCoords?['y']?.toString() ?? '0';
    request.fields['z'] = roiCoords?['z']?.toString() ?? '0';
    request.fields['width'] = '64';
    request.fields['height'] = '64';
    request.fields['shape'] = 'rectangle';

    var response = await request.send();
    return response.statusCode == 200;
  }

  // ==========================
  // MANUAL SEGMENT
  // ==========================
  Future<bool> manualSegment(String token, int fileId, File maskFile) async {
    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/segment/manual/$fileId"),
    );

    request.headers["Authorization"] = "Bearer $token";
    request.files.add(await http.MultipartFile.fromPath("mask_file", maskFile.path));

    var response = await request.send();
    return response.statusCode == 200;
  }

  // ==========================
  // MASKS
  // ==========================
  Future<List<dynamic>> getMyMasks(String token) async {
    final response = await http.get(
      Uri.parse("$baseUrl/my-masks"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception("Maskeler alınamadı");
  }

  Future<bool> deleteMask(String token, int maskId) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/segment/$maskId"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    return response.statusCode == 200;
  }
  Future<List<dynamic>> getPatientFiles(String token, int patientId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/files/$patientId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Dosyalar çekilemedi');
  }

// 2. Bir dosyaya ait tüm maskeleri çeker (Dün yazdığımız yeni router)
  Future<List<dynamic>> getMasksByFile(String token, int fileId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/masks/file/$fileId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Maskeler çekilemedi');
  }

// 3. Dosyayı kalıcı olarak siler (Yukarıda yazdığımız yeni router)
  Future<void> deleteFile(String token, int fileId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/files/$fileId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) throw Exception('Dosya silinemedi');
  }
}