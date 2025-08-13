from flask import Flask, request, jsonify, Response
from flask_cors import CORS
import os
import cv2
from ultralytics import YOLO
import threading
import time
import matplotlib.path as mpltPath
import re
from google.cloud import firestore

# Firestore 金鑰設定
cred_path = "firebase_key.json"
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = cred_path
db = firestore.Client()

app = Flask(__name__)
CORS(app)

DATA_DIR = 'polygon_data'
ALERT_FRAME_DIR = 'alert_frames'
VIDEO_DIR = r'c:\Users\a0923\forbidden_area_app_db\video_library'
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(ALERT_FRAME_DIR, exist_ok=True)

model = YOLO('yolov8n.pt')
intrusion_status = {}

import json

def point_in_any_polygon(x, y, fences):
    for fence_name, fence in fences.items():
        flattened_polygons = fence.get('polygons', [])
        
        # 重建多邊形結構用於檢測
        for poly_data in flattened_polygons:
            if isinstance(poly_data, dict) and 'points' in poly_data:
                points = poly_data['points']
                polygon_pts = []
                for point in points:
                    if isinstance(point, dict) and 'x' in point and 'y' in point:
                        polygon_pts.append((point['x'], point['y']))
                
                if len(polygon_pts) >= 3 and point_in_polygon(x, y, polygon_pts):
                    return True
    return False

def point_in_polygon(x, y, polygon_pts):
    """檢查點是否在多邊形內部"""
    path = mpltPath.Path(polygon_pts)
    return path.contains_point((x, y))

def load_fences_by_video(video_name):
    doc_ref = db.collection('fences_data').document(video_name)
    doc = doc_ref.get()
    if doc.exists:
        data = doc.to_dict()
        fences = data.get('fences', {})
        return fences
    else:
        return {}

def intrusion_detection_thread(video_name):
    video_path = os.path.join(VIDEO_DIR, video_name)
    if not os.path.exists(video_path):
        print(f"影片不存在: {video_path}")
        intrusion_status[video_name] = False
        return

    cap = cv2.VideoCapture(video_path)

    while True:
        ret, frame = cap.read()
        if not ret:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            continue

        fences = load_fences_by_video(video_name)
        if not fences:
            intrusion_status[video_name] = False
            time.sleep(1)
            continue

        results = model(frame)[0]
        alert_flag = False

        for det in results.boxes:
            cls_id = int(det.cls[0])
            if model.names[cls_id].lower() == 'person':
                x1, y1, x2, y2 = map(int, det.xyxy[0])
                center_x = (x1 + x2) // 2
                center_y = (y1 + y2) // 2
                if point_in_any_polygon(center_x, center_y, fences):
                    alert_flag = True
                    save_path = os.path.join(ALERT_FRAME_DIR, f'{video_name}_alert.jpg')
                    cv2.imwrite(save_path, frame)
                    print(f'⚠️ 警告：有人進入禁區：({center_x}, {center_y})')
                    break

        intrusion_status[video_name] = alert_flag
        time.sleep(2)

    cap.release()

@app.route('/get_fences/<video_name>', methods=['GET'])
def get_fences(video_name):
    try:
        fences_dict = load_fences_by_video(video_name)
        
        # 將字典格式轉換為陣列格式，符合前端期望
        fences_array = []
        for fence_name, fence_data in fences_dict.items():
            # 將平坦化的資料重新組織成前端期望的格式
            reconstructed_polygons = []
            flattened_polygons = fence_data.get('polygons', [])
            
            for poly_data in flattened_polygons:
                if isinstance(poly_data, dict) and 'points' in poly_data:
                    points = poly_data['points']
                    # 將點座標重新組織
                    polygon_points = []
                    for point in points:
                        if isinstance(point, dict) and 'x' in point and 'y' in point:
                            polygon_points.append({
                                'x': point['x'],
                                'y': point['y']
                            })
                    if polygon_points:
                        reconstructed_polygons.append(polygon_points)
            
            fence_item = {
                'name': fence_name,
                'time': fence_data.get('time', '00:00~23:59'),
                'polygons': reconstructed_polygons
            }
            fences_array.append(fence_item)
        
        return jsonify({'fences': fences_array}), 200
    except Exception as e:
        return jsonify({'fences': [], 'error': str(e)}), 500

