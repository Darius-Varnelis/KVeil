# Compare incomming video with known faces
# Running in a local python instance to get around PATH issues

# Import time so we can start timing asap
import time

# Start timing
timings = {
	"st": time.time()
}

# Import required modules
import sys
import os
os.environ.setdefault("OPENCV_OPENCL_DEVICE", "disabled")
import json
import configparser
import dlib
import cv2
try:
	cv2.ocl.setUseOpenCL(False)
except Exception:
	pass
import datetime
import snapshot
import threading
import numpy as np
import _thread as thread
from recorders.video_capture import VideoCapture


def init_detector(lock):
	"""Start face detector, encoder and predictor in a new thread"""
	global face_detector, pose_predictor, face_encoder

	# Test if at lest 1 of the data files is there and abort if it's not
	if not os.path.isfile(PATH + "/dlib-data/shape_predictor_5_face_landmarks.dat"):
		print("Data files have not been downloaded, please run the following commands:")
		print("\n\tcd " + PATH + "/dlib-data")
		print("\tsudo ./install.sh\n")
		lock.release()
		sys.exit(1)

	# Use the CNN detector if enabled
	if use_cnn:
		face_detector = dlib.cnn_face_detection_model_v1(PATH + "/dlib-data/mmod_human_face_detector.dat")
	else:
		face_detector = dlib.get_frontal_face_detector()

	# Start the others regardless
	pose_predictor = dlib.shape_predictor(PATH + "/dlib-data/shape_predictor_5_face_landmarks.dat")
	face_encoder = dlib.face_recognition_model_v1(PATH + "/dlib-data/dlib_face_recognition_resnet_model_v1.dat")

	# Note the time it took to initialize detectors
	timings["ll"] = time.time() - timings["ll"]
	lock.release()


def make_snapshot(type):
	"""Generate snapshot after detection"""
	snapshot.generate(snapframes, [
		type + " LOGIN",
		"Date: " + datetime.datetime.now(datetime.UTC).strftime("%Y/%m/%d %H:%M:%S UTC"),
		"Scan time: " + str(round(time.time() - timings["fr"], 2)) + "s",
		"Frames: " + str(frames) + " (" + str(round(frames / (time.time() - timings["fr"]), 2)) + "FPS)",
		"Hostname: " + os.uname().nodename,
		"Best certainty value: " + str(round(lowest_certainty * 10, 1))
	])


# Make sure we were given an username to tast against
if len(sys.argv) < 2:
	sys.exit(12)

# Get the absolute path to the current directory
PATH = os.path.abspath(__file__ + "/..")

# The username of the user being authenticated
user = sys.argv[1]
# The model file contents
models = []
# Encoded face models
encodings = []
# Amount of ignored 100% black frames
black_tries = 0
# Amount of ingnored dark frames
dark_tries = 0
# Total amount of frames captured
frames = 0
# Captured frames for snapshot capture
snapframes = []
# Tracks the lowest certainty value in the loop
lowest_certainty = 10
# Face recognition/detection instances
face_detector = None
pose_predictor = None
face_encoder = None

# Try to load the face model from the models folder
try:
	models = json.load(open(PATH + "/models/" + user + ".dat"))

	for model in models:
		encodings += model["data"]
except FileNotFoundError:
	sys.exit(10)

# Check if the file contains a model
if len(models) < 1:
	sys.exit(10)

# Read config from disk
config = configparser.ConfigParser()
config.read(PATH + "/config.ini")

# Get all config values needed
use_cnn = config.getboolean("core", "use_cnn", fallback=False)
timeout = config.getint("video", "timeout", fallback=5)
dark_threshold = config.getfloat("video", "dark_threshold", fallback=50.0)
video_certainty = config.getfloat("video", "certainty", fallback=3.5) / 10
end_report = config.getboolean("debug", "end_report", fallback=False)
capture_failed = config.getboolean("snapshots", "capture_failed", fallback=False)
capture_successful = config.getboolean("snapshots", "capture_successful", fallback=False)

# Save the time needed to start the script
timings["in"] = time.time() - timings["st"]

