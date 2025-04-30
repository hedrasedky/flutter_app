import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:precure/Home_pages/BiometricDataPage.dart';
import 'package:precure/Home_pages/EmergencyAlertsPage.dart';
import 'package:precure/Home_pages/HealthReportsPage.dart';
import 'package:precure/Home_pages/Settings_Page.dart';
import 'package:precure/Home_pages/chat_bot.dart';
import 'package:precure/Home_pages/profile_settings.dart';
import 'package:precure/edit.dart';
import 'package:precure/theme/gradient_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({super.key, required this.userName});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String? _userName;
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('currentUserName') ?? 'User';
      _profileImagePath =
          prefs.getString('profileImagePath'); // جلب مسار الصورة
    });
  }

  final List<Widget> _pages = [
    const Placeholder(),
    const EditProfilePage(),
    const SettingsPage(),
    const ChatScreen(),
  ];

void _onItemTapped(int index) async {
  if (index == 1) {
    // Profile
    setState(() {
      _selectedIndex = index;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileSettingsPage()),
    );

    setState(() {
      _selectedIndex = 0;
    });
  } else if (index == 2) {
    // Settings
    setState(() {
      _selectedIndex = index;
    });

    final updatedData = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );

    if (updatedData != null) {
      setState(() {
        if (updatedData['name'] != null) {
          _userName = updatedData['name'];
        }
        if (updatedData['profileImagePath'] != null) {
          _profileImagePath = updatedData['profileImagePath'];
        }
      });
    }

    setState(() {
      _selectedIndex = 0;
    });
  } else if (index == 3) {
    // Chatbot
    setState(() {
      _selectedIndex = index;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChatScreen()),
    );

    setState(() {
      _selectedIndex = 0;
    });
  } else {
    setState(() {
      _selectedIndex = index;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
       appBar: AppBar(
  backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
  elevation: 0,
  title: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: _profileImagePath != null
                ? FileImage(File(_profileImagePath!))
                : const AssetImage('images/Sample_User_Icon.png')
                    as ImageProvider,
          ),
          const SizedBox(width: 10),
          Text(
            _userName != null ? 'Hello, $_userName' : 'Loading...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).appBarTheme.foregroundColor,
            ),
          ),
        ],
      ),
      IconButton(
        icon: Icon(Icons.notifications_none,
            color: Theme.of(context).appBarTheme.foregroundColor),
        onPressed: () {
          // التنقل إلى صفحة EmergencyAlertsPage
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EmergencyAlertsPage()),
          );
        },
      ),
    ],
  ),
),
        body: Container(
          color: Colors.transparent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
            child: Column(
              children: _features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _buildFeatureCard(
                    context,
                    feature['imagePath'] as String,
                    feature['title'] as String,
                    feature['page'] as Widget,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).bottomNavigationBarTheme.backgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            items: [
              BottomNavigationBarItem(
                icon: Image.asset(
                  'images/home_icon.png', // Replace with your colorful home icon
                  width: 100,
                  height: 30,
                ),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Image.asset(
                  'images/profile.png', // Replace with your colorful profile icon
                  width: 100,
                  height: 30,
                ),
                label: 'Profile',
              ),
              BottomNavigationBarItem(
                icon: Image.asset(
                  'images/setting_icon.png', // Replace with your colorful settings icon
                  width: 100,
                  height: 30,
                ),
                label: 'Settings',
              ),
              BottomNavigationBarItem(
                icon: Image.asset(
                  'images/chatbot.png', // Replace with your colorful chatbot icon
                  width: 100,
                  height: 30,
                ),
                label: 'Chatbot',
                tooltip: 'Chatbot', // Optional tooltip for better accessibility
              ),
            ],
            currentIndex: _selectedIndex,
            selectedItemColor: Theme.of(context).primaryColorLight,
            unselectedItemColor: Theme.of(context).unselectedWidgetColor,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            showUnselectedLabels: true, // Show unselected labels for clarity
            selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15 // Make selected labels bold
                ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold, // Make unselected labels bold
            ),
          ),
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> _features = [
    {
      'imagePath': 'images/biometric2.png',
      'title': 'Biometric Data',
      'page': const BiometricDataPage(
        connectedDevice: null,
      ),
    },
    {
      'imagePath': 'images/reports.png',
      'title': 'Health Reports',
      'page': const HealthReportsPage()
    },
    {
      'imagePath': 'images/emergancy2.png',
      'title': 'Emergency Alerts',
      'page': const EmergencyAlertsPage()
    },
  ];

  Widget _buildFeatureCard(
      BuildContext context, String imagePath, String title, Widget page) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => page),
        );
      },
      child: Card(
        color: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 13,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: DecorationImage(
              image: AssetImage(imagePath),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: GoogleFonts.bitter(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
