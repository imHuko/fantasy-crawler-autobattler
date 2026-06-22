extends Node

# -------------------------------------------------------
# TelemetryManager — optional local run tracking + upload,
# plus a persistent in-game feedback button on every screen.
# -------------------------------------------------------

const SETTINGS_PATH  = "user://settings.json"
const LOG_PATH       = "user://telemetry.json"
const SUBMIT_URL     = "https://fpvwpxtsrmrmdvnswrzx.supabase.co/rest/v1/telemetry_sessions"
const FEEDBACK_URL   = "https://fpvwpxtsrmrmdvnswrzx.supabase.co/rest/v1/feedback"
const SUPABASE_KEY   = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwdndweHRzcm1ybWR2bnN3cnp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyNzkyNTksImV4cCI6MjA5Mzg1NTI1OX0.gxsUTibmHHUhPydl9DTjpjfjGIghjW8WwGyIlAbFgMY"

signal upload_done(success: bool, message: String)

var enabled: bool = false

var _session: Dictionary = {}
var _session_active: bool = false
var _session_start_ms: float = 0.0

func _ready() -> void:
	_load_settings()
	_build_feedback_button()

# -------------------------------------------------------
# Persistent feedback button
# -------------------------------------------------------

func _build_feedback_button() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var btn = Button.new()
	btn.text = "?"
	btn.tooltip_text = "Send feedback to developer"
	btn.add_theme_font_size_override("font_size", 18)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left  = -52
	btn.offset_top   = -52
	btn.offset_right = -10
	btn.offset_bottom = -10
	btn.pressed.connect(_show_feedback_popup)
	root.add_child(btn)

func _show_feedback_popup() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 101
	add_child(layer)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left  = -210
	panel.offset_top   = -130
	panel.offset_right = 210
	panel.offset_bottom = 130
	layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Send Feedback to Dev"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Bug, balance issue, or anything else — describe what happened."
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(sub)

	var input = TextEdit.new()
	input.custom_minimum_size = Vector2(0, 90)
	input.placeholder_text = "What happened?"
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(input)

	var status = Label.new()
	status.add_theme_font_size_override("font_size", 11)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(110, 36)
	cancel_btn.pressed.connect(func(): layer.queue_free())
	hbox.add_child(cancel_btn)

	var send_btn = Button.new()
	send_btn.text = "Send"
	send_btn.custom_minimum_size = Vector2(110, 36)
	send_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	send_btn.pressed.connect(func():
		var msg = input.text.strip_edges()
		if msg == "":
			status.text = "Write something first."
			return
		send_btn.disabled = true
		send_btn.text = "Sending..."
		_submit_feedback(msg, func(ok: bool, result_msg: String):
			if ok:
				status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
				status.text = "Sent! Thank you."
				get_tree().create_timer(1.5).timeout.connect(func(): layer.queue_free())
			else:
				send_btn.disabled = false
				send_btn.text = "Send"
				status.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
				status.text = result_msg
		)
	)
	hbox.add_child(send_btn)

	input.grab_focus()

func _submit_feedback(message: String, on_done: Callable) -> void:
	var scene_name = ""
	var tree = get_tree()
	if tree and tree.current_scene:
		scene_name = tree.current_scene.name

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, _body):
		http.queue_free()
		var ok = result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 201)
		on_done.call(ok, "Failed (HTTP %d)" % code if not ok else "")
	)
	var headers = [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=minimal",
	]
	var body = JSON.stringify({
		"session_id": _session.get("session_id", ""),
		"message":    message,
		"stage":      PlayerInventory.current_stage,
		"scene":      scene_name,
	})
	http.request(FEEDBACK_URL, headers, HTTPClient.METHOD_POST, body)

# -------------------------------------------------------
# Session tracking
# -------------------------------------------------------

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH): return
	var f = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		enabled = data.get("telemetry_enabled", false)

func save_settings() -> void:
	var existing: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary: existing = data
	existing["telemetry_enabled"] = enabled
	var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(existing, "\t"))
	f.close()

func start_session(difficulty: String, stage: int) -> void:
	if not enabled: return
	flush()
	_session_start_ms = Time.get_ticks_msec()
	_session = {
		"session_id": Time.get_datetime_string_from_system().replace("T", "_"),
		"difficulty": difficulty,
		"events": []
	}
	_session_active = true
	_record("session_started", {"difficulty": difficulty, "stage": stage})

func log_event(type: String, data: Dictionary = {}) -> void:
	if not enabled or not _session_active: return
	_record(type, data)

func flush() -> void:
	if not enabled or not _session_active or _session.is_empty(): return
	var all_sessions: Array = []
	if FileAccess.file_exists(LOG_PATH):
		var f = FileAccess.open(LOG_PATH, FileAccess.READ)
		var existing = JSON.parse_string(f.get_as_text())
		f.close()
		if existing is Array: all_sessions = existing
	all_sessions.append(_session)
	var f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(all_sessions, "\t"))
	f.close()

func submit_all(on_done: Callable = Callable()) -> void:
	if not FileAccess.file_exists(LOG_PATH):
		if on_done.is_valid(): on_done.call(false, "No data to send.")
		return

	var f = FileAccess.open(LOG_PATH, FileAccess.READ)
	var body = f.get_as_text()
	f.close()

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, _body):
		http.queue_free()
		var ok = result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 201)
		var msg = "Sent!" if ok else "Upload failed (HTTP %d)" % code
		if ok:
			var fw = FileAccess.open(LOG_PATH, FileAccess.WRITE)
			fw.store_string("[]")
			fw.close()
		upload_done.emit(ok, msg)
		if on_done.is_valid(): on_done.call(ok, msg)
	)
	var headers = [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=minimal",
	]
	http.request(SUBMIT_URL, headers, HTTPClient.METHOD_POST, body)

func _record(type: String, data: Dictionary) -> void:
	var event = {"t": _elapsed_s(), "type": type}
	event.merge(data)
	_session["events"].append(event)

func _elapsed_s() -> float:
	return (Time.get_ticks_msec() - _session_start_ms) / 1000.0
