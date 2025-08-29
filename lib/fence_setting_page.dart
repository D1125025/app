import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FenceSettingPage extends StatefulWidget {
  final String cameraName;
  final String fenceName; // 動態傳入

  const FenceSettingPage({
    Key? key,
    required this.cameraName,
    required this.fenceName,
  }) : super(key: key);

  @override
  State<FenceSettingPage> createState() => _FenceSettingPageState();
}

class _FenceSettingPageState extends State<FenceSettingPage> {
  String _selectedMode = "distance"; // 預設距離模式
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);

  // 時間模式 controller
  late TextEditingController timeMildController;
  late TextEditingController timeMediumController;
  late TextEditingController timeSevereController;

  // 距離模式 controller
  late TextEditingController distanceMildController;
  late TextEditingController distanceMediumController;
  late TextEditingController distanceSevereController;

  bool _loading = true;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // 初始化 controller
    timeMildController = TextEditingController();
    timeMediumController = TextEditingController();
    timeSevereController = TextEditingController();

    distanceMildController = TextEditingController();
    distanceMediumController = TextEditingController();
    distanceSevereController = TextEditingController();

    _loadFenceSettings();
  }

  @override
  void dispose() {
    timeMildController.dispose();
    timeMediumController.dispose();
    timeSevereController.dispose();

    distanceMildController.dispose();
    distanceMediumController.dispose();
    distanceSevereController.dispose();
    super.dispose();
  }

  Future<void> _loadFenceSettings() async {
    setState(() => _loading = true);

    try {
      final docRef = firestore.collection('fences_data').doc(widget.cameraName);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data();
        final fenceData = data?['fences']?[widget.fenceName];

        if (fenceData != null) {
          // 讀取時間範圍
          final timeStr = fenceData['time'] ?? "00:00~23:59";
          final parts = timeStr.split('~');
          if (parts.length == 2) {
            final startParts = parts[0].split(':');
            final endParts = parts[1].split(':');
            if (startParts.length == 2 && endParts.length == 2) {
              _startTime = TimeOfDay(
                  hour: int.tryParse(startParts[0]) ?? 0,
                  minute: int.tryParse(startParts[1]) ?? 0);
              _endTime = TimeOfDay(
                  hour: int.tryParse(endParts[0]) ?? 23,
                  minute: int.tryParse(endParts[1]) ?? 59);
            }
          }

          _selectedMode = fenceData['mode'] ?? 'distance';

          // 設定時間模式欄位
          timeMildController.text = (fenceData['mode'] == "time"
                  ? fenceData['mild']
                  : 5)
              .toString();
          timeMediumController.text = (fenceData['mode'] == "time"
                  ? fenceData['medium']
                  : 10)
              .toString();
          timeSevereController.text = (fenceData['mode'] == "time"
                  ? fenceData['severe']
                  : 20)
              .toString();

          // 設定距離模式欄位
          distanceMildController.text = (fenceData['mode'] == "distance"
                  ? fenceData['mild']
                  : 0.0)
              .toString();
          distanceMediumController.text = (fenceData['mode'] == "distance"
                  ? fenceData['medium']
                  : 0.0)
              .toString();
          distanceSevereController.text = (fenceData['mode'] == "distance"
                  ? fenceData['severe']
                  : 0.0)
              .toString();
        }
      } else {
        // 若無資料，給預設值
        timeMildController.text = "5";
        timeMediumController.text = "10";
        timeSevereController.text = "20";

        distanceMildController.text = "0.0";
        distanceMediumController.text = "0.0";
        distanceSevereController.text = "0.0";
      }
    } catch (e) {
      print("讀取電子圍籬設定失敗: $e");
    }

    setState(() => _loading = false);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startTime = picked;
        else _endTime = picked;
      });
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return "--:--";
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  Future<void> _saveToFirebase() async {
    try {
      final mildValue = _selectedMode == "time"
          ? int.tryParse(timeMildController.text) ?? 5
          : double.tryParse(distanceMildController.text) ?? 0.0;
      final mediumValue = _selectedMode == "time"
          ? int.tryParse(timeMediumController.text) ?? 10
          : double.tryParse(distanceMediumController.text) ?? 0.0;
      final severeValue = _selectedMode == "time"
          ? int.tryParse(timeSevereController.text) ?? 20
          : double.tryParse(distanceSevereController.text) ?? 0.0;

      final docRef = firestore.collection('fences_data').doc(widget.cameraName);

      await docRef.set({
        'fences': {
          widget.fenceName: {
            'time': "${_formatTime(_startTime)}~${_formatTime(_endTime)}",
            'mode': _selectedMode,
            'mild': mildValue,
            'medium': mediumValue,
            'severe': severeValue,
          }
        }
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("設定已儲存並上傳 Firebase")),
      );

      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("儲存失敗: $e")),
      );
    }
  }

  Widget _buildNumberField(
      String label, TextEditingController controller, String unit) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 100,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              suffixText: unit,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSettings() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("時間模式設定 (單位：分鐘)",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildNumberField("輕度警告", timeMildController, "分鐘"),
            const SizedBox(height: 8),
            _buildNumberField("中級警告", timeMediumController, "分鐘"),
            const SizedBox(height: 8),
            _buildNumberField("嚴重警告", timeSevereController, "分鐘"),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceSettings() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("距離模式設定 (單位：公尺)",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildNumberField("輕度警告 (< 公尺)", distanceMildController, "公尺"),
            const SizedBox(height: 8),
            _buildNumberField("中級警告 (< 公尺)", distanceMediumController, "公尺"),
            const SizedBox(height: 8),
            _buildNumberField("嚴重警告 (< 公尺)", distanceSevereController, "公尺"),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fenceName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "電子圍籬運作時間：",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text("開始時間: ${_formatTime(_startTime)}"),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text("結束時間: ${_formatTime(_endTime)}"),
                ),
              ],
            ),
            const Divider(height: 40),
            const Text(
              "請選擇判斷模式：",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            RadioListTile<String>(
              title: const Text("依照時間判斷"),
              value: "time",
              groupValue: _selectedMode,
              onChanged: (val) {
                setState(() {
                  _selectedMode = val!;
                });
              },
            ),
            RadioListTile<String>(
              title: const Text("依照距離判斷"),
              value: "distance",
              groupValue: _selectedMode,
              onChanged: (val) {
                setState(() {
                  _selectedMode = val!;
                });
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: _selectedMode == "time"
                    ? _buildTimeSettings()
                    : _buildDistanceSettings(),
              ),
            ),
            ElevatedButton(
              onPressed: _saveToFirebase,
              child: const Text("儲存設定"),
            ),
          ],
        ),
      ),
    );
  }
}
