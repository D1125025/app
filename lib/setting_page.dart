import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'polygon_draw_page.dart';

class SettingPage extends StatefulWidget {
  final String videoPath;
  final String initialName;

  const SettingPage({
    Key? key,
    required this.videoPath,
    required this.initialName,
  }) : super(key: key);

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  late TextEditingController _deviceNameController;

  List<Map<String, dynamic>> permissions = [];
  List<Map<String, dynamic>> fences = [];

  bool _loading = true;
  bool _saving = false;

  String get videoName => p.basename(widget.videoPath);

  @override
  void initState() {
    super.initState();
    _deviceNameController = TextEditingController(text: widget.initialName);
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    await Future.wait([_loadSettings(), _loadFences()]);
    setState(() => _loading = false);
  }

  // Firestore 只存 deviceName 與 permissions
  Future<void> _loadSettings() async {
    try {
      DocumentSnapshot doc =
          await firestore.collection('monitors').doc(videoName).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _deviceNameController.text = data['deviceName'] ?? widget.initialName;

          permissions = data['permissions'] != null
              ? (data['permissions'] as List<dynamic>)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
              : [
                  {"title": "攀爬", "time": "23:00~06:00", "enabled": true},
                  {"title": "火災", "time": "00:00~23:59", "enabled": true},
                  {"title": "跌倒", "time": "05:00~18:00", "enabled": true},
                ];
        });
      } else {
        final defaultData = {
          'deviceName': widget.initialName,
          'permissions': [
            {"title": "攀爬", "time": "23:00~06:00", "enabled": true},
            {"title": "火災", "time": "00:00~23:59", "enabled": true},
            {"title": "跌倒", "time": "05:00~18:00", "enabled": true},
          ],
        };
        await firestore.collection('monitors').doc(videoName).set(defaultData);
        setState(() {
          _deviceNameController.text = widget.initialName;
          permissions = (defaultData['permissions'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      print('Firestore 讀取錯誤: $e');
    }
  }

  // 電子圍籬全部從 Flask API 讀取
  Future<void> _loadFences() async {
    try {
        final response = await http.get(
        Uri.parse('http://10.0.2.2:5000/get_fences/$videoName'),
        );

        if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loadedFences = data['fences'] != null
            ? (data['fences'] as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];

        setState(() {
            fences = loadedFences;
        });

        print("=== Fences from API ===");
        for (var f in fences) {
            print("名稱: ${f['name']}");
            print("時間: ${f['time']}");
            print("座標: ${jsonEncode(f['polygons'])}");
            print("-----------------------");
        }
        } else {
        print('取得電子圍籬失敗: ${response.statusCode}, ${response.body}');
        }
    } catch (e) {
        print('抓取電子圍籬異常: $e');
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);

    try {
      // 先寫 monitors 文件基本資料（deviceName 與 permissions）
      await firestore.collection('monitors').doc(videoName).set({
        'deviceName': _deviceNameController.text,
        'permissions': permissions,
      });

      // fences 分開上傳給後端 API
      for (var fence in fences) {
        final url = Uri.parse('http://10.0.2.2:5000/save_fence_polygon');
        try {
          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'video_name': videoName,
              'fence_name': fence['name'],
              'time': fence['time'],
              'polygons': fence['polygons'],
            }),
          );
          if (response.statusCode != 200) {
            print('多邊形資料上傳失敗 ${fence['name']}: ${response.statusCode}');
          }
        } catch (e) {
          print('多邊形資料上傳異常 ${fence['name']}: $e');
        }
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('設定已儲存')));
      Navigator.pop(context, _deviceNameController.text);
    } catch (e) {
      print('Firestore 寫入失敗: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('儲存失敗')));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> pickTime(Function(String) onTimeChanged, String currentTime) async {
    TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (start == null) return;

    TimeOfDay? end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (end == null) return;

    String newTime = "${start.format(context)}~${end.format(context)}";
    onTimeChanged(newTime);
  }

  List<List<Offset>> convertToOffset(List<dynamic> rawPolygons) {
    return rawPolygons.map((poly) {
      return (poly as List<dynamic>)
          .map((point) => Offset(
                (point['x'] as num).toDouble(),
                (point['y'] as num).toDouble(),
              ))
          .toList();
    }).toList();
  }

  List<List<Map<String, double>>> convertToMap(List<List<Offset>> polygons) {
    return polygons
        .map((poly) => poly
            .map((point) => {
                  'x': point.dx,
                  'y': point.dy,
                })
            .toList())
        .toList();
  }

  // 獲取下一個可用的圍籬編號
  int _getNextFenceNumber() {
    if (fences.isEmpty) {
      return 1;
    }
    
    Set<int> existingNumbers = <int>{};
    
    // 解析現有圍籬名稱中的數字
    for (var fence in fences) {
      String fenceName = fence['name'] ?? '';
      // 匹配 "電子圍籬" 後面的數字
      RegExp regex = RegExp(r'電子圍籬(\d+)');
      Match? match = regex.firstMatch(fenceName);
      if (match != null) {
        int number = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (number > 0) {
          existingNumbers.add(number);
        }
      }
    }
    
    // 找到最小的未使用數字
    int nextNumber = 1;
    while (existingNumbers.contains(nextNumber)) {
      nextNumber++;
    }
    
    return nextNumber;
  }

  Future<void> _addFence() async {
    print("按下新增電子圍籬按鈕");
    print("當前 fences 清單:");
    for (var f in fences) {
    print("名稱: ${f['name']}");
    }


    int nextNumber = _getNextFenceNumber();
    String fenceName = "電子圍籬$nextNumber";

    final result = await Navigator.push(
    context,
    MaterialPageRoute(
        builder: (_) => PolygonDrawPage(
        videoPath: widget.videoPath,
        viewOnly: false,
        initialPolygons: [],
        fenceName: fenceName, // <- 直接給它初始名稱
        fenceTime: "00:00~23:59", // 可選
        ),
    ),
    );


    print("PolygonDrawPage 回傳 result: $result");

    if (result != null && result is Map<String, dynamic>) {
        
        final newFence = {
            "name": result['fence_name'] ?? "電子圍籬$nextNumber",
            "time": result['fence_time'] ?? "00:00~23:59",
            "polygons": convertToMap(result['polygons']),
        };

        print("準備新增圍籬: ${newFence['name']}");
        print("座標: ${jsonEncode(newFence['polygons'])}");

        // 更新本地 fences 清單
        setState(() {
        fences.add(newFence);
        });

        print("新增後 fences 清單: $fences");

        // 同步到後端
        await _saveFenceToServer(newFence);
    } else {
        print("新增電子圍籬取消或回傳格式不正確");
    }
  }



  Future<void> _editFence(int index) async {
    final polygonsRaw = fences[index]['polygons'] as List<dynamic>? ?? [];
    final initialPolygons = convertToOffset(polygonsRaw);

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
        builder: (_) => PolygonDrawPage(
            videoPath: widget.videoPath,
            viewOnly: false,
            initialPolygons: initialPolygons,
        ),
        ),
    );

    if (result != null && result is List<List<Offset>>) {
        setState(() {
        fences[index]['polygons'] = convertToMap(result);
        });

        await _saveFenceToServer(fences[index]);
    }
  }

  Future<void> _deleteFence(int index) async {
    final fence = fences[index];
    final fenceName = fence['name'];
    final url = Uri.parse('http://10.0.2.2:5000/delete_fence_polygon');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_name': videoName,
          'fence_name': fenceName,
        }),
      );
      if (response.statusCode == 200) {
        setState(() => fences.removeAt(index));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已刪除電子圍籬 $fenceName')));
            await _loadFences();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刪除失敗: ${response.statusCode}')));
      }
    } catch (e) {
      print('刪除 fence 發生錯誤: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('刪除失敗')));
    }
  }

  Future<void> _saveFenceToServer(Map<String, dynamic> fence) async {
    final url = Uri.parse('http://10.0.2.2:5000/save_fence_polygon');
    try {
        final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
            'video_name': videoName,
            'fence_name': fence['name'],
            'time': fence['time'],
            'polygons': fence['polygons'],
        }),
        );
        if (response.statusCode == 200) {
        print('多邊形資料上傳成功: ${fence['name']}');
        await _loadFences();
        } else {
        print('多邊形資料上傳失敗 ${fence['name']}: ${response.statusCode}');
        }
    } catch (e) {
        print('多邊形資料上傳異常 ${fence['name']}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: '儲存設定',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 設備名稱
            Row(
              children: [
                const Text('設備名稱:', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 權限設定
            const Text('權限設定:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            for (int i = 0; i < permissions.length; i++)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(permissions[i]['title']),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () async {
                          await pickTime((newTime) {
                            setState(() => permissions[i]['time'] = newTime);
                          }, permissions[i]['time']);
                        },
                        child: Text(
                          "[${permissions[i]['time']}]",
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: permissions[i]['enabled'],
                    onChanged: (val) {
                      setState(() => permissions[i]['enabled'] = val);
                    },
                  )
                ],
              ),
            const SizedBox(height: 20),

            // 電子圍籬
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('電子圍籬:', style: TextStyle(fontSize: 16)),
                ElevatedButton(
                  onPressed: _addFence,
                  child: const Text('新增電子圍籬'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < fences.length; i++)
              Card(
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(child: Text(fences[i]['name'])),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () async {
                          await pickTime((newTime) {
                            setState(() => fences[i]['time'] = newTime);
                          }, fences[i]['time']);
                        },
                        child: Text(
                          "[${fences[i]['time']}]",
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editFence(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('確認刪除'),
                              content: Text('確定要刪除 ${fences[i]['name']} 嗎？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('刪除'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) _deleteFence(i);
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}