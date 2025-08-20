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
from datetime import datetime
import json

# ================= Firebase Admin 推播 =================
import firebase_admin
from firebase_admin import credentials, messaging

# Firestore & Firebase Admin 金鑰設定
cred_path = "firebase_key.json"
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = cred_path
db = firestore.Client()

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

def send_fcm_notification(token, title, body):
    """發送 FCM 推播給指定 token"""
    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=token
        )
        response = messaging.send(message)
        print(f"📲 推播成功: {response}")
    except Exception as e:
        print(f"❌ 推播失敗: {e}")

def notify_all_users(title, body):
    """取得所有使用者 FCM Token，並發送推播"""
    try:
        users_ref = db.collection('users')
        docs = users_ref.stream()
        for doc in docs:
            data = doc.to_dict()
            token = data.get('fcm_token')
            if token:
                send_fcm_notification(token, title, body)
    except Exception as e:
        print(f"❌ 取得使用者 token 失敗: {e}")

# ======================================================

app = Flask(__name__)
CORS(app)

DATA_DIR = 'polygon_data'
ALERT_FRAME_DIR = 'alert_frames'
VIDEO_DIR = r'c:\Users\a0923\forbidden_area_app_db\video_library'
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(ALERT_FRAME_DIR, exist_ok=True)

model = YOLO('yolov8n.pt')
intrusion_status = {}
detection_threads = {}  # 記錄偵測執行緒狀態

# -------------------- 功能函式 --------------------

def point_in_any_polygon(x, y, fences):
    """檢查點是否在任何圍籬內"""
    for fence_name, fence in fences.items():
        flattened_polygons = fence.get('polygons', [])
        for poly_data in flattened_polygons:
            if isinstance(poly_data, dict) and 'points' in poly_data:
                points = poly_data['points']
                polygon_pts = []
                for point in points:
                    if isinstance(point, dict) and 'x' in point and 'y' in point:
                        polygon_pts.append((point['x'], point['y']))
                if len(polygon_pts) >= 3 and point_in_polygon(x, y, polygon_pts):
                    return fence_name
    return None

def point_in_polygon(x, y, polygon_pts):
    """檢查點是否在多邊形內部"""
    try:
        path = mpltPath.Path(polygon_pts)
        return path.contains_point((x, y))
    except Exception as e:
        print(f"多邊形檢測錯誤: {e}")
        return False

def load_fences_by_video(video_name):
    """從 Firestore 載入指定影片的圍籬資料"""
    try:
        doc_ref = db.collection('fences_data').document(video_name)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            fences = data.get('fences', {})
            return fences
        else:
            return {}
    except Exception as e:
        print(f"載入圍籬資料錯誤: {e}")
        return {}

def save_alert_to_firestore(camera_name, fence_name, event_type="電子圍籬入侵"):
    """儲存警報資料到 Firestore"""
    try:
        now = datetime.now()
        event_id = f"EVT_{now.strftime('%Y%m%d_%H%M%S')}"
        date_key = now.strftime('%Y-%m-%d')

        alert_data = {
            'event_type': event_type,
            'fence_name': fence_name,
            'timestamp': now.isoformat(),
            'created_at': firestore.SERVER_TIMESTAMP
        }

        db.collection('alerts').document(camera_name).collection(date_key).document(event_id).set(alert_data)
        print(f"✅ 警報已儲存: {camera_name}/{date_key}/{event_id}")

    except Exception as e:
        print(f"❌ 儲存警報資料失敗: {e}")

# -------------------- 偵測執行緒 --------------------

def intrusion_detection_thread(video_name):
    """入侵偵測執行緒"""
    video_path = os.path.join(VIDEO_DIR, video_name)
    if not os.path.exists(video_path):
        print(f"影片不存在: {video_path}")
        intrusion_status[video_name] = False
        return

    cap = cv2.VideoCapture(video_path)
    last_alert_time = 0
    
    print(f"🎬 開始偵測影片: {video_name}")

    while True:
        ret, frame = cap.read()
        if not ret:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            continue

        fences = load_fences_by_video(video_name)
        if not fences:
            intrusion_status[video_name] = False
            time.sleep(2)
            continue

        results = model(frame)[0]
        alert_flag = False
        current_time = time.time()

        for det in results.boxes:
            cls_id = int(det.cls[0])
            if model.names[cls_id].lower() == 'person':
                x1, y1, x2, y2 = map(int, det.xyxy[0])
                center_x = (x1 + x2) // 2
                center_y = (y1 + y2) // 2
                
                invaded_fence = point_in_any_polygon(center_x, center_y, fences)
                if invaded_fence:
                    alert_flag = True
                    
                    if current_time - last_alert_time > 10:
                        save_path = os.path.join(ALERT_FRAME_DIR, f'{video_name}_alert_{int(current_time)}.jpg')
                        cv2.imwrite(save_path, frame)
                        save_alert_to_firestore(video_name, invaded_fence)

                        print(f'⚠️ 警告：有人進入禁區 {invaded_fence}：({center_x}, {center_y})')

                        # 推播給所有使用者
                        notify_all_users(
                            title="電子圍籬警報",
                            body=f"{video_name} 有人進入禁區 {invaded_fence}"
                        )

                        last_alert_time = current_time
                    break

        intrusion_status[video_name] = alert_flag
        time.sleep(1)

