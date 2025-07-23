import 'dart:ui';

class PolygonDB {
  /// 不做任何事，直接回傳空 polygon
  static Future<List<List<Offset>>> getPolygons(String videoPath) async {
    return [[]];
  }

  /// 不儲存
  static Future<void> savePolygons(String videoPath, List<List<Offset>> polygons) async {}

  /// 不清空（因為沒東西）
  static Future<void> clearAll() async {}

  /// 匯出資料庫也不做
  static Future<void> exportDatabase() async {}
}
