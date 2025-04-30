import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'bpm_stream.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة الإشعارات المحلية
  await _initializeNotifications();
  runApp(const MyApp());
}

// تهيئة flutter_local_notifications
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Monitoring System',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const EmergencyAlertsPage(),
    );
  }
}

class AppThemes {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.transparent,
    primaryColor: Colors.blue.shade700,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue.shade700,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Colors.blue.shade700,
      foregroundColor: Colors.white,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Colors.black),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
    cardTheme: CardTheme(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    primaryColor: Colors.blueGrey,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1F1F1F),
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.blueGrey,
      foregroundColor: Colors.white,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Colors.white),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
    cardTheme: CardTheme(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

class EmergencyAlertsPage extends StatefulWidget {
  const EmergencyAlertsPage({super.key});

  @override
  State<EmergencyAlertsPage> createState() => _EmergencyAlertsPageState();
}

class _EmergencyAlertsPageState extends State<EmergencyAlertsPage> {
  final List<AlertItem> _alerts = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  Position? _currentPosition;
  bool _isSelecting = false;
  final List<int> _selectedIndices = [];
  static const String _alertsKey = 'saved_alerts';
  String? _statusFilter; // تصفية حسب status
  String? _movementFilter; // تصفية حسب movementStatus

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // تهيئة البيانات الأولية
  Future<void> _loadInitialData() async {
    await _loadSavedAlerts();
    await _initializeServices();
  }

  // تحميل التنبيهات المحفوظة
  Future<void> _loadSavedAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAlerts = prefs.getString(_alertsKey);
    if (savedAlerts != null) {
      final List<dynamic> decoded = json.decode(savedAlerts);
      setState(() {
        _alerts.addAll(decoded.map((e) => AlertItem.fromJson(e)).toList());
      });
    }
  }

  // تهيئة الخدمات (الموقع واستقبال البيانات)
  Future<void> _initializeServices() async {
    await _requestLocationPermission();
    await _getCurrentLocation();

    // الاستماع إلى بيانات BPMWithMovement
    bpmStreamController.stream.listen((BPMWithMovement data) async {
      final now = DateTime.now();
      if (data.bpm < 60) {
        await _addCriticalAlert(data.bpm, now, data.movementStatus);
        await _showNotification(
          'Low Heart Rate Alert',
          'Heart rate ${data.bpm} BPM detected while ${data.movementStatus}.',
        );
        await _playAlertSound();
      } else if (data.bpm > 100 && data.movementStatus != 'Running') {
        await _addCriticalAlert(data.bpm, now, data.movementStatus);
        await _showNotification(
          'High Heart Rate Alert',
          'Heart rate ${data.bpm} BPM detected while ${data.movementStatus}.',
        );
        await _playAlertSound();
      } else {
        await _addNormalAlert(data.bpm, now, data.movementStatus);
      }
    });
  }

  // عرض إشعار محلي
  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'heart_rate_channel',
      'Heart Rate Alerts',
      channelDescription: 'Notifications for critical heart rate alerts',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: 'alert',
    );
  }

  // حفظ التنبيهات في SharedPreferences
  Future<void> _saveAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _alertsKey,
      json.encode(_alerts.map((e) => e.toJson()).toList()),
    );
  }

  // تبديل وضع الاختيار
  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
      _isSelecting = _selectedIndices.isNotEmpty;
    });
  }

  // بدء وضع الاختيار
  void _startSelectionMode() {
    setState(() {
      _isSelecting = true;
    });
  }

  // إلغاء وضع الاختيار
  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedIndices.clear();
    });
  }

  // حذف التنبيهات المختارة
  Future<void> _deleteSelected() async {
    if (_selectedIndices.isEmpty) return;

    setState(() {
      _selectedIndices.sort((a, b) => b.compareTo(a));
      for (var index in _selectedIndices) {
        if (index >= 0 && index < _alerts.length) {
          _alerts.removeAt(index);
        }
      }
      _selectedIndices.clear();
      _isSelecting = false;
    });
    await _saveAlerts();
  }

  // بناء شريط الاختيار
  Widget _buildSelectionBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isSelecting ? 60 : 0,
      color: Colors.blue.shade700,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _cancelSelection,
          ),
          Text(
            '${_selectedIndices.length} selected',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _deleteSelected,
          ),
        ],
      ),
    );
  }

  // مسح جميع التنبيهات
  Future<void> _clearAllAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alertsKey);
    setState(() {
      _alerts.clear();
    });
  }

  // تأكيد مسح جميع التنبيهات
  Future<void> _showClearConfirmation() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Alerts'),
        content: const Text('Are you sure you want to delete all alerts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _clearAllAlerts();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  // طلب إذن الموقع
  Future<void> _requestLocationPermission() async {
    final status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  // الحصول على الموقع الحالي
  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  // إضافة تنبيه حرج
  Future<void> _addCriticalAlert(int heartRate, DateTime time, String movementStatus) async {
    final alert = AlertItem(
      heartRate: heartRate,
      time: time,
      status: heartRate < 60 ? 'low' : 'high',
      location: _currentPosition,
      isRead: false,
      movementStatus: movementStatus,
    );
    setState(() => _alerts.insert(0, alert));
    await _saveAlerts();
    await _showCriticalAlertNotification(alert);
  }

  // إضافة تنبيه عادي
  Future<void> _addNormalAlert(int heartRate, DateTime time, String movementStatus) async {
    if (_alerts.isEmpty || _alerts.length % 5 == 0) {
      final alert = AlertItem(
        heartRate: heartRate,
        time: time,
        status: 'normal',
        location: _currentPosition,
        isRead: false,
        movementStatus: movementStatus,
      );
      setState(() => _alerts.insert(0, alert));
      await _saveAlerts();
    }
  }

  // تشغيل صوت التنبيه
  Future<void> _playAlertSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alert.wav'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  // عرض إشعار التنبيه الحرج
  Future<void> _showCriticalAlertNotification(AlertItem alert) async {
    debugPrint('Critical Alert: ${alert.status} - ${alert.heartRate} bpm while ${alert.movementStatus}');
  }

  // طلب مساعدة طارئة
  Future<void> _triggerEmergencyHelp() async {
    final prefs = await SharedPreferences.getInstance();
    final emergencyNumber = prefs.getString('emergencyNumber') ?? '123';

    final alert = AlertItem(
      heartRate: 0,
      time: DateTime.now(),
      status: 'emergency',
      location: _currentPosition,
      isRead: false,
      movementStatus: 'Unknown',
    );

    setState(() => _alerts.insert(0, alert));
    await _saveAlerts();
    await _audioPlayer.play(AssetSource('sounds/emergency.wav'));
    await _showNotification(
      'Emergency Help Requested',
      'Emergency call initiated at ${DateFormat('hh:mm a').format(DateTime.now())}.',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Emergency Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Will call: $emergencyNumber'),
            if (_currentPosition != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Location: ${_currentPosition!.latitude.toStringAsFixed(4)}, '
                  '${_currentPosition!.longitude.toStringAsFixed(4)}',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Call'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _makePhoneCall(emergencyNumber);
    }
  }

  // إجراء مكالمة هاتفية
  Future<void> _makePhoneCall(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not call the number')),
      );
    }
  }

  // الاتصال بالإسعاف
  Future<void> _callAmbulance() async {
    await _makePhoneCall('123');
    await _sendEmergencyNotification();
  }

  // وضع علامة "مقروء" على جميع التنبيهات
  Future<void> _markAllAsRead() async {
    setState(() {
      for (var alert in _alerts) {
        alert.isRead = true;
      }
    });
    await _saveAlerts();
  }

  // الاتصال برقم الطوارئ
  Future<void> _callEmergencyNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final emergencyNumber = prefs.getString('emergencyNumber') ?? '123';
    await _makePhoneCall(emergencyNumber);
  }

  // إرسال إشعار طوارئ
  Future<void> _sendEmergencyNotification() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency notification sent!')),
    );
    await _showNotification(
      'Emergency Alert',
      'Ambulance called at ${DateFormat('hh:mm a').format(DateTime.now())}.',
    );
    debugPrint('Sending emergency notification...');
  }

  // إنشاء بيانات وهمية للرسم البياني
  List<FlSpot> _generateDummyChartData(int heartRate) {
    final List<FlSpot> spots = [];
    final random = Random();
    for (int i = 0; i < 10; i++) {
      final variation = random.nextInt(10) - 5; // تغيير عشوائي بين -5 و+5
      spots.add(FlSpot(i.toDouble(), (heartRate + variation).toDouble()));
    }
    return spots;
  }

  // عرض تفاصيل التنبيه
  Future<void> _showAlertDetails(AlertItem alert) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getAlertTitle(alert)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Time: ${DateFormat('hh:mm a - yyyy/MM/dd').format(alert.time)}'),
              if (alert.movementStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Movement: ${alert.movementStatus}'),
                ),
              if (alert.location != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Location: ${alert.location!.latitude.toStringAsFixed(4)}, '
                    '${alert.location!.longitude.toStringAsFixed(4)}',
                  ),
                ),
              if (alert.status != 'emergency') ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(),
                ),
                const Text('Heart rate chart:'),
                SizedBox(
                  height: 150,
                  child: LineChart(
                    LineChartData(
                      minY: alert.heartRate - 20,
                      maxY: alert.heartRate + 20,
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true),
                        ),
                      ),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _generateDummyChartData(alert.heartRate),
                          isCurved: true,
                          color: Colors.blue,
                          barWidth: 3,
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.blue.withOpacity(0.3),
                          ),
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // بناء واجهة المستخدم
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // تصفية التنبيهات بناءً على status أو movementStatus
    final filteredAlerts = _alerts.where((alert) {
      bool matchesStatus = _statusFilter == null || alert.status == _statusFilter;
      bool matchesMovement =
          _movementFilter == null || alert.movementStatus == _movementFilter;
      return matchesStatus && matchesMovement;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSelecting
            ? const Text('Selection Mode')
            : const Text('Heart Rate Alerts'),
        actions: _isSelecting
            ? []
            : [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _showClearConfirmation,
                  tooltip: 'Clear all alerts',
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: _markAllAsRead,
                  tooltip: 'Mark all as read',
                ),
              ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.brightness == Brightness.light
                  ? const Color(0xFFf5f7fa)
                  : const Color(0xFF1E1E1E),
              theme.brightness == Brightness.light
                  ? const Color(0xFFc3cfe2)
                  : const Color(0xFF2D2D2D),
            ],
          ),
        ),
        child: Column(
          children: [
            _buildSelectionBar(),
            // أزرار التصفية
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<String>(
                    hint: const Text('Filter by Status'),
                    value: _statusFilter,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Status'),
                      ),
                      ...['high', 'low', 'normal', 'emergency']
                          .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(status.capitalize()),
                              ))
                          .toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _statusFilter = value;
                      });
                    },
                  ),
                  DropdownButton<String>(
                    hint: const Text('Filter by Movement'),
                    value: _movementFilter,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Movements'),
                      ),
                      ...['Running', 'Walking', 'Stationary']
                          .map((movement) => DropdownMenuItem(
                                value: movement,
                                child: Text(movement),
                              ))
                          .toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _movementFilter = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  filteredAlerts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.monitor_heart_outlined,
                                  size: 60, color: theme.disabledColor),
                              const SizedBox(height: 16),
                              Text(
                                'No alerts match the selected filters',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: theme.disabledColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredAlerts.length,
                          itemBuilder: (context, index) {
                            final alert = filteredAlerts[index];
                            final originalIndex = _alerts.indexOf(alert);
                            return GestureDetector(
                              onTap: () {
                                if (_isSelecting) {
                                  _toggleSelection(originalIndex);
                                } else {
                                  setState(() => alert.isRead = true);
                                  _saveAlerts();
                                  _showAlertDetails(alert);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelecting) {
                                  _startSelectionMode();
                                }
                                _toggleSelection(originalIndex);
                              },
                              child: _buildAlertCard(alert, originalIndex, theme),
                            );
                          },
                        ),
                  if (!_isSelecting) ...[
                    Positioned(
                      left: 20,
                      bottom: 20,
                      child: FloatingActionButton(
                        heroTag: 'emergency_call',
                        onPressed: _callEmergencyNumber,
                        backgroundColor: Colors.green,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone, color: Colors.white, size: 30),
                            Text(
                              'Emergency',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: FloatingActionButton(
                        heroTag: 'ambulance',
                        onPressed: _callAmbulance,
                        backgroundColor: Colors.red,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.local_hospital, color: Colors.white, size: 28),
                            Text(
                              'SOS',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بناء بطاقة التنبيه
  Widget _buildAlertCard(AlertItem alert, int index, ThemeData theme) {
    final color = alert.status == 'high'
        ? Colors.red
        : alert.status == 'low'
            ? Colors.orange
            : alert.status == 'emergency'
                ? Colors.purple
                : Colors.green;

    return Card(
      color: _selectedIndices.contains(index)
          ? theme.primaryColor.withOpacity(0.2)
          : theme.cardTheme.color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_isSelecting)
                  Checkbox(
                    value: _selectedIndices.contains(index),
                    onChanged: (value) => _toggleSelection(index),
                  ),
                Icon(
                  alert.status == 'emergency' ? Icons.emergency : Icons.monitor_heart,
                  color: color,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getAlertTitle(alert),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (!alert.isRead && !_isSelecting)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Time: ${DateFormat('hh:mm a - yyyy/MM/dd').format(alert.time)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
            ),
            if (alert.movementStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Movement: ${alert.movementStatus}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.disabledColor,
                    fontSize: 12,
                  ),
                ),
              ),
            if (alert.location != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Location: ${alert.location!.latitude.toStringAsFixed(4)}, '
                  '${alert.location!.longitude.toStringAsFixed(4)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.disabledColor,
                    fontSize: 12,
                  ),
                ),
              ),
            if (alert.status != 'emergency') ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: alert.heartRate / 200,
                backgroundColor: theme.dividerColor,
                color: color,
                minHeight: 6,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${alert.heartRate} bpm',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(
                    'Normal range: 60-100',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // إنشاء عنوان التنبيه
  String _getAlertTitle(AlertItem alert) {
    switch (alert.status) {
      case 'high':
        return 'Warning: High Heart Rate (${alert.heartRate} BPM) while ${alert.movementStatus ?? "Unknown"}';
      case 'low':
        return 'Warning: Low Heart Rate (${alert.heartRate} BPM) while ${alert.movementStatus ?? "Unknown"}';
      case 'emergency':
        return 'Emergency Help Requested';
      default:
        return 'Normal Heart Rate (${alert.heartRate} BPM) while ${alert.movementStatus ?? "Unknown"}';
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

class AlertItem {
  final int heartRate;
  final DateTime time;
  final String status;
  final Position? location;
  bool isRead;
  final String? movementStatus;

  AlertItem({
    required this.heartRate,
    required this.time,
    required this.status,
    this.location,
    this.isRead = false,
    this.movementStatus,
  });

  Map<String, dynamic> toJson() => {
        'heartRate': heartRate,
        'time': time.toIso8601String(),
        'status': status,
        'location': location != null
            ? {
                'latitude': location!.latitude,
                'longitude': location!.longitude,
              }
            : null,
        'isRead': isRead,
        'movementStatus': movementStatus,
      };

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      heartRate: json['heartRate'],
      time: DateTime.parse(json['time']),
      status: json['status'],
      location: json['location'] != null
          ? Position(
              latitude: json['location']['latitude'],
              longitude: json['location']['longitude'],
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            )
          : null,
      isRead: json['isRead'],
      movementStatus: json['movementStatus'],
    );
  }
}

// امتداد لتسهيل تحويل النصوص إلى الحرف الأول كبير
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
