from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import json
import cv2
import numpy as np
from ultralytics import YOLO
import threading
import time
import matplotlib.path as mpltPath

app = Flask(__name__)
CORS(app)

DATA_DIR = 'polygon_data'
VIDEO_DIR = 'video_library'
ALERT_FRAME_DIR = 'alert_frames'
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(VIDEO_DIR, exist_ok=True)
os.makedirs(ALERT_FRAME_DIR, exist_ok=True)

# 載入 YOLO 模型
model = YOLO('yolov8n.pt')

# 判斷點是否在任一多邊形內
def point_in_any_polygon(x, y, polygons):
    for poly in polygons:
        polygon_pts = [(p['x'], p['y']) for p in poly]
        path = mpltPath.Path(polygon_pts)
        if path.contains_point((x, y)):
            return True
    return False

# 儲存多邊形資料
@app.route('/save_polygon', methods=['POST'])
def save_polygon():
    data = request.get_json()
    if not data or 'video_name' not in data or 'polygons' not in data:
        return jsonify({'message': '缺少必要資料'}), 400

    video_name = data['video_name']
    polygons = data['polygons']

    save_path = os.path.join(DATA_DIR, f'{video_name}.json')
    with open(save_path, 'w', encoding='utf-8') as f:
        json.dump(polygons, f, ensure_ascii=False, indent=2)

    print(f'✅ 已儲存多邊形資料到 {save_path}')
    return jsonify({'message': '多邊形資料儲存成功'}), 200

# 背景線程：持續讀取影片並執行偵測
def monitor_video(video_name):
    polygon_path = os.path.join(DATA_DIR, f'{video_name}.json')
    video_path = os.path.join(VIDEO_DIR, video_name)

    if not os.path.exists(video_path):
        print(f"❌ 找不到影片 {video_path}")
        return

    cap = cv2.VideoCapture(video_path)
    frame_rate = cap.get(cv2.CAP_PROP_FPS)
    frame_interval = int(frame_rate * 3)  # 每 3 秒擷取一幀

    while True:
        success, frame = cap.read()
        if not success:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)  # 影片重播
            continue

        frame_id = int(cap.get(cv2.CAP_PROP_POS_FRAMES))
        if frame_id % frame_interval != 0:
            continue

        if not os.path.exists(polygon_path):
            continue

        with open(polygon_path, 'r', encoding='utf-8') as f:
            polygons = json.load(f)

        # 偵測人物
        results = model(frame)[0]

        for det in results.boxes:
            cls_id = int(det.cls[0])
            if model.names[cls_id] == 'person':
                x1, y1, x2, y2 = map(int, det.xyxy[0])
                center_x = (x1 + x2) // 2
                center_y = (y1 + y2) // 2
                if point_in_any_polygon(center_x, center_y, polygons):
                    alert_path = os.path.join(ALERT_FRAME_DIR, f'{video_name}_alert.jpg')
                    cv2.imwrite(alert_path, frame)
                    print(f'⚠️ 警告！{video_name} 有人入侵：({center_x}, {center_y})')
                    break  # 有一人入侵就警告一次

        time.sleep(0.1)

# 啟動所有影片監控線程
def start_all_monitors():
    for file in os.listdir(VIDEO_DIR):
        if file.endswith('.mp4') or file.endswith('.avi'):
            threading.Thread(target=monitor_video, args=(file,), daemon=True).start()
            print(f'▶️ 開始監控 {file}')

if __name__ == '__main__':
    start_all_monitors()
    app.run(host='0.0.0.0', port=5000, debug=True)
