import 'package:flutter/material.dart';
import 'package:precure/Home_pages/profile_settings.dart';
import 'package:precure/Home_pages/connect_devices.dart';
import 'package:precure/Home_pages/change_password.dart';
import 'package:precure/login.dart';
import 'package:precure/theme/gradient_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:precure/api_config.dart';
import 'package:precure/theme/theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool isDarkMode = false;
  String selectedLanguage = 'English';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('darkMode') ?? false;
      selectedLanguage = prefs.getString('language') ?? 'English';
    });
  }

  Future<void> _changeLanguage(String language) async {
    const String apiUrl =
        "${ApiConfig.baseUrl}${ApiConfig.updateSettingsEndpoint}";
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedLanguage = language;
    });
    await prefs.setString('language', language);
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isLoggedIn', false); // Set login status to false
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (Route<dynamic> route) => false,
                );
              },
              child: const Text("Logout"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Settings"),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          elevation: 8,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildListTileWithImage(
              imageUrl: "https://img.icons8.com/color/48/000000/user.png",
              title: "Profile Settings",
              onTap: () async {
                final updatedData = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ProfileSettingsPage()),
                );

                if (updatedData != null) {
                  setState(() {
                    if (updatedData['name'] != null) {
                      SharedPreferences.getInstance().then((prefs) {
                        prefs.setString('currentUserName', updatedData['name']);
                      });
                    }
                    if (updatedData['emergencyNumber'] != null) {
                      SharedPreferences.getInstance().then((prefs) {
                        prefs.setString(
                            'emergencyNumber', updatedData['emergencyNumber']);
                      });
                    }
                    if (updatedData['profileImagePath'] != null) {
                      SharedPreferences.getInstance().then((prefs) {
                        prefs.setString('profileImagePath',
                            updatedData['profileImagePath']);
                      });
                    }
                  });

                  Navigator.pop(context, updatedData);
                }
              },
            ),
            const Divider(),
            _buildListTileWithImage(
              imageUrl:
                  "https://img.icons8.com/color/48/000000/smartphone-tablet.png",
              title: "Connected Devices",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ConnectedDevicesPage()),
                );
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("Dark Mode"),
              value: context.watch<ThemeProvider>().isDarkMode,
              onChanged: (value) async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool('darkMode', value);
                context.read<ThemeProvider>().setDarkMode(value);
              },
              secondary: Image.network(
                "https://img.icons8.com/color/48/000000/moon-symbol.png",
                width: 30,
                height: 30,
              ),
            ),
            const Divider(),
            ListTile(
              leading: Image.network(
                "https://img.icons8.com/color/48/000000/language.png",
                width: 30,
                height: 30,
              ),
              title: const Text("Language"),
              trailing: DropdownButton<String>(
                value: selectedLanguage,
                onChanged: (String? newValue) {
                  if (newValue != null) _changeLanguage(newValue);
                },
                items: ['English', 'Arabic'].map((String language) {
                  return DropdownMenuItem<String>(
                    value: language,
                    child: Text(language),
                  );
                }).toList(),
              ),
            ),
            const Divider(),
            _buildListTileWithImage(
              imageUrl: "https://img.icons8.com/color/48/000000/password.png",
              title: "Change Password",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ChangePasswordPage()),
                );
              },
            ),
            const Divider(),
            _buildListTileWithImage(
              imageUrl:
                  "https://img.icons8.com/color/48/000000/logout-rounded.png",
              title: "Logout",
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTileWithImage({
    required String imageUrl,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Image.network(
        imageUrl,
        width: 30,
        height: 30,
      ),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
