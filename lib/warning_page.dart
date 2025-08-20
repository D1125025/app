import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class WarningRecordPage extends StatefulWidget {
  final String cameraName; // cam1.mp4 (原始名稱)
  final String userId;     // 使用者ID

  const WarningRecordPage({
    Key? key,
    required this.cameraName,
    required this.userId,
  }) : super(key: key);

  @override
  State<WarningRecordPage> createState() => _WarningRecordPageState();
}

class _WarningRecordPageState extends State<WarningRecordPage> {
  List<AlertData> allAlerts = [];
  bool isLoading = true;
  String deviceDisplayName = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceDisplayName();
    _loadAllAlerts();
  }

  // 🔹 從 Firestore 找使用者自訂名稱
  Future<void> _loadDeviceDisplayName() async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('cameras')
          .doc(widget.cameraName);

      final doc = await docRef.get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          deviceDisplayName = data['display_name'] ?? widget.cameraName;
        });
      } else {
        setState(() {
          deviceDisplayName = widget.cameraName;
        });
      }
    } catch (e) {
      setState(() {
        deviceDisplayName = widget.cameraName;
      });
    }
  }

  // 🔹 從後端 API 取得警告資料
  Future<void> _loadAllAlerts() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('http://10.0.2.2:5000/get_alerts_by_camera/${widget.cameraName}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final alertsData = data['alerts'] as List<dynamic>? ?? [];

        List<AlertData> alerts = alertsData.map((alertJson) {
          final ts = alertJson['timestamp'] ?? '';
          DateTime parsedTime = DateTime.tryParse(ts) ?? DateTime.now();
          return AlertData(
            cameraName: widget.cameraName,
            eventId: alertJson['event_id'] ?? '未知事件',
            eventType: alertJson['event_type'] ?? '未知事件類型',
            occurTime: ts,
            date: parsedTime.toIso8601String().split('T')[0],
            timestamp: parsedTime,
          );
        }).toList();

        setState(() {
          allAlerts = alerts;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              "警告紀錄 - $deviceDisplayName",
              style: const TextStyle(fontSize: 16),
            ),
            if (deviceDisplayName != widget.cameraName)
              Text(
                "(${widget.cameraName})",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllAlerts,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : allAlerts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        "目前沒有警告紀錄",
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _buildAlertsList(),
    );
  }

  Widget _buildAlertsList() {
    // 按日期分組
    Map<String, List<AlertData>> groupedAlerts = {};
    for (var alert in allAlerts) {
      groupedAlerts.putIfAbsent(alert.date, () => []);
      groupedAlerts[alert.date]!.add(alert);
    }

    final sortedDates = groupedAlerts.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: sortedDates.map((date) {
        List<AlertData> alerts = groupedAlerts[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    date,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
            ),
            ...alerts.map((alert) => _buildAlertCard(alert)).toList(),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildAlertCard(AlertData alert) {
    IconData eventIcon;
    Color eventColor;

    switch (alert.eventType) {
      case '電子圍籬入侵':
        eventIcon = Icons.warning;
        eventColor = Colors.red;
        break;
      case '攀爬':
        eventIcon = Icons.stairs;
        eventColor = Colors.orange;
        break;
      case '火災':
        eventIcon = Icons.local_fire_department;
        eventColor = Colors.red;
        break;
      case '跌倒':
        eventIcon = Icons.person_off;
        eventColor = Colors.purple;
        break;
      default:
        eventIcon = Icons.error;
        eventColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: eventColor.withOpacity(0.2),
          child: Icon(eventIcon, color: eventColor, size: 24),
        ),
        title: Text(
          deviceDisplayName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '事件：${alert.eventType}',
              style: TextStyle(
                color: eventColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '時間：${alert.occurTime}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            alert.eventId,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class AlertData {
  final String cameraName;
  final String eventId;
  final String eventType;
  final String occurTime;
  final DateTime timestamp;
  final String date;

  AlertData({
    required this.cameraName,
    required this.eventId,
    required this.eventType,
    required this.occurTime,
    required this.timestamp,
    required this.date,
  });
}
