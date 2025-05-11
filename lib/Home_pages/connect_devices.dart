import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart';
import 'biometricdatapage.dart';

class ConnectedDevicesPage extends StatefulWidget {
  const ConnectedDevicesPage({super.key});

  @override
  _ConnectedDevicesPageState createState() => _ConnectedDevicesPageState();
}

class _ConnectedDevicesPageState extends State<ConnectedDevicesPage> {
  final Logger _logger = Logger('ConnectedDevicesPage');
  BluetoothDevice? connectedDevice;
  StreamSubscription<ScanResult>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool isScanning = false;
  bool isConnecting = false;
  List<ScanResult> scanResults = [];

  @override
  void initState() {
    super.initState();
    // تهيئة التسجيل
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      print('${record.level.name}: ${record.time}: ${record.message}');
    });
    requestPermissions();
  }

  Future<void> requestPermissions() async {
    var statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (!statuses.values.every((status) => status.isGranted)) {
      _logger.warning("Some permissions not granted: $statuses");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى منح أذونات البلوتوث')),
        );
      }
    } else {
      _logger.info("All Bluetooth permissions granted");
    }
  }

  void startScan() async {
    if (isScanning || isConnecting) return;

    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      _logger.info("Started Bluetooth scan");

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            scanResults = results.where((result) => result.device.name.isNotEmpty).toList();
          });
        }
      }, onError: (e) {
        _logger.severe("Scan error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء الفحص: $e')),
          );
        }
      }) as StreamSubscription<ScanResult>?;

      await Future.delayed(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
      await FlutterBluePlus.stopScan();
      _logger.info("Stopped Bluetooth scan");
    } catch (e) {
      _logger.severe("Error starting scan: $e");
      if (mounted) {
        setState(() {
          isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الفحص: $e')),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (isConnecting) return;

    setState(() {
      isConnecting = true;
    });

    const maxRetries = 3;
    int retryCount = 0;
    bool isConnected = false;

    while (retryCount < maxRetries && !isConnected && mounted) {
      try {
        retryCount++;
        _logger.info(
            "Attempting to connect to ${device.name} (${device.id}), attempt $retryCount/$maxRetries");

        // إيقاف الفحص قبل الاتصال
        await FlutterBluePlus.stopScan();
        _scanSubscription?.cancel();

        // الاتصال مع مهلة 20 ثانية
        await device.connect(timeout: const Duration(seconds: 20));
        _logger.info("Initial connection to ${device.name} established");

        // مراقبة حالة الاتصال
        _connectionSubscription?.cancel();
        _connectionSubscription = device.connectionState.listen((state) async {
          _logger.info("Connection state for ${device.name}: $state");
          if (state == BluetoothConnectionState.connected) {
            isConnected = true;
            if (mounted) {
              setState(() {
                connectedDevice = device;
                isConnecting = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم الاتصال بـ ${device.name}')),
              );
            }

            // اكتشاف الخدمات
            List<BluetoothService> services = await device.discoverServices();
            _logger.info("Discovered ${services.length} services for ${device.name}");
            for (BluetoothService service in services) {
              _logger.info("Service UUID: ${service.uuid.toString()}");
              for (BluetoothCharacteristic characteristic in service.characteristics) {
                _logger.info("  Characteristic UUID: ${characteristic.uuid.toString()}");
              }
            }

            bool heartRateServiceFound = false;
            BluetoothCharacteristic? heartRateCharacteristic;

            for (BluetoothService service in services) {
              // الخدمة القياسية لمعدل ضربات القلب
              if (service.uuid.toString() == "0000180d-0000-1000-8000-00805f9b34fb") {
                heartRateServiceFound = true;
                for (BluetoothCharacteristic characteristic in service.characteristics) {
                  if (characteristic.uuid.toString() == "00002a37-0000-1000-8000-00805f9b34fb") {
                    heartRateCharacteristic = characteristic;
                    await characteristic.setNotifyValue(true);
                    characteristic.value.listen((value) {
                      if (value.isNotEmpty && mounted) {
                        _logger.info("Raw Heart Rate Data: $value");
                        int heartRate = value[1]; // تنسيق قياسي (قد يحتاج تعديل)
                        _logger.info("Heart Rate: $heartRate bpm");
                      }
                    });
                    break;
                  }
                }
              }
              if (heartRateServiceFound) break;
            }

            if (!heartRateServiceFound) {
              await device.disconnect();
              _logger.warning("No Heart Rate Service found on ${device.name}");
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${device.name} لا يدعم خدمة معدل ضربات القلب')),
                );
                setState(() {
                  isConnecting = false;
                });
              }
              return;
            }

            // الانتقال لصفحة البيانات
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BiometricDataPage(
                    connectedDevice: device,
                    heartRateCharacteristic: heartRateCharacteristic,
                  ),
                ),
              ).then((_) {
                // عند العودة من BiometricDataPage، إعادة تعيين الحالة
                if (mounted) {
                  setState(() {
                    isConnecting = false;
                    connectedDevice = null;
                  });
                }
              });
            }
          } else if (state == BluetoothConnectionState.disconnected) {
            _logger.warning("Device ${device.name} disconnected unexpectedly");
            if (mounted) {
              setState(() {
                connectedDevice = null;
                isConnecting = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم قطع الاتصال بـ ${device.name}')),
              );
            }
          }
        });
      } catch (e) {
        _logger.severe("Connection Error for ${device.name}: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل الاتصال بـ ${device.name}: $e')),
          );
          setState(() {
            isConnecting = false;
          });
        }
        await device.disconnect();

        if (retryCount < maxRetries) {
          _logger.info("Retrying connection to ${device.name}...");
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (!isConnected && mounted) {
      setState(() {
        isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاتصال بـ ${device.name} بعد $maxRetries محاولات')),
      );
    }
  }

  Future<void> _disconnectDevice() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
        _connectionSubscription?.cancel();
        _logger.info("Disconnected from ${connectedDevice!.name}");
        if (mounted) {
          setState(() {
            connectedDevice = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم قطع الاتصال')),
          );
        }
      } catch (e) {
        _logger.severe("Error disconnecting: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء قطع الاتصال: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _disconnectDevice();
    FlutterBluePlus.stopScan();
    super.dispose();
    _logger.info("ConnectedDevicesPage disposed");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأجهزة المتصلة'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: Theme.of(context).brightness == Brightness.dark
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: isScanning || isConnecting ? null : startScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  isScanning ? 'جارٍ الفحص...' : 'فحص الأجهزة',
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            ),
            if (isScanning)
              const Center(child: CircularProgressIndicator()),
            if (connectedDevice != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth_connected, color: Colors.green),
                  title: Text(connectedDevice!.name.isNotEmpty
                      ? connectedDevice!.name
                      : 'جهاز غير معروف'),
                  subtitle: const Text('متصل'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _disconnectDevice,
                  ),
                ),
              ),
            Expanded(
              child: scanResults.isEmpty && !isScanning
                  ? const Center(child: Text('لم يتم العثور على أجهزة'))
                  : ListView.builder(
                      itemCount: scanResults.length,
                      itemBuilder: (context, index) {
                        final result = scanResults[index];
                        final device = result.device;
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(device.name.isNotEmpty ? device.name : 'جهاز غير معروف'),
                            subtitle: Text(device.id.toString()),
                            trailing: isConnecting && device == connectedDevice
                                ? const CircularProgressIndicator()
                                : ElevatedButton(
                                    onPressed: () => _connectToDevice(device),
                                    child: const Text('اتصال'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}