extends Node
## penInk に描かせる。penInk の tools/animator_server.py (penInk Animator が使っている描画サーバー) を
## 起こして、同じポーズ・同じ向きの絵を 1 枚もらう。キャラは core.ExportPenink が書いたフォルダ。

signal drawn(img: Image, seconds: float)
signal status(text: String)

const PLAYER_H := 1.75          ## penInk の「キャラの高さ px」はこの身長が基準 (penink/render.py)

var python := "py"
var penink_dir := "C:/Users/taket/penInk"
var port := 0
var pid := -1
var ready_ok := false
var _folder := ""
var _pending: Dictionary = {}
var _busy := false
var _timer: Timer
var _left := 0.0


func _ready() -> void:
	var env := OS.get_environment("PENINK")
	if env != "":
		penink_dir = env
	_timer = Timer.new()
	_timer.wait_time = 0.4
	_timer.timeout.connect(_poll)
	add_child(_timer)


func available() -> bool:
	return FileAccess.file_exists(penink_dir.path_join("tools/animator_server.py"))


## キャラのフォルダが変わったら立ち上げ直す
func start(folder: String) -> void:
	stop()
	_folder = folder
	if not available():
		status.emit("penInk が見つかりません: " + penink_dir)
		return
	for p in range(8830, 8990):
		var s := TCPServer.new()
		if s.listen(p, "127.0.0.1") == OK:
			s.stop()
			port = p
			break
	var args := PackedStringArray([penink_dir.path_join("tools/animator_server.py"), folder, "--port", str(port),
			"--parent", str(OS.get_process_id()), "--workers", "1",
			"--log", OS.get_user_data_dir().path_join("penink.log")])
	pid = OS.create_process(python, args, false)
	if pid <= 0:
		status.emit("Python (py) を起動できませんでした")
		return
	status.emit("penInk を起こしています…")
	_left = 60.0
	_timer.start()


func stop() -> void:
	if _timer:
		_timer.stop()
	if pid > 0:
		OS.kill(pid)
	pid = -1
	ready_ok = false
	_busy = false


func _exit_tree() -> void:
	stop()


func _poll() -> void:
	_left -= _timer.wait_time
	if _left <= 0.0 or (pid > 0 and not OS.is_process_running(pid)):
		_timer.stop()
		status.emit("penInk が立ち上がりませんでした (ログ: %s)" % OS.get_user_data_dir().path_join("penink.log"))
		return
	_http(HTTPClient.METHOD_GET, "/api/ping", "", func(code: int, _body: PackedByteArray, _h: PackedStringArray):
		if code == 200 and not ready_ok:
			_timer.stop()
			ready_ok = true
			status.emit("penInk の準備ができました")
			_flush())


## req: {yaw, pitch, px, bones: {名前: [x, y, z] (度)}, root: [x, y, z]}
func draw(req: Dictionary) -> void:
	_pending = req
	_flush()


func _flush() -> void:
	if not ready_ok or _busy or _pending.is_empty():
		return
	var req := _pending
	_pending = {}
	_busy = true
	status.emit("penInk が描いています…")
	var t0 := Time.get_ticks_msec()
	_http(HTTPClient.METHOD_POST, "/api/render", JSON.stringify(req), func(code: int, body: PackedByteArray, _h: PackedStringArray):
		_busy = false
		if code == 200:
			var img := Image.new()
			if img.load_png_from_buffer(body) == OK:
				drawn.emit(img, (Time.get_ticks_msec() - t0) / 1000.0)
				status.emit("penInk %.1f 秒" % ((Time.get_ticks_msec() - t0) / 1000.0))
		else:
			status.emit("penInk が描けませんでした: " + body.get_string_from_utf8().left(200))
		_flush())


func _http(method: int, path: String, body: String, cb: Callable) -> void:
	var r := HTTPRequest.new()
	r.timeout = 120.0
	add_child(r)
	r.request_completed.connect(func(_result: int, code: int, headers: PackedStringArray, data: PackedByteArray):
		r.queue_free()
		cb.call(code, data, headers))
	var err := r.request("http://127.0.0.1:%d%s" % [port, path], PackedStringArray(["Content-Type: application/json"]), method, body)
	if err != OK:
		r.queue_free()
		cb.call(0, PackedByteArray(), PackedStringArray())
