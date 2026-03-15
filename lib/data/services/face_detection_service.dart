// lib/data/services/face_detection_service.dart
//
// STRICT FACE VERIFICATION — Multi-region LBP from live NV21 frames
// ─────────────────────────────────────────────────────────────────────────────
// Both registration AND attendance use the same NV21 Y-plane extraction path,
// same resolution (medium = 640×480), same front camera.
// This eliminates domain mismatch and makes cross-matching impossible.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/employee_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public result types
// ─────────────────────────────────────────────────────────────────────────────
enum FaceMatchStatus {
  matched,
  notRecognized,
  livenessFailure,
  insufficientData,
  noFaceDetected,
  needsMigration,
}

class FaceMatchResult {
  final FaceMatchStatus status;
  final EmployeeModel? employee;
  final String message;
  final double? bestScore;

  const FaceMatchResult({
    required this.status,
    this.employee,
    required this.message,
    this.bestScore,
  });

  bool get isMatched => status == FaceMatchStatus.matched;

  static const FaceMatchResult noFace = FaceMatchResult(
    status: FaceMatchStatus.noFaceDetected,
    message: 'No face detected. Please position your face in the frame.',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal types
// ─────────────────────────────────────────────────────────────────────────────
class _MLBP {
  final List<double> regions; // 7 × 128 = 896 values
  final List<double> geometry; // pairwise landmark distances, L2-normalised

  const _MLBP({required this.regions, required this.geometry});
}

class _MatchScore {
  final double mlbp;
  final double geo;
  final double weighted;
  const _MatchScore({
    required this.mlbp,
    required this.geo,
    required this.weighted,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceDetectionService
// ─────────────────────────────────────────────────────────────────────────────
class FaceDetectionService {
  FaceDetector? _faceDetector;
  bool _isInitialized = false;
  bool _isProcessing = false;

  static const int _kVersion = 5;

  // ── Thresholds ────────────────────────────────────────────────────────────
  static const double _mlbpWeight = 0.75;
  static const double _geoWeight = 0.25;
  static const double _finalThreshold = 0.90;
  static const double _mlbpMinScore = 0.85;
  static const double _geoMinScore = 0.80;
  static const double _minCandidateGap = 0.03;

  // ── Liveness ──────────────────────────────────────────────────────────────
  static const double _maxYawDeg = 12.0;
  static const double _maxPitchDeg = 10.0;
  static const double _minEyeOpenProb = 0.60;
  static const double _minFaceSize = 0.15;

  // ── Sampling ──────────────────────────────────────────────────────────────
  static const int _registrationFrames = 10;
  static const int _attendanceFrames = 5;
  final List<_MLBP> _samples = [];

  // ── Region definitions (x%, y%, w%, h%) on 128×128 chip ─────────────────
  static const List<List<double>> _regions = [
    [0.10, 0.05, 0.80, 0.20], // forehead
    [0.05, 0.20, 0.38, 0.22], // left eye + brow
    [0.57, 0.20, 0.38, 0.22], // right eye + brow
    [0.25, 0.40, 0.50, 0.22], // nose
    [0.10, 0.60, 0.38, 0.22], // left cheek
    [0.52, 0.60, 0.38, 0.22], // right cheek
    [0.15, 0.75, 0.70, 0.22], // mouth + chin
  ];

  static const int _lbpBins = 128;
  static const int _chipSize = 128;

  // ─────────────────────────────────────────────────────────────────────────
  void initialize() {
    if (_isInitialized) return;
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _isInitialized = true;
  }

  void resetSamples() => _samples.clear();
  int get sampleCount => _samples.length;

  // ── Face detection ────────────────────────────────────────────────────────
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (!_isInitialized) initialize();
    if (_faceDetector == null) return [];
    try {
      return await _faceDetector!.processImage(inputImage);
    } catch (e) {
      debugPrint('[FDS] detectFaces: $e');
      return [];
    }
  }

  Future<List<Face>> detectFacesFromFile(File imageFile) async =>
      detectFaces(InputImage.fromFile(imageFile));

  Future<List<Face>> detectFacesFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isProcessing) return [];
    _isProcessing = true;
    try {
      final inp = _cameraImageToInputImage(image, camera);
      if (inp == null) return [];
      return await detectFaces(inp);
    } catch (e) {
      debugPrint('[FDS] detectFacesFromCamera: $e');
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  // ── Liveness ──────────────────────────────────────────────────────────────
  String? livenessCheck(
    Face face, {
    int frameWidth = 640,
    int frameHeight = 480,
  }) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (yaw > _maxYawDeg) return 'Please face the camera directly.';
    if (pitch > _maxPitchDeg) return 'Please keep your head level.';
    final l = face.leftEyeOpenProbability ?? 1.0;
    final r = face.rightEyeOpenProbability ?? 1.0;
    if (l < _minEyeOpenProb || r < _minEyeOpenProb) {
      return 'Please keep your eyes open.';
    }
    if (face.boundingBox.height / frameHeight < _minFaceSize) {
      return 'Please move closer to the camera.';
    }
    return null;
  }

  bool isFaceGoodQuality(Face face) => livenessCheck(face) == null;

  // ── Chip extraction from NV21 CameraImage ─────────────────────────────────
  img.Image? _chipFromCameraImage(CameraImage camImg, Face face) {
    try {
      final yPlane = camImg.planes[0];
      final w = camImg.width;
      final h = camImg.height;
      final yBytes = yPlane.bytes;
      final rowStride = yPlane.bytesPerRow;

      final gray = img.Image(width: w, height: h, numChannels: 1);
      for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
          final idx = row * rowStride + col;
          final lum = (idx < yBytes.length) ? yBytes[idx] & 0xFF : 0;
          gray.setPixelRgb(col, row, lum, lum, lum);
        }
      }
      return _cropToChip(gray, face, w, h);
    } catch (e) {
      debugPrint('[FDS] chipFromCamera: $e');
      return null;
    }
  }

  // ── Chip extraction from decoded img.Image (migration / static) ──────────
  img.Image? extractFaceChipFromImage(img.Image source, Face face) {
    try {
      final gray = img.grayscale(source);
      return _cropToChip(gray, face, source.width, source.height);
    } catch (e) {
      debugPrint('[FDS] chipFromImage: $e');
      return null;
    }
  }

  img.Image? _cropToChip(img.Image gray, Face face, int w, int h) {
    final bbox = face.boundingBox;
    final padX = (bbox.width * 0.15).round();
    final padY = (bbox.height * 0.15).round();
    final x1 = (bbox.left - padX).clamp(0, w - 1).round();
    final y1 = (bbox.top - padY).clamp(0, h - 1).round();
    final x2 = (bbox.right + padX).clamp(0, w - 1).round();
    final y2 = (bbox.bottom + padY).clamp(0, h - 1).round();
    if (x2 <= x1 || y2 <= y1) return null;
    final crop = img.copyCrop(
      gray,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );
    final eq = img.adjustColor(crop, contrast: 1.2);
    return img.copyResize(
      eq,
      width: _chipSize,
      height: _chipSize,
      interpolation: img.Interpolation.linear,
    );
  }

  // ── LBP histogram for one region ─────────────────────────────────────────
  List<double> _lbpRegion(img.Image chip, List<double> region) {
    final rx = (region[0] * _chipSize).round();
    final ry = (region[1] * _chipSize).round();
    final rw = (region[2] * _chipSize).round().clamp(4, _chipSize - rx);
    final rh = (region[3] * _chipSize).round().clamp(4, _chipSize - ry);

    final lum = List.generate(
      rh,
      (row) => List.generate(rw, (col) {
        final px = rx + col;
        final py = ry + row;
        if (px < 0 || px >= _chipSize || py < 0 || py >= _chipSize) return 0.0;
        return chip.getPixel(px, py).r.toDouble();
      }),
    );

    final hist = List<double>.filled(_lbpBins, 0.0);
    const dx = [-1, 0, 1, 1, 1, 0, -1, -1];
    const dy = [-1, -1, -1, 0, 1, 1, 1, 0];

    for (int row = 1; row < rh - 1; row++) {
      for (int col = 1; col < rw - 1; col++) {
        final centre = lum[row][col];
        int code = 0;
        for (int k = 0; k < 8; k++) {
          if (lum[row + dy[k]][col + dx[k]] >= centre) code |= (1 << k);
        }
        hist[code >> 1] += 1.0;
      }
    }
    return _l2(hist);
  }

  // ── 7-region MLBP → 896-dim vector ───────────────────────────────────────
  List<double> _computeMLBP(img.Image chip) {
    final result = <double>[];
    for (final region in _regions) {
      result.addAll(_lbpRegion(chip, region));
    }
    return result;
  }

  // ── Landmark geometry ─────────────────────────────────────────────────────
  List<double>? _computeGeometry(Face face) {
    const types = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
    ];
    final pts = <List<double>>[];
    for (final t in types) {
      final lm = face.landmarks[t];
      if (lm != null) {
        pts.add([lm.position.x.toDouble(), lm.position.y.toDouble()]);
      }
    }
    if (pts.length < 6) return null;
    final bbox = face.boundingBox;
    if (bbox.width == 0 || bbox.height == 0) return null;
    final norm = pts
        .map(
          (v) => [
            (v[0] - bbox.left) / bbox.width,
            (v[1] - bbox.top) / bbox.height,
          ],
        )
        .toList();
    final dists = <double>[];
    for (int i = 0; i < norm.length; i++) {
      for (int j = i + 1; j < norm.length; j++) {
        final dx = norm[i][0] - norm[j][0];
        final dy = norm[i][1] - norm[j][1];
        dists.add(sqrt(dx * dx + dy * dy));
      }
    }
    return _l2(dists);
  }

