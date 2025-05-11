import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:precure/theme/gradient_background.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';

class HealthReportsPage extends StatefulWidget {
  const HealthReportsPage({super.key});

  @override
  _HealthReportsPageState createState() => _HealthReportsPageState();
}

class _HealthReportsPageState extends State<HealthReportsPage> {
  int _currentTabIndex = 0;
  final ThemeMode _currentTheme = ThemeMode.light;
  Color _primaryColor = Colors.blue.shade700;

  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  BluetoothDevice? _connectedDevice;
  double currentHeartRate = 65.0;
  List<double> weeklyHeartRates = [65, 70, 68, 67, 72, 75, 74];
  List<FlSpot> monthlyHeartRates = [
    const FlSpot(0, 65),
    const FlSpot(1, 68),
    const FlSpot(2, 70),
    const FlSpot(3, 72),
    const FlSpot(4, 75),
    const FlSpot(5, 73),
    const FlSpot(6, 70),
    const FlSpot(7, 68),
    const FlSpot(8, 67),
    const FlSpot(9, 65),
    const FlSpot(10, 63),
    const FlSpot(11, 60),
    const FlSpot(12, 62),
    const FlSpot(13, 65),
    const FlSpot(14, 67),
    const FlSpot(15, 70),
    const FlSpot(16, 72),
    const FlSpot(17, 75),
    const FlSpot(18, 77),
    const FlSpot(19, 75),
    const FlSpot(20, 73),
    const FlSpot(21, 70),
    const FlSpot(22, 68),
    const FlSpot(23, 65),
    const FlSpot(24, 63),
    const FlSpot(25, 65),
    const FlSpot(26, 67),
    const FlSpot(27, 70),
    const FlSpot(28, 72),
    const FlSpot(29, 75),
  ];
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initPreferences();
    scanForDevices();
  }

  Future<void> _initPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadStoredData();
  }

  void _loadStoredData() {
    setState(() {
      // Load current heart rate
      currentHeartRate = _prefs.getDouble('currentHeartRate') ?? 65.0;

      // Load weekly data
      String? weeklyData = _prefs.getString('weeklyHeartRates');
      if (weeklyData != null) {
        weeklyHeartRates = (jsonDecode(weeklyData) as List).cast<double>();
      }

      // Load monthly data
      String? monthlyData = _prefs.getString('monthlyHeartRates');
      if (monthlyData != null) {
        List<dynamic> decoded = jsonDecode(monthlyData);
        monthlyHeartRates = decoded.asMap().entries.map((entry) {
          return FlSpot(entry.key.toDouble(), entry.value.toDouble());
        }).toList();
      }
    });
  }

  void scanForDevices() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult scanResult in results) {
        if (scanResult.device.name == "YourSmartWatch") {
          connectToDevice(scanResult.device);
          break;
        }
      }
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    await device.connect(autoConnect: false);
    setState(() {
      _connectedDevice = device;
    });
    discoverServices(device);
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.uuid.toString() == "UUID_HeartRate") {
          await characteristic.setNotifyValue(true);
          characteristic.value.listen((value) {
            double newHeartRate = value[0].toDouble();
            _updateHeartRateData(newHeartRate);
          });
        }
      }
    }
  }

  void _updateHeartRateData(double newHeartRate) async {
    setState(() {
      currentHeartRate = newHeartRate;
    });

    // Save current heart rate
    await _prefs.setDouble('currentHeartRate', newHeartRate);

    // Get current date for tracking
    DateTime now = DateTime.now();
    int dayOfWeek = now.weekday - 1; // 0 (Monday) to 6 (Sunday)
    int dayOfMonth = now.day - 1; // 0 to 29 (assuming 30-day month for simplicity)

    // Update weekly data
    weeklyHeartRates[dayOfWeek] = newHeartRate;
    await _prefs.setString('weeklyHeartRates', jsonEncode(weeklyHeartRates));

    // Update monthly data
    monthlyHeartRates[dayOfMonth] = FlSpot(dayOfMonth.toDouble(), newHeartRate);
    await _prefs.setString(
        'monthlyHeartRates',
        jsonEncode(monthlyHeartRates.map((spot) => spot.y).toList())
    );

    // Trigger UI update
    setState(() {});
  }

  Future<void> _downloadReport() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Health Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.Text('Daily Heart Rate:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('${currentHeartRate.toStringAsFixed(0)} BPM'),
            pw.SizedBox(height: 20),
            pw.Text('Weekly Heart Rate Comparison:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(weeklyHeartRates.map((e) => e.toStringAsFixed(0)).join(', ')),
            pw.SizedBox(height: 20),
            pw.Text('Monthly Heart Rate Trends:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(monthlyHeartRates.map((e) => '${e.x.toInt()}: ${e.y.toStringAsFixed(0)} BPM').join(', ')),
          ],
        ),
      ),
    );

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Health_Report.pdf');
      await file.writeAsBytes(await pdf.save());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report downloaded successfully: ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download report: $e')),
      );
    }
  }

  void _refreshData() {
    setState(() {
      currentHeartRate = 0;
      weeklyHeartRates = List.filled(7, 0.0);
      monthlyHeartRates = List.generate(30, (index) => FlSpot(index.toDouble(), 0.0));
    });

    // Save reset data
    _prefs.setDouble('currentHeartRate', 0);
    _prefs.setString('weeklyHeartRates', jsonEncode(weeklyHeartRates));
    _prefs.setString('monthlyHeartRates', jsonEncode(monthlyHeartRates.map((spot) => spot.y).toList()));

    // Simulate live data updates (kept for manual refresh)
    Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        currentHeartRate = 60 + (timer.tick % 20);
        weeklyHeartRates[timer.tick % 7] = currentHeartRate.toDouble();
        monthlyHeartRates[timer.tick % 30] = FlSpot(
          (timer.tick % 30).toDouble(),
          currentHeartRate.toDouble(),
        );
      });

      // Save simulated data
      _prefs.setDouble('currentHeartRate', currentHeartRate);
      _prefs.setString('weeklyHeartRates', jsonEncode(weeklyHeartRates));
      _prefs.setString('monthlyHeartRates', jsonEncode(monthlyHeartRates.map((spot) => spot.y).toList()));

      if (timer.tick >= 30) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Health Reports'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: Icon(Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode),
              onPressed: () {
                setState(() {
                  // تغيير الـ theme يتم من إعدادات التطبيق
                });
              },
            ),
            PopupMenuButton<Color>(
              icon: const Icon(Icons.palette),
              onSelected: (color) {
                setState(() {
                  _primaryColor = color;
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: Colors.blue.shade700, child: const Text('Blue')),
                const PopupMenuItem(value: Colors.green, child: Text('Green')),
                const PopupMenuItem(
                    value: Colors.purple, child: Text('Purple')),
                const PopupMenuItem(
                    value: Colors.orange, child: Text('Orange')),
              ],
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildTabSelector(),
              const SizedBox(height: 24),
              _buildCurrentReport(),
              const SizedBox(height: 24),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildTabButton(0, 'Daily'),
          _buildTabButton(1, 'Weekly'),
          _buildTabButton(2, 'Monthly'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    bool isSelected = _currentTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _currentTabIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? _primaryColor.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? _primaryColor
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentReport() {
    switch (_currentTabIndex) {
      case 0:
        return _buildDailyReport();
      case 1:
        return _buildWeeklyReport();
      case 2:
        return _buildMonthlyReport();
      default:
        return Container();
    }
  }

  Widget _buildDailyReport() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Text(
              'Daily Heart Rate',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${currentHeartRate.toStringAsFixed(0)} BPM',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyReport() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Weekly Heart Rate Comparison',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 400,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 120,
                  minY: 40,
                  barGroups: _buildWeeklyBarGroups(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 20,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '${value.toInt()} BPM',
                              style: const TextStyle(
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 1.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Day ${meta.formattedValue}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildWeeklyBarGroups() {
    return weeklyHeartRates.asMap().entries.map((entry) {
      final index = entry.key;
      final heartRate = entry.value;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: heartRate > 0 ? heartRate : 40, // Default to 40 if no data
            color: _primaryColor,
            width: 12,
          ),
        ],
      );
    }).toList();
  }

  Widget _buildMonthlyReport() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Monthly Heart Rate Trends',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 400,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: monthlyHeartRates,
                      isCurved: true,
                      color: _primaryColor,
                      barWidth: 2,
                      belowBarData: BarAreaData(
                        show: true,
                        color: _primaryColor.withOpacity(0.1),
                      ),
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 20,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '${value.toInt()} BPM',
                              style: const TextStyle(
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}',
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  minY: 40,
                  maxY: 120,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.download, color: Colors.black),
          label: const Text('Download Report',
              style: TextStyle(color: Colors.black)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _downloadReport,
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.sync, color: Colors.black),
          label:
              const Text('Refresh Data', style: TextStyle(color: Colors.black)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _refreshData,
        ),
      ],
    );
  }
}