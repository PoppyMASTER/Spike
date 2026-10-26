extends Node
## Online play (autoload "Net"): two phones meet in a "room" on a free public MQTT relay
## reached over WebSocket — no server of our own, works on mobile data and through any NAT.
##   host  publishes on  skyspike/v1/<CODE>/h   (start, 30 Hz match snapshots, end)
##   guest publishes on  skyspike/v1/<CODE>/g   (join, inputs)
## The room code is 4 letters + the index of the relay the host reached, so both use the same one.

signal connected
signal failed(reason: String)
signal message(d: Dictionary)
signal peer_lost

const BROKERS := [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
]
const LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const TIMEOUT := 7.0

var ws: WebSocketPeer
var role := ""          # "host" | "guest" | ""
var code := ""
var broker_idx := 0
var up := false         # MQTT session established
var buf := PackedByteArray()
var last_rx := 0.0      # last message from the peer (seconds)
var last_ping := 0.0
var pid := 1
var _try_list: Array = []
var _conn_t := 0.0
var _connack := false
var _sent_connect := false
var override_url := ""  # tests: ws://127.0.0.1:9001

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if "--broker" in a:
		override_url = a[a.find("--broker") + 1]
	set_process(false)

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ---------------------------------------------------------------- rooms
func host() -> void:
	close()
	role = "host"
	code = ""
	for i in 4:
		code += LETTERS[randi() % LETTERS.length()]
	_try_list = range(BROKERS.size())
	_next_broker()

func join(c: String) -> bool:
	c = c.strip_edges().to_upper().replace(" ", "")
	if c.length() != 5 or not c[4].is_valid_int() or int(c[4]) < 1 or int(c[4]) > BROKERS.size():
		return false
	close()
	role = "guest"
	code = c.substr(0, 4)
	_try_list = [int(c[4]) - 1]
	_next_broker()
	return true

func room_code() -> String:
	return code + str(broker_idx + 1)

func close() -> void:
	if ws and up:
		_send_raw(PackedByteArray([0xE0, 0x00]))   # DISCONNECT
	if ws:
		ws.close()
	ws = null
	up = false
	_connack = false
	role = ""
	buf.clear()
	set_process(false)

func send(d: Dictionary) -> void:
	if not up:
		return
	var topic := "skyspike/v1/%s/%s" % [code, "h" if role == "host" else "g"]
	_publish(topic, var_to_bytes(d))

# ---------------------------------------------------------------- connection
func _next_broker() -> void:
	if _try_list.is_empty():
		var r := role
		close()
		failed.emit("Impossible de joindre le serveur relais (connexion internet ?)" if r != "" else "")
		return
	broker_idx = _try_list.pop_front()
	ws = WebSocketPeer.new()
	ws.supported_protocols = PackedStringArray(["mqtt"])
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var url: String = override_url if override_url != "" else BROKERS[broker_idx]
	if ws.connect_to_url(url) != OK:
		_next_broker()
		return
	_conn_t = now()
	_connack = false
	_sent_connect = false
	up = false
	buf.clear()
	set_process(true)

func _process(_dt: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING:
		if now() - _conn_t > 6.0:
			ws.close()
			_next_broker()
		return
	if st == WebSocketPeer.STATE_CLOSED:
		var was_up := up
		up = false
		if was_up:
			ws = null
			set_process(false)
			peer_lost.emit()
		else:
			_next_broker()
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	if not _connack and not _sent_connect:
		_send_connect()
		_sent_connect = true
		_conn_t = now()
	if not up and now() - _conn_t > 6.0:
		ws.close()
		_next_broker()
		return
	while ws.get_available_packet_count() > 0:
		buf.append_array(ws.get_packet())
	_parse()
	if up:
		if now() - last_ping > 20.0:
			last_ping = now()
			_send_raw(PackedByteArray([0xC0, 0x00]))
		if last_rx > 0 and now() - last_rx > TIMEOUT:
			last_rx = 0.0
			peer_lost.emit()

# ---------------------------------------------------------------- MQTT 3.1.1 (QoS 0 only)
static func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var o := PackedByteArray([b.size() >> 8, b.size() & 0xFF])
	o.append_array(b)
	return o
static func _varlen(n: int) -> PackedByteArray:
	var o := PackedByteArray()
	while true:
		var d := n % 128
		n = n / 128
		if n > 0:
			d |= 0x80
		o.append(d)
		if n == 0:
			break
	return o
func _packet(head: int, body: PackedByteArray) -> PackedByteArray:
	var o := PackedByteArray([head])
	o.append_array(_varlen(body.size()))
	o.append_array(body)
	return o
func _send_raw(b: PackedByteArray) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(b, WebSocketPeer.WRITE_MODE_BINARY)

func _send_connect() -> void:
	var body := _str("MQTT")
	body.append_array(PackedByteArray([4, 0x02, 0, 60]))   # level 4, clean session, keepalive 60 s
	body.append_array(_str("skyspike-%s-%d" % [role, randi() % 1000000]))
	_send_raw(_packet(0x10, body))

func _subscribe(topic: String) -> void:
	pid = (pid % 60000) + 1
	var body := PackedByteArray([pid >> 8, pid & 0xFF])
	body.append_array(_str(topic))
	body.append(0)
	_send_raw(_packet(0x82, body))

func _publish(topic: String, payload: PackedByteArray) -> void:
	var body := _str(topic)
	body.append_array(payload)
	_send_raw(_packet(0x30, body))

func _parse() -> void:
	while buf.size() >= 2:
		var mult := 1
		var n := 0
		var i := 1
		var ok := false
		while i < buf.size() and i < 5:
			var d: int = buf[i]
			n += (d & 0x7F) * mult
			mult *= 128
			i += 1
			if d & 0x80 == 0:
				ok = true
				break
		if not ok or buf.size() < i + n:
			return
		var head: int = buf[0]
		var body := buf.slice(i, i + n)
		buf = buf.slice(i + n)
		match head >> 4:
			2:   # CONNACK
				if body.size() >= 2 and body[1] == 0:
					_connack = true
					up = true
					last_ping = now()
					_subscribe("skyspike/v1/%s/%s" % [code, "g" if role == "host" else "h"])
					connected.emit()
				else:
					ws.close()
			3:   # PUBLISH (QoS 0: no packet id)
				var tl := (int(body[0]) << 8) | int(body[1])
				var qos := (head >> 1) & 3
				var off := 2 + tl + (2 if qos > 0 else 0)
				var v = bytes_to_var(body.slice(off))
				if v is Dictionary:
					last_rx = now()
					message.emit(v)
			_:
				pass
