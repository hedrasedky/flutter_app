import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';

class HeartRateMeasurement extends StatefulWidget {
  final Function(int) onBPM;

  const HeartRateMeasurement({super.key, required this.onBPM});

  @override
  _HeartRateMeasurementState createState() => _HeartRateMeasurementState();
}

class _HeartRateMeasurementState extends State<HeartRateMeasurement> {
  CameraController? _cameraController;
  bool _isMeasuring = false;
  int _progress = 0;
  Timer? _progressTimer;
  final List<double> _intensityData = [];
  final List<DateTime> _peakTimestamps = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    await _cameraController!.setFlashMode(FlashMode.torch);

    _cameraController!.startImageStream(_processCameraImage);
  }

  void _processCameraImage(CameraImage image) {
    final bytes = image.planes.first.bytes;
    final avgIntensity = bytes.reduce((a, b) => a + b) / bytes.length;

    if (avgIntensity < 50) {
      // Finger is on the camera
      if (!_isMeasuring) {
        _startMeasurement();
      }
      _intensityData.add(avgIntensity);
      _detectPeak(avgIntensity);
    } else {
      // Finger removed
      if (_isMeasuring) {
        _resetMeasurement();
      }
    }
  }

  void _startMeasurement() {
    setState(() {
      _isMeasuring = true;
      _progress = 0;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _progress += 2;
      });

      if (_progress >= 100) {
        timer.cancel();
        _calculateBPM();
      }
    });
  }

  void _resetMeasurement() {
    setState(() {
      _isMeasuring = false;
      _progress = 0;
      _intensityData.clear();
      _peakTimestamps.clear();
    });
    _progressTimer?.cancel();
  }

  void _detectPeak(double intensity) {
    // Simple peak detection logic
    if (_intensityData.length < 3) return;

    final prev = _intensityData[_intensityData.length - 2];
    final curr = _intensityData.last;

    if (curr > prev && curr > intensity) {
      _peakTimestamps.add(DateTime.now());
    }
  }

  void _calculateBPM() {
    if (_peakTimestamps.length < 2) {
      _resetMeasurement();
      return;
    }

    final intervals = <int>[];
    for (int i = 1; i < _peakTimestamps.length; i++) {
      intervals.add(_peakTimestamps[i].difference(_peakTimestamps[i - 1]).inMilliseconds);
    }

    final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    final bpm = (60000 / avgInterval).round();

    widget.onBPM(bpm);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _cameraController != null && _cameraController!.value.isInitialized
                ? CameraPreview(_cameraController!)
                : const CircularProgressIndicator(),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  'جارٍ القياس ($_progress%)',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 10),
                const Text(
                  'ضع إصبعك على الكاميرا',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
