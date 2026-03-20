import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service that records a 30-second video when SOS is triggered
/// and uploads it to Firebase Storage under `sos_recordings/`.
class VideoRecordingService {
  static CameraController? _controller;
  static bool _isRecording = false;
  static Timer? _stopTimer;

  /// Start recording a 30-second video using the rear camera.
  /// The video is automatically stopped and uploaded after 30 seconds.
  static Future<void> startSOSRecording() async {
    if (_isRecording) return;

    try {
      // Request camera and microphone permissions
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        debugPrint('VideoRecordingService: Camera/mic permission denied');
        return;
      }

      // Get available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('VideoRecordingService: No cameras available');
        return;
      }

      // Prefer back camera for evidence recording
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Initialize camera controller
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await _controller!.initialize();

      // Start recording
      await _controller!.startVideoRecording();
      _isRecording = true;
      debugPrint('VideoRecordingService: Recording started');

      // Auto-stop after 30 seconds
      _stopTimer = Timer(const Duration(seconds: 30), () {
        stopAndUpload();
      });
    } catch (e) {
      debugPrint('VideoRecordingService: Failed to start recording — $e');
      _cleanup();
    }
  }

  /// Stop recording and upload the video to Firebase Storage.
  static Future<void> stopAndUpload() async {
    if (!_isRecording || _controller == null) return;

    _stopTimer?.cancel();
    _stopTimer = null;

    try {
      // Stop recording
      final videoFile = await _controller!.stopVideoRecording();
      _isRecording = false;
      debugPrint('VideoRecordingService: Recording stopped — ${videoFile.path}');

      // Upload to Firebase Storage
      await _uploadVideo(videoFile.path);
    } catch (e) {
      debugPrint('VideoRecordingService: Failed to stop recording — $e');
    } finally {
      _cleanup();
    }
  }

  /// Upload a video file to Firebase Storage.
  static Future<void> _uploadVideo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('VideoRecordingService: File does not exist');
        return;
      }

      // Generate a unique filename with timestamp
      final now = DateTime.now();
      final fileName =
          'SOS_${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}.mp4';

      final ref = FirebaseStorage.instance.ref('sos_recordings/$fileName');
      await ref.putFile(
        file,
        SettableMetadata(contentType: 'video/mp4'),
      );

      debugPrint('VideoRecordingService: Video uploaded as $fileName');

      // Clean up local file
      await file.delete();
    } catch (e) {
      debugPrint('VideoRecordingService: Upload failed — $e');
    }
  }

  /// Release camera resources.
  static void _cleanup() {
    _controller?.dispose();
    _controller = null;
    _isRecording = false;
  }

  /// Check if currently recording.
  static bool get isRecording => _isRecording;
}
