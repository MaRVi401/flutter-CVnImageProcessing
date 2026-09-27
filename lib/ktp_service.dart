import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class KtpDataSimple {
  final String? nik;
  final String? nama;
  final String? tempatTglLahir;
  final String? jenisKelamin;

  KtpDataSimple({this.nik, this.nama, this.tempatTglLahir, this.jenisKelamin});
}

class KtpService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// FUNGSI UTAMA SCAN KTP
  /// Menerima file gambar & opsi 4 titik sudut (keypoints dari YOLO Pose)
  Future<KtpDataSimple> scanKtp(File imageFile, {List<Point<double>>? corners}) async {
    // 1. CROP & UNWARP: Jika ada 4 titik dari YOLO Pose, potong & luruskan KTP
    File imageToProcess = imageFile;
    if (corners != null && corners.length == 4) {
      File? cropped = await _cropAndWarpKtp(imageFile, corners);
      if (cropped != null) {
        imageToProcess = cropped;
      }
    }

    // 2. ADVANCED PREPROCESSING: Grayscale & Contrast Enhancement
    File processedFile = await _preprocessImage(imageToProcess);

    final inputImage = InputImage.fromFile(processedFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Hapus file olahan sementara
    if (await processedFile.exists() && processedFile.path != imageFile.path) {
      await processedFile.delete();
    }

    String fullRawText = recognizedText.text;
    List<TextLine> allLines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        allLines.add(line);
      }
    }

    String? nik;
    String? nama;
    String? tempatTglLahir;
    String? jenisKelamin;

    final RegExp nikRegex = RegExp(r'\b\d{16}\b');

    // -------------------------------------------------------------
    // EKSTRAKSI 1: NIK
    // -------------------------------------------------------------
    for (TextLine line in allLines) {
      String normalizedText = _fixDigitTypo(line.text);
      if (nikRegex.hasMatch(normalizedText) && nik == null) {
        nik = nikRegex.stringMatch(normalizedText);
      }
    }
    if (nik == null) {
      String normalizedFull = _fixDigitTypo(fullRawText);
      if (nikRegex.hasMatch(normalizedFull)) {
        nik = nikRegex.stringMatch(normalizedFull);
      }
    }

    // -------------------------------------------------------------
    // EKSTRAKSI 2: NAMA
    // -------------------------------------------------------------
    for (int i = 0; i < allLines.length; i++) {
      String lineText = allLines[i].text.toUpperCase().trim();

      if ((lineText.contains('NAMA') || lineText.contains('NAM4')) && nama == null) {
        if (allLines[i].text.contains(':')) {
          String val = allLines[i].text.split(':').last.trim();
          if (val.length > 2 && !val.toUpperCase().contains('NAMA')) {
            nama = _fixTextTypo(val);
          }
        }

        if (nama == null || nama.isEmpty) {
          for (TextLine candidate in allLines) {
            double yDiff = (candidate.boundingBox.top - allLines[i].boundingBox.top).abs();
            if (yDiff < 22 && candidate != allLines[i]) {
              String candText = candidate.text.replaceAll(':', '').trim();
              if (candText.isNotEmpty && !candText.toUpperCase().contains('NAMA')) {
                nama = _fixTextTypo(candText);
                break;
              }
            }
          }
        }

        if ((nama == null || nama.isEmpty) && i + 1 < allLines.length) {
          String nextText = allLines[i + 1].text.replaceAll(':', '').trim();
          if (!nextText.toUpperCase().contains('TEMPAT') && !nextText.toUpperCase().contains('LAHIR')) {
            nama = _fixTextTypo(nextText);
          }
        }
      }

      // -------------------------------------------------------------
      // EKSTRAKSI 3: TEMPAT / TGL LAHIR
      // -------------------------------------------------------------
      if ((lineText.contains('LAHIR') || lineText.contains('TEMPAT')) && tempatTglLahir == null) {
        List<String> rawParts = [];
        for (TextLine candidate in allLines) {
          double yDiff = (candidate.boundingBox.top - allLines[i].boundingBox.top).abs();
          if (yDiff < 22) {
            String cText = candidate.text.replaceAll(':', '').trim();
            if (cText.isNotEmpty && !cText.toUpperCase().contains('TEMPAT') && !cText.toUpperCase().contains('LAHIR')) {
              rawParts.add(cText);
            }
          }
        }

        String rawTtl = rawParts.isNotEmpty ? rawParts.join(' ') : allLines[i].text;
        if (rawTtl.contains(':')) {
          rawTtl = rawTtl.split(':').last.trim();
        }

        tempatTglLahir = _cleanTtl(rawTtl);
      }

      // -------------------------------------------------------------
      // EKSTRAKSI 4: JENIS KELAMIN
      // -------------------------------------------------------------
      if (jenisKelamin == null) {
        if (lineText.contains('LAKI') || lineText.contains('LAK1') || lineText.contains('LAK1-LAK1')) {
          jenisKelamin = 'LAKI-LAKI';
        } else if (lineText.contains('PEREMPUAN') || lineText.contains('PEREM') || lineText.contains('PUAN')) {
          jenisKelamin = 'PEREMPUAN';
        }
      }
    }

    return KtpDataSimple(
      nik: nik,
      nama: nama,
      tempatTglLahir: tempatTglLahir,
      jenisKelamin: jenisKelamin,
    );
  }

  // =========================================================================
  // HELPER LOGIC (CROP & WARP DARI KEYPOINTS YOLO)
  // =========================================================================

  Future<File?> _cropAndWarpKtp(File originFile, List<Point<double>> corners) async {
    try {
      final bytes = await originFile.readAsBytes();
      img.Image? srcImage = img.decodeImage(bytes);
      if (srcImage == null) return null;

      // Cari bounding box terluar dari 4 titik sudut
      double minX = corners.map((p) => p.x).reduce(min);
      double maxX = corners.map((p) => p.x).reduce(max);
      double minY = corners.map((p) => p.y).reduce(min);
      double maxY = corners.map((p) => p.y).reduce(max);

      int x = minX.toInt().clamp(0, srcImage.width - 1);
      int y = minY.toInt().clamp(0, srcImage.height - 1);
      int w = (maxX - minX).toInt().clamp(1, srcImage.width - x);
      int h = (maxY - minY).toInt().clamp(1, srcImage.height - y);

      // Potong gambar berdasarkan area KTP yang terdeteksi
      img.Image cropped = img.copyCrop(srcImage, x: x, y: y, width: w, height: h);

      String tempPath = '${originFile.parent.path}/temp_ktp_cropped.jpg';
      File croppedFile = File(tempPath);
      await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 100));

      return croppedFile;
    } catch (_) {
      return null;
    }
  }

  // Preprocessing Gambar
  Future<File> _preprocessImage(File originFile) async {
    try {
      final bytes = await originFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) return originFile;

      img.Image grayscale = img.grayscale(image);
      img.Image adjusted = img.adjustColor(
        grayscale,
        contrast: 1.8,
        brightness: 1.1,
      );

      String tempPath = '${originFile.parent.path}/temp_ocr_clean.jpg';
      File processedFile = File(tempPath);
      await processedFile.writeAsBytes(img.encodeJpg(adjusted, quality: 100));

      return processedFile;
    } catch (_) {
      return originFile;
    }
  }

  String _fixDigitTypo(String raw) {
    return raw
        .replaceAll('B', '8')
        .replaceAll('D', '0')
        .replaceAll('o', '0')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll('S', '5')
        .replaceAll('Z', '2')
        .replaceAll('A', '4')
        .replaceAll('G', '6')
        .replaceAll('q', '9');
  }

  String _fixTextTypo(String raw) {
    return raw
        .replaceAll('4', 'A')
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('3', 'E')
        .replaceAll('5', 'S')
        .replaceAll('8', 'B')
        .replaceAll('6', 'G')
        .replaceAll(RegExp(r'[^a-zA-Z\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanTtl(String raw) {
    String text = raw.replaceAll(RegExp(r'^[;:!|]+'), '').trim();
    text = text.replaceAll('.', '-').replaceAll(',', '-').replaceAll(' ', '');

    final dateReg = RegExp(r'\d{2}-\d{2}-\d{4}');
    if (dateReg.hasMatch(text)) {
      String dateStr = dateReg.stringMatch(text)!;
      String cityStr = text.replaceAll(dateStr, '').replaceAll('-', '').trim();
      cityStr = _fixTextTypo(cityStr);
      if (cityStr.isNotEmpty) {
        return '$cityStr, $dateStr';
      }
      return dateStr;
    }

    return text;
  }

  void dispose() {
    _textRecognizer.close();
  }
}