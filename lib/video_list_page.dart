//video_list_page.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoListPage extends StatefulWidget {
  @override
  _VideoListPageState createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  late VideoPlayerController _controller1;
  late VideoPlayerController _controller2;

  @override
  void initState() {
    super.initState();

    _controller1 = VideoPlayerController.asset('assets/videos/cam1.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller1.setLooping(true);
        _controller1.play();
      }).catchError((e) {
        print("影片 cam1 初始化失敗: $e");
      });

    _controller2 = VideoPlayerController.asset('assets/videos/cam2.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller2.setLooping(true);
        _controller2.play();
      }).catchError((e) {
        print("影片 cam2 初始化失敗: $e");
      });
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('影片列表頁'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _controller1.value.isInitialized
                ? GestureDetector(
              onTap: () {
                // 點擊影片1後的動作，待會再做
              },
              child: AspectRatio(
                aspectRatio: _controller1.value.aspectRatio,
                child: VideoPlayer(_controller1),
              ),
            )
                : Center(child: CircularProgressIndicator()),
          ),
          Expanded(
            child: _controller2.value.isInitialized
                ? GestureDetector(
              onTap: () {
                // 點擊影片2後的動作，待會再做
              },
              child: AspectRatio(
                aspectRatio: _controller2.value.aspectRatio,
                child: VideoPlayer(_controller2),
              ),
            )
                : Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
