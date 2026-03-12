// lib/data/services/face_detection_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/employee_model.dart';

class FaceDetectionService {
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  void initialize() {
    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
    _isInitialized = true;
  }

  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (!_isInitialized) initialize();
    return await _faceDetector.processImage(inputImage);
  }

  Future<List<Face>> detectFacesFromFile(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    return detectFaces(inputImage);
  }

  Future<List<Face>> detectFacesFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final inputImage = _convertCameraImage(image, camera);
    if (inputImage == null) return [];
    return detectFaces(inputImage);
  }

  // ── Face Descriptor ──────────────────────────────────────────────────────────
  // Builds a geometric descriptor from face landmarks.
  // Stored as a JSON string in Firestore under employee.faceDescriptor.
  String? buildFaceDescriptor(Face face) {
    try {
      final landmarks = <String, List<double>>{};

      // Collect all available landmarks
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

      for (final type in landmarkTypes) {
        final landmark = face.landmarks[type];
        if (landmark != null) {
          landmarks[type.name] = [
            landmark.position.x.toDouble(),
            landmark.position.y.toDouble(),
          ];
        }
      }

      if (landmarks.length < 3) return null; // not enough landmarks

      // Normalise relative to face bounding box so descriptor is scale-invariant
      final bbox = face.boundingBox;
      final normLandmarks = <String, List<double>>{};
      landmarks.forEach((key, pos) {
        normLandmarks[key] = [
          (pos[0] - bbox.left) / bbox.width,
          (pos[1] - bbox.top) / bbox.height,
        ];
      });

      // Build geometric feature vector: pairwise distances between landmarks
      final positions = normLandmarks.values.toList();
      final features = <double>[];
      for (int i = 0; i < positions.length; i++) {
        for (int j = i + 1; j < positions.length; j++) {
          final dx = positions[i][0] - positions[j][0];
          final dy = positions[i][1] - positions[j][1];
          features.add(sqrt(dx * dx + dy * dy));
        }
      }

      final descriptor = {
        'landmarks': normLandmarks,
        'features': features,
        'headEulerY': face.headEulerAngleY ?? 0.0,
        'version': 1,
      };

      return jsonEncode(descriptor);
    } catch (e) {
      print('[FaceDetection] buildFaceDescriptor error: $e');
      return null;
    }
  }

  // ── Face Matching ────────────────────────────────────────────────────────────
  // Returns the best-matching employee if similarity exceeds threshold.
  EmployeeModel? matchFaceToEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
    double threshold = 0.78, // 0–1 scale; higher = stricter
  }) {
    final descriptor = buildFaceDescriptor(detectedFace);
    if (descriptor == null) return null;

    EmployeeModel? bestMatch;
    double bestScore = 0;

    for (final employee in employees) {
      if (employee.faceDescriptor == null ||
          employee.faceDescriptor!.isEmpty) continue;

      final score = _compareFaceDescriptors(descriptor, employee.faceDescriptor!);
      print('[FaceDetection] ${employee.name} score: ${score.toStringAsFixed(3)}');

      if (score > bestScore) {
        bestScore = score;
        bestMatch = employee;
      }
    }

    if (bestScore >= threshold) {
      print('[FaceDetection] Matched: ${bestMatch?.name} (score: $bestScore)');
      return bestMatch;
    }

    print('[FaceDetection] No match found. Best score: $bestScore');
    return null;
  }

  double _compareFaceDescriptors(String desc1Json, String desc2Json) {
    try {
      final d1 = jsonDecode(desc1Json) as Map<String, dynamic>;
      final d2 = jsonDecode(desc2Json) as Map<String, dynamic>;

      final f1 = List<double>.from(d1['features'] as List);
      final f2 = List<double>.from(d2['features'] as List);

      if (f1.isEmpty || f2.isEmpty) return 0;

      // Use the shorter vector length for safety
      final len = min(f1.length, f2.length);

      // Cosine similarity between feature vectors
      double dot = 0, mag1 = 0, mag2 = 0;
      for (int i = 0; i < len; i++) {
        dot += f1[i] * f2[i];
        mag1 += f1[i] * f1[i];
        mag2 += f2[i] * f2[i];
      }

      if (mag1 == 0 || mag2 == 0) return 0;
      return dot / (sqrt(mag1) * sqrt(mag2));
    } catch (e) {
      print('[FaceDetection] compare error: $e');
      return 0;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  bool isFaceDetected(List<Face> faces) => faces.isNotEmpty;

  bool isFaceGoodQuality(Face face) {
    // Check face is looking mostly forward
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    return yaw < 20 && pitch < 15;
  }

  double getFaceConfidence(Face face) {
    double confidence = 0.5;
    if (face.leftEyeOpenProbability != null) {
      confidence += face.leftEyeOpenProbability! * 0.25;
    }
    if (face.rightEyeOpenProbability != null) {
      confidence += face.rightEyeOpenProbability! * 0.25;
    }
    return confidence.clamp(0.0, 1.0);
  }

  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    if (_isInitialized) {
      _faceDetector.close();
      _isInitialized = false;
    }
  }
}