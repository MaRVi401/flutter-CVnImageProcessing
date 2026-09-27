import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'ktp_service.dart';
import 'yolo_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
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
  final _yoloService = YoloService();

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  bool _isLoading = false;

  List<Point<double>>? _detectedCorners;

  // Controllers untuk Form Auto-Fill
  final _nikController = TextEditingController();
  final _namaController = TextEditingController();
  final _ttlController = TextEditingController();
  final _genderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    // 1. Load Model YOLO TFLite
    await _yoloService.loadModel();

    // 2. Initialize Camera
    if (_cameras.isNotEmpty) {
      _cameraController = CameraController(
        _cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);

      // 3. Start Real-time Frame Processing
      _cameraController!.startImageStream((CameraImage image) async {
        if (_isProcessingFrame || _isLoading) return;
        _isProcessingFrame = true;

        try {
          YoloPoseResult? result = await _yoloService.detectFromCameraImage(image);
          if (mounted) {
            setState(() {
              _detectedCorners = result?.keypoints.map((p) => Point(p[0], p[1])).toList();
            });
          }
        } catch (_) {
        } finally {
          _isProcessingFrame = false;
        }
      });
    }
  }

  // A. FITUR 1: AMBIL FOTO DARI LIVE PREVIEW KAMERA
  Future<void> _captureAndProcessKtp() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => _isLoading = true);

    try {
      final XFile photo = await _cameraController!.takePicture();
      File imageFile = File(photo.path);

      KtpDataSimple data = await _ktpService.scanKtp(
        imageFile,
        corners: _detectedCorners,
      );

      _fillFormData(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KTP Berhasil Discan via Kamera!')),
        );
      }

      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal Membaca KTP: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // B. FITUR 2: IMPORT / UPLOAD DARI GALERI HP
  Future<void> _importFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    File imageFile = File(pickedFile.path);

    try {
      KtpDataSimple data = await _ktpService.scanKtp(imageFile);

      _fillFormData(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KTP Berhasil Discan dari Galeri!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal Membaca KTP: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _fillFormData(KtpDataSimple data) {
    setState(() {
      if (data.nik != null) _nikController.text = data.nik!;
      if (data.nama != null) _namaController.text = data.nama!;
      if (data.tempatTglLahir != null) _ttlController.text = data.tempatTglLahir!;
      if (data.jenisKelamin != null) _genderController.text = data.jenisKelamin!;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _yoloService.dispose();
    _ktpService.dispose();
    _nikController.dispose();
    _namaController.dispose();
    _ttlController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live KTP Scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live Preview Kamera + Scanner Overlay
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isCameraInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        CustomPaint(
                          painter: ScannerOverlayPainter(corners: _detectedCorners),
                        ),
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 12),

            // DUA TOMBOL: KAMERA & GALERI BERSISIAN
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _captureAndProcessKtp,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Ambil Foto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _importFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Upload File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _buildField(_nikController, 'NIK (16 Digit)', Icons.badge, isNumber: true),
            _buildField(_namaController, 'Nama Lengkap', Icons.person),
            _buildField(_ttlController, 'Tempat/Tanggal Lahir', Icons.cake),
            _buildField(_genderController, 'Jenis Kelamin', Icons.wc),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: () {
                final dataSimpan = {
                  'nik': _nikController.text,
                  'nama': _namaController.text,
                  'ttl': _ttlController.text,
                  'jenis_kelamin': _genderController.text,
                };
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
      padding: const EdgeInsets.only(bottom: 12.0),
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

// Custom Painter untuk Live Scanning Overlay (Garis Hijau & 4 Titik Merah)
class ScannerOverlayPainter extends CustomPainter {
  final List<Point<double>>? corners;

  ScannerOverlayPainter({this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    if (corners != null && corners!.length == 4) {
      final path = Path()
        ..moveTo(corners![0].x * size.width, corners![0].y * size.height)
        ..lineTo(corners![1].x * size.width, corners![1].y * size.height)
        ..lineTo(corners![2].x * size.width, corners![2].y * size.height)
        ..lineTo(corners![3].x * size.width, corners![3].y * size.height)
        ..close();

      canvas.drawPath(path, borderPaint);

      for (var p in corners!) {
        canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), 6, pointPaint);
      }
    } else {
      final rect = Rect.fromLTWH(
        size.width * 0.05,
        size.height * 0.1,
        size.width * 0.9,
        size.height * 0.8,
      );
      final guidePaint = Paint()
        ..color = Colors.white.withAlpha(128)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        guidePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}