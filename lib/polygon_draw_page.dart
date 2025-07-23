import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:screenshot/screenshot.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class PolygonDrawPage extends StatefulWidget {
  final String videoPath;
  final bool viewOnly;
  const PolygonDrawPage({
    required this.videoPath,
    this.viewOnly = false,
  });

  @override
  _PolygonDrawPageState createState() => _PolygonDrawPageState();
}

class _PolygonDrawPageState extends State<PolygonDrawPage> {
  late VideoPlayerController _controller;
  late ScreenshotController screenshotController;
  List<List<Offset>> polygons = [[]];
  List<bool> isPolygonLocked = [false];
  int currentPolygonIndex = 0;
  int? selectedPointIndex;
  bool isAlertDialogShowing = false;
  late String videoName;
  bool _isCapturing = false; // 防止重複截圖

  @override
  void initState() {
    super.initState();
    screenshotController = ScreenshotController();
    // 只取純檔名，排除路徑（兼容 Windows 路徑）
    videoName = widget.videoPath.split('/').last.split('\\').last;

    _controller = VideoPlayerController.asset(widget.videoPath)
      ..initialize().then((_) async {
        setState(() {
          polygons = [[]];
          isPolygonLocked = [false];
          _controller.setLooping(true);
          _controller.play();
        });

        Timer.periodic(Duration(seconds: 2), (timer) async {
          if (!mounted || !_controller.value.isInitialized) return;
          if (_isCapturing) return;  // 上一張截圖還沒完成就跳過
          _isCapturing = true;

          try {
            final imageBytes = await screenshotController.capture(pixelRatio: 1.5);
            if (imageBytes != null) {
              await sendFrameToServer(imageBytes);
            }
          } catch (e) {
            print('截圖或傳送錯誤: $e');
          }

          _isCapturing = false;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetPolygon() {
    setState(() {
      polygons = [[]];
      isPolygonLocked = [false];
      currentPolygonIndex = 0;
    });
  }

  void _addNewPolygon() {
    setState(() {
      polygons.add([]);
      isPolygonLocked.add(false);
      currentPolygonIndex = polygons.length - 1;
    });
  }

  Future<void> sendPolygonsToServer(String videoPath, List<List<Offset>> polygons) async {
    final url = Uri.parse('http://10.0.2.2:5000/save_polygon');
    final polygonJson = polygons.map((poly) => poly.map((p) => {'x': p.dx, 'y': p.dy}).toList()).toList();

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_name': videoName,
          'polygons': polygonJson,
        }),
      );
      print(response.statusCode == 200
          ? '✅ 傳送成功：${response.body}'
          : '❌ 傳送失敗：${response.statusCode}');
    } catch (e) {
      print('❌ 傳送異常: $e');
    }
  }

  Future<void> sendFrameToServer(Uint8List imageBytes) async {
    final url = Uri.parse('http://10.0.2.2:5000/detect_intrusion');
    final request = http.MultipartRequest('POST', url);
    request.fields['video_name'] = videoName;
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      imageBytes,
      filename: 'frame.jpg',
      contentType: MediaType('image', 'jpeg'),
    ));

    try {
      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      print('🔁 Server response: $respStr');

      if (response.statusCode == 200) {
        final result = jsonDecode(respStr);
        if (result['alert'] == true) {
          showWarningDialog();
        }
      } else {
        print('伺服器錯誤狀態碼: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 傳送錯誤: $e');
    }
  }

  void showWarningDialog() {
    if (isAlertDialogShowing) return;
    isAlertDialogShowing = true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ 偵測到入侵'),
        content: Text('有人進入禁區！'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              isAlertDialogShowing = false;
            },
            child: Text('關閉'),
          )
        ],
      ),
    );
  }

  void _savePolygon() async {
    setState(() {
      isPolygonLocked[currentPolygonIndex] = true;
    });
    await sendPolygonsToServer(widget.videoPath, polygons);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已儲存並上傳到伺服器')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isViewOnly = widget.viewOnly;

    return Scaffold(
      appBar: AppBar(title: Text('多區域框選')),
      body: _controller.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Screenshot(
                  controller: screenshotController,
                  child: Stack(
                    children: [
                      VideoPlayer(_controller),
                      GestureDetector(
                        onTapDown: isViewOnly || isPolygonLocked[currentPolygonIndex]
                            ? null
                            : (details) {
                                final touch = details.localPosition;
                                final index = polygons[currentPolygonIndex]
                                    .indexWhere((p) => (p - touch).distance < 20);
                                if (index == -1) {
                                  setState(() {
                                    polygons[currentPolygonIndex].add(touch);
                                  });
                                }
                              },
                        onPanStart: (details) {
                          if (isViewOnly || isPolygonLocked[currentPolygonIndex]) return;
                          final touch = details.localPosition;
                          for (int i = 0; i < polygons[currentPolygonIndex].length; i++) {
                            if ((polygons[currentPolygonIndex][i] - touch).distance < 20) {
                              selectedPointIndex = i;
                              break;
                            }
                          }
                        },
                        onPanUpdate: (details) {
                          if (isViewOnly || isPolygonLocked[currentPolygonIndex]) return;
                          if (selectedPointIndex != null) {
                            setState(() {
                              polygons[currentPolygonIndex][selectedPointIndex!] =
                                  details.localPosition;
                            });
                          }
                        },
                        onPanEnd: (details) {
                          selectedPointIndex = null;
                        },
                        child: CustomPaint(
                          painter: MultiPolygonPainter(polygons),
                          child: Container(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Center(child: CircularProgressIndicator()),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ElevatedButton(onPressed: _resetPolygon, child: Text('重新框選')),
              SizedBox(width: 10),
              ElevatedButton(onPressed: _addNewPolygon, child: Text('➕ 新增框選')),
              SizedBox(width: 10),
              ElevatedButton(onPressed: _savePolygon, child: Text('儲存多邊形')),
            ],
          ),
        ),
      ),
    );
  }
}

class MultiPolygonPainter extends CustomPainter {
  final List<List<Offset>> polygons;

  MultiPolygonPainter(this.polygons);

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final pointPaint = Paint()..color = Colors.blue;

    for (var polygon in polygons) {
      if (polygon.length >= 2) {
        final path = Path()..addPolygon(polygon, true);
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
      }

      for (var point in polygon) {
        canvas.drawCircle(point, 6, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}Z