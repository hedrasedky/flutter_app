
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:heart_bpm/heart_bpm.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';

// استيراد StreamController
import 'bpm_stream.dart';

class BiometricDataPage extends StatefulWidget {
  final BluetoothDevice? connectedDevice;

  const BiometricDataPage({super.key, required this.connectedDevice});

  @override
  _BiometricDataPageState createState() => _BiometricDataPageState();
}

class _BiometricDataPageState extends State<BiometricDataPage> {
  // Heart Rate Variables
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? heartRateCharacteristic;
  BluetoothCharacteristic? accelerometerCharacteristic;
  List<FlSpot> heartRateData = [];
  int smartwatchBPM = 0;
  int phoneCameraBPM = 0;
  Timer? updateTimer;
  Timer? _analysisTimer;
  final int maxDataPoints = 50;
  double startTime = DateTime.now().millisecondsSinceEpoch.toDouble();
  String smartwatchName = "No device connected";
  List<int> todayBPM = [];
  List<int> yesterdayBPM = [70, 75, 80, 72, 76];

  // Accelerometer Variables
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  double _currentAcceleration = 0.0;
  String _movementStatus = "Stationary";
  String _accelerometerSource = "Phone";
  final List<double> _accelerationHistory = [];
  final int _maxAccelerationPoints = 50;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    connectedDevice = widget.connectedDevice;