  // ── Assemble ──────────────────────────────────────────────────────────────
  _MLBP? _buildMLBP(img.Image chip, Face face) {
    final geo = _computeGeometry(face);
    if (geo == null) return null;
    return _MLBP(regions: _computeMLBP(chip), geometry: geo);
  }

  // ── Multi-sample accumulation ─────────────────────────────────────────────
  bool addLiveSample(img.Image chip, Face face) {
    final d = _buildMLBP(chip, face);
    if (d == null) return false;
    _samples.add(d);
    return _samples.length >= _attendanceFrames;
  }

  bool addRegistrationSample(img.Image chip, Face face) {
    final d = _buildMLBP(chip, face);
    if (d == null) return false;
    _samples.add(d);
    return _samples.length >= _registrationFrames;
  }

  _MLBP? _averageSamples() {
    if (_samples.isEmpty) return null;
    final n = _samples.length;
    final rLen = _samples[0].regions.length;
    final gLen = _samples[0].geometry.length;
    final aR = List<double>.filled(rLen, 0.0);
    final aG = List<double>.filled(gLen, 0.0);
    for (final s in _samples) {
      for (int i = 0; i < rLen && i < s.regions.length; i++)
        aR[i] += s.regions[i] / n;
      for (int i = 0; i < gLen && i < s.geometry.length; i++)
        aG[i] += s.geometry[i] / n;
    }
    return _MLBP(regions: aR, geometry: aG);
  }

