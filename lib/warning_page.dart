import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WarningRecordPage extends StatefulWidget {
  const WarningRecordPage({Key? key}) : super(key: key);

  @override
  State<WarningRecordPage> createState() => _WarningRecordPageState();
}

class _WarningRecordPageState extends State<WarningRecordPage> {
  /// 手動格式化日期（yyyy/MM/dd）
  String formatDate(DateTime date) {
    return "${date.year.toString().padLeft(4, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.day.toString().padLeft(2, '0')}";
  }

  /// 手動格式化時間（yyyy/MM/dd HH:mm:ss）
  String formatDateTime(DateTime date) {
    return "${date.year.toString().padLeft(4, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.day.toString().padLeft(2, '0')}  "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}:"
        "${date.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("警告紀錄"),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('alerts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("目前沒有警告紀錄"));
          }

          // 按日期分組
          Map<String, List<QueryDocumentSnapshot>> groupedData = {};
          for (var doc in snapshot.data!.docs) {
            final timestamp = (doc['timestamp'] as Timestamp).toDate();
            String dateStr = formatDate(timestamp);
            groupedData.putIfAbsent(dateStr, () => []);
            groupedData[dateStr]!.add(doc);
          }

          return ListView(
            children: groupedData.entries.map((entry) {
              String date = entry.key;
              List<QueryDocumentSnapshot> records = entry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 日期標籤
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          date,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  // 紀錄列表
                  ...records.map((doc) {
                    final timestamp =
                        (doc['timestamp'] as Timestamp).toDate();
                    String timeStr = formatDateTime(timestamp);
                    String camera = doc['camera'] ?? '未知攝影機';
                    String event = doc['event'] ?? '未知事件';

                    return Container(
                      margin:
                          const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // icon 占位
                          Container(
                            width: 30,
                            height: 30,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(width: 10),
                          // 文字
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(camera,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(timeStr,
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text("偵測到$event"),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
