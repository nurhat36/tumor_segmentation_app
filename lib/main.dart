import 'package:flutter/material.dart';
import 'package:tumor_segmentation_app2/pages/image_list_page.dart'; // Bu sayfa belki kullanılmıyordur, gerekliyse düzeltirsin.
import 'services/api_service.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'pages/patient_list_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tümör Segmentasyon Uygulaması',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
      ),
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
  bool _obscurePassword = true;

  // Google ile giriş metodu
  void _handleGoogleSignIn() async {
    setState(() => isLoading = true);

    try {
      final token = await api.signInWithGoogle(); // ApiService'deki Google giriş metodunu çağır

      setState(() => isLoading = false);

      if (token!= null) {
        // Google ile giriş başarılı
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        // Backend'in user_id'yi Google'dan aldığı email veya Google ID'ye göre oluşturup token içine koyduğunu varsayıyoruz
        // Bu kısım senin backend'inin token yapısına göre değişebilir.
        // Örneğin: 'sub' alanı Google user ID'si olabilir veya 'email' olabilir.
        // int? userId = decodedToken['user_id']; // Eğer backend user_id'yi jwt'ye ekliyorsa
        print('Google ile giriş başarılı! Backend token: $token');
        // print('User ID (decoded from backend token): $userId'); // Eğer 'user_id' varsa

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google ile giriş başarılı!")),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PatientListPage(
              token: token,
            ),
          ),
        );
      } else {
        // Google ile giriş başarısız veya iptal edildi
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google ile giriş başarısız oldu veya iptal edildi.")),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      print("Google girişinde bir hata oluştu: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google ile girişte bir hata oluştu: $e")),
      );
    }
  }

  void login() async {
    setState(() => isLoading = true);

    try {
      final token = await api.login(
        usernameController.text,
        passwordController.text,
      );

      setState(() => isLoading = false);

      if (token!= null) {
        // Token decode (user_id backend token içine koyuyorsa)
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);

        int? userId = decodedToken['user_id'];

        print('User ID: $userId');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Giriş başarılı!")),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PatientListPage(
              token: token,
            ),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/İkon Alanı
                  Icon(
                    Icons.medical_services,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  // Başlık
                  Text(
                    "Tümör Segmentasyon",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Uygulamasına Hoşgeldiniz",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),

                  // Kullanıcı Adı Alanı
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: "Kullanıcı Adı",
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şifre Alanı
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: "Şifre",
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword =!_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                  ),
                  const SizedBox(height: 24),

                  // Giriş Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isLoading? null : login,
                      child: isLoading
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : const Text(
                        "Giriş Yap",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Yeni eklendi: Google ile Giriş Butonu
                  // Yeni eklendi: Google ile Giriş Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton( // .icon kullanımını kaldırdık
                      onPressed: isLoading ? null : _handleGoogleSignIn,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[400]!),
                        backgroundColor: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center, // Ortalamak için
                        children: [

                          const SizedBox(width: 12), // İkon ile metin arasına boşluk
                          const Flexible( // Metnin taşmasını engeller
                            child: FittedBox( // Gerekirse metni küçültür
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "Google ile Giriş Yap",
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16), // Diğer butonlarla arasına boşluk ekle

                  // Kayıt Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: isLoading? null : register,
                      child: const Text("Hesap Oluştur"),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Yardım Metni
                  Text(
                    "Hesabınız yok mu? Hesap Oluştur butonuna tıklayın",
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}