# Import face recognition, takes some time
timings["ll"] = time.time()

# Start threading and wait for init to finish
lock = thread.allocate_lock()
lock.acquire()
thread.start_new_thread(init_detector, (lock, ))

# Start video capture on the IR camera
timings["ic"] = time.time()

class _FastV4L2Capture:
	"""Direct CAP_V4L2 opener that skips multi-backend probing and initial frame discard."""
	def __init__(self, cfg):
		dev = cfg.get("video", "device_path")
		if not os.path.exists(dev):
			print("Camera path is not configured correctly, please edit the 'device_path' config value.")
			sys.exit(1)
		self.internal = cv2.VideoCapture(dev, cv2.CAP_V4L2)
		if not self.internal.isOpened():
			raise RuntimeError("V4L2 open failed")
		if cfg.getboolean("video", "force_mjpeg", fallback=False):
			self.internal.set(cv2.CAP_PROP_FOURCC, 1196444237)
		self.fw = cfg.getint("video", "frame_width", fallback=-1)
		self.fh = cfg.getint("video", "frame_height", fallback=-1)
		if self.fw != -1:
			self.internal.set(cv2.CAP_PROP_FRAME_WIDTH, self.fw)
		if self.fh != -1:
			self.internal.set(cv2.CAP_PROP_FRAME_HEIGHT, self.fh)

	def read_frame(self):
		ret, frame = self.internal.read()
		if not ret:
			print("Failed to read camera specified in your 'device_path', aborting")
			sys.exit(1)
		if frame.ndim == 2:
			return frame, frame
		return frame, cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

	def release(self):
		devnull_fd = os.open(os.devnull, os.O_WRONLY)
		saved_stderr_fd = os.dup(2)
		os.dup2(devnull_fd, 2)
		try:
			self.internal.release()
		finally:
			os.dup2(saved_stderr_fd, 2)
			os.close(saved_stderr_fd)
			os.close(devnull_fd)

if config.get("video", "recording_plugin", fallback="opencv") == "opencv":
	try:
		video_capture = _FastV4L2Capture(config)
	except Exception:
		video_capture = VideoCapture(config)
else:
	video_capture = VideoCapture(config)
try:
	video_capture.internal.set(cv2.CAP_PROP_BUFFERSIZE, 1)
except Exception:
	pass

# Read exposure from config to use in the main loop
exposure = config.getint("video", "exposure", fallback=-1)

# Note the time it took to open the camera
timings["ic"] = time.time() - timings["ic"]

# Fetch the max frame height and scaling before starting capture
max_height = config.getfloat("video", "max_height", fallback=0.0)
height = video_capture.internal.get(cv2.CAP_PROP_FRAME_HEIGHT) or 1
scaling_factor = (max_height / height) or 1

frames = 0
valid_frames = 0
dark_running_total = 0

clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))

# Live IR preview emitter for the KDE lock screen (org.kveil.lockscreen)
def _init_lockscreen_preview():
	if os.environ.get("HOWDY_PREVIEW") != "1":
		if os.geteuid() == 0:
			return None
		pid = os.getppid()
		found = False
		for _ in range(8):
			if pid <= 1:
				break
			try:
				with open("/proc/%d/comm" % pid, "r") as f:
					if f.read().strip().startswith("kscreenlocker"):
						found = True
						break
				with open("/proc/%d/stat" % pid, "r") as f:
					s = f.read()
				rparen = s.rfind(")")
				pid = int(s[rparen + 2:].split()[1])
			except Exception:
				break
		if not found:
			return None
	import pwd
	user_home = pwd.getpwuid(os.geteuid()).pw_dir
	cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(user_home, ".config")
	try:
		with open(os.path.join(cfg_home, "kveil", "settings.json"), "r") as f:
			cfg = json.load(f)
		if cfg.get("irPreviewEnabled") is False:
			return None
	except Exception:
		pass
	cache_home = os.environ.get("XDG_CACHE_HOME") or os.path.join(user_home, ".cache")
	pdir = os.path.join(cache_home, "kveil", "ir-preview")
	os.makedirs(pdir, mode=0o700, exist_ok=True)
	return pdir