  // ── Serialise ─────────────────────────────────────────────────────────────
  String _serialize(_MLBP d) => jsonEncode({
    'regions': d.regions,
    'geometry': d.geometry,
    'v': _kVersion,
  });

  _MLBP? _parse(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final v = (m['v'] as num?)?.toInt() ?? 0;
      if (v >= 5 && m.containsKey('regions')) {
        return _MLBP(
          regions: List<double>.from(m['regions'] as List),
          geometry: List<double>.from(m['geometry'] as List),
        );
      }
      return null; // legacy v1-v4
    } catch (e) {
      debugPrint('[FDS] parse: $e');
      return null;
    }
  }

  bool _isLegacyDescriptor(String jsonStr) => _parse(jsonStr) == null;

  // ── Scoring ───────────────────────────────────────────────────────────────
  double _cosine(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final len = min(a.length, b.length);
    double dot = 0, m1 = 0, m2 = 0;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
      m1 += a[i] * a[i];
      m2 += b[i] * b[i];
    }
    return (m1 == 0 || m2 == 0) ? 0.0 : dot / (sqrt(m1) * sqrt(m2));
  }

  _MatchScore? _scoreAgainst(_MLBP live, String storedJson) {
    final stored = _parse(storedJson);
    if (stored == null) return null;
    final mlbpScore = _cosine(live.regions, stored.regions);
    final geoScore = _cosine(live.geometry, stored.geometry);
    final weighted = mlbpScore * _mlbpWeight + geoScore * _geoWeight;
    return _MatchScore(mlbp: mlbpScore, geo: geoScore, weighted: weighted);
  }

  bool _passes(_MatchScore s) =>
      s.mlbp >= _mlbpMinScore &&
      s.geo >= _geoMinScore &&
      s.weighted >= _finalThreshold;

  // ── PUBLIC: registration accumulator (called by FaceRegistrationScreen) ───
  /// Accumulates 10 live frames and returns the averaged descriptor string
  /// when ready. Returns null while still collecting.
  String? accumulateRegistrationFrame(CameraImage camImg, Face face) {
    final chip = _chipFromCameraImage(camImg, face);
    if (chip == null) return null;
    final ready = addRegistrationSample(chip, face);
    if (!ready) return null;
    final avg = _averageSamples();
    resetSamples();
    if (avg == null) return null;
    return _serialize(avg);
  }

  // ── PUBLIC: build from static image (fallback / migration) ───────────────
  String? buildFaceDescriptorFromStaticImage(img.Image decoded, Face face) {
    try {
      final chip = extractFaceChipFromImage(decoded, face);
      if (chip == null) return null;
      final desc = _buildMLBP(chip, face);
      if (desc == null) return null;
      return _serialize(desc);
    } catch (e) {
      debugPrint('[FDS] staticImage: $e');
      return null;
    }
  }

  // ── PUBLIC: rebuild from stored photo URL (migration service) ─────────────
  Future<String?> buildFaceDescriptorFromPhotoUrl(String photoUrl) async {
    try {
      final response = await http
          .get(Uri.parse(photoUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final decoded = img.decodeImage(response.bodyBytes);
      if (decoded == null) return null;
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/mig_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(decoded, quality: 95));
      final faces = await detectFacesFromFile(tempFile);
      await tempFile.delete().catchError((_) => tempFile);
      if (faces.isEmpty) return null;
      return buildFaceDescriptorFromStaticImage(decoded, faces.first);
    } catch (e) {
      debugPrint('[FDS] migration: $e');
      return null;
    }
  }

  // ── Legacy geometry-only fallback (kept for callers) ─────────────────────
  String? buildFaceDescriptor(Face face) {
    final geo = _computeGeometry(face);
    if (geo == null) return null;
    return jsonEncode({
      'lbp': List<double>.filled(128, 0.0),
      'intensity': List<double>.filled(80, 0.0),
      'geometry': geo,
      'v': 4, // mark as legacy so it triggers migration
    });
  }

  // =========================================================================
  // PUBLIC: 1-to-N IDENTIFICATION
  // =========================================================================
  FaceMatchResult identifyEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
    CameraImage? cameraImage,
  }) {
    final livenessErr = livenessCheck(
      detectedFace,
      frameWidth: cameraImage?.width ?? 640,
      frameHeight: cameraImage?.height ?? 480,
    );
    if (livenessErr != null) {
      return FaceMatchResult(
        status: FaceMatchStatus.livenessFailure,
        message: livenessErr,
      );
    }

    final chip = cameraImage != null
        ? _chipFromCameraImage(cameraImage, detectedFace)
        : null;
    if (chip == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face data. Please try again.',
      );
    }

    final ready = addLiveSample(chip, detectedFace);
    if (!ready) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Collecting samples... hold still.',
      );
    }

    final live = _averageSamples();
    resetSamples();
    if (live == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not build face descriptor. Please try again.',
      );
    }

    bool anyLegacy = false;
    final List<({EmployeeModel emp, _MatchScore score})> candidates = [];

    for (final emp in employees) {
      if (emp.faceDescriptor == null || emp.faceDescriptor!.isEmpty) continue;
      if (_isLegacyDescriptor(emp.faceDescriptor!)) {
        anyLegacy = true;
        continue;
      }
      final score = _scoreAgainst(live, emp.faceDescriptor!);
      if (score == null) continue;
      if (_passes(score)) candidates.add((emp: emp, score: score));
    }

    if (candidates.isEmpty) {
      return const FaceMatchResult(
        status: FaceMatchStatus.notRecognized,
        message: 'Face Not Registered',
      );
    }

    candidates.sort((a, b) => b.score.weighted.compareTo(a.score.weighted));
    final best = candidates.first;

    if (candidates.length > 1) {
      final gap = best.score.weighted - candidates[1].score.weighted;
      if (gap < _minCandidateGap) {
        return const FaceMatchResult(
          status: FaceMatchStatus.notRecognized,
          message:
              'Could not identify clearly. Please reposition and try again.',
        );
      }
    }

    return FaceMatchResult(
      status: FaceMatchStatus.matched,
      employee: best.emp,
      message: 'Verified: ${best.emp.name}',
      bestScore: best.score.weighted,
    );
  }

  // =========================================================================
  // PUBLIC: 1-to-1 VERIFICATION
  // =========================================================================
  FaceMatchResult verifyEmployee({
    required Face detectedFace,
    required EmployeeModel expectedEmployee,
    bool useSamples = false,
    CameraImage? cameraImage,
  }) {
    if (expectedEmployee.faceDescriptor == null ||
        expectedEmployee.faceDescriptor!.isEmpty) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'No registered face found for this employee.',
      );
    }

    if (_isLegacyDescriptor(expectedEmployee.faceDescriptor!)) {
      return FaceMatchResult(
        status: FaceMatchStatus.needsMigration,
        message:
            'Face data for ${expectedEmployee.name} needs updating. '
            'Please contact admin.',
      );
    }

    final livenessErr = livenessCheck(
      detectedFace,
      frameWidth: cameraImage?.width ?? 640,
      frameHeight: cameraImage?.height ?? 480,
    );
    if (livenessErr != null) {
      return FaceMatchResult(
        status: FaceMatchStatus.livenessFailure,
        message: livenessErr,
      );
    }

    final chip = cameraImage != null
        ? _chipFromCameraImage(cameraImage, detectedFace)
        : null;
    if (chip == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face data. Please try again.',
      );
    }

    _MLBP? live;
    if (useSamples) {
      final ready = addLiveSample(chip, detectedFace);
      if (!ready) {
        return const FaceMatchResult(
          status: FaceMatchStatus.insufficientData,
          message: 'Collecting samples... hold still.',
        );
      }
      live = _averageSamples();
      resetSamples();
    } else {
      live = _buildMLBP(chip, detectedFace);
    }

    if (live == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face features. Please try again.',
      );
    }

    final score = _scoreAgainst(live, expectedEmployee.faceDescriptor!);
    if (score == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Stored face data is corrupted. Please re-register.',
      );
    }

    if (_passes(score)) {
      return FaceMatchResult(
        status: FaceMatchStatus.matched,
        employee: expectedEmployee,
        message: 'Identity confirmed: ${expectedEmployee.name}',
        bestScore: score.weighted,
      );
    }

    final who = expectedEmployee.name;
    return FaceMatchResult(
      status: FaceMatchStatus.notRecognized,
      message: score.weighted > 0.55
          ? 'Unauthorized person. Only $who can perform this action.'
          : 'Face not recognized. Only $who is authorized.',
      bestScore: score.weighted,
    );
  }

  // ── Legacy compat ─────────────────────────────────────────────────────────
  EmployeeModel? matchFaceToEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
  }) => identifyEmployee(
    detectedFace: detectedFace,
    employees: employees,
  ).employee;

  double getFaceConfidence(Face face) {
    double c = 0.5;
    if (face.leftEyeOpenProbability != null)
      c += face.leftEyeOpenProbability! * 0.25;
    if (face.rightEyeOpenProbability != null)
      c += face.rightEyeOpenProbability! * 0.25;
    return c.clamp(0.0, 1.0);
  }

  bool isFaceDetected(List<Face> faces) => faces.isNotEmpty;

  // ── CameraImage → InputImage ──────────────────────────────────────────────
  InputImage? _cameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    try {
      int total = 0;
      for (final p in image.planes) total += p.bytes.length;
      final bytes = Uint8List(total);
      int offset = 0;
      for (final p in image.planes) {
        bytes.setRange(offset, offset + p.bytes.length, p.bytes);
        offset += p.bytes.length;
      }
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('[FDS] convertCamera: $e');
      return null;
    }
  }

  List<double> _l2(List<double> v) {
    double sq = 0;
    for (final x in v) sq += x * x;
    final n = sqrt(sq) + 1e-9;
    return v.map((x) => x / n).toList();
  }

  void dispose() {
    if (_isInitialized) {
      _faceDetector?.close();
      _faceDetector = null;
      _isInitialized = false;
      _isProcessing = false;
      _samples.clear();
    }
  }
}


