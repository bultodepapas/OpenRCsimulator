# TELEM-06 test helper: a tiny HTTP collector on 127.0.0.1 for the telemetry sender. It reads each request's head
# and Content-Length body, records them and answers with the configured status (202 by default) and extra header
# lines; `silent` accepts and never answers. Poll it from the test's frame loop; it never blocks.
extends RefCounted

var server := TCPServer.new()
var port := 0
var status_code := 202
var extra_headers := PackedStringArray()
var silent := false
## {head: String, body: PackedByteArray} per complete request, in order.
var requests: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _closing: Array[Dictionary] = []
var _held: Array[StreamPeerTCP] = []


func start() -> bool:
	if server.listen(0, "127.0.0.1") != OK:
		return false
	port = server.get_local_port()
	return port > 0


func url(path := "/v1/batches") -> String:
	return "http://127.0.0.1:%d%s" % [port, path]


func poll() -> void:
	while server.is_connection_available():
		_pending.append({"peer": server.take_connection(), "data": PackedByteArray()})
	for i in range(_pending.size() - 1, -1, -1):
		var entry: Dictionary = _pending[i]
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_pending.remove_at(i) # the client gave up (cancelled) before sending a whole request
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got: Array = peer.get_data(available)
			entry.data.append_array(got[1] as PackedByteArray)
		var text: String = (entry.data as PackedByteArray).get_string_from_ascii()
		var split := text.find("\r\n\r\n")
		if split < 0:
			continue
		var head := text.substr(0, split)
		var length := 0
		for line: String in head.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.substr(15).strip_edges())
		var body: PackedByteArray = (entry.data as PackedByteArray).slice(split + 4)
		if body.size() < length:
			continue
		requests.append({"head": head, "body": body.slice(0, length)})
		_pending.remove_at(i)
		if silent:
			_held.append(peer)
			continue
		var answer := "{\"status\":\"ok\"}".to_utf8_buffer()
		var lines := PackedStringArray(["HTTP/1.1 %d Status" % status_code, "Content-Type: application/json",
			"Connection: close", "Content-Length: %d" % answer.size()])
		lines.append_array(extra_headers)
		peer.put_data(("\r\n".join(lines) + "\r\n\r\n").to_utf8_buffer())
		peer.put_data(answer)
		_closing.append({"peer": peer, "frames": 0})
	for i in range(_closing.size() - 1, -1, -1):
		_closing[i].frames += 1
		if _closing[i].frames > 30:
			(_closing[i].peer as StreamPeerTCP).disconnect_from_host()
			_closing.remove_at(i)


func stop() -> void:
	for peer: StreamPeerTCP in _held:
		peer.disconnect_from_host()
	_held.clear()
	server.stop()