def _preview_tracking_enabled():
	try:
		import pwd
		user_home = pwd.getpwuid(os.geteuid()).pw_dir
		cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(user_home, ".config")
		with open(os.path.join(cfg_home, "kveil", "settings.json"), "r") as f:
			return json.load(f).get("irPreviewTracking", True) is not False
	except Exception:
		return True

_preview_dir = _init_lockscreen_preview()
_preview_track = _preview_tracking_enabled() if _preview_dir else False

def _cleanup_preview():
	if not _preview_dir:
		return
	for name in ("frame.jpg", "face.png", "frame.tmp.jpg", "face.tmp.png"):
		try:
			os.remove(os.path.join(_preview_dir, name))
		except OSError:
			pass

if _preview_dir:
	import atexit
	atexit.register(_cleanup_preview)

def _emit_preview_frame(img):
	if not _preview_dir:
		return
	try:
		tmp = os.path.join(_preview_dir, "frame.tmp.jpg")
		dst = os.path.join(_preview_dir, "frame.jpg")
		cv2.imwrite(tmp, img, [cv2.IMWRITE_JPEG_QUALITY, 82])
		os.replace(tmp, dst)
	except Exception:
		pass

def _emit_preview_face(face_box, img_shape, seq):
	if not _preview_dir:
		return
	try:
		ih, iw = img_shape[:2]
		if face_box is not None and iw > 0 and ih > 0:
			if isinstance(face_box, (tuple, list)):
				fx1, fy1, fx2, fy2 = face_box
			else:
				fl = face_box.rect if hasattr(face_box, "rect") else face_box
				fx1, fy1, fx2, fy2 = fl.left(), fl.top(), fl.right(), fl.bottom()
			x1 = max(0.0, min(1.0, float(fx1) / iw))
			y1 = max(0.0, min(1.0, float(fy1) / ih))
			x2 = max(0.0, min(1.0, float(fx2) / iw))
			y2 = max(0.0, min(1.0, float(fy2) / ih))
			px = np.array([[[255, int(round(y1 * 255)), int(round(x1 * 255))],
			                [seq & 0xFF, int(round(y2 * 255)), int(round(x2 * 255))]]], dtype=np.uint8)
		else:
			px = np.array([[[0, 0, 0], [seq & 0xFF, 0, 0]]], dtype=np.uint8)
		tmp = os.path.join(_preview_dir, "face.tmp.png")
		dst = os.path.join(_preview_dir, "face.png")
		cv2.imwrite(tmp, px)
		os.replace(tmp, dst)
	except Exception:
		pass


# Decouple camera capture + preview + fast face tracking from the ~200ms ResNet recognizer
# so the preview stream and tracking brackets run at the full hardware camera rate.
_stop_event = threading.Event()
_slot_lock = threading.Lock()
_slot_cond = threading.Condition(_slot_lock)
_latest_pair = None
_latest_seq = 0
_preview_detector = None

def _init_preview_detector():
	global _preview_detector
	_preview_detector = dlib.get_frontal_face_detector()

if _preview_dir and _preview_track:
	threading.Thread(target=_init_preview_detector, daemon=True).start()

def _load_haar_fallback():
	if not (_preview_dir and _preview_track):
		return None
	for path in (
		"/usr/share/opencv5/haarcascades/haarcascade_frontalface_alt2.xml",
		"/usr/share/opencv4/haarcascades/haarcascade_frontalface_alt2.xml",
		"/usr/share/opencv/haarcascades/haarcascade_frontalface_alt2.xml",
		"/usr/share/opencv5/haarcascades/haarcascade_frontalface_default.xml",
		"/usr/share/opencv4/haarcascades/haarcascade_frontalface_default.xml",
		"/usr/share/opencv/haarcascades/haarcascade_frontalface_default.xml",
	):
		if os.path.isfile(path):
			clf = cv2.CascadeClassifier(path)
			if not clf.empty():
				return clf
	return None

_haar_detector = _load_haar_fallback()

