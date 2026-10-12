# UI-16 test helper: a tiny HTTP server on 127.0.0.1 that answers like GitHub's list-releases endpoint: 200 with
# the JSON it was given, or 304 without a body when the request carries its ETag. Poll it from the test's frame
# loop; it never blocks the main thread, so it also serves an HTTPRequest that runs without threads.
extends RefCounted

var server := TCPServer.new()
var body := PackedByteArray()
var etag := "W/\"fixture-1\""
## 200 unless a test asks for an error status (403 rate limit, 500 ...).
var status_code := 200
## Accept connections and never answer: the client must time out on its own.
var silent := false
## The head of every request received, in order (for assertions on the headers the app sends).
var requests: Array[String] = []
var port := 0
var _pending: Array[Dictionary] = []
var _closing: Array[Dictionary] = []
var _held: Array[StreamPeerTCP] = []


func start(json_text: String) -> bool:
	body = json_text.to_utf8_buffer()
	if server.listen(0, "127.0.0.1") != OK:
		return false
	port = server.get_local_port()
	return port > 0


func url() -> String:
	return "http://127.0.0.1:%d/repos/x/y/releases?per_page=10" % port


## Replace the answer (a new release was published) and its ETag.
func publish(json_text: String, new_etag: String) -> void:
	body = json_text.to_utf8_buffer()
	etag = new_etag


func poll() -> void:
	while server.is_connection_available():
		_pending.append({ peer = server.take_connection(), head = "" })
	for i in range(_pending.size() - 1, -1, -1):
		var entry: Dictionary = _pending[i]
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_data(n)
			entry.head += (got[1] as PackedByteArray).get_string_from_ascii()
		if entry.head.contains("\r\n\r\n"):
			requests.append(entry.head)
			_pending.remove_at(i)
			if silent:
				_held.append(peer) # open, never answered
				continue
			_respond(peer, entry.head)
			_closing.append({ peer = peer, frames = 0 })
	for i in range(_closing.size() - 1, -1, -1):
		_closing[i].frames += 1
		if _closing[i].frames > 30: # let the client read everything before the socket closes
			(_closing[i].peer as StreamPeerTCP).disconnect_from_host()
			_closing.remove_at(i)


func stop() -> void:
	for peer in _held:
		peer.disconnect_from_host()
	_held.clear()
	server.stop()


func _respond(peer: StreamPeerTCP, head: String) -> void:
	if status_code != 200:
		var error_body := ("{\"message\": \"status %d\"}" % status_code).to_utf8_buffer()
		peer.put_data(("HTTP/1.1 %d Error\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: %d\r\n\r\n" % [status_code, error_body.size()]).to_utf8_buffer())
		peer.put_data(error_body)
		return
	var not_modified := head.contains("If-None-Match: " + etag)
	var lines := PackedStringArray([
		"HTTP/1.1 304 Not Modified" if not_modified else "HTTP/1.1 200 OK",
		"ETag: " + etag,
		"Content-Type: application/json; charset=utf-8",
		"Connection: close",
		"Content-Length: %d" % (0 if not_modified else body.size()),
		"", "",
	])
	peer.put_data("\r\n".join(lines).to_utf8_buffer())
	if not not_modified:
		peer.put_data(body)