# -------------------- Flask 路由 --------------------

@app.route('/get_alerts_by_camera/<camera_name>', methods=['GET'])
def get_alerts_by_camera(camera_name):
    try:
        camera_ref = db.collection('alerts').document(camera_name)
        docs = camera_ref.collections()  # 每個日期的子集合
        alerts_list = []

        for date_col in docs:
            date_str = date_col.id
            events = date_col.stream()
            for event in events:
                data = event.to_dict()
                data['event_id'] = event.id
                data['date'] = date_str
                alerts_list.append(data)

        # 按日期倒序
        alerts_list.sort(key=lambda x: x.get('date', ''), reverse=True)
        return jsonify({'alerts': alerts_list}), 200

    except Exception as e:
        print(f"取得警報失敗: {e}")
        return jsonify({'alerts': [], 'error': str(e)}), 500


@app.route('/get_fences/<video_name>', methods=['GET'])
def get_fences(video_name):
    try:
        fences_dict = load_fences_by_video(video_name)
        fences_array = []
        for fence_name, fence_data in fences_dict.items():
            reconstructed_polygons = []
            flattened_polygons = fence_data.get('polygons', [])
            for poly_data in flattened_polygons:
                if isinstance(poly_data, dict) and 'points' in poly_data:
                    points = poly_data['points']
                    polygon_points = [{'x': p['x'], 'y': p['y']} for p in points if 'x' in p and 'y' in p]
                    if polygon_points:
                        reconstructed_polygons.append(polygon_points)
            fences_array.append({'name': fence_name, 'time': fence_data.get('time', '00:00~23:59'), 'polygons': reconstructed_polygons})
        return jsonify({'fences': fences_array}), 200
    except Exception as e:
        print(f"取得圍籬資料錯誤: {e}")
        return jsonify({'fences': [], 'error': str(e)}), 500

@app.route('/get_alerts', methods=['GET'])
def get_alerts():
    try:
        alerts_ref = db.collection('alerts').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(100)
        docs = alerts_ref.stream()
        alerts = []
        for doc in docs:
            alert_data = doc.to_dict()
            alert_data['id'] = doc.id
            alerts.append(alert_data)
        return jsonify({'alerts': alerts}), 200
    except Exception as e:
        print(f"取得警報記錄錯誤: {e}")
        return jsonify({'alerts': [], 'error': str(e)}), 500

from google.cloud.firestore import DELETE_FIELD

@app.route('/save_fence_polygon', methods=['POST'])
def save_fence_polygon_handler():
    try:
        data = request.get_json()
        video_name = data.get('video_name')
        fence_name = data.get('fence_name')
        time_setting = data.get('time')
        polygons = data.get('polygons')

        if not video_name or not fence_name or polygons is None:
            return jsonify({'message': '缺少必要資料'}), 400

        if isinstance(polygons, dict):
            polygons = [polygons]
        elif not isinstance(polygons, list):
            return jsonify({'message': '多邊形資料格式錯誤'}), 400

        flattened_polygons = []
        for poly in polygons:
            if isinstance(poly, str):
                try:
                    poly = json.loads(poly)
                except:
                    continue
            if isinstance(poly, dict) and 'points' in poly:
                poly = poly['points']
            if not isinstance(poly, list):
                continue
            points_data = [{'x': float(p['x']), 'y': float(p['y'])} for p in poly if 'x' in p and 'y' in p]
            if points_data:
                flattened_polygons.append({'points': points_data})

        if not flattened_polygons:
            return jsonify({'message': '多邊形資料清理後為空'}), 400

        doc_ref = db.collection('fences_data').document(video_name)
        doc_ref.set({'fences': {fence_name: {'time': time_setting, 'polygons': flattened_polygons}}}, merge=True)
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
        doc_ref.update({f'fences.{fence_name}': DELETE_FIELD})
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
        headers = {'Content-Type': 'video/mp4','Content-Length': str(file_size),'Accept-Ranges': 'bytes'}
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

# -------------------- 啟動 --------------------

if __name__ == '__main__':
    video_list = os.listdir(VIDEO_DIR)
    for vname in video_list:
        threading.Thread(target=intrusion_detection_thread, args=(vname,), daemon=True).start()
    print("🚀 Flask 伺服器已啟動，開始偵測所有影片")
    app.run(host='0.0.0.0', port=5000, debug=True)
