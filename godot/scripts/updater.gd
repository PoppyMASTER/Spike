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

var apk_build := 0
var active_build := 0
var ready_build := 0

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

func _check() -> void:
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	if req.request(BASE + "manifest.json") != OK:
		req.queue_free()
		return
	var r = await req.request_completed
	req.queue_free()
	if r[1] != 200:
		return
	var m = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if not (m is Dictionary) or not m.has("build"):
		return
	var remote := int(m.build)
	if remote <= active_build:
		return
	var dl := HTTPRequest.new()
	dl.download_file = PCK_NEW
	dl.timeout = 120.0
	add_child(dl)
	if dl.request(BASE + String(m.get("pck", "update.pck"))) != OK:
		dl.queue_free()
		return
	var r2 = await dl.request_completed
	dl.queue_free()
	if r2[1] == 200 and FileAccess.file_exists(PCK_NEW):
		var st := _state()
		st.pending = remote
		_save_state(st)
		ready_build = remote
		update_ready.emit(remote)
	else:
		DirAccess.remove_absolute(PCK_NEW)
