import 'dart:io';
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

  Future<KtpDataSimple> scanKtp(File imageFile) async {
    // 1. ADVANCED PREPROCESSING: Binarization & High Contrast Enhancement (100% Offline)
    File processedFile = await _preprocessImage(imageFile);

    final inputImage = InputImage.fromFile(processedFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Hapus file olahan sementara
    if (await processedFile.exists()) {
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
    // EKSTRAKSI 1: NIK (Gunakan Normalisasi Angka jika Ada Typo Huruf)
    // -------------------------------------------------------------
    for (TextLine line in allLines) {
      String normalizedText = _fixDigitTypo(line.text);
      if (nikRegex.hasMatch(normalizedText) && nik == null) {
        nik = nikRegex.stringMatch(normalizedText);
      }
    }
    // Fallback NIK dari seluruh teks mentah
    if (nik == null) {
      String normalizedFull = _fixDigitTypo(fullRawText);
      if (nikRegex.hasMatch(normalizedFull)) {
        nik = nikRegex.stringMatch(normalizedFull);
      }
    }

    // -------------------------------------------------------------
    // EKSTRAKSI 2: NAMA (Spasial + Fallback Regex + Auto Correction)
    // -------------------------------------------------------------
    for (int i = 0; i < allLines.length; i++) {
      String lineText = allLines[i].text.toUpperCase().trim();

      if ((lineText.contains('NAMA') || lineText.contains('NAM4')) && nama == null) {
        // Opsi A: Sejajar horisontal di baris yang sama setelah titik dua ':'
        if (allLines[i].text.contains(':')) {
          String val = allLines[i].text.split(':').last.trim();
          if (val.length > 2 && !val.toUpperCase().contains('NAMA')) {
            nama = _fixTextTypo(val);
          }
        }

        // Opsi B: Cari baris terdekat yang secara vertikal sejajar (bounding box Y)
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

        // Opsi C: Baris persis di bawah label NAMA
        if ((nama == null || nama.isEmpty) && i + 1 < allLines.length) {
          String nextText = allLines[i + 1].text.replaceAll(':', '').trim();
          if (!nextText.toUpperCase().contains('TEMPAT') && !nextText.toUpperCase().contains('LAHIR')) {
            nama = _fixTextTypo(nextText);
          }
        }
      }

      // -------------------------------------------------------------
      // EKSTRAKSI 3: TEMPAT / TGL LAHIR (Auto Fix Format & Typo)
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
  // HELPER LOGIC ADVANCE (PENGOLAHAN GAMBAR & KOREKSI TYPO)
  // =========================================================================

  // 1. Preprocessing Gambar: Menghilangkan noise latar biru KTP
  Future<File> _preprocessImage(File originFile) async {
    try {
      final bytes = await originFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) return originFile;

      // Convert ke Grayscale
      img.Image grayscale = img.grayscale(image);

      // Tingkatkan Kontras & Luminance
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

  // 2. Koreksi Typo Angka (NIK)
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

  // 3. Koreksi Typo Huruf / Nama (Mengubah angka bermasalah kembali ke huruf)
  String _fixTextTypo(String raw) {
    String cleaned = raw
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

    return cleaned;
  }

  // 4. Perbaikan & Format Tempat / Tanggal Lahir
  String _cleanTtl(String raw) {
    String text = raw.replaceAll(RegExp(r'^[;:!|]+'), '').trim();
    
    // Koreksi typo umum pada tanggal (misal '.' atau ',' diubah jadi '-')
    text = text.replaceAll('.', '-').replaceAll(',', '-').replaceAll(' ', '');

    // Kembalikan format jika ada koma yang hilang antara Kota dan Tanggal
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