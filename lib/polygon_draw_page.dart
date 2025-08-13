import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PolygonDrawPage extends StatefulWidget {
  final String videoPath;
  final bool viewOnly;
  final List<List<Offset>>? initialPolygons;
  final String fenceName;
  final String fenceTime;

  const PolygonDrawPage({
    required this.videoPath,
    this.viewOnly = false,
    this.initialPolygons,
    this.fenceName = '', // 改成空字串，讓 initState 自動生成
    this.fenceTime = '00:00-24:00',
    super.key,
  });

  @override
  _PolygonDrawPageState createState() => _PolygonDrawPageState();
}

class _PolygonDrawPageState extends State<PolygonDrawPage> {
  late VideoPlayerController _controller;
  List<List<Offset>> polygons = [];
  bool isPolygonLocked = false;
  int? selectedPointIndex;
  late String videoName;
  late String fenceName;

  @override
  void initState() {
    super.initState();

    videoName = widget.videoPath.split('/').last.split('\\').last;
    polygons = widget.initialPolygons ?? [];

    if (polygons.isEmpty) polygons.add([]);

    // 如果傳入 fenceName 為空，自動生成名稱
    fenceName = widget.fenceName.isNotEmpty ? widget.fenceName : _generateFenceName();

    _controller = VideoPlayerController.network(widget.videoPath)
      ..initialize().then((_) {
        setState(() {
          _controller.setLooping(true);
          _controller.play();
        });
      });
  }

  String _generateFenceName() {
    // 這裡示範簡單生成 fence 名稱，可改成從 SettingPage 取得現有 fence list
    return '電子圍籬1'; // 或從後端取得已有 fence 再決定序號
  }

  Future<void> _savePolygon() async {
    setState(() {
      isPolygonLocked = true;
    });

    final url = Uri.parse('http://10.0.2.2:5000/save_fence_polygon');
    final polygonJson = polygons
        .map((poly) => {'points': poly.map((p) => {'x': p.dx, 'y': p.dy}).toList()})
        .toList();

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_name': videoName,
          'fence_name': widget.fenceName,
          'time': widget.fenceTime,
          'polygons': polygonJson,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已儲存並上傳到伺服器')));
        }

        // ✅ 存檔成功後回傳 fence 資料給上一頁
        Navigator.pop(context, {
          'fence_name': widget.fenceName,
          'fence_time': widget.fenceTime,
          'polygons': polygons,
        });

      } else {
        print('❌ 傳送失敗：${response.statusCode}');
      }
    } catch (e) {
      print('❌ 傳送異常: $e');
    }
  }


  Future<void> _deletePolygon() async {
    final url = Uri.parse('http://10.0.2.2:5000/delete_fence/${videoName}/${widget.fenceName}');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        setState(() {
          polygons = [[]];
          isPolygonLocked = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已刪除圍籬資料')),
          );
        }
      } else {
        print('❌ 刪除失敗：${response.statusCode}');
      }
    } catch (e) {
      print('❌ 刪除異常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isViewOnly = widget.viewOnly || isPolygonLocked;

    return Scaffold(
      appBar: AppBar(
        title: Text('編輯圍籬 - ${widget.fenceName}'),
        actions: [
          if (!isViewOnly)
            IconButton(
              onPressed: _savePolygon,
              icon: const Icon(Icons.save),
              tooltip: '儲存多邊形',
            ),
          if (!isViewOnly)
            IconButton(
              onPressed: _deletePolygon,
              icon: const Icon(Icons.delete),
              tooltip: '刪除多邊形',
            ),
        ],
      ),
      body: _controller.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  children: [
                    VideoPlayer(_controller),
                    GestureDetector(
                      onTapDown: isViewOnly
                          ? null
                          : (details) {
                              final touch = details.localPosition;
                              final index = polygons[0]
                                  .indexWhere((p) => (p - touch).distance < 20);
                              if (index == -1) {
                                setState(() {
                                  polygons[0].add(touch);
                                });
                              }
                            },
                      onPanStart: (details) {
                        if (isViewOnly) return;
                        final touch = details.localPosition;
                        for (int i = 0; i < polygons[0].length; i++) {
                          if ((polygons[0][i] - touch).distance < 20) {
                            selectedPointIndex = i;
                            break;
                          }
                        }
                      },
                      onPanUpdate: (details) {
                        if (isViewOnly) return;
                        if (selectedPointIndex != null) {
                          setState(() {
                            polygons[0][selectedPointIndex!] = details.localPosition;
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
            )
          : const Center(child: CircularProgressIndicator()),
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
}
