import 'package:flutter/material.dart';
import 'package:tumor_segmentation_app2/pages/image_list_page.dart';
import 'services/api_service.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FastAPI Login Demo',
      home: LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiService api = ApiService();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;

  void login() async {
    setState(() => isLoading = true);

    try {
      final loginData = await api.login(
        usernameController.text,
        passwordController.text,
      );

      setState(() => isLoading = false);

      if (loginData != null) {
        String token = loginData["token"];

        // Token'ı decode et
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        int userId = decodedToken['user_id'];

        print('User ID: $userId');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Giriş başarılı! Kullanıcı ID: $userId")),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ImageListPage(token: token, userId: userId),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Giriş başarısız!")),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bir hata oluştu: $e")),

      );
      print("Bir hata oluştu: $e");
    }
  }


  void register() async {
    setState(() => isLoading = true);
    bool success = await api.register(usernameController.text, passwordController.text);
    setState(() => isLoading = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kayıt başarılı! Giriş yapabilirsiniz.")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kayıt başarısız!")),

      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FastAPI Login")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: "Kullanıcı Adı"),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Şifre"),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (isLoading) const CircularProgressIndicator(),
            if (!isLoading) Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(onPressed: login, child: const Text("Giriş Yap")),
                ElevatedButton(onPressed: register, child: const Text("Kayıt Ol")),
              ],
            )
          ],
        ),
      ),
    );
  }
}
