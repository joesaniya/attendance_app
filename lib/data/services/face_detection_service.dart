// lib/data/services/face_detection_service.dart

import 'dart:io';
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

  InputImage? _convertCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final imageRotation = InputImageRotationValue.fromRawValue(
              camera.sensorOrientation) ??
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

  // Simple face matching - compare bounding boxes and landmarks
  // In production, use a proper face recognition model
  Future<EmployeeModel?> matchFace({
    required List<Face> detectedFaces,
    required List<EmployeeModel> employees,
  }) async {
    if (detectedFaces.isEmpty) return null;

    // For demo purposes: if face is detected with high confidence,
    // return a match. In production, implement proper face embedding comparison.
    final face = detectedFaces.first;

    // Check face quality
    if (face.smilingProbability != null) {
      // Face is detected and has landmarks - consider it a valid detection
      // In a real system, compare face embeddings with stored descriptors
      return null; // Return matched employee in real implementation
    }

    return null;
  }

  bool isFaceDetected(List<Face> faces) => faces.isNotEmpty;

  double getFaceConfidence(Face face) {
    // Calculate confidence based on available metrics
    double confidence = 0.5;
    if (face.leftEyeOpenProbability != null) {
      confidence += face.leftEyeOpenProbability! * 0.25;
    }
    if (face.rightEyeOpenProbability != null) {
      confidence += face.rightEyeOpenProbability! * 0.25;
    }
    return confidence.clamp(0.0, 1.0);
  }

  void dispose() {
    if (_isInitialized) {
      _faceDetector.close();
      _isInitialized = false;
    }
  }
}
