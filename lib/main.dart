import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ Firebase 初始化
import 'home_page.dart'; // 等你之後再實作

void main() async {
  WidgetsFlutterBinding.ensureInitialized();          // ✅ 先確保 Flutter 綁定
  await Firebase.initializeApp();                     // ✅ 初始化 Firebase
  runApp(MyApp());                                    // ⬅️ 啟動 App
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '監視器APP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),                                // ✅ 導向首頁
    );
  }
}
