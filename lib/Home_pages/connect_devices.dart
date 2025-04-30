import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lottie/lottie.dart'; // مكتبة Lottie للأنيميشن
import 'package:precure/Home_pages/BiometricDataPage.dart';
import 'package:precure/theme/gradient_background.dart';

class ConnectedDevicesPage extends StatefulWidget {
  const ConnectedDevicesPage({super.key});

  @override
  _ConnectedDevicesPageState createState() => _ConnectedDevicesPageState();
}

class _ConnectedDevicesPageState extends State<ConnectedDevicesPage> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  void _startScan() {
    setState(() {
      isScanning = true;
      scanResults.clear(); // مسح النتائج السابقة قبل بدء الفحص الجديد
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        // فلترة النتائج لعرض الساعات فقط التي تحتوي على UUID خاص بالخدمة الصحية 0x180D
        scanResults = results.where((result) {
          return result.advertisementData.serviceUuids.contains("180D");
        }).toList();
      });
    }).onDone(() {
      setState(() {
        isScanning = false;
      });
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
  try {
    if (device.connectionState != BluetoothConnectionState.connected) {
      await FlutterBluePlus.stopScan(); // إيقاف الفحص بعد الاتصال
      await device.connect();
      setState(() {
        connectedDevice = device;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );
      // الانتقال إلى صفحة Biometric Data مع تمرير الجهاز المتصل
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BiometricDataPage(connectedDevice: device),
        ),
      );
    } else {
      // إذا كان الجهاز متصل بالفعل
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.name} is already connected')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to connect to ${device.name}')),
    );
  }
}


  void _disconnectDevice() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
        setState(() {
          connectedDevice = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to disconnect')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GradientBackground( // إضافة الـ GradientBackground هنا
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Connected Devices'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Start Scan',
              onPressed: _startScan, // بدء الفحص عند الضغط
            ),
          ],
        ),
        body: Column(
          children: [
            if (connectedDevice != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Connected to: \${connectedDevice!.name}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ),
            if (isScanning)
              Center(
                child: Lottie.asset(
                  'lottie/Main Scene.json', // ملف الأنيميشن
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              ),
            Expanded(
              child: scanResults.isEmpty
                  ? Center(
                      child: Text(
                        isScanning
                            ? 'Scanning for devices...'
                            : 'No devices found. Press the search icon to scan.',
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    )
                  : ListView(
                      children: scanResults.map((result) {
                        final device = result.device;
                        return ListTile(
                          tileColor: theme.cardColor,
                          title: Text(
                            device.name.isNotEmpty
                                ? device.name
                                : "Unknown Device",
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          subtitle: Text(
                            device.id.toString(),
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          trailing: connectedDevice?.id == device.id
                              ? ElevatedButton(
                                  onPressed: _disconnectDevice,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('Disconnect'),
                                )
                              : ElevatedButton(
                                  onPressed: () => _connectToDevice(device),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.primaryColor,
                                  ),
                                  child: const Text('Connect'),
                                ),
                        );
                      }).toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _startScan, // بدء الفحص عند الضغط
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Scan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: theme.scaffoldBackgroundColor, // لون خلفية الصفحة
      ),
    );
  }
}
