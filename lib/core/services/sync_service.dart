// lib/core/services/sync_service.dart
import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'local_db_service.dart';
import 'network_service.dart';
import '../constants/app_constants.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final LocalDbService _localDb = LocalDbService();
  final NetworkService _network = NetworkService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  StreamSubscription<bool>? _networkSub;
  bool _isSyncing = false;

  void initialize() {
    log('[SyncService] Initializing...');
    _networkSub = _network.onNetworkChange.listen((isOnline) {
      if (isOnline) {
        log('[SyncService] Device is online. Triggering sync...');
        syncNow();
      }
    });
  }

  void dispose() {
    _networkSub?.cancel();
  }

  Future<void> syncNow() async {
    if (_isSyncing) return;
    final isOnline = await _network.isConnected();
    if (!isOnline) {
      log('[SyncService] Offline, overriding sync attempt.');
      return;
    }
    
    _isSyncing = true;
    try {
      final unsynced = await _localDb.getUnsyncedAttendance();
      if (unsynced.isEmpty) {
        log('[SyncService] No pending attendance records to sync.');
        _isSyncing = false;
        return;
      }

      log('[SyncService] Found ${unsynced.length} pending records. Syncing...');

      for (var record in unsynced) {
        bool uploadedPhoto = false;
        String? newPhotoUrl;
        
        final localPhotoPath = record['localPhotoPath'] as String?;
        final id = record['id'] as String;
        final employeeId = record['employeeId'] as String;
        final employeeName = record['employeeName'] as String?;

        if (localPhotoPath != null && localPhotoPath.isNotEmpty) {
          final file = File(localPhotoPath);
          if (file.existsSync()) {
            final fileName = 'attendance_${id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final ref = _storage.ref().child('${AppConstants.attendancePhotosPath}/$employeeId/$fileName');
            
            try {
              await ref.putFile(file);
              newPhotoUrl = await ref.getDownloadURL();
              uploadedPhoto = true;
            } catch (e) {
              log('[SyncService] Failed to upload photo: $e');
            }
          }
        }

        final syncMap = Map<String, dynamic>.from(record);
        syncMap.remove('isSynced');
        syncMap.remove('localPhotoPath');
        
        // Use uploaded photo photoUrl if available
        if (uploadedPhoto && newPhotoUrl != null) {
            syncMap['employeePhotoUrl'] = newPhotoUrl;
        }

        try {
          await _firestore.collection(AppConstants.attendanceCollection).doc(id).set(syncMap, SetOptions(merge: true));
          await _localDb.markAttendanceSynced(id);
          log('[SyncService] Synced record: $id');
        } catch (e) {
          log('[SyncService] Failed to sync record $id: $e');
        }
      }
    } catch (e) {
      log('[SyncService] Error during sync loop: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
