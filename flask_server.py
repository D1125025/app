# flask_server.py
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
import os
import json
import cv2
import numpy as np
from ultralytics import YOLO
import io
from PIL import Image
import matplotlib.path as mpltPath
import re
from google.cloud import firestore

cred_path = "firebase_key.json"
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = cred_path
db = firestore.Client()


app = Flask(__name__)
CORS(app)

DATA_DIR = 'polygon_data'
ALERT_FRAME_DIR = 'alert_frames'
VIDEO_DIR = r'c:\Users\a0923\forbidden_area_app_db\video_library'  # 影片資料夾路徑，請改成你的路徑
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(ALERT_FRAME_DIR, exist_ok=True)

# 載入 YOLO 模型
model = YOLO('yolov8n.pt')  # 可換成你需要的模型

# 判斷點是否在任一多邊形內
def point_in_any_polygon(x, y, polygons):
    for poly in polygons:
        polygon_pts = [(p['x'], p['y']) for p in poly]
        path = mpltPath.Path(polygon_pts)
        if path.contains_point((x, y)):
            return True
    return False

@app.route('/get_polygon/<video_name>', methods=['GET'])
def get_polygon(video_name):
    doc_ref = db.collection('fences').document(video_name)
    doc = doc_ref.get()
    if doc.exists:
        data = doc.to_dict()
        polygons_data = data.get('polygons', [])
        # 把格式轉回原本的 List[List[{'x':..., 'y':...}]]
        polygons = [poly['points'] for poly in polygons_data]
        return jsonify({'polygons': polygons}), 200
    else:
        return jsonify({'polygons': []}), 200


@app.route('/delete_polygon/<video_name>', methods=['DELETE'])
def delete_polygon(video_name):
    try:
        db.collection('fences').document(video_name).delete()
        return jsonify({'message': '已刪除'}), 200
    except Exception as e:
        return jsonify({'message': f'刪除失敗: {str(e)}'}), 500



# 儲存多邊形資料路由
@app.route('/save_polygon', methods=['POST'])
def save_polygon():
    data = request.get_json()
    print("收到資料:", data)
    if not data or 'video_name' not in data or 'polygons' not in data:
        return jsonify({'message': '缺少必要資料'}), 400

    video_name = data['video_name']
    polygons = data['polygons']

    print(f"⚠️ 嘗試寫入 Firestore: {video_name}")

    try:
        # 轉換格式，讓每個多邊形是 map 包裹點的 list
        formatted_polygons = [
            {'points': poly}  # 假設前端送的點格式已經是 {'x': ..., 'y': ...}
            for poly in polygons
        ]

        db.collection('fences').document(video_name).set({
            'video_name': video_name,
            'polygons': formatted_polygons
        })

        print(f"✅ Firestore 寫入成功: {video_name}")
    except Exception as e:
        print(f"❌ Firestore 寫入錯誤: {e}")
        return jsonify({'message': '儲存失敗', 'error': str(e)}), 500

    return jsonify({'message': '多邊形資料儲存成功'}), 200


# 偵測入侵路由
@app.route('/detect_intrusion', methods=['POST'])
def detect_intrusion():
    if 'image' not in request.files or 'video_name' not in request.form:
        return jsonify({'alert': False, 'message': '缺少資料'}), 400

    video_name = request.form['video_name']
    # 直接從 Firestore 讀多邊形
    doc_ref = db.collection('fences').document(video_name)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({'alert': False, 'message': '找不到多邊形資料'}), 404

    polygons = doc.to_dict().get('polygons', [])
    polygons_points = [poly.get('points', []) for poly in polygons]

# 後面用 polygons_points


    # 將圖片轉為 OpenCV 格式
    image_file = request.files['image']
    img_pil = Image.open(io.BytesIO(image_file.read())).convert('RGB')
    img_np = np.array(img_pil)
    img_cv = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)

    # 偵測人物
    results = model(img_cv)[0]

    for det in results.boxes:
        cls_id = int(det.cls[0])
        if model.names[cls_id] == 'person':
            x1, y1, x2, y2 = map(int, det.xyxy[0])
            center_x = (x1 + x2) // 2
            center_y = (y1 + y2) // 2
            if point_in_any_polygon(center_x, center_y, polygons_points):
                # ⚠️ 有人進入禁區
                save_path = os.path.join(ALERT_FRAME_DIR, f'{video_name}_alert.jpg')
                cv2.imwrite(save_path, img_cv)
                print(f'⚠️ 警告！有人進入禁區：({center_x}, {center_y})')
                return jsonify({'alert': True})

    return jsonify({'alert': False})

# 支援 HTTP Range 的影片串流路由
def get_file_range(file_path):
    file_size = os.path.getsize(file_path)
    range_header = request.headers.get('Range', None)
    if not range_header:
        with open(file_path, 'rb') as f:
            data = f.read()
        headers = {
            'Content-Type': 'video/mp4',
            'Content-Length': str(file_size),
            'Accept-Ranges': 'bytes'
        }
        return Response(data, 200, headers=headers)
    else:
        byte1, byte2 = 0, None
        m = re.search(r'bytes=(\d+)-(\d*)', range_header)
        if m:
            groups = m.groups()
            if groups[0]:
                byte1 = int(groups[0])
            if groups[1]:
                byte2 = int(groups[1])
        length = file_size - byte1
        if byte2 is not None:
            length = byte2 - byte1 + 1
        with open(file_path, 'rb') as f:
            f.seek(byte1)
            data = f.read(length)
        rv = Response(data, 206, mimetype='video/mp4', content_type='video/mp4', direct_passthrough=True)
        rv.headers.add('Content-Range', f'bytes {byte1}-{byte1 + length - 1}/{file_size}')
        rv.headers.add('Accept-Ranges', 'bytes')
        rv.headers.add('Content-Length', str(length))
        return rv

@app.route('/video_feed/<video_name>')
def video_feed(video_name):
    video_path = os.path.join(VIDEO_DIR, video_name)
    if not os.path.exists(video_path):
        return "File not found", 404
    print(f'Try to send file: {video_path}')
    return get_file_range(video_path)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
