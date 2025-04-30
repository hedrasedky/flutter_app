import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Map<String, dynamic>> messages = [];
  TextEditingController messageController = TextEditingController();
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  String? _userProfileImagePath;
  final String botImage = "images/chat_bot.png";

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadUserProfileImage();
  }

  Future<void> _loadUserProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userProfileImagePath = prefs.getString('profileImagePath');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    messageController.dispose();
    super.dispose();
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(messages);
    await prefs.setString('chat_messages', encoded);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('chat_messages');
    if (saved != null) {
      final decoded = jsonDecode(saved);
      setState(() {
        messages = List<Map<String, dynamic>>.from(decoded);
      });
    }
  }

  Future<void> _clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_messages');
    setState(() {
      messages.clear();
    });
  }

  Future<void> _confirmClearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد أنك تريد حذف كل المحادثات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _clearMessages();
    }
  }

  Future<void> sendMessage(String text) async {
    setState(() {
      messages.add({'sender': 'user', 'message': text});
      _isLoading = true;
    });

    _saveMessages();
    _scrollToBottom();

    try {
      final model = GenerativeModel(
        model: 'gemini-pro',
        apiKey: 'AIzaSyClqwEo4rZxx2ZsCmDBpuHY8a5iX8-jWX4',
      );

      final response = await model.generateContent([Content.text(text)]);

      setState(() {
        messages.add({
          'sender': 'bot',
          'message': response.text ?? "لا يمكن الرد الآن",
        });
        _isLoading = false;
      });

      _saveMessages();
    } catch (e) {
      setState(() {
        messages.add({
          'sender': 'bot',
          'message': "حدث خطأ في الاتصال بالخادم. يرجى المحاولة لاحقاً",
        });
        _isLoading = false;
      });
      _saveMessages();
      print("Error details: $e");
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Chatbot",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.blue[800],
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[800]!, Colors.blue[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            tooltip: 'مسح المحادثة',
            onPressed: _confirmClearChat,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                itemCount: messages.length,
                itemBuilder: (ctx, index) {
                  final message = messages[index];
                  final isUser = message['sender'] == 'user';
                  final avatar = isUser
                      ? (_userProfileImagePath != null
                          ? FileImage(File(_userProfileImagePath!))
                          : const CachedNetworkImageProvider(
                              "https://i.pravatar.cc/150?img=3"))
                      : AssetImage(botImage);

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment:
                        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isUser)
                        Container(
                          margin: const EdgeInsets.only(right: 8, top: 8),
                          child: CircleAvatar(
                            backgroundImage: avatar as ImageProvider,
                            radius: 22,
                            backgroundColor: Colors.blue[100],
                            child: ClipOval(
                              child: Image(
                                image: avatar,
                                fit: BoxFit.cover,
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ),
                        ),
                      Flexible(
                        child: Animate(
                          effects: const [
                            FadeEffect(duration: Duration(milliseconds: 300)),
                            SlideEffect(
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              begin: Offset(0.2, 0),
                              end: Offset(0, 0),
                            ),
                          ],
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Colors.blue[700]
                                  : Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: Radius.circular(isUser ? 20 : 0),
                                bottomRight: Radius.circular(isUser ? 0 : 20),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              gradient: isUser
                                  ? LinearGradient(
                                      colors: [
                                        Colors.blue[700]!,
                                        Colors.blue[500]!,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                            ),
                            child: isUser
                                ? Text(
                                    message['message'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    softWrap: true,
                                  )
                                : BubbleNormal(
                                    text: message['message'],
                                    isSender: false,
                                    color: Colors.white.withOpacity(0.95),
                                    tail: true,
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                      height: 1.4,
                                    ),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width * 0.7,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      if (isUser)
                        Container(
                          margin: const EdgeInsets.only(left: 8, top: 8),
                          child: CircleAvatar(
                            backgroundImage: avatar as ImageProvider,
                            radius: 22,
                            backgroundColor: Colors.blue[100],
                            child: ClipOval(
                              child: Image(
                                image: avatar,
                                fit: BoxFit.cover,
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Animate(
                  effects: const [
                    FadeEffect(duration: Duration(milliseconds: 500)),
                  ],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ).animate().scale(
                            duration: const Duration(milliseconds: 300),
                            delay: const Duration(milliseconds: 0),
                            curve: Curves.easeInOut,
                          ),
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ).animate().scale(
                            duration: const Duration(milliseconds: 300),
                            delay: const Duration(milliseconds: 100),
                            curve: Curves.easeInOut,
                          ),
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ).animate().scale(
                            duration: const Duration(milliseconds: 300),
                            delay: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                          ),
                    ],
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: "اكتب رسالتك...",
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        hintStyle: TextStyle(color: Colors.grey[600]),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Animate(
                    effects: const [
                      ScaleEffect(
                        begin: Offset(0.8, 0.8),
                        end: Offset(1, 1),
                        duration: Duration(milliseconds: 200),
                      ),
                    ],
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue[700]!, Colors.blue[500]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: Colors.transparent,
                        radius: 24,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: () async {
                            if (messageController.text.isEmpty) return;
                            await sendMessage(messageController.text);
                            messageController.clear();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
