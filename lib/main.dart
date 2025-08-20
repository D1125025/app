import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("📩 背景訊息: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  User? currentUser;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }

  void _checkCurrentUser() async {
    currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      print('已登入: UID=${currentUser!.uid}');
      _requestPermission();
      _getTokenAndSave();
      _listenForegroundMessages();
      setState(() {}); // 更新畫面
    }
  }

  Future<void> signInWithEmail() async {
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      currentUser = userCredential.user;
      print('登入成功: UID=${currentUser?.uid}');

      _requestPermission();
      _getTokenAndSave();
      _listenForegroundMessages();
      setState(() {}); // 更新畫面
    } on FirebaseAuthException catch (e) {
      print('登入失敗: ${e.message}');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登入失敗: ${e.message}')));
    }
  }

  void _requestPermission() async {
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('通知權限: ${settings.authorizationStatus}');
  }

  void _getTokenAndSave() async {
    if (currentUser == null) return;
    String? token = await _messaging.getToken();
    print('🔑 FCM Token: $token');

    if (token != null) {
      // 預設 camKey 為 cam1.mp4，可依需求改
      final defaultCameras = {
        'cam1.mp4': {
          'electronic_fence': {
            'enabled': true,
            'time': '00:00~23:59',
            'title': '電子圍籬入侵',
          },
          'fall_detection': {
            'enabled': true,
            'time': '00:00~23:59',
            'title': '跌倒',
          },
          'climb_detection': {
            'enabled': true,
            'time': '00:00~23:59',
            'title': '攀爬',
          },
        },
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .set({
        'fcm_token': token,
        'updated_at': FieldValue.serverTimestamp(),
        'cameras': defaultCameras,
      }, SetOptions(merge: true));
    }
  }

  void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print(
          '📩 前景訊息: ${message.notification?.title} - ${message.notification?.body}');
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text(
      //         "${message.notification?.title ?? ''}\n${message.notification?.body ?? ''}"),
      //   ),
      // );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '監視器APP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: currentUser == null
          ? Scaffold(
              appBar: AppBar(title: Text("登入")),
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(labelText: '密碼'),
                      obscureText: true,
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: signInWithEmail,
                      child: Text("登入"),
                    ),
                  ],
                ),
              ),
            )
          : HomePage(
              userId: currentUser!.uid,
            ),
    );
  }
}