def _box_iou(a, b):
	ax1, ay1, ax2, ay2 = a
	bx1, by1, bx2, by2 = b
	ix1 = max(ax1, bx1)
	iy1 = max(ay1, by1)
	ix2 = min(ax2, bx2)
	iy2 = min(ay2, by2)
	iw = max(0.0, ix2 - ix1)
	ih = max(0.0, iy2 - iy1)
	inter = iw * ih
	if inter <= 0.0:
		return 0.0
	area_a = max(1.0, (ax2 - ax1) * (ay2 - ay1))
	area_b = max(1.0, (bx2 - bx1) * (by2 - by1))
	return inter / (area_a + area_b - inter)

def _pick_best_hog(dets, scores, prev_box, frame_area, ox=0, oy=0, scale_x=1.0, scale_y=1.0, max_w=None, max_h=None):
	best_box = None
	best_rank = -1e9
	for d, s in zip(dets, scores):
		rx1 = (float(d.left()) + ox) * scale_x
		ry1 = (float(d.top()) + oy) * scale_y
		rx2 = (float(d.right()) + ox) * scale_x
		ry2 = (float(d.bottom()) + oy) * scale_y
		raw_area = max(1.0, (rx2 - rx1) * (ry2 - ry1))
		bx1 = max(0.0, rx1) if max_w is not None else rx1
		by1 = max(0.0, ry1) if max_h is not None else ry1
		bx2 = min(float(max_w), rx2) if max_w is not None else rx2
		by2 = min(float(max_h), ry2) if max_h is not None else ry2
		if bx2 <= bx1 or by2 <= by1:
			continue
		if max_w is not None and ((bx2 - bx1) * (by2 - by1)) / raw_area < 0.45:
			continue
		cand = (bx1, by1, bx2, by2)
		area_bonus = 0.10 * (((bx2 - bx1) * (by2 - by1)) / max(1.0, frame_area))
		iou_bonus = 0.30 * _box_iou(cand, prev_box) if prev_box is not None else 0.0
		rank = float(s) + area_bonus + iou_bonus
		if rank > best_rank:
			best_rank = rank
			best_box = cand
	return best_box

