import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'ktp_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KTP Registration',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const RegisterScreen(),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _ktpService = KtpService();
  bool _isLoading = false;

  // 4 Controller untuk data yang akan di-autofill
  final _nikController = TextEditingController();
  final _namaController = TextEditingController();
  final _ttlController = TextEditingController();
  final _genderController = TextEditingController();

  Future<void> _processKtp(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 90);

    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    File imageFile = File(pickedFile.path);

    try {
      // 1. Scan KTP
      KtpDataSimple data = await _ktpService.scanKtp(imageFile);

      // 2. Auto-Fill Form Fields
      setState(() {
        if (data.nik != null) _nikController.text = data.nik!;
        if (data.nama != null) _namaController.text = data.nama!;
        if (data.tempatTglLahir != null) _ttlController.text = data.tempatTglLahir!;
        if (data.jenisKelamin != null) _genderController.text = data.jenisKelamin!;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data NIK, Nama, TTL & Jenis Kelamin berhasil diisi!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal Membaca KTP: $e')),
        );
      }
    } finally {
      // 3. Hapus foto dari penyimpanan sementara
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nikController.dispose();
    _namaController.dispose();
    _ttlController.dispose();
    _genderController.dispose();
    _ktpService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrasi KTP')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _processKtp(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _processKtp(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Upload File'),
                  ),
                ),
              ],
            ),
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 24),
            _buildField(_nikController, 'NIK (16 Digit)', Icons.badge, isNumber: true),
            _buildField(_namaController, 'Nama Lengkap', Icons.person),
            _buildField(_ttlController, 'Tempat/Tanggal Lahir', Icons.cake),
            _buildField(_genderController, 'Jenis Kelamin', Icons.wc),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final dataSimpan = {
                  'nik': _nikController.text,
                  'nama': _namaController.text,
                  'ttl': _ttlController.text,
                  'jenis_kelamin': _genderController.text,
                };
                // Menggunakan debugPrint sesuai rekomendasi linter Flutter
                debugPrint('Data Terdaftar: $dataSimpan');
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan Registrasi', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}