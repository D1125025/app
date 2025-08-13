import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'polygon_draw_page.dart';
import 'setting_page.dart';
import 'warning_page.dart';


class HomePage extends StatefulWidget {
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

    cameraNames = List.generate(videoPaths.length, (i) => 'Camera ${i + 1}');

    controllers = List.generate(videoPaths.length, (index) => VideoPlayerController.network(''));

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
                      final updatedName = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingPage(
                            videoPath: controller.dataSource,
                            initialName: cameraNames[index],
                          ),
                        ),
                      );
                      if (updatedName != null && updatedName is String) {
                        setState(() {
                          cameraNames[index] = updatedName;
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
                    // 點擊異常按鈕，跳轉到警告紀錄頁
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WarningRecordPage(),
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
