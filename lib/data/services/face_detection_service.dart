// lib/data/services/face_detection_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/employee_model.dart';

class FaceDetectionService {
  FaceDetector? _faceDetector;
  bool _isInitialized = false;

  // ── Prevent concurrent processing that causes GC buffer drops ────────────────
  bool _isProcessing = false;

  void initialize() {
    if (_isInitialized) return;
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
    if (_faceDetector == null) return [];
    try {
      return await _faceDetector!.processImage(inputImage);
    } catch (e) {
      return [];
    }
  }

  Future<List<Face>> detectFacesFromFile(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    return detectFaces(inputImage);
  }

  /// Safe camera image processing — copies bytes immediately before GC can drop them.
  Future<List<Face>> detectFacesFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) async {
    // Guard: skip if already processing to avoid buffer backlog
    if (_isProcessing) return [];
    _isProcessing = true;
    try {
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) return [];
      return await detectFaces(inputImage);
    } catch (e) {
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  // ── Face Descriptor ──────────────────────────────────────────────────────────
  String? buildFaceDescriptor(Face face) {
    try {
      final landmarks = <String, List<double>>{};

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

      if (landmarks.length < 3) return null;

      final bbox = face.boundingBox;
      if (bbox.width == 0 || bbox.height == 0) return null;

      final normLandmarks = <String, List<double>>{};
      landmarks.forEach((key, pos) {
        normLandmarks[key] = [
          (pos[0] - bbox.left) / bbox.width,
          (pos[1] - bbox.top) / bbox.height,
        ];
      });

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
      return null;
    }
  }

  // ── Face Matching ────────────────────────────────────────────────────────────
  EmployeeModel? matchFaceToEmployee({
    required Face detectedFace,
    required List<EmployeeModel> employees,
    double threshold = 0.78,
  }) {
    final descriptor = buildFaceDescriptor(detectedFace);
    if (descriptor == null) return null;

    EmployeeModel? bestMatch;
    double bestScore = 0;

    for (final employee in employees) {
      if (employee.faceDescriptor == null || employee.faceDescriptor!.isEmpty) {
        continue;
      }

      final score = _compareFaceDescriptors(
        descriptor,
        employee.faceDescriptor!,
      );

      if (score > bestScore) {
        bestScore = score;
        bestMatch = employee;
      }
    }

    if (bestScore >= threshold) {
      return bestMatch;
    }
    return null;
  }

  double _compareFaceDescriptors(String desc1Json, String desc2Json) {
    try {
      final d1 = jsonDecode(desc1Json) as Map<String, dynamic>;
      final d2 = jsonDecode(desc2Json) as Map<String, dynamic>;

      final f1 = List<double>.from(d1['features'] as List);
      final f2 = List<double>.from(d2['features'] as List);

      if (f1.isEmpty || f2.isEmpty) return 0;

      final len = min(f1.length, f2.length);

      double dot = 0, mag1 = 0, mag2 = 0;
      for (int i = 0; i < len; i++) {
        dot += f1[i] * f2[i];
        mag1 += f1[i] * f1[i];
        mag2 += f2[i] * f2[i];
      }

      if (mag1 == 0 || mag2 == 0) return 0;
      return dot / (sqrt(mag1) * sqrt(mag2));
    } catch (e) {
      return 0;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  bool isFaceDetected(List<Face> faces) => faces.isNotEmpty;

  bool isFaceGoodQuality(Face face) {
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

  /// KEY FIX: Copy all plane bytes into a single owned buffer immediately,
  /// before returning — this prevents the GC from dropping the native buffer
  /// while ML Kit is still reading it (the root cause of IllegalArgumentException).
  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    try {
      // Calculate total byte length upfront
      int totalBytes = 0;
      for (final plane in image.planes) {
        totalBytes += plane.bytes.length;
      }

      // Allocate a single owned buffer and copy all planes into it
      final Uint8List allBytes = Uint8List(totalBytes);
      int offset = 0;
      for (final plane in image.planes) {
        allBytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      return InputImage.fromBytes(
        bytes: allBytes,
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
      _faceDetector?.close();
      _faceDetector = null;
      _isInitialized = false;
      _isProcessing = false;
    }
  }
}
