extends Node
## Updates without reinstalling (autoload "Updater", loaded FIRST).
## Every APK build also publishes a resource pack (update.pck) + manifest.json on the GitHub release
## "godot-latest". At start-up this node:
##   1. (in _init, before any other script loads) mounts user://update.pck if it is newer than the APK,
##      so the whole game — scripts, data, art, sounds — runs from the latest build;
##   2. then checks the manifest in the background and downloads a newer pack for the next launch.

const BASE := "https://github.com/PoppyMASTER/Spike/releases/download/godot-latest/"
const PCK := "user://update.pck"
const PCK_NEW := "user://update.pck.part"
const STATE := "user://update.json"

signal update_ready(build: int)
signal status_changed(s: String)

var apk_build := 0
var active_build := 0
var ready_build := 0
var remote_build := 0
var status := "idle"     # idle | checking | uptodate | downloading | ready | error
var _busy := false

func _set_status(s: String) -> void:
	status = s
	status_changed.emit(s)

## Options menu button: check now (no-op if a check is already running)
func check_now() -> void:
	if _busy:
		return
	if ready_build > 0:
		_set_status("ready")
		return
	_check()

func _init() -> void:
	apk_build = _read_build()
	var st := _state()
	# a pack downloaded during the previous session: promote it now
	if FileAccess.file_exists(PCK_NEW) and int(st.get("pending", 0)) > 0:
		DirAccess.remove_absolute(PCK)
		DirAccess.rename_absolute(PCK_NEW, PCK)
		st.build = st.pending
		st.erase("pending")
		_save_state(st)
	active_build = apk_build
	var pb := int(st.get("build", 0))
	if pb > apk_build and FileAccess.file_exists(PCK):
		if ProjectSettings.load_resource_pack(PCK, true):
			active_build = pb
		else:
			DirAccess.remove_absolute(PCK)

func _ready() -> void:
	if OS.has_feature("editor") or "--sim" in OS.get_cmdline_user_args():
		return
	_check.call_deferred()

static func _read_build() -> int:
	if FileAccess.file_exists("res://build.txt"):
		return int(FileAccess.get_file_as_string("res://build.txt").strip_edges())
	return 0
func _state() -> Dictionary:
	if FileAccess.file_exists(STATE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(STATE))
		if d is Dictionary:
			return d
	return {}
func _save_state(d: Dictionary) -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))

const API := "https://api.github.com/repos/PoppyMASTER/Spike/releases/tags/godot-latest"
var last_error := ""

## GET helper: [http code, body] — result != OK is reported as code -result
func _fetch(url: String, headers := PackedStringArray()) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	req.max_redirects = 10
	add_child(req)
	var err := req.request(url, headers)
	if err != OK:
		req.queue_free()
		return [-1000 - err, PackedByteArray()]
	var r = await req.request_completed
	req.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return [-int(r[0]), PackedByteArray()]
	return [int(r[1]), r[3]]

## latest build number: release manifest first, then the GitHub API (release title "… build N")
func _remote_build() -> int:
	var a := await _fetch(BASE + "manifest.json")
	if a[0] == 200:
		var m = JSON.parse_string((a[1] as PackedByteArray).get_string_from_utf8())
		if m is Dictionary and m.has("build"):
			return int(m.build)
	var e1 := "manifeste %d" % a[0]
	var b := await _fetch(API, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: SkySpike"]))
	if b[0] == 200:
		var j = JSON.parse_string((b[1] as PackedByteArray).get_string_from_utf8())
		if j is Dictionary:
			var rx := RegEx.create_from_string("build (\\d+)")
			var mt := rx.search(String(j.get("name", "")))
			if mt:
				return int(mt.get_string(1))
	last_error = "%s, api %d" % [e1, b[0]]
	return -1

func _check() -> void:
	_busy = true
	_set_status("checking")
	var remote := await _remote_build()
	if remote < 0:
		_done("error")
		return
	remote_build = remote
	if remote <= active_build:
		_done("uptodate")
		return
	if remote == ready_build:
		_done("ready")
		return
	_set_status("downloading")
	var dl := HTTPRequest.new()
	dl.download_file = PCK_NEW
	dl.timeout = 180.0
	dl.max_redirects = 10
	add_child(dl)
	if dl.request(BASE + "update.pck") != OK:
		dl.queue_free()
		last_error = "téléchargement"
		_done("error")
		return
	var r2 = await dl.request_completed
	dl.queue_free()
	if r2[1] == 200 and FileAccess.file_exists(PCK_NEW):
		var st := _state()
		st.pending = remote
		_save_state(st)
		ready_build = remote
		_done("ready")
		update_ready.emit(remote)
	else:
		DirAccess.remove_absolute(PCK_NEW)
		last_error = "téléchargement %d/%d" % [r2[0], r2[1]]
		_done("error")

func _done(s: String) -> void:
	_busy = false
	_set_status(s)