/*

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Size; // ONLY Size from dart:ui

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/employee_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────
enum FaceMatchStatus {
  matched,
  notRecognized,
  livenessFailure,
  insufficientData,
  noFaceDetected,
  needsMigration,
}

class FaceMatchResult {
  final FaceMatchStatus status;
  final EmployeeModel? employee;
  final String message;
  final double? bestScore;

  const FaceMatchResult({
    required this.status,
    this.employee,
    required this.message,
    this.bestScore,
  });

  bool get isMatched => status == FaceMatchStatus.matched;

  static const FaceMatchResult noFace = FaceMatchResult(
    status: FaceMatchStatus.noFaceDetected,
    message: 'No face detected. Please position your face in the frame.',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal structs
// ─────────────────────────────────────────────────────────────────────────────
class _RichDescriptor {
  final List<double> lbp;
  final List<double> intensity;
  final List<double> geometry;
  const _RichDescriptor({
    required this.lbp,
    required this.intensity,
    required this.geometry,
  });
}

class _MatchScore {
  final double lbp;
  final double intensity;
  final double geo;
  final double weighted;
  final bool hasPixelData;
  const _MatchScore({
    required this.lbp,
    required this.intensity,
    required this.geo,
    required this.weighted,
    required this.hasPixelData,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceDetectionService
// ─────────────────────────────────────────────────────────────────────────────
class FaceDetectionService {
  FaceDetector? _faceDetector;
  bool _isInitialized = false;
  bool _isProcessing = false;

  // ── Thresholds ─────────────────────────────────────────────────────────────
  static const double _finalThreshold = 0.82;
  static const double _lbpMinScore = 0.75;
  static const double _intensityMinScore = 0.70;
  static const double _geoMinScore = 0.72;
  static const double _lbpWeight = 0.55;
  static const double _intensityWeight = 0.25;
  static const double _geoWeight = 0.20;
  static const double _minCandidateGap = 0.025;

  // ── Liveness ───────────────────────────────────────────────────────────────
  static const double _maxYawDeg = 15.0;
  static const double _maxPitchDeg = 12.0;
  static const double _minEyeOpenProb = 0.55;

  // ── Multi-sample ───────────────────────────────────────────────────────────
  static const int _samplesRequired = 3;
  final List<_RichDescriptor> _samples = [];

  // ── Descriptor sizes ───────────────────────────────────────────────────────
  static const int _lbpBins = 128;
  static const int _numRegions = 5;
  static const int _gridCells = 16;
  static const int _kVersion = 4;

  // ─────────────────────────────────────────────────────────────────────────
  void initialize() {
    if (_isInitialized) return;
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.18,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _isInitialized = true;
  }

  void resetSamples() => _samples.clear();

  // ─────────────────────────────────────────────────────────────────────────
  // Face detection
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (!_isInitialized) initialize();
    if (_faceDetector == null) return [];
    try {
      return await _faceDetector!.processImage(inputImage);
    } catch (_) {
      return [];
    }
  }

  Future<List<Face>> detectFacesFromFile(File imageFile) async =>
      detectFaces(InputImage.fromFile(imageFile));

  Future<List<Face>> detectFacesFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isProcessing) return [];
    _isProcessing = true;
    try {
      final inp = _cameraImageToInputImage(image, camera);
      if (inp == null) return [];
      return await detectFaces(inp);
    } catch (_) {
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Liveness
  // ─────────────────────────────────────────────────────────────────────────
  String? livenessCheck(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (yaw > _maxYawDeg)
      return 'Please face the camera directly (don\'t turn your head).';
    if (pitch > _maxPitchDeg)
      return 'Please keep your head level (don\'t tilt up/down).';
    final l = face.leftEyeOpenProbability ?? 1.0;
    final r = face.rightEyeOpenProbability ?? 1.0;
    if (l < _minEyeOpenProb || r < _minEyeOpenProb)
      return 'Please keep your eyes open.';
    return null;
  }

  bool isFaceGoodQuality(Face face) => livenessCheck(face) == null;

  // =========================================================================
  // DESCRIPTOR COMPUTATION
  // =========================================================================

  // ── 64×64 grayscale chip from CameraImage ─────────────────────────────────
  img.Image? extractFaceChipFromCamera(CameraImage camImg, Face face) {
    try {
      final yPlane = camImg.planes[0];
      final w = camImg.width;
      final h = camImg.height;
      final yBytes = yPlane.bytes;
      final rowStride = yPlane.bytesPerRow;

      final gray = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final idx = y * rowStride + x;
          final lum = (idx < yBytes.length) ? yBytes[idx] & 0xFF : 0;
          gray.setPixel(x, y, img.ColorRgb8(lum, lum, lum));
        }
      }
      return _cropAndResize(gray, face, w, h);
    } catch (e) {
      debugPrint('[FaceChip/Camera] $e');
      return null;
    }
  }

  // ── 64×64 grayscale chip from img.Image ───────────────────────────────────
  img.Image? extractFaceChipFromImage(img.Image source, Face face) {
    try {
      final gray = img.grayscale(source);
      return _cropAndResize(gray, face, source.width, source.height);
    } catch (e) {
      debugPrint('[FaceChip/Image] $e');
      return null;
    }
  }

  img.Image? _cropAndResize(img.Image gray, Face face, int w, int h) {
    final bbox = face.boundingBox;
    final padX = (bbox.width * 0.20).round();
    final padY = (bbox.height * 0.20).round();
    final x1 = (bbox.left - padX).clamp(0, w - 1).round();
    final y1 = (bbox.top - padY).clamp(0, h - 1).round();
    final x2 = (bbox.right + padX).clamp(0, w - 1).round();
    final y2 = (bbox.bottom + padY).clamp(0, h - 1).round();
    if (x2 <= x1 || y2 <= y1) return null;
    final chip = img.copyCrop(
      gray,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );
    return img.copyResize(
      chip,
      width: 64,
      height: 64,
      interpolation: img.Interpolation.linear,
    );
  }

  // ── LBP histogram (128 bins) ──────────────────────────────────────────────
  List<double> _computeLBP(img.Image chip) {
    final w = chip.width;
    final h = chip.height;
    final lum = List.generate(
      h,
      (y) => List.generate(w, (x) => chip.getPixel(x, y).r.toDouble()),
    );
    final hist = List<double>.filled(_lbpBins, 0.0);
    const dx = [-1, 0, 1, 1, 1, 0, -1, -1];
    const dy = [-1, -1, -1, 0, 1, 1, 1, 0];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final centre = lum[y][x];
        int code = 0;
        for (int k = 0; k < 8; k++) {
          if (lum[y + dy[k]][x + dx[k]] >= centre) code |= (1 << k);
        }
        hist[code >> 1] += 1.0;
      }
    }
    return _l2(hist);
  }

  // ── Regional intensity grid (5 × 4×4 = 80 values) ────────────────────────
  List<double> _computeIntensity(img.Image chip) {
    const regions = [
      [0.15, 0.02, 0.70, 0.22],
      [0.05, 0.25, 0.38, 0.28],
      [0.57, 0.25, 0.38, 0.28],
      [0.28, 0.42, 0.44, 0.28],
      [0.18, 0.68, 0.64, 0.28],
    ];
    final sig = <double>[];
    for (final r in regions) {
      final rx = (r[0] * 64).round();
      final ry = (r[1] * 64).round();
      final rw = (r[2] * 64).round().clamp(1, 64 - rx);
      final rh = (r[3] * 64).round().clamp(1, 64 - ry);
      final cw = rw / 4.0;
      final ch = rh / 4.0;
      for (int cy = 0; cy < 4; cy++) {
        for (int cx = 0; cx < 4; cx++) {
          final x0 = rx + (cx * cw).round();
          final y0 = ry + (cy * ch).round();
          final x1 = (x0 + cw).round().clamp(x0 + 1, 64);
          final y1 = (y0 + ch).round().clamp(y0 + 1, 64);
          double sum = 0;
          int cnt = 0;
          for (int py = y0; py < y1; py++) {
            for (int px = x0; px < x1; px++) {
              if (px >= 0 && px < 64 && py >= 0 && py < 64) {
                sum += chip.getPixel(px, py).r.toDouble();
                cnt++;
              }
            }
          }
          sig.add(cnt > 0 ? sum / (cnt * 255.0) : 0.0);
        }
      }
    }
    return _l2(sig);
  }

  // ── Landmark geometry ─────────────────────────────────────────────────────
  List<double>? _computeGeometry(Face face) {
    const types = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
    ];
    final raw = <List<double>>[];
    for (final t in types) {
      final lm = face.landmarks[t];
      if (lm != null)
        raw.add([lm.position.x.toDouble(), lm.position.y.toDouble()]);
    }
    if (raw.length < 6) return null;
    final bbox = face.boundingBox;
    if (bbox.width == 0 || bbox.height == 0) return null;
    final norm = raw
        .map(
          (v) => [
            (v[0] - bbox.left) / bbox.width,
            (v[1] - bbox.top) / bbox.height,
          ],
        )
        .toList();
    final dists = <double>[];
    for (int i = 0; i < norm.length; i++) {
      for (int j = i + 1; j < norm.length; j++) {
        final dx = norm[i][0] - norm[j][0];
        final dy = norm[i][1] - norm[j][1];
        dists.add(sqrt(dx * dx + dy * dy));
      }
    }
    return _l2(dists);
  }

  // ── Assemble ──────────────────────────────────────────────────────────────
  _RichDescriptor? _buildDescriptor(Face face, img.Image? chip) {
    final geo = _computeGeometry(face);
    if (geo == null) return null;
    return _RichDescriptor(
      lbp: chip != null ? _computeLBP(chip) : List.filled(_lbpBins, 0.0),
      intensity: chip != null
          ? _computeIntensity(chip)
          : List.filled(_numRegions * _gridCells, 0.0),
      geometry: geo,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: build descriptor from live camera frame (attendance scanner)
  // ─────────────────────────────────────────────────────────────────────────
  String? buildFaceDescriptorFromCamera(Face face, CameraImage camImg) {
    final chip = extractFaceChipFromCamera(camImg, face);
    final desc = _buildDescriptor(face, chip);
    if (desc == null) return null;
    return _serialize(desc);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: build descriptor from a static img.Image (employee registration)
  // Called by EmployeeFormScreen._captureFace() after the image file has
  // already been decoded — avoids a second disk read.
  // ─────────────────────────────────────────────────────────────────────────
  String? buildFaceDescriptorFromStaticImage(img.Image decoded, Face face) {
    try {
      final chip = extractFaceChipFromImage(decoded, face);
      final desc = _buildDescriptor(face, chip);
      if (desc == null) return null;
      return _serialize(desc);
    } catch (e) {
      debugPrint('[buildFaceDescriptorFromStaticImage] $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: rebuild descriptor from stored photo URL (migration)
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> buildFaceDescriptorFromPhotoUrl(String photoUrl) async {
    try {
      final response = await http
          .get(Uri.parse(photoUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('[Migration] HTTP ${response.statusCode}');
        return null;
      }
      final decoded = img.decodeImage(response.bodyBytes);
      if (decoded == null) {
        debugPrint('[Migration] Decode failed');
        return null;
      }

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/mig_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(decoded, quality: 95));
      final faces = await detectFacesFromFile(tempFile);
      await tempFile.delete().catchError((_) => tempFile);

      if (faces.isEmpty) {
        debugPrint('[Migration] No face');
        return null;
      }
      final geo = _computeGeometry(faces.first);
      if (geo == null) {
        debugPrint('[Migration] Bad landmarks');
        return null;
      }

      return buildFaceDescriptorFromStaticImage(decoded, faces.first);
    } catch (e) {
      debugPrint('[Migration] Error: $e');
      return null;
    }
  }

  // ── Geometry-only fallback ─────────────────────────────────────────────
  String? buildFaceDescriptor(Face face) {
    final geo = _computeGeometry(face);
    if (geo == null) return null;
    return jsonEncode({
      'lbp': List<double>.filled(_lbpBins, 0.0),
      'intensity': List<double>.filled(_numRegions * _gridCells, 0.0),
      'geometry': geo,
      'v': _kVersion,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Serialise / deserialise
  // ─────────────────────────────────────────────────────────────────────────
  String _serialize(_RichDescriptor d) => jsonEncode({
    'lbp': d.lbp,
    'intensity': d.intensity,
    'geometry': d.geometry,
    'v': _kVersion,
  });

  _RichDescriptor? _parse(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final lbp = List<double>.from(m['lbp'] as List? ?? []);
      final intensityVec = List<double>.from(m['intensity'] as List? ?? []);
      final geoRaw = m['geometry'] ?? m['pairDist'] ?? m['features'];
      final geo = List<double>.from(geoRaw as List? ?? []);
      return _RichDescriptor(lbp: lbp, intensity: intensityVec, geometry: geo);
    } catch (_) {
      return null;
    }
  }

  bool _isLegacy(_RichDescriptor d) =>
      d.lbp.isEmpty || !d.lbp.any((v) => v != 0.0);

  // ─────────────────────────────────────────────────────────────────────────
  // Cosine + L2
  // ─────────────────────────────────────────────────────────────────────────
  double _cosine(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final len = min(a.length, b.length);
    double dot = 0, m1 = 0, m2 = 0;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
      m1 += a[i] * a[i];
      m2 += b[i] * b[i];
    }
    return (m1 == 0 || m2 == 0) ? 0.0 : dot / (sqrt(m1) * sqrt(m2));
  }

  List<double> _l2(List<double> v) {
    double sq = 0;
    for (final x in v) sq += x * x;
    final n = sqrt(sq) + 1e-9;
    return v.map((x) => x / n).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Score + threshold check
  // ─────────────────────────────────────────────────────────────────────────
  _MatchScore _score(_RichDescriptor live, _RichDescriptor stored) {
    final lbpS = _cosine(live.lbp, stored.lbp);
    final intS = _cosine(live.intensity, stored.intensity);
    final geoS = _cosine(live.geometry, stored.geometry);
    final hasP = !_isLegacy(stored);
    final w = hasP
        ? lbpS * _lbpWeight + intS * _intensityWeight + geoS * _geoWeight
        : geoS;
    return _MatchScore(
      lbp: lbpS,
      intensity: intS,
      geo: geoS,
      weighted: w,
      hasPixelData: hasP,
    );
  }

  bool _passes(_MatchScore s) {
    if (!s.hasPixelData) return false;
    return s.lbp >= _lbpMinScore &&
        s.intensity >= _intensityMinScore &&
        s.geo >= _geoMinScore &&
        s.weighted >= _finalThreshold;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Multi-sample
  // ─────────────────────────────────────────────────────────────────────────
  bool _addSample(_RichDescriptor d) {
    _samples.add(d);
    return _samples.length >= _samplesRequired;
  }

  _RichDescriptor? _average() {
    if (_samples.isEmpty) return null;
    final n = _samples.length;
    final lLen = _samples[0].lbp.length;
    final iLen = _samples[0].intensity.length;
    final gLen = _samples[0].geometry.length;
    final aL = List<double>.filled(lLen, 0.0);
    final aI = List<double>.filled(iLen, 0.0);
    final aG = List<double>.filled(gLen, 0.0);
    for (final s in _samples) {
      for (int i = 0; i < lLen && i < s.lbp.length; i++) aL[i] += s.lbp[i] / n;
      for (int i = 0; i < iLen && i < s.intensity.length; i++)
        aI[i] += s.intensity[i] / n;
      for (int i = 0; i < gLen && i < s.geometry.length; i++)
        aG[i] += s.geometry[i] / n;
    }
    return _RichDescriptor(lbp: aL, intensity: aI, geometry: aG);
  }

  // =========================================================================
  // PUBLIC: 1-to-N IDENTIFICATION
  // =========================================================================
  FaceMatchResult identifyEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
    CameraImage? cameraImage,
  }) {
    final err = livenessCheck(detectedFace);
    if (err != null) {
      return FaceMatchResult(
        status: FaceMatchStatus.livenessFailure,
        message: err,
      );
    }
    final chip = cameraImage != null
        ? extractFaceChipFromCamera(cameraImage, detectedFace)
        : null;
    final live = _buildDescriptor(detectedFace, chip);
    if (live == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face features. Please try again.',
      );
    }
    final ready = _addSample(live);
    if (!ready) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Collecting samples... hold still.',
      );
    }
    final avg = _average();
    resetSamples();
    if (avg == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not average samples. Please try again.',
      );
    }

    bool anyLegacy = false;
    final List<({EmployeeModel emp, _MatchScore score})> candidates = [];

    for (final emp in employees) {
      if (emp.faceDescriptor == null || emp.faceDescriptor!.isEmpty) continue;
      final stored = _parse(emp.faceDescriptor!);
      if (stored == null) continue;
      if (_isLegacy(stored)) {
        anyLegacy = true;
        continue;
      }
      final s = _score(avg, stored);
      if (_passes(s)) candidates.add((emp: emp, score: s));
    }

    if (candidates.isEmpty) {
      return const FaceMatchResult(
        status: FaceMatchStatus.notRecognized,
        message:
            'Face not recognized. Only registered employees can mark attendance.',
      );
    }

    candidates.sort((a, b) => b.score.weighted.compareTo(a.score.weighted));
    final best = candidates.first;

    if (candidates.length > 1) {
      final gap = best.score.weighted - candidates[1].score.weighted;
      if (gap < _minCandidateGap) {
        return const FaceMatchResult(
          status: FaceMatchStatus.notRecognized,
          message: 'Ambiguous match. Please reposition and try again.',
        );
      }
    }

    return FaceMatchResult(
      status: FaceMatchStatus.matched,
      employee: best.emp,
      message: 'Verified: ${best.emp.name}',
      bestScore: best.score.weighted,
    );
  }

  // =========================================================================
  // PUBLIC: 1-to-1 VERIFICATION
  // =========================================================================
  FaceMatchResult verifyEmployee({
    required Face detectedFace,
    required EmployeeModel expectedEmployee,
    bool useSamples = false,
    CameraImage? cameraImage,
  }) {
    if (expectedEmployee.faceDescriptor == null ||
        expectedEmployee.faceDescriptor!.isEmpty) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'No registered face found for this employee.',
      );
    }
    final err = livenessCheck(detectedFace);
    if (err != null) {
      return FaceMatchResult(
        status: FaceMatchStatus.livenessFailure,
        message: err,
      );
    }
    final stored = _parse(expectedEmployee.faceDescriptor!);
    if (stored == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Stored face data is corrupted. Please re-register.',
      );
    }
    if (_isLegacy(stored)) {
      return FaceMatchResult(
        status: FaceMatchStatus.needsMigration,
        message:
            'Face data for ${expectedEmployee.name} needs updating. Please contact admin.',
      );
    }

    final chip = cameraImage != null
        ? extractFaceChipFromCamera(cameraImage, detectedFace)
        : null;
    final live = _buildDescriptor(detectedFace, chip);
    if (live == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face features. Please try again.',
      );
    }

    _RichDescriptor? toMatch;
    if (useSamples) {
      final ready = _addSample(live);
      if (!ready) {
        return const FaceMatchResult(
          status: FaceMatchStatus.insufficientData,
          message: 'Collecting samples... hold still.',
        );
      }
      toMatch = _average();
      resetSamples();
    } else {
      toMatch = live;
    }
    if (toMatch == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face features. Please try again.',
      );
    }

    final s = _score(toMatch, stored);
    if (_passes(s)) {
      return FaceMatchResult(
        status: FaceMatchStatus.matched,
        employee: expectedEmployee,
        message: 'Identity confirmed: ${expectedEmployee.name}',
        bestScore: s.weighted,
      );
    }

    final who = expectedEmployee.name;
    return FaceMatchResult(
      status: FaceMatchStatus.notRecognized,
      message: s.weighted > 0.60
          ? 'Unauthorized person detected. Only $who can perform this action.'
          : 'Face not recognized. Only $who is authorized for this action.',
      bestScore: s.weighted,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Legacy compat
  // ─────────────────────────────────────────────────────────────────────────
  EmployeeModel? matchFaceToEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
  }) => identifyEmployee(
    detectedFace: detectedFace,
    employees: employees,
  ).employee;

  double getFaceConfidence(Face face) {
    double c = 0.5;
    if (face.leftEyeOpenProbability != null)
      c += face.leftEyeOpenProbability! * 0.25;
    if (face.rightEyeOpenProbability != null)
      c += face.rightEyeOpenProbability! * 0.25;
    return c.clamp(0.0, 1.0);
  }

  bool isFaceDetected(List<Face> faces) => faces.isNotEmpty;

  // ─────────────────────────────────────────────────────────────────────────
  // CameraImage → InputImage
  // InputImage / InputImageMetadata / InputImageRotationValue /
  // InputImageFormatValue are from google_mlkit_face_detection — NO ui. prefix
  // ─────────────────────────────────────────────────────────────────────────
  InputImage? _cameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    try {
      int total = 0;
      for (final p in image.planes) total += p.bytes.length;
      final bytes = Uint8List(total);
      int offset = 0;
      for (final p in image.planes) {
        bytes.setRange(offset, offset + p.bytes.length, p.bytes);
        offset += p.bytes.length;
      }
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    if (_isInitialized) {
      _faceDetector?.close();
      _faceDetector = null;
      _isInitialized = false;
      _isProcessing = false;
      _samples.clear();
    }
  }
}
*/