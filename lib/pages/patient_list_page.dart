import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'image_list_page.dart';

class PatientListPage extends StatefulWidget {
  final String token;

  const PatientListPage({super.key, required this.token});

  @override
  State<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends State<PatientListPage> {
  final ApiService apiService = ApiService();
  late Future<List<dynamic>> patientsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      patientsFuture = apiService.getPatients(widget.token);
    });
  }

  // ================== HASTA EKLE ==================
  void _showAddPatientDialog() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Yeni Hasta Ekle"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Hasta Adı",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(context);

              try {
                await apiService.createPatient(widget.token, name);
                _refresh();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Hasta eklendi")),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Hata: $e")),
                );
              }
            },
            child: const Text("Ekle"),
          ),
        ],
      ),
    );
  }

  // ================== HASTA SİL ==================
  void _deletePatient(int id) async {
    final confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Silme Onayı"),
        content: const Text("Bu hastayı silmek istiyor musunuz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("İptal"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sil"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await apiService.deletePatient(widget.token, id);
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hasta silindi")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Hastalar"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          )
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: patientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Hata: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Hiç hasta bulunamadı."));
          }

          final patients = snapshot.data!;

          return ListView.builder(
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(patient["name"] ?? "İsimsiz"),
                  subtitle: Text("ID: ${patient["id"]}"),

                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ImageListPage(
                          token: widget.token,
                          patientId: patient["id"],
                          patientName: patient["name"],
                        ),
                      ),
                    );
                  },

                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deletePatient(patient["id"]),
                      ),
                      const Icon(Icons.arrow_forward_ios),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPatientDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}