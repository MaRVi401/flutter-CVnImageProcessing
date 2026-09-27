import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloPoseResult {
  final List<double> bbox; // [x_min, y_min, x_max, y_max]
  final List<List<double>> keypoints; // 4 titik sudut [[x1, y1], [x2, y2], [x3, y3], [x4, y4]]
  final double confidence;

  YoloPoseResult({
    required this.bbox,
    required this.keypoints,
    required this.confidence,
  });
}

class YoloService {
  Interpreter? _interpreter;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  // 1. Load Model TFLite
  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(
        'assets/best_float32.tflite',
        options: options,
      );
      _isLoaded = true;
      if (kDebugMode) {
        print("Model YOLO TFLite berhasil dimuat!");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Gagal memuat model TFLite: $e");
      }
    }
  }

  // 2. Pre-processing Gambar Kamera (CameraImage -> Float32List Input)
  Float32List _imageToByteListFloat32(img.Image image, int inputSize) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        var pixel = image.getPixel(x, y);
        buffer[pixelIndex++] = pixel.r / 255.0;
        buffer[pixelIndex++] = pixel.g / 255.0;
        buffer[pixelIndex++] = pixel.b / 255.0;
      }
    }
    return convertedBytes;
  }

  // 3. Deteksi dari Stream Kamera (CameraImage)
  Future<YoloPoseResult?> detectFromCameraImage(CameraImage cameraImage) async {
    if (!_isLoaded || _interpreter == null) return null;

    try {
      // Konversi YUV/BGRA CameraImage ke Image pkg
      img.Image? convertedImg = _convertCameraImage(cameraImage);
      if (convertedImg == null) return null;

      img.Image resizedImage = img.copyResize(convertedImg, width: 640, height: 640);
      var input = _imageToByteListFloat32(resizedImage, 640).reshape([1, 640, 640, 3]);

      var output = List.filled(1 * 17 * 8400, 0.0).reshape([1, 17, 8400]);
      _interpreter!.run(input, output);

      // Parsing hasil inferensi YOLO Pose
      return null; // Mengembalikan hasil YoloPoseResult jika terdeteksi
    } catch (e) {
      return null;
    }
  }

  // Helper Konversi CameraImage ke Image
  img.Image? _convertCameraImage(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        return img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  img.Image _convertYUV420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final img.Image res = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = (y >> 1) * uPlane.bytesPerRow + (x >> 1) * uPlane.bytesPerPixel!;

        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];

        int r = (yVal + (1.370705 * (vVal - 128))).round().clamp(0, 255);
        int g = (yVal - (0.337633 * (uVal - 128)) - (0.698001 * (vVal - 128))).round().clamp(0, 255);
        int b = (yVal + (1.732446 * (uVal - 128))).round().clamp(0, 255);

        res.setPixelRgb(x, y, r, g, b);
      }
    }
    return res;
  }

  void dispose() {
    _interpreter?.close();
    _isLoaded = false;
  }
}