// lib/data/services/face_detection_service.dart
//
// STRICT SINGLE-EMPLOYEE FACE VERIFICATION
// ─────────────────────────────────────────────────────────────────────────────
// Design goals:
//   1. The system is an ATTENDANCE KIOSK — not a search-across-N-faces system.
//      The employee first says "I am Jenny", then the system verifies whether
//      the face in front of the camera IS Jenny. This is 1-to-1 verification,
//      not 1-to-N identification.
//
//   2. Three independent guards must ALL pass:
//      a. Cosine similarity   ≥ 0.93  (angular closeness of feature vectors)
//      b. Euclidean distance  ≤ 0.28  (magnitude closeness)
//      c. Ratio distance      ≤ 0.15  (biometric ratio closeness)
//
//   3. Multi-sample averaging: collect 3 descriptor samples across frames
//      and average them before matching. This reduces single-frame noise
//      and makes spoofing harder.
//
//   4. Liveness heuristics:
//      • Head must be roughly frontal (yaw < 12°, pitch < 10°)
//      • Both eyes must be open (probability > 0.6)
//      • Face bounding box must cover reasonable area of frame
//
//   5. Rejection is EXPLICIT: returns a typed FaceMatchResult so the UI
//      can show the exact reason for rejection.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/employee_model.dart';

// ── Result types ──────────────────────────────────────────────────────────────
enum FaceMatchStatus {
  matched, // exact match — proceed
  notRecognized, // face detected but doesn't match any registered employee
  livenessFailure, // face detected but liveness checks failed (eyes closed, not frontal)
  insufficientData, // face detected but can't build descriptor (bad quality)
  noFaceDetected, // no face in frame
}

class FaceMatchResult {
  final FaceMatchStatus status;
  final EmployeeModel? employee; // non-null only when status == matched
  final String message;
  final double? bestCosine; // debug info

  const FaceMatchResult({
    required this.status,
    this.employee,
    required this.message,
    this.bestCosine,
  });

  bool get isMatched => status == FaceMatchStatus.matched;

  static const FaceMatchResult noFace = FaceMatchResult(
    status: FaceMatchStatus.noFaceDetected,
    message: 'No face detected. Please position your face in the frame.',
  );
}

// ── Main service ──────────────────────────────────────────────────────────────
class FaceDetectionService {
  FaceDetector? _faceDetector;
  bool _isInitialized = false;
  bool _isProcessing = false;

  // ── Thresholds ────────────────────────────────────────────────────────────
  // Guard A: cosine similarity (1.0 = identical vectors)
  static const double _cosineThreshold = 0.98; // tightened from 0.93

  // Guard B: normalised Euclidean distance (0.0 = identical)
  static const double _euclideanThreshold = 0.12; // tightened from 0.28

  // Guard C: geometric ratio distance (0.0 = identical face structure)
  static const double _ratioThreshold = 0.07; // tightened from 0.15

  // Liveness: maximum head rotation allowed
  static const double _maxYawDeg = 12.0;
  static const double _maxPitchDeg = 10.0;

  // Liveness: minimum eye-open probability
  static const double _minEyeOpenProb = 0.60;

  // Number of samples to average per verification attempt
  static const int _samplesRequired = 3;

  // Accumulated samples for current verification session
  final List<Map<String, List<double>>> _samples = [];

  void initialize() {
    if (_isInitialized) return;
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true, // needed for eye-open probability
        enableTracking: false, // tracking off — we want per-frame quality
        minFaceSize: 0.20, // larger minimum = closer face required
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _isInitialized = true;
  }

  void resetSamples() => _samples.clear();

  // ── Face detection ────────────────────────────────────────────────────────
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (!_isInitialized) initialize();
    if (_faceDetector == null) return [];
    try {
      return await _faceDetector!.processImage(inputImage);
    } catch (_) {
      return [];
    }
  }

  Future<List<Face>> detectFacesFromFile(File imageFile) async {
    return detectFaces(InputImage.fromFile(imageFile));
  }

  Future<List<Face>> detectFacesFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isProcessing) return [];
    _isProcessing = true;
    try {
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) return [];
      return await detectFaces(inputImage);
    } catch (_) {
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  // ── Liveness check ────────────────────────────────────────────────────────
  /// Returns null if liveness passes, or a rejection reason string.
  String? livenessCheck(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();

    if (yaw > _maxYawDeg) {
      return 'Please face the camera directly (don\'t turn your head).';
    }
    if (pitch > _maxPitchDeg) {
      return 'Please keep your head level (don\'t tilt up/down).';
    }

    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    if (leftEye < _minEyeOpenProb || rightEye < _minEyeOpenProb) {
      return 'Please keep your eyes open.';
    }

    return null; // liveness passed
  }

  bool isFaceGoodQuality(Face face) => livenessCheck(face) == null;

  // ── Descriptor building ───────────────────────────────────────────────────
  /// Builds a feature map split into pairwise distances and geometric ratios.
  /// Returns null if < 6 landmarks are found (insufficient data).
  Map<String, List<double>>? _buildFeatureMap(Face face) {
    final landmarkTypes = [
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

    final raw = <String, List<double>>{};
    for (final type in landmarkTypes) {
      final lm = face.landmarks[type];
      if (lm != null) {
        raw[type.name] = [lm.position.x.toDouble(), lm.position.y.toDouble()];
      }
    }

    if (raw.length < 6) return null;

    final bbox = face.boundingBox;
    if (bbox.width == 0 || bbox.height == 0) return null;

    // Normalise coordinates to [0,1] within the bounding box
    final norm = raw.map(
      (k, v) => MapEntry(k, [
        (v[0] - bbox.left) / bbox.width,
        (v[1] - bbox.top) / bbox.height,
      ]),
    );

    // ── Pairwise distances (captures relative geometry) ────────────────────
    final positions = norm.values.toList();
    final pairDist = <double>[];
    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        pairDist.add(_dist(positions[i], positions[j]));
      }
    }

    // ── Biometric ratios (person-specific constants) ───────────────────────
    final ratios = <double>[];
    final lEye = norm[FaceLandmarkType.leftEye.name];
    final rEye = norm[FaceLandmarkType.rightEye.name];
    final nose = norm[FaceLandmarkType.noseBase.name];
    final lMouth = norm[FaceLandmarkType.leftMouth.name];
    final rMouth = norm[FaceLandmarkType.rightMouth.name];
    final bMouth = norm[FaceLandmarkType.bottomMouth.name];
    final lEar = norm[FaceLandmarkType.leftEar.name];
    final rEar = norm[FaceLandmarkType.rightEar.name];
    final lCheek = norm[FaceLandmarkType.leftCheek.name];
    final rCheek = norm[FaceLandmarkType.rightCheek.name];

    if (lEye != null && rEye != null) {
      final ipd = _dist(lEye, rEye);

      // Inter-pupillary distance (normalised by bbox — person-invariant ratio)
      ratios.add(ipd);

      final eyeMid = [(lEye[0] + rEye[0]) / 2, (lEye[1] + rEye[1]) / 2];

      if (nose != null) {
        ratios.add(_dist(nose, eyeMid) / (ipd + 1e-9)); // nose-to-eye ratio
        if (bMouth != null) {
          ratios.add(_dist(bMouth, nose) / (ipd + 1e-9)); // lip-to-nose ratio
        }
      }
      if (lMouth != null && rMouth != null) {
        final mw = _dist(lMouth, rMouth);
        ratios.add(mw / (ipd + 1e-9)); // mouth-width ratio
        if (bMouth != null) {
          final mc = [(lMouth[0] + rMouth[0]) / 2, (lMouth[1] + rMouth[1]) / 2];
          ratios.add(_dist(bMouth, mc) / (mw + 1e-9)); // mouth height ratio
        }
      }
      if (lEar != null && rEar != null) {
        final fw = _dist(lEar, rEar);
        ratios.add(ipd / (fw + 1e-9)); // eye-span to face-width
        if (lCheek != null && rCheek != null) {
          ratios.add(_dist(lCheek, rCheek) / (fw + 1e-9)); // cheek-width ratio
        }
      }
    }

    return {'pairDist': pairDist, 'ratios': ratios};
  }

  // ── Serialise descriptor for storage ─────────────────────────────────────
  String? buildFaceDescriptor(Face face) {
    final map = _buildFeatureMap(face);
    if (map == null) return null;
    return jsonEncode({
      'pairDist': map['pairDist'],
      'ratios': map['ratios'],
      'v': 3,
    });
  }

  // ── Multi-sample accumulation ─────────────────────────────────────────────
  /// Add one frame's features to the sample buffer.
  /// Returns true when enough samples are collected and matching can proceed.
  bool addSample(Face face) {
    final map = _buildFeatureMap(face);
    if (map == null) return false;
    _samples.add(map);
    return _samples.length >= _samplesRequired;
  }

  /// Average the accumulated samples into a single feature map.
  Map<String, List<double>>? _averagedFeatures() {
    if (_samples.isEmpty) return null;
    final n = _samples.length;

    // All samples should have same vector lengths — use first as template
    final avgPair = List<double>.filled(_samples[0]['pairDist']!.length, 0.0);
    final avgRatio = List<double>.filled(_samples[0]['ratios']!.length, 0.0);

    for (final s in _samples) {
      final pd = s['pairDist']!;
      final ra = s['ratios']!;
      for (int i = 0; i < avgPair.length && i < pd.length; i++) {
        avgPair[i] += pd[i] / n;
      }
      for (int i = 0; i < avgRatio.length && i < ra.length; i++) {
        avgRatio[i] += ra[i] / n;
      }
    }

    return {'pairDist': avgPair, 'ratios': avgRatio};
  }

  // ── Core matching ─────────────────────────────────────────────────────────
  /// Compare two descriptors, returning cosine similarity, Euclidean distance,
  /// and ratio distance. All three must pass their thresholds.
  _MatchScore _compareDescriptors(
    Map<String, List<double>> live,
    String storedJson,
  ) {
    try {
      final stored = jsonDecode(storedJson) as Map<String, dynamic>;

      List<double> storedPair = [];
      List<double> storedRatio = [];

      if (stored.containsKey('pairDist')) {
        storedPair = List<double>.from(stored['pairDist'] as List);
      } else if (stored.containsKey('features')) {
        // legacy v1
        storedPair = List<double>.from(stored['features'] as List);
      }

      if (stored.containsKey('ratios')) {
        storedRatio = List<double>.from(stored['ratios'] as List);
      }

      final livePair = live['pairDist']!;
      final liveRatio = live['ratios']!;

      // ── Guard A + B on pairwise distances ──────────────────────────────
      final pLen = min(livePair.length, storedPair.length);
      if (pLen == 0) return _MatchScore.zero;

      double dot = 0, mag1 = 0, mag2 = 0, sqDist = 0;
      for (int i = 0; i < pLen; i++) {
        dot += livePair[i] * storedPair[i];
        mag1 += livePair[i] * livePair[i];
        mag2 += storedPair[i] * storedPair[i];
        final d = livePair[i] - storedPair[i];
        sqDist += d * d;
      }
      final cosine = (mag1 == 0 || mag2 == 0)
          ? 0.0
          : dot / (sqrt(mag1) * sqrt(mag2));
      final euclidean = sqrt(sqDist) / sqrt(pLen.toDouble());

      // ── Guard C on geometric ratios ────────────────────────────────────
      final rLen = min(liveRatio.length, storedRatio.length);
      double ratioDist = 1.0; // worst case if no ratios
      if (rLen > 0) {
        double rSq = 0;
        for (int i = 0; i < rLen; i++) {
          final d = liveRatio[i] - storedRatio[i];
          rSq += d * d;
        }
        ratioDist = sqrt(rSq) / sqrt(rLen.toDouble());
      }

      return _MatchScore(
        cosine: cosine,
        euclidean: euclidean,
        ratioDist: ratioDist,
      );
    } catch (_) {
      return _MatchScore.zero;
    }
  }

  // ── Public: 1-to-N identification (used only for first check-in) ──────────
  /// Scan through ALL registered employees and find the best match.
  /// Returns a typed result with reason on failure.
  FaceMatchResult identifyEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
  }) {
    // Liveness check
    final livenessErr = livenessCheck(detectedFace);
    if (livenessErr != null) {
      return FaceMatchResult(
        status: FaceMatchStatus.livenessFailure,
        message: livenessErr,
      );
    }

    final liveFeatures = _buildFeatureMap(detectedFace);
    if (liveFeatures == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face features. Please try again.',
      );
    }

    EmployeeModel? bestEmployee;
    _MatchScore bestScore = _MatchScore.zero;

    for (final emp in employees) {
      if (emp.faceDescriptor == null || emp.faceDescriptor!.isEmpty) continue;
      final score = _compareDescriptors(liveFeatures, emp.faceDescriptor!);
      if (score.cosine > bestScore.cosine) {
        bestScore = score;
        bestEmployee = emp;
      }
    }

    if (bestEmployee == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.notRecognized,
        message:
            'Face not recognized. Only registered employees can mark attendance.',
      );
    }

    // All 3 guards must pass
    if (bestScore.cosine >= _cosineThreshold &&
        bestScore.euclidean <= _euclideanThreshold &&
        bestScore.ratioDist <= _ratioThreshold) {
      return FaceMatchResult(
        status: FaceMatchStatus.matched,
        employee: bestEmployee,
        message: 'Verified: ${bestEmployee.name}',
        bestCosine: bestScore.cosine,
      );
    }

    // Face found but similarity too low
    return FaceMatchResult(
      status: FaceMatchStatus.notRecognized,
      message: 'Face not recognized. Unauthorized person detected.',
      bestCosine: bestScore.cosine,
    );
  }

  // ── Public: 1-to-1 verification (check-out, break, lunch) ────────────────
  /// Verify that the face currently in frame belongs to [expectedEmployee].
  /// Uses multi-sample averaging when [useSamples] is true.
  FaceMatchResult verifyEmployee({
    required Face detectedFace,
    required EmployeeModel expectedEmployee,
    bool useSamples = false,
  }) {
    if (expectedEmployee.faceDescriptor == null ||
        expectedEmployee.faceDescriptor!.isEmpty) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'No registered face found for this employee.',
      );
    }

    // Liveness check
    final livenessErr = livenessCheck(detectedFace);
    if (livenessErr != null) {
      return FaceMatchResult(
        status: FaceMatchStatus.livenessFailure,
        message: livenessErr,
      );
    }

    Map<String, List<double>>? liveFeatures;

    if (useSamples) {
      // Accumulate sample — return early if not enough yet
      final ready = addSample(detectedFace);
      if (!ready) {
        return const FaceMatchResult(
          status: FaceMatchStatus.insufficientData,
          message: 'Collecting samples... hold still.',
        );
      }
      liveFeatures = _averagedFeatures();
      resetSamples(); // clear after use
    } else {
      liveFeatures = _buildFeatureMap(detectedFace);
    }

    if (liveFeatures == null) {
      return const FaceMatchResult(
        status: FaceMatchStatus.insufficientData,
        message: 'Could not extract face features. Please try again.',
      );
    }

    final score = _compareDescriptors(
      liveFeatures,
      expectedEmployee.faceDescriptor!,
    );

    if (score.cosine >= _cosineThreshold &&
        score.euclidean <= _euclideanThreshold &&
        score.ratioDist <= _ratioThreshold) {
      return FaceMatchResult(
        status: FaceMatchStatus.matched,
        employee: expectedEmployee,
        message: 'Identity confirmed: ${expectedEmployee.name}',
        bestCosine: score.cosine,
      );
    }

    // Specific rejection message
    final who = expectedEmployee.name;
    if (score.cosine > 0.80) {
      // Similarity is moderate — likely a different-but-somewhat-similar person
      return FaceMatchResult(
        status: FaceMatchStatus.notRecognized,
        message:
            'Unauthorized person detected. Only $who can perform this action.',
        bestCosine: score.cosine,
      );
    }

    return FaceMatchResult(
      status: FaceMatchStatus.notRecognized,
      message: 'Face not recognized. Only $who is authorized for this action.',
      bestCosine: score.cosine,
    );
  }

  // ── Legacy compat (kept for any existing callers) ─────────────────────────
  EmployeeModel? matchFaceToEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
  }) {
    final result = identifyEmployee(
      detectedFace: detectedFace,
      employees: employees,
    );
    return result.employee;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  double _dist(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return sqrt(dx * dx + dy * dy);
  }

  double getFaceConfidence(Face face) {
    double c = 0.5;
    if (face.leftEyeOpenProbability != null)
      c += face.leftEyeOpenProbability! * 0.25;
    if (face.rightEyeOpenProbability != null)
      c += face.rightEyeOpenProbability! * 0.25;
    return c.clamp(0.0, 1.0);
  }

  bool isFaceDetected(List<Face> faces) => faces.isNotEmpty;

  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
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

// ── Internal score struct ─────────────────────────────────────────────────────
class _MatchScore {
  final double cosine;
  final double euclidean;
  final double ratioDist;

  const _MatchScore({
    required this.cosine,
    required this.euclidean,
    required this.ratioDist,
  });

  static const _MatchScore zero = _MatchScore(
    cosine: 0,
    euclidean: double.infinity,
    ratioDist: double.infinity,
  );
}
