import 'package:flutter/material.dart';
import 'package:precure/theme/gradient_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  _ProfileSettingsPageState createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emergencyNumberController =
      TextEditingController();
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('currentUserName') ?? '';
      _emailController.text = prefs.getString('currentUserEmail') ?? '';
      _emergencyNumberController.text =
          prefs.getString('currentEmergencyNumber') ?? '';
      _profileImagePath =
          prefs.getString('profileImagePath'); // تحميل مسار الصورة
    });
  }

  Future<void> _saveUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentUserName', _nameController.text.trim());
    await prefs.setString('currentUserEmail', _emailController.text.trim());
    await prefs.setString(
        'currentEmergencyNumber', _emergencyNumberController.text.trim());
    if (_profileImagePath != null) {
      await prefs.setString(
          'profileImagePath', _profileImagePath!); // حفظ مسار الصورة
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully!')),
    );

    // تحديث البيانات في الصفحة التي استدعت هذه الصفحة دون الرجوع
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'emergencyNumber': _emergencyNumberController.text.trim(),
      'profileImagePath': _profileImagePath,
    });
  }

  Future<void> _updateProfileImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _profileImagePath = pickedFile.path; // تحديث مسار الصورة
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile image updated!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;

return GradientBackground(
  child: Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const Text('Profile Settings'),
      backgroundColor: theme.appBarTheme.backgroundColor,
      foregroundColor: theme.appBarTheme.foregroundColor,
    ),
    body: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: GestureDetector(
              onTap: _updateProfileImage,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: theme.scaffoldBackgroundColor,
                child: CircleAvatar(
                  radius: 48,
                  backgroundImage: _profileImagePath != null
                      ? FileImage(File(_profileImagePath!))
                      : const AssetImage('images/Sample_User_Icon.png')
                          as ImageProvider,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: theme.cardColor,
                      child: Icon(Icons.camera_alt,
                          size: 18, color: theme.iconTheme.color),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person, color: theme.iconTheme.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              filled: true,
              fillColor: theme.cardColor,
              labelStyle:
                  TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 20),
          TextField(
            controller: _emergencyNumberController,
            decoration: InputDecoration(
              labelText: 'Emergency Number',
              prefixIcon: Icon(Icons.phone, color: theme.iconTheme.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              filled: true,
              fillColor: theme.cardColor,
              labelStyle:
                  TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _saveUserData,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Save Changes',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  ),
);

  }
}
