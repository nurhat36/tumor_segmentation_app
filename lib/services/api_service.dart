import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl = "http://192.168.1.188:8000";
  // Android emulator için 10.0.2.2 kullan
  // Gerçek cihaz için bilgisayarın IP adresini yaz

  Future<bool> register(String username, String password) async {
    final url = Uri.parse("$baseUrl/auth/register");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>?> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/token'),
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {"username": username, "password": password},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // Eğer backend user_id de dönüyorsa direk al:
      return {
        "token": data["access_token"],
        "user_id": data["user_id"],  // backend bu alanı döndürmeli
      };
    }
    return null;
  }
  Future<List<dynamic>> getSegmentedImages(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/my-masks'), // userId göndermeye gerek yok
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Veriler alınamadı: ${response.statusCode}");
    }
  }
  Future<void> deleteSegmentedImage(String token, int id) async {
    final url = Uri.parse("$baseUrl/segment/$id");
    final response = await http.delete(
      url,
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Silinemedi: ${response.body}");
    }
  }

}