    if (connectedDevice != null) {
      _initializeHeartRateData();
    } else {
      startScanAndConnect();
    }
  }

  bool _isValidHeartRate(int bpm) {
    return bpm > 30 && bpm < 250;
  }

  int _parseHeartRate(List<int> value) {
    if (value.isEmpty) return 0;

    int flags = value[0];
    bool is16Bit = (flags & 0x01) != 0;

    if (is16Bit && value.length >= 3) {
      return (value[1] << 8) | value[2];
    } else if (value.length >= 2) {
      return value[1];
    }
    return 0;
  }

  double _parseAccelerometerData(List<int> value) {
    if (value.length < 6) return 0.0;

    int x = (value[0] << 8) | value[1];
    int y = (value[2] << 8) | value[3];
    int z = (value[4] << 8) | value[5];

    const double scale = 0.001;
    double accelX = x * scale;
    double accelY = y * scale;
    double accelZ = z * scale;

    return sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
  }

  void _checkCriticalHeartRate(int bpm) {
    // إرسال BPM وحالة الحركة إلى EmergencyAlertsPage
    if (bpm < 60 || bpm > 100) {
      bpmStreamController.add(BPMWithMovement(bpm: bpm, movementStatus: _movementStatus));
    }
  }

  Future<void> _initializeHeartRateData() async {
    try {
      var services = await connectedDevice!.discoverServices();
      bool accelerometerFound = false;

      for (var service in services) {
        if (service.uuid.toString().toLowerCase().contains("180d")) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains("2a37")) {
              heartRateCharacteristic = char;
              await char.setNotifyValue(true);
              
              connectedDevice!.connectionState.listen((state) {
                if (state == BluetoothConnectionState.disconnected) {
                  if (mounted) {
                    setState(() {
                      smartwatchBPM = 0;
                      smartwatchName = "Disconnected";
                      _accelerometerSource = "Phone";
                    });
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Disconnected from ${connectedDevice!.name}')),
                  );
                  Future.delayed(const Duration(seconds: 3), () {
                    if (!connectedDevice!.isConnected) {
                      _initializeHeartRateData();
                    }
                  });
                }
              });

              char.value.listen((value) {
                int bpm = _parseHeartRate(value);
                if (_isValidHeartRate(bpm)) {
                  if (_movementStatus == "Running" && bpm > 100) {
                    print('High BPM due to running - ignoring');
                    return;
                  }
                  
                  double time = (DateTime.now().millisecondsSinceEpoch.toDouble() - startTime) / 1000;
                  setState(() {
                    smartwatchBPM = bpm;
                    heartRateData.add(FlSpot(time, bpm.toDouble()));
                    todayBPM.add(bpm);

                    if (heartRateData.length > maxDataPoints * 2) {
                      heartRateData.removeRange(0, heartRateData.length - maxDataPoints);
                    }

                    if (todayBPM.length > 500) {
                      todayBPM.removeRange(0, todayBPM.length - 500);
                    }
                  });
                  _checkCriticalHeartRate(bpm);
                }
              });
              
              smartwatchName = connectedDevice!.name.isNotEmpty
                  ? connectedDevice!.name
                  : "Unnamed Device";
              startPeriodicUpdates();
            }
          }
        }
        if (service.uuid.toString().toLowerCase().contains("1816")) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains("2a5d") || char.properties.notify) {
              accelerometerCharacteristic = char;
              await char.setNotifyValue(true);
              accelerometerFound = true;
              
              char.value.listen((value) {
                double acceleration = _parseAccelerometerData(value);
                
                setState(() {
                  _currentAcceleration = acceleration;
                  _accelerationHistory.add(acceleration);
                  _accelerometerSource = "Watch";
                  
                  if (_accelerationHistory.length > _maxAccelerationPoints) {
                    _accelerationHistory.removeAt(0);
                  }
                  
                  if (acceleration > 15) {
                    _movementStatus = "Running";
                  } else if (acceleration > 8) {
                    _movementStatus = "Walking";
                  } else {
                    _movementStatus = "Stationary";
                  }
                });
              });
            }
          }
        }
      }

      if (!accelerometerFound) {
        _startAccelerometer();
      }
    } catch (e) {
      print("Error during initialization: $e");
      _startAccelerometer();
    }
  }

  void _startAccelerometer() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      double acceleration = _calculateAcceleration(event);
      
      setState(() {
        _currentAcceleration = acceleration;
        _accelerationHistory.add(acceleration);
        _accelerometerSource = "Phone";
        
        if (_accelerationHistory.length > _maxAccelerationPoints) {
          _accelerationHistory.removeAt(0);
        }
        
        if (acceleration > 15) {
          _movementStatus = "Running";
        } else if (acceleration > 8) {
          _movementStatus = "Walking";
        } else {
          _movementStatus = "Stationary";
        }
      });
    });
  }

  double _calculateAcceleration(AccelerometerEvent event) {
    return sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
  }

  void _stopAccelerometer() {
    _accelerometerSubscription?.cancel();
  }

  Future<void> requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.camera.request();
    await Permission.sensors.request();
  }

  void startScanAndConnect() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult result in results) {
        if (result.advertisementData.serviceUuids.contains("180D") ||
            result.device.name.isNotEmpty) {
          try {
            await result.device.connect(timeout: const Duration(seconds: 10));
            if (!mounted) {
              return setState(() {
                smartwatchName = result.device.name.isNotEmpty
                    ? result.device.name
                    : "Unnamed Device";
              });
            }
            var services = await result.device.discoverServices();
            bool accelerometerFound = false;

            for (var service in services) {
              if (service.uuid.toString().toLowerCase().contains("180d")) {
                for (var char in service.characteristics) {
                  if (char.uuid.toString().toLowerCase().contains("2a37")) {
                    heartRateCharacteristic = char;
                    await char.setNotifyValue(true);
                    char.value.listen((value) {
                      if (value.isNotEmpty && value.length > 1) {
                        int bpm = _parseHeartRate(value);
                        double time = (DateTime.now().millisecondsSinceEpoch.toDouble() - startTime) / 1000;
                        setState(() {
                          smartwatchBPM = bpm;
                          heartRateData.add(FlSpot(time, bpm.toDouble()));
                          todayBPM.add(bpm);
                          if (heartRateData.length > maxDataPoints) {
                            heartRateData.removeAt(0);
                          }
                        });
                        _checkCriticalHeartRate(bpm);
                        saveToFile(bpm);
                      }
                    });
                  }
                }
              }
              if (service.uuid.toString().toLowerCase().contains("1816")) {
                for (var char in service.characteristics) {
                  if (char.uuid.toString().toLowerCase().contains("2a5d") || char.properties.notify) {
                    accelerometerCharacteristic = char;
                    await char.setNotifyValue(true);
                    accelerometerFound = true;
                    
                    char.value.listen((value) {
                      double acceleration = _parseAccelerometerData(value);
                      
                      setState(() {
                        _currentAcceleration = acceleration;
                        _accelerationHistory.add(acceleration);
                        _accelerometerSource = "Watch";
                        
                        if (_accelerationHistory.length > _maxAccelerationPoints) {
                          _accelerationHistory.removeAt(0);
                        }
                        
                        if (acceleration > 15) {
                          _movementStatus = "Running";
                        } else if (acceleration > 8) {
                          _movementStatus = "Walking";
                        } else {
                          _movementStatus = "Stationary";
                        }
                      });
                    });
                  }
                }
              }
            }
            FlutterBluePlus.stopScan();
            startPeriodicUpdates();
            if (!accelerometerFound) {
              _startAccelerometer();
            }
            break;
          } on Exception catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Connection failed: ${e.toString()}')),
              );
            }
            await FlutterBluePlus.stopScan();
          }
        }
      }
    });
  }

  void startPeriodicUpdates() {
    updateTimer?.cancel();
    
    updateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || heartRateCharacteristic == null || 
          !(connectedDevice?.isConnected ?? false)) {
        updateTimer?.cancel();
        return;
      }
      
      try {
        var value = await heartRateCharacteristic!.read().timeout(const Duration(seconds: 3));
        int bpm = _parseHeartRate(value);
        if (_isValidHeartRate(bpm)) {
          double time = (DateTime.now().millisecondsSinceEpoch.toDouble() - startTime) / 1000;
          if (mounted) {
            setState(() {
              smartwatchBPM = bpm;
              heartRateData.add(FlSpot(time, bpm.toDouble()));
              todayBPM.add(bpm);
            });
            _checkCriticalHeartRate(bpm);
          }
        }
      } catch (e) {
        print('Error reading heart rate: $e');
      }
    });
  }

  Future<void> saveToFile(int bpm) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/heart_rate_log.txt');
    final now = DateTime.now();
    final line = '${now.toIso8601String()} - $bpm - $_movementStatus\n';
    await file.writeAsString(line, mode: FileMode.append);
  }

  double compareTodayWithYesterday() {
    if (todayBPM.isEmpty || yesterdayBPM.isEmpty) return 0.0;
    double todayAvg = todayBPM.reduce((a, b) => a + b) / todayBPM.length;
    double yesterdayAvg = yesterdayBPM.reduce((a, b) => a + b) / yesterdayBPM.length;
    return todayAvg - yesterdayAvg;
  }

  void measureHeartRateFromPhone() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _CameraMeasurementScreen(
          onBPM: (value) {
            setState(() {
              phoneCameraBPM = value;
            });
            _checkCriticalHeartRate(value);
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  void dispose() {
    updateTimer?.cancel();
    _analysisTimer?.cancel();
    _stopAccelerometer();
    heartRateCharacteristic?.setNotifyValue(false);
    accelerometerCharacteristic?.setNotifyValue(false);
    connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Biometric Data"),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: theme.brightness == Brightness.dark
              ? null
              : const LinearGradient(
                  colors: [
                    Color.fromARGB(255, 243, 247, 255),
                    Color(0xFF42A5F5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Lottie.asset(
                'lottie/heart_beat.json',
                width: 300,
                height: 100,
                fit: BoxFit.contain,
                repeat: true,
                animate: true,
                options: LottieOptions(enableMergePaths: true),
              ),
              const SizedBox(height: 20),
              Text(
                "Connected to: $smartwatchName",
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 16,
                ),
              ),
              Row(
                children: [
                  Icon(
                    connectedDevice?.isConnected ?? false 
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                    color: connectedDevice?.isConnected ?? false 
                      ? Colors.green 
                      : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connectedDevice?.isConnected ?? false 
                      ? "Connected" 
                      : "Disconnected",
                    style: TextStyle(
                      color: connectedDevice?.isConnected ?? false 
                        ? Colors.green 
                        : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _buildCard(
                title: "Smartwatch",
                value: smartwatchBPM > 0 ? "$smartwatchBPM bpm" : "0 bpm",
                gradientColors: [
                  const Color.fromARGB(255, 54, 47, 46),
                  Colors.red.shade700,
                ],
                icon: Icons.watch,
                chart: heartRateData.isNotEmpty
                    ? LineChart(
                        LineChartData(
                          minY: 40,
                          maxY: 180,
                          titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true),
                            ),
                          ),
                          gridData: const FlGridData(show: true),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: heartRateData,
                              isCurved: true,
                              color: Colors.white,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      )
                    : const Center(
                        child: Text(
                          "No Heart Rate Data",
                          style: TextStyle(
                            color: Color.fromARGB(255, 255, 254, 254),
                            fontSize: 20,
                          ),
                        ),
                      ),
                additionalInfo: "Acceleration: ${_currentAcceleration.toStringAsFixed(2)} m/s²\nStatus: $_movementStatus\nSource: $_accelerometerSource",
                additionalIcon: Icons.directions_run,
              ),
              const SizedBox(height: 20),
              _buildCard(
                title: "Phone Camera",
                value: phoneCameraBPM > 0 ? "$phoneCameraBPM bpm" : "0 bpm",
                gradientColors: [
                  const Color.fromARGB(255, 54, 47, 46),
                  Colors.red.shade700,
                ],
                icon: Icons.camera_alt,
                buttonRow: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: measureHeartRateFromPhone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        "Measure Now",
                        style: TextStyle(color: theme.primaryColor),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: startPeriodicUpdates,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        "Update Data",
                        style: TextStyle(color: theme.primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Difference from yesterday: ${compareTodayWithYesterday().toStringAsFixed(1)} bpm",
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String value,
    required List<Color> gradientColors,
    required IconData icon,
    Widget? chart,
    Widget? button,
    Widget? buttonRow,
    String? additionalInfo,
    IconData? additionalIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(0.3),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (value.isNotEmpty)
              Text(
                value,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            const SizedBox(height: 10),
            if (additionalInfo != null)
              Row(
                children: [
                  if (additionalIcon != null)
                    CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.3),
                      radius: 12,
                      child: Icon(additionalIcon, color: Colors.white, size: 16),
                    ),
                  if (additionalIcon != null) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      additionalInfo,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            if (chart != null)
              SizedBox(
                height: 150,
                child: chart,
              ),
            if (button != null)
              Center(
                child: button,
              ),
            if (buttonRow != null) buttonRow,
          ],
        ),
      ),
    );
  }
}

class _CameraMeasurementScreen extends StatefulWidget {
  final Function(int) onBPM;

  const _CameraMeasurementScreen({required this.onBPM});

  @override
  _CameraMeasurementScreenState createState() => _CameraMeasurementScreenState();
}

class _CameraMeasurementScreenState extends State<_CameraMeasurementScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  int progress = 0;
  bool isMeasuring = false;
  bool isFingerOnSensor = false;
  Timer? progressTimer;
  Timer? _analysisTimer;
  int? measuredBPM;
  bool measurementCompleted = false;
  double _lastLightLevel = 0;
  int _noFingerCounter = 0;
  String _movementStatus = "Stationary"; // Default value for movement status

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller.initialize();
    if (mounted) {
      setState(() => _isCameraInitialized = true);
      _startLightAnalysis();
    }
  }

  void _startLightAnalysis() {
    _analysisTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (!_controller.value.isStreamingImages || !isMeasuring) return;

      try {
        final frame = await _controller.takePicture();
        final image = img.decodeImage(await File(frame.path).readAsBytes());
        if (image == null) return;

        final lightLevel = _calculateLightLevel(image);
        final lightChange = (lightLevel - _lastLightLevel).abs();

        setState(() {
          if (lightChange > 20 && lightLevel < 100) {
            isFingerOnSensor = true;
            _noFingerCounter = 0;
          } else {
            _noFingerCounter++;
            if (_noFingerCounter > 3) {
              isFingerOnSensor = false;
            }
          }
          _lastLightLevel = lightLevel;
        });

        if (isFingerOnSensor && !isMeasuring && !measurementCompleted) {
          _startMeasurement();
        } else if (!isFingerOnSensor && isMeasuring) {
          _resetMeasurement();
        }

        await File(frame.path).delete();
      } catch (e) {
        print('Error analyzing frame: $e');
      }
    });
  }

  double _calculateLightLevel(img.Image image) {
    int sum = 0;
    final pixels = image.getBytes();
    for (int i = 0; i < pixels.length; i += 4) {
      sum += (pixels[i] + pixels[i + 1] + pixels[i + 2]) ~/ 3;
    }
    return sum / (image.width * image.height);
  }

  void _startMeasurement() {
    setState(() {
      isMeasuring = true;
      progress = 0;
      measurementCompleted = false;
      measuredBPM = null;
    });

    progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (progress < 100) {
        setState(() => progress += 2);
      } else {
        timer.cancel();
        _completeMeasurement();
      }
    });
  }

  void _completeMeasurement() {
    setState(() {
      isMeasuring = false;
      measurementCompleted = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => HeartBPMDialog(
        context: context,
        onBPM: (value) {
          setState(() => measuredBPM = value);
          widget.onBPM(value);
          _checkCriticalHeartRate(value);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _checkCriticalHeartRate(int bpm) {
    if (bpm < 60 || bpm > 100) {
      bpmStreamController.add(BPMWithMovement(bpm: bpm, movementStatus: _movementStatus));
    }
  }

  void _resetMeasurement() {
    progressTimer?.cancel();
    setState(() {
      isMeasuring = false;
      progress = 0;
      measurementCompleted = false;
    });
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    progressTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isCameraInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: CameraPreview(_controller),
              ),
            ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.7),
                border: Border.all(
                  color: isFingerOnSensor ? Colors.red : Colors.grey,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isFingerOnSensor)
                    const Icon(
                      Icons.fingerprint,
                      color: Colors.red,
                      size: 60,
                    ),
                  if (isMeasuring) ...[
                    const SizedBox(height: 20),
                    Text(
                      '$progress%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: Colors.grey,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (measurementCompleted && measuredBPM != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Measurement Complete',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '$measuredBPM BPM',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              isFingerOnSensor
                  ? 'Keep your finger on the camera'
                  : 'Cover the camera completely with your finger',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
