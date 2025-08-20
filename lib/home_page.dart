// home_page.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'polygon_draw_page.dart';
import 'setting_page.dart';
import 'warning_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  final String userId; // ⚠️ 新增 userId
  const HomePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> videoPaths = [];
  List<VideoPlayerController> controllers = [];
  List<String> cameraNames = [];

  final String serverIP = 'http://10.0.2.2:5000';

  @override
  void initState() {
    super.initState();

    videoPaths = [
      '$serverIP/video_feed/cam1.mp4',
      '$serverIP/video_feed/cam2.mp4',
    ];

    // 預設 display_name
    cameraNames = List.generate(videoPaths.length, (i) => 'Camera ${i + 1}');
    controllers = List.generate(videoPaths.length, (index) => VideoPlayerController.network(''));

    loadUserCameraSettings();

    for (int i = 0; i < videoPaths.length; i++) {
      final path = videoPaths[i];
      final controller = VideoPlayerController.network(path);

      controller.initialize().then((_) {
        controller.setLooping(true);
        controller.play();

        setState(() {
          controllers[i] = controller;
        });
      });
    }
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // 🔹 讀取 Firestore 設定
  Future<void> loadUserCameraSettings() async {
    for (int i = 0; i < videoPaths.length; i++) {
      String camKey = videoPaths[i].split('/').last; // cam1.mp4
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('cameras')
          .doc(camKey);

      final doc = await docRef.get();

      if (!doc.exists) {
        // 第一次登入：三個偵測項目全開、時間全天
        await docRef.set({
          'display_name': 'Camera ${i + 1}',
          'detection': {
            'wall_climb': {'enabled': true, 'time': '00:00-23:59'},
            'fall': {'enabled': true, 'time': '00:00-23:59'},
            'intrusion': {'enabled': true, 'time': '00:00-23:59'},
          },
        });
        cameraNames[i] = 'Camera ${i + 1}';
      } else {
        final data = doc.data()!;
        cameraNames[i] = data['display_name'] ?? 'Camera ${i + 1}';
      }
    }
    setState(() {});
  }

  Widget buildCameraCard(int index, VideoPlayerController controller) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                )
              : Container(
                  height: 200,
                  child: const Center(child: CircularProgressIndicator()),
                ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(cameraNames[index],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PolygonDrawPage(
                            videoPath: controller.dataSource,
                            viewOnly: false,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_location_alt),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('查看')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // ⚠️ 這裡改成傳 videoPath
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingPage(
                            userId: widget.userId,
                            videoPath: controller.dataSource,
                            initialName: cameraNames[index],
                          ),
                        ),
                      );
                      if (updated != null && updated is String) {
                        setState(() {
                          cameraNames[index] = updated;
                        });
                      }
                    },
                    icon: const Icon(Icons.videocam),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('設定')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final camKey = controller.dataSource.split('/').last;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WarningRecordPage(
                            userId: widget.userId,
                            cameraName: camKey,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.warning),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('異常')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主頁面'),
      ),
      body: ListView.builder(
        itemCount: controllers.length,
        itemBuilder: (context, index) {
          return buildCameraCard(index, controllers[index]);
        },
      ),
    );
  }
}
