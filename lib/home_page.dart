import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'polygon_db.dart';
import 'polygon_draw_page.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  List<String> videoPaths = [];
  List<VideoPlayerController> controllers = [];
  Map<String, List<List<Offset>>> polygonMap = {};

  final String serverIP = 'http://10.0.2.2:5000'; // 不用 const，放外面也行

  @override
  void initState() {
    super.initState();

    // 初始化影片清單
    videoPaths = [
      '$serverIP/video_feed/cam1.mp4',
      '$serverIP/video_feed/cam2.mp4',
    ];

    PolygonDB.clearAll(); // 清除多邊形暫存資料

    for (String path in videoPaths) {
      final controller = VideoPlayerController.network(path);

      controller.initialize().then((_) async {
        controller.setLooping(true);
        controller.play();

        final points = await PolygonDB.getPolygons(path);
        setState(() {
          polygonMap[path] = points;
          controllers.add(controller);
        });
      });
    }
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      if (controller.value.isInitialized) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  Widget buildCameraCard(String title, VideoPlayerController controller) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                  child: Center(child: CircularProgressIndicator()),
                ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child:
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    icon: Icon(Icons.edit_location_alt),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('標記'),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PolygonDrawPage(
                            videoPath: controller.dataSource,
                            viewOnly: true,
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.videocam),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('查看'),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // TODO: 顯示異常紀錄
                    },
                    icon: Icon(Icons.warning),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('異常'),
                    ),
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
        title: Text('主頁面'),
      ),
      body: ListView.builder(
        itemCount: controllers.length,
        itemBuilder: (context, index) {
          final controller = controllers[index];
          final title = 'Camera ${index + 1}';
          return buildCameraCard(title, controller);
        },
      ),
    );
  }
}
