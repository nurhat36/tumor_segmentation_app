import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl = "http://oncovisionai.com.tr/api";

  // ==========================
  // REGISTER
  // ==========================
  Future<bool> register(String username, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": username,
        "password": password,
      }),
    );

    return response.statusCode == 200;
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
  // UPLOAD FILE
  // ==========================
  Future<Map<String, dynamic>?> uploadFile(
      String token, int patientId, File file) async {
    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/files/$patientId"),
    );

    request.headers["Authorization"] = "Bearer $token";

    request.files.add(
      await http.MultipartFile.fromPath("file", file.path),
    );

    var response = await request.send();

    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      return json.decode(respStr);
    }

    return null;
  }

  // ==========================
  // AUTO SEGMENT
  // ==========================
  Future<bool> autoSegment(String token, int fileId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/segment/$fileId"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    return response.statusCode == 200;
  }

  // ==========================
  // MANUAL SEGMENT
  // ==========================
  Future<bool> manualSegment(
      String token, int fileId, File maskFile) async {
    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/segment/manual/$fileId"),
    );

    request.headers["Authorization"] = "Bearer $token";

    request.files.add(
      await http.MultipartFile.fromPath("mask_file", maskFile.path),
    );

    var response = await request.send();

    return response.statusCode == 200;
  }

  // ==========================
  // GET MY MASKS
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

  // ==========================
  // DELETE MASK
  // ==========================
  Future<bool> deleteMask(String token, int maskId) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/segment/$maskId"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    return response.statusCode == 200;
  }
  Future<List<dynamic>> getPatients(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/patients'),
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
      Uri.parse('$baseUrl/patients/'),
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
  Future<List<dynamic>> getImagesByPatient(
      String token, int patientId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/images'),
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
  Future<void> uploadFileToPatient(
      String token, int patientId, File file) async {

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/files/$patientId'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
      ),
    );

    var response = await request.send();

    if (response.statusCode != 200) {
      throw Exception("Upload başarısız");
    }
  }
}