from google.cloud.firestore import DELETE_FIELD

@app.route('/save_fence_polygon', methods=['POST'])
def save_fence_polygon_handler():
    try:
        data = request.get_json()
        print(f"[DEBUG] 接收到資料: {data}")

        video_name = data.get('video_name')
        fence_name = data.get('fence_name')
        time_setting = data.get('time')
        polygons = data.get('polygons')

        if not video_name or not fence_name or polygons is None:
            return jsonify({'message': '缺少必要資料'}), 400

        # 確保 polygons 是 list
        if isinstance(polygons, dict):
            polygons = [polygons]
        elif not isinstance(polygons, list):
            return jsonify({'message': '多邊形資料格式錯誤'}), 400

        # 將多邊形座標平坦化儲存
        flattened_polygons = []
        for i, poly in enumerate(polygons):
            if isinstance(poly, str):
                try:
                    poly = json.loads(poly)
                except:
                    continue
            if isinstance(poly, dict) and 'points' in poly:
                poly = poly['points']
            if not isinstance(poly, list):
                continue
            points_data = []
            for j, p in enumerate(poly):
                if isinstance(p, dict) and 'x' in p and 'y' in p:
                    try:
                        points_data.append({
                            'point_index': j,
                            'x': float(p['x']),
                            'y': float(p['y'])
                        })
                    except:
                        continue
            if points_data:
                flattened_polygons.append({
                    'polygon_index': i,
                    'points': points_data
                })

        if not flattened_polygons:
            return jsonify({'message': '多邊形資料清理後為空'}), 400

        # --- 這裡改成先讀取原本的 fences，再新增 ---
        doc_ref = db.collection('fences_data').document(video_name)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            fences = data.get('fences', {})
        else:
            fences = {}

        # 新增或更新單一 fence
        fences[fence_name] = {
            'time': time_setting,
            'polygons': flattened_polygons
        }

        # 寫回 Firestore
        doc_ref.set({'fences': fences}, merge=True)

        print(f"[DEBUG] 成功儲存 fence: {fence_name}, 平坦化後的資料: {flattened_polygons}")
        return jsonify({'message': '單筆 fence 多邊形資料儲存成功'}), 200

    except Exception as e:
        print(f"[ERROR] /save_fence_polygon: {e}")
        return jsonify({'message': '儲存失敗', 'error': str(e)}), 500



@app.route('/delete_fence_polygon', methods=['POST'])
def delete_fence_polygon():
    try:
        data = request.get_json()
        video_name = data.get('video_name')
        fence_name = data.get('fence_name')

        if not video_name or not fence_name:
            return jsonify({'message': '缺少 video_name 或 fence_name'}), 400

        doc_ref = db.collection('fences_data').document(video_name)

        # 用 update 刪除 fences.{fence_name} 欄位
        doc_ref.update({
            f'fences.{fence_name}': DELETE_FIELD
        })

        return jsonify({'message': f'Fence {fence_name} 已刪除'}), 200
    except Exception as e:
        return jsonify({'message': f'刪除失敗: {str(e)}'}), 500

@app.route('/check_alert/<video_name>', methods=['GET'])
def check_alert(video_name):
    alert = intrusion_status.get(video_name, False)
    return jsonify({'alert': alert})

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

        if byte2 is None or byte2 >= file_size:
            byte2 = file_size - 1

        length = byte2 - byte1 + 1
        if length < 0:
            length = 0

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
    return get_file_range(video_path)

if __name__ == '__main__':
    video_list = os.listdir(VIDEO_DIR)
    # for vname in video_list:
    #     threading.Thread(target=intrusion_detection_thread, args=(vname,), daemon=True).start()

    app.run(host='0.0.0.0', port=5000, debug=True)