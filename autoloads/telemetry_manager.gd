extends Node

# -------------------------------------------------------
# TelemetryManager — optional local run tracking + upload.
# Toggle: checkbox in main menu.
# Local file: user://telemetry.json (append-only sessions).
# Upload:     submit_all() POSTs the full log as JSON to
#             SUBMIT_URL. Set that constant to your endpoint.
# -------------------------------------------------------

const SETTINGS_PATH = "user://settings.json"
const LOG_PATH      = "user://telemetry.json"
const SUBMIT_URL    = "https://fpvwpxtsrmrmdvnswrzx.supabase.co/rest/v1/telemetry_sessions"
const SUPABASE_KEY  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwdndweHRzcm1ybWR2bnN3cnp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyNzkyNTksImV4cCI6MjA5Mzg1NTI1OX0.gxsUTibmHHUhPydl9DTjpjfjGIghjW8WwGyIlAbFgMY"

signal upload_done(success: bool, message: String)

var enabled: bool = false

var _session: Dictionary = {}
var _session_active: bool = false
var _session_start_ms: float = 0.0

func _ready() -> void:
	_load_settings()

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
	if SUBMIT_URL == "":
		if on_done.is_valid(): on_done.call(false, "No upload URL configured.")
		return
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
			# Clear local log after successful upload so it doesn't resend next time
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