def _detect_hog_half_padded(hog, gray, prev_box, frame_area):
	"""Detect large or border-clipped faces by running dlib HOG on a 0.5x border-replicated frame."""
	ih, iw = gray.shape[:2]
	half = cv2.resize(gray, (0, 0), fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
	hh, hw = half.shape[:2]
	if hh <= 0 or hw <= 0:
		return None
	pad = 48
	padded = cv2.copyMakeBorder(half, pad, pad, pad, pad, cv2.BORDER_REPLICATE)
	dets, scores, _ = hog.run(padded, 0, -0.25)
	return _pick_best_hog(
		dets, scores, prev_box, frame_area,
		ox=-pad, oy=-pad,
		scale_x=iw / float(hw), scale_y=ih / float(hh),
		max_w=iw, max_h=ih,
	)

def _pick_best_haar(hfaces, prev_box, frame_area, ih, ox=0.0, oy=0.0, scale_x=1.0, scale_y=1.0, max_w=None, max_h=None):
	best_haar = None
	best_score = -1.0
	prev_h = (prev_box[3] - prev_box[1]) if prev_box is not None else 0.0
	for (x, y, w, h) in hfaces:
		fx = (x + ox) * scale_x
		fy = (y + oy) * scale_y
		fw = w * scale_x
		fh = h * scale_y
		if prev_h > ih * 0.45 and fh < prev_h * 0.45:
			continue
		# Inset Haar box slightly to align with dlib's tighter face crop
		bx1 = fx + 0.08 * fw
		by1 = fy + 0.14 * fh
		bx2 = fx + 0.92 * fw
		by2 = fy + 0.96 * fh
		if max_w is not None:
			bx1 = max(0.0, bx1)
			bx2 = min(float(max_w), bx2)
		if max_h is not None:
			by1 = max(0.0, by1)
			by2 = min(float(max_h), by2)
		if bx2 <= bx1 or by2 <= by1:
			continue
		cand = (bx1, by1, bx2, by2)
		score = (
			_box_iou(cand, prev_box) + 0.05 * ((fw * fh) / max(1.0, frame_area))
			if prev_box is not None
			else float(fw * fh)
		)
		if score > best_score:
			best_score = score
			best_haar = cand
	return best_haar

def _frame_face_box(gray, raw_box):
	ih, iw = gray.shape[:2]
	bx1, by1, bx2, by2 = raw_box
	bw = max(1.0, bx2 - bx1)
	bh = max(1.0, by2 - by1)
	sp = pose_predictor
	if sp is not None:
		try:
			rect = dlib.rectangle(int(round(bx1)), int(round(by1)), int(round(bx2)), int(round(by2)))
			sh = sp(gray, rect)
			if sh.num_parts >= 5:
				rx = (sh.part(0).x + sh.part(1).x) * 0.5
				ry = (sh.part(0).y + sh.part(1).y) * 0.5
				lx = (sh.part(2).x + sh.part(3).x) * 0.5
				ly = (sh.part(2).y + sh.part(3).y) * 0.5
				ex = (rx + lx) * 0.5
				ey = (ry + ly) * 0.5
				nx = float(sh.part(4).x)
				ny = float(sh.part(4).y)
				iod = float(np.hypot(lx - rx, ly - ry))
				if iod >= bw * 0.15 and ny > ey:
					side = max(bw * 1.32, min(bw * 1.65, max(iod * 3.25, bw * 1.42)))
					cx = 0.65 * ex + 0.35 * nx
					return (
						max(0.0, min(float(iw), cx - 0.5 * side)),
						max(0.0, min(float(ih), ey - 0.40 * side)),
						max(0.0, min(float(iw), cx + 0.5 * side)),
						max(0.0, min(float(ih), ey + 0.60 * side)),
					)
		except Exception:
			pass
	return (
		max(0.0, min(float(iw), bx1 - 0.21 * bw)),
		max(0.0, min(float(ih), by1 - 0.32 * bh)),
		max(0.0, min(float(iw), bx2 + 0.21 * bw)),
		max(0.0, min(float(ih), by2 + 0.12 * bh)),
	)

def _detect_preview_face(gray, prev_box):
	ih, iw = gray.shape[:2]
	frame_area = float(iw * ih)
	box = None
	hog = _preview_detector
	prev_large = prev_box is not None and (prev_box[3] - prev_box[1]) > ih * 0.65

	# Stage 1a: if tracking a large close-up face, start with fast 0.5x padded HOG (~7ms)
	if hog is not None and prev_large:
		box = _detect_hog_half_padded(hog, gray, prev_box, frame_area)

	# Stage 1b: upsample=1 inside an expanded ROI around previous face (~8ms, detects down to 40px)
	if hog is not None and box is None and prev_box is not None:
		px1, py1, px2, py2 = prev_box
		pw = max(1.0, px2 - px1)
		ph = max(1.0, py2 - py1)
		cx = (px1 + px2) * 0.5
		cy = (py1 + py2) * 0.5
		rw = min(iw, max(200, int(pw * 2.4)))
		rh = min(ih, max(200, int(ph * 2.4)))
		rx1 = max(0, min(iw - rw, int(cx - rw * 0.5)))
		ry1 = max(0, min(ih - rh, int(cy - rh * 0.5)))
		rx2 = rx1 + rw
		ry2 = ry1 + rh
		roi = np.ascontiguousarray(gray[ry1:ry2, rx1:rx2])
		dets, scores, _ = hog.run(roi, 1, -0.30)
		box = _pick_best_hog(dets, scores, prev_box, frame_area, rx1, ry1)

	# Stage 2a: full-frame upsample=1 HOG (~25ms on 512x320)
	if hog is not None and box is None:
		dets, scores, _ = hog.run(gray, 1, -0.20)
		box = _pick_best_hog(dets, scores, prev_box, frame_area, 0, 0)

	# Stage 2b: 0.5x border-padded HOG catches faces that fill the entire view or touch frame borders
	if hog is not None and box is None and not prev_large:
		box = _detect_hog_half_padded(hog, gray, prev_box, frame_area)

	# Stage 3: Haar cascade fallback for tilted/angled/glasses frames where HOG drops
	if box is None and _haar_detector is not None:
		# Try padded 0.5x Haar first with a large minSize so close-up faces match whole-face, not eye/nose patches
		half = cv2.resize(gray, (0, 0), fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
		hh, hw = half.shape[:2]
		if hh > 0 and hw > 0:
			pad = 48
			padded = cv2.copyMakeBorder(half, pad, pad, pad, pad, cv2.BORDER_REPLICATE)
			hfaces_big = _haar_detector.detectMultiScale(
				padded, scaleFactor=1.15, minNeighbors=6, minSize=(56, 56)
			)
			if len(hfaces_big) > 0:
				box = _pick_best_haar(
					hfaces_big, prev_box, frame_area, ih,
					ox=-pad, oy=-pad,
					scale_x=iw / float(hw), scale_y=ih / float(hh),
					max_w=iw, max_h=ih,
				)

		if box is None:
			min_dim = max(48, int(min(iw, ih) * 0.16))
			hfaces = _haar_detector.detectMultiScale(
				gray, scaleFactor=1.15, minNeighbors=6, minSize=(min_dim, min_dim)
			)
			if len(hfaces) > 0:
				box = _pick_best_haar(hfaces, prev_box, frame_area, ih, max_w=iw, max_h=ih)

	if box is not None:
		box = _frame_face_box(gray, box)

	# Light EMA smoothing on continuous tracks to remove 1-2px HOG grid jitter
	if box is not None and prev_box is not None and _box_iou(box, prev_box) > 0.35:
		alpha = 0.65
		box = tuple(alpha * n + (1.0 - alpha) * p for n, p in zip(box, prev_box))

	return box

def _capture_loop():
	global frames, black_tries, dark_tries, valid_frames, dark_running_total
	global _latest_pair, _latest_seq
	preview_seq = 0
	prev_preview_box = None
	missed_preview_frames = 0
	peak_raw_mean = 0.0
	dark_skip_streak = 0

	while not _stop_event.is_set():
		frames += 1
		try:
			cap_frame, cap_gs = video_capture.read_frame()
		except SystemExit:
			break
		except Exception:
			break

		raw_mean = float(np.mean(cap_gs))
		cap_gs = clahe.apply(cap_gs)

		if capture_failed or capture_successful:
			if len(snapframes) < 3:
				snapframes.append(cap_frame)

		hist = cv2.calcHist([cap_gs], [0], None, [8], [0, 256])
		hist_total = np.sum(hist)
		darkness = (hist[0] / hist_total * 100) if hist_total > 0 else 100.0

		if (hist_total == 0) or (darkness == 100):
			black_tries += 1
			continue

		dark_running_total += darkness
		valid_frames += 1
		if darkness > dark_threshold:
			dark_tries += 1
			continue

		if scaling_factor != 1:
			cap_frame = cv2.resize(cap_frame, None, fx=scaling_factor, fy=scaling_factor, interpolation=cv2.INTER_AREA)
			cap_gs = cv2.resize(cap_gs, None, fx=scaling_factor, fy=scaling_factor, interpolation=cv2.INTER_AREA)

		if _preview_dir and darkness < 95.0:
			is_dark_flicker = (raw_mean < 12.0) or (peak_raw_mean >= 24.0 and raw_mean < peak_raw_mean * 0.45)
			if is_dark_flicker and dark_skip_streak < 8:
				dark_skip_streak += 1
			else:
				dark_skip_streak = 0
				peak_raw_mean = max(raw_mean, peak_raw_mean * 0.985)
				_emit_preview_frame(cap_gs)
				preview_seq = (preview_seq + 1) & 0xFF
				# Emit frame 1 trigger immediately so QML displays live video without waiting for detection
				if preview_seq == 1:
					_emit_preview_face(None, cap_gs.shape, preview_seq)
				if _preview_track:
					detected_box = _detect_preview_face(cap_gs, prev_preview_box)
				else:
					detected_box = None
				if detected_box is not None:
					prev_preview_box = detected_box
					missed_preview_frames = 0
				else:
					missed_preview_frames += 1
					if missed_preview_frames >= 4:
						prev_preview_box = None
				if preview_seq != 1 or detected_box is not None:
					_emit_preview_face(detected_box, cap_gs.shape, preview_seq)

		with _slot_cond:
			_latest_pair = (cap_frame, cap_gs)
			_latest_seq += 1
			_slot_cond.notify()

		if exposure != -1:
			video_capture.internal.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1.0)
			video_capture.internal.set(cv2.CAP_PROP_EXPOSURE, float(exposure))

_cap_thread = threading.Thread(target=_capture_loop, daemon=True)
_cap_thread.start()

# Wait for recognition detectors before starting matching loop (capture + preview already running)
lock.acquire()
lock.release()
del lock

timings["fr"] = time.time()

def _stop_capture():
	_stop_event.set()
	_cap_thread.join(timeout=0.4)
	try:
		video_capture.release()
	except Exception:
		pass

_consumed_seq = 0

while True:
	# Stop if we've exceded the time limit
	remaining = timeout - (time.time() - timings["fr"])
	if remaining <= 0:
		_stop_capture()
		# Create a timeout snapshot if enabled
		if capture_failed:
			make_snapshot("FAILED")

		if dark_tries == valid_frames:
			print("All frames were too dark, please check dark_threshold in config")
			print("Average darkness: " + str(dark_running_total / max(1, valid_frames)) + ", Threshold: " + str(dark_threshold))
			sys.exit(13)
		else:
			sys.exit(11)

	with _slot_cond:
		if _latest_seq == _consumed_seq:
			_slot_cond.wait(timeout=min(0.1, remaining))
		if _latest_seq == _consumed_seq or _latest_pair is None:
			continue
		frame, gsframe = _latest_pair
		_consumed_seq = _latest_seq

	# Get all faces from that frame as encodings
	# Upsamples 1 time
	face_locations = face_detector(gsframe, 1)

	# Loop through each face
	for fl in face_locations:
		if use_cnn:
			fl = fl.rect

		# Fetch the faces in the image
		face_landmark = pose_predictor(frame, fl)
		face_encoding = np.array(face_encoder.compute_face_descriptor(frame, face_landmark, 1))

		# Match this found face against a known face
		matches = np.linalg.norm(encodings - face_encoding, axis=1)

		# Get best match
		match_index = np.argmin(matches)
		match = matches[match_index]

		# Update certainty if we have a new low
		if lowest_certainty > match:
			lowest_certainty = match

		# Check if a match that's confident enough
		if 0 < match < video_certainty:
			timings["tt"] = time.time() - timings["st"]
			timings["fl"] = time.time() - timings["fr"]

			# If set to true in the config, print debug text
			if end_report:
				def print_timing(label, k):
					"""Helper function to print a timing from the list"""
					print("  %s: %dms" % (label, round(timings[k] * 1000)))

				# Print a nice timing report
				print("Time spent")
				print_timing("Starting up", "in")
				print("  Open cam + load libs: %dms" % (round(max(timings["ll"], timings["ic"]) * 1000, )))
				print_timing("  Opening the camera", "ic")
				print_timing("  Importing recognition libs", "ll")
				print_timing("Searching for known face", "fl")
				print_timing("Total time", "tt")

				print("\nResolution")
				width = video_capture.fw or 1
				print("  Native: %dx%d" % (height, width))
				# Save the new size for diagnostics
				scale_height, scale_width = frame.shape[:2]
				print("  Used: %dx%d" % (scale_height, scale_width))

				# Show the total number of frames and calculate the FPS by deviding it by the total scan time
				print("\nFrames searched: %d (%.2f fps)" % (frames, frames / timings["fl"]))
				print("Black frames ignored: %d " % (black_tries, ))
				print("Dark frames ignored: %d " % (dark_tries, ))
				print("Certainty of winning frame: %.3f" % (match * 10, ))

				print("Winning model: %d (\"%s\")" % (match_index, models[match_index]["label"]))

			_stop_capture()

			# Make snapshot if enabled
			if capture_successful:
				make_snapshot("SUCCESSFUL")

			# End peacefully
			sys.exit(0)
