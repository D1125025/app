import 'package:flutter/material.dart';
import 'polygon_draw_page.dart'; // 請確保這個檔案名正確或改成你的路徑

class SettingPage extends StatefulWidget {
  final String videoPath;
  final String initialName; // 接收初始設備名稱
  const SettingPage({
    Key? key,
    required this.videoPath,
    required this.initialName,
  }) : super(key: key);

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late TextEditingController _deviceNameController;

  // 權限設定資料
  List<Map<String, dynamic>> permissions = [
    {"title": "攀牆", "time": "23:00~06:00", "enabled": true},
    {"title": "火災", "time": "00:00~23:59", "enabled": false},
    {"title": "跌倒", "time": "05:00~18:00", "enabled": true},
  ];

  // 電子圍籬資料
  List<Map<String, String>> fences = [
    {"name": "電子圍籬1", "time": "23:00~06:00"},
  ];

  @override
  void initState() {
    super.initState();
    _deviceNameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  // 彈出時間選擇器
  Future<void> pickTime(Function(String) onTimeChanged, String currentTime) async {
    TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 0, minute: 0),
    );
    if (start == null) return;

    TimeOfDay? end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (end == null) return;

    String newTime = "${start.format(context)}~${end.format(context)}";
    onTimeChanged(newTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("設定"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _deviceNameController.text), // 回傳設備名稱
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // 設備名稱
            Row(
              children: [
                const Text("設備名稱", style: TextStyle(fontSize: 16)),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 權限設定
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("權限設定", style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    for (var item in permissions)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(item['title']),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  pickTime((newTime) {
                                    setState(() {
                                      item['time'] = newTime;
                                    });
                                  }, item['time']);
                                },
                                child: Text(
                                  "[${item['time']}]",
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: item['enabled'],
                            onChanged: (val) {
                              setState(() {
                                item['enabled'] = val;
                              });
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 電子圍籬
            for (int i = 0; i < fences.length; i++)
              Card(
                child: ListTile(
                  title: Row(
                    children: [
                      Text(fences[i]['name']!),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          pickTime((newTime) {
                            setState(() {
                              fences[i]['time'] = newTime;
                            });
                          }, fences[i]['time']!);
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
                  trailing: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        fences.removeAt(i);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                    ),
                    child: const Text("刪除"),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // 新增電子圍籬
            ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PolygonDrawPage(
                      videoPath: widget.videoPath,
                      viewOnly: false,
                    ),
                  ),
                );

                if (result != null && result is bool && result == true) {
                  setState(() {
                    int newIndex = fences.length + 1;
                    fences.add({
                      "name": "電子圍籬$newIndex",
                      "time": "00:00~23:59",
                    });
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.black,
              ),
              child: const Text("新增電子圍籬"),
            ),
          ],
        ),
      ),
    );
  }
}

// 可視需要保留或刪除此空白頁面
class SelectFencePage extends StatelessWidget {
  const SelectFencePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("框選電子圍籬")),
      body: const Center(child: Text("這裡是框選頁面")),
    );
  }
}
