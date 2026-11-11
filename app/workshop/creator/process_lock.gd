extends RefCounted
## Single-writer process lock of one Aircraft Creator store root (AC-13, ADR-04).
##
## The lock is a loopback TCP listener, an OS-owned resource: a second process cannot bind the
## same port while the owner lives, and the OS closes it when the owner exits or is killed. It is
## never taken over by age or process ID. No file is written.
##
## Candidates: `CANDIDATES` ports taken from the SHA-256 of the canonical root, so two roots rarely
## share a port and a root always asks the same ports. They lie in 20000..32767, below every
## desktop ephemeral range: in the dynamic range Windows reserves whole blocks for Hyper-V (8 % of
## it on the development machine) and client sockets come and go, which would make a candidate
## unavailable at random. The holder listens on one candidate and a background thread answers
## every connection with `banner(root)` and closes it.
##
## `acquire` examines every candidate, in order:
## - A candidate this process can bind has no holder. The first one becomes the lock and is
##   answered from then on; later ones are released at once.
## - A candidate that cannot be bound is asked for its banner. This root's banner means a holder;
##   silence or another banner is unrelated software and is skipped.
## A connect is used only where the bind fails because, on Windows, a connect to a closed loopback
## port stays pending for seconds, while a successful exclusive bind is immediate proof.
## Every question is asked after this process answers on its own port, so of two simultaneous
## starters at least one sees the other. The one on the higher candidate yields at once; the one
## on the lower candidate waits a bounded time for it to go and yields if it stays (it was
## settled before this process bound a port that unrelated software had just freed).
## Self-checks before the lock is reported: the own port must answer with the banner over
## loopback and must refuse a second bind. A failed self-check, or no bindable candidate, is
## `unsupported`: the caller stays read-only and never falls back to another lock.
##
## Limits: a holder suspended longer than `BANNER_MSEC` looks like unrelated software to a second
## starter. A root reached through different links or drive aliases has different identities; the
## store therefore accepts only a plain folder under the user data directory.

const PROTOCOL := "openrc-creator-lock v1"
const ADDRESS := "127.0.0.1"
const CANDIDATES := 8
const PORT_FIRST := 20000
const PORT_COUNT := 12768

const STATUS_ACQUIRED := "acquired"
const STATUS_BUSY := "busy"
const STATUS_UNSUPPORTED := "unsupported"
const STATUS_ERROR := "error"

## A connect to a listening loopback port completes in the kernel without the listener's help
## (about 10 ms observed, one poll). Given up only after this time and `CONNECT_POLLS` polls.
const CONNECT_MSEC := 250
const CONNECT_POLLS := 4
## Time a connected candidate has to send its banner; the holder answers within `SERVE_MSEC`.
const BANNER_MSEC := 1500
const SERVE_MSEC := 4
## How long the lower of two simultaneous starters waits for the higher one to yield: longer
## than the higher one needs to ask every candidate and release.
const YIELD_MSEC := CONNECT_MSEC + BANNER_MSEC + 750
const YIELD_STEP_MSEC := 40
const _BANNER_BYTES := 128

const _HOLDER := "holder"
const _FOREIGN := "foreign"
const _CLOSED := "closed"

## Identity of a held root -> instance ID of its lock in this process.
static var _held := {}
static var _guard := Mutex.new()

var _identity := ""
var _instance := 0
var _port := 0
var _server: TCPServer
var _thread: Thread
var _responder: Responder


## Absolute root with forward slashes and no trailing slash; "" when it is not absolute.
## Case is folded where the usual file systems ignore it.
static func canonical_root(root: String) -> String:
	var path := root
	if path.begins_with("user://") or path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	path = path.replace("\\", "/").simplify_path()
	while path.length() > 1 and path.ends_with("/"):
		path = path.substr(0, path.length() - 1)
	if not path.is_absolute_path():
		return ""
	if OS.get_name() in ["Windows", "macOS"]:
		path = path.to_lower()
	return path


## SHA-256 of the canonical root, lowercase hex; "" for an unusable root.
static func identity(root: String) -> String:
	var canonical := canonical_root(root)
	if canonical.is_empty():
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(canonical.to_utf8_buffer())
	return hashing.finish().hex_encode()


## The line a holder sends: protocol, root identity, LF.
static func banner(root: String) -> String:
	return "%s %s\n" % [PROTOCOL, identity(root)]


## The fixed candidate series of a root: distinct ports from consecutive digest byte pairs.
static func candidate_ports(root: String) -> PackedInt32Array:
	var ports := PackedInt32Array()
	var digest := identity(root).hex_decode()
	var at := 0
	while ports.size() < CANDIDATES and at + 1 < digest.size():
		var candidate := PORT_FIRST + ((digest[at] << 8) | digest[at + 1]) % PORT_COUNT
		if not ports.has(candidate):
			ports.append(candidate)
		at += 2
	return ports


## Returns `{status, lock, port, detail}`. `status` is "acquired", "busy", "unsupported" or
## "error". `lock` is the lock object when acquired, otherwise null: it has `release()` and
## `is_held()` and releases when freed. `port` is the holder's port when known, else 0. `detail`
## is English, for logs. A second acquire of a root this process already holds is "busy".
static func acquire(root: String) -> Dictionary:
	var root_identity := identity(root)
	if root_identity.is_empty():
		return _outcome(STATUS_ERROR, null, 0, "The store root is not an absolute path.")
	var ports := candidate_ports(root)
	var line: PackedByteArray = banner(root).to_ascii_buffer()
	var own_script: Script = load("res://workshop/creator/process_lock.gd")
	_guard.lock()
	var holder: Variant = _held.get(root_identity)
	if holder != null and is_instance_id_valid(holder):
		var other: Object = instance_from_id(holder)
		_guard.unlock()
		return _outcome(STATUS_BUSY, null, int(other.call("listening_port")), "This process already holds the lock.")
	# Reserved before any port is bound so two threads of one process cannot both proceed.
	var lock: RefCounted = own_script.new()
	lock._instance = lock.get_instance_id()
	lock._identity = root_identity
	_held[root_identity] = lock._instance
	_guard.unlock()

	var own := -1
	var blocked := PackedInt32Array()
	for index: int in ports.size():
		var server := TCPServer.new()
		if server.listen(ports[index], ADDRESS) != OK:
			blocked.append(index)
		elif own >= 0:
			server.stop()
		else:
			own = index
			if not lock._serve(server, ports[index], line):
				lock.release()
				return _outcome(STATUS_ERROR, null, 0, "The lock responder thread could not start.")
	var asked := PackedInt32Array()
	for index: int in blocked:
		asked.append(ports[index])
	if own >= 0:
		asked.append(ports[own])
	var answers := _ask(asked, line)

	var holders := PackedInt32Array()
	for index: int in blocked:
		if answers[ports[index]] == _HOLDER:
			holders.append(index)
	if own < 0:
		lock.release()
		if not holders.is_empty():
			return _outcome(STATUS_BUSY, null, ports[holders[0]], "Another process holds the lock.")
		return _outcome(STATUS_UNSUPPORTED, null, 0, "No candidate port could be bound.")
	if answers[ports[own]] != _HOLDER:
		lock.release()
		return _outcome(STATUS_UNSUPPORTED, null, 0, "The own lock port did not answer over loopback.")
	var twin := TCPServer.new()
	if twin.listen(ports[own], ADDRESS) == OK:
		twin.stop()
		lock.release()
		return _outcome(STATUS_UNSUPPORTED, null, 0, "This platform let a second listener bind the lock port.")
	var waited := 0
	while not holders.is_empty():
		if holders[0] < own or waited >= YIELD_MSEC:
			var holder_port := ports[holders[0]]
			lock.release()
			return _outcome(STATUS_BUSY, null, holder_port, "Another process holds the lock.")
		# Only higher candidates answered: simultaneous starters yield to this one, or one is settled.
		OS.delay_msec(YIELD_STEP_MSEC)
		waited += YIELD_STEP_MSEC
		holders = _still_held(ports, holders, line)
	return _outcome(STATUS_ACQUIRED, lock, ports[own], "")


func is_held() -> bool:
	return _server != null


func listening_port() -> int:
	return _port


## Stops answering, joins the thread and closes the listener. Safe to call twice.
func release() -> void:
	_shut_down(_responder, _thread, _server, _identity, _instance)
	_responder = null
	_thread = null
	_server = null
	_identity = ""


func _notification(what: int) -> void:
	# A dying RefCounted cannot call its own methods: only members and static code are used here.
	if what == NOTIFICATION_PREDELETE:
		_shut_down(_responder, _thread, _server, _identity, _instance)


static func _shut_down(responder: Responder, thread: Thread, server: TCPServer, held_identity: String, instance: int) -> void:
	if responder != null:
		responder.halt()
	if thread != null and thread.is_started():
		thread.wait_to_finish()
	if server != null:
		server.stop()
	if not held_identity.is_empty():
		_guard.lock()
		if _held.get(held_identity) == instance:
			_held.erase(held_identity)
		_guard.unlock()


## Takes ownership of a listening server and answers on it from a background thread.
func _serve(server: TCPServer, bound_port: int, line: PackedByteArray) -> bool:
	_server = server
	_port = bound_port
	_responder = Responder.new()
	_responder.server = server
	_responder.line = line
	_thread = Thread.new()
	if _thread.start(_responder.run) != OK:
		_thread = null
		return false
	return true


static func _outcome(status: String, lock: RefCounted, holder_port: int, detail: String) -> Dictionary:
	return {status = status, lock = lock, port = holder_port, detail = detail}


## Which of the candidate indexes in `holders` still have a holder.
static func _still_held(ports: PackedInt32Array, holders: PackedInt32Array, line: PackedByteArray) -> PackedInt32Array:
	var asked := PackedInt32Array()
	for index: int in holders:
		var server := TCPServer.new()
		if server.listen(ports[index], ADDRESS) == OK:
			server.stop()
		else:
			asked.append(ports[index])
	var answers := _ask(asked, line)
	var remaining := PackedInt32Array()
	for index: int in holders:
		if answers.get(ports[index], _CLOSED) == _HOLDER:
			remaining.append(index)
	return remaining


## Connects to every port at once and classifies each: this root's banner, something else that
## accepted the connection, or nothing reachable. Returns port -> classification.
static func _ask(ports: PackedInt32Array, line: PackedByteArray) -> Dictionary:
	var answers := {}
	var asked: Array[Dictionary] = []
	var started := Time.get_ticks_msec()
	for candidate: int in ports:
		var peer := StreamPeerTCP.new()
		if peer.connect_to_host(ADDRESS, candidate) == OK:
			asked.append({peer = peer, port = candidate, connected_at = -1, polls = 0, received = PackedByteArray()})
		else:
			answers[candidate] = _CLOSED
	while not asked.is_empty():
		var waiting: Array[Dictionary] = []
		for entry: Dictionary in asked:
			var peer: StreamPeerTCP = entry.peer
			peer.poll()
			entry.polls = int(entry.polls) + 1
			var status := peer.get_status()
			var now := Time.get_ticks_msec()
			var received: PackedByteArray = entry.received
			var verdict := ""
			if status == StreamPeerTCP.STATUS_CONNECTED:
				if int(entry.connected_at) < 0:
					entry.connected_at = now
				var available := peer.get_available_bytes()
				if available > 0:
					var read: Array = peer.get_partial_data(mini(available, _BANNER_BYTES - received.size()))
					if read[0] == OK:
						received.append_array(read[1])
						entry.received = received
				if received.size() >= line.size() or received.has(0x0A):
					verdict = _HOLDER if received == line else _FOREIGN
				elif now - int(entry.connected_at) > BANNER_MSEC:
					verdict = _FOREIGN
			elif status == StreamPeerTCP.STATUS_CONNECTING:
				if now - started > CONNECT_MSEC and int(entry.polls) >= CONNECT_POLLS:
					verdict = _CLOSED
			elif int(entry.connected_at) >= 0:
				# The other side closed: a holder has sent its whole banner before that.
				verdict = _HOLDER if received == line else _FOREIGN
			else:
				verdict = _CLOSED
			if verdict.is_empty():
				waiting.append(entry)
			else:
				answers[int(entry.port)] = verdict
				peer.disconnect_from_host()
		asked = waiting
		if not asked.is_empty():
			OS.delay_msec(1)
	return answers


## Answers connections on the lock port until halted. Runs on the lock's thread; the main thread
## touches the server again only after joining it.
class Responder extends RefCounted:
	var server: TCPServer
	var line: PackedByteArray
	var _halted := false
	var _mutex := Mutex.new()

	func halt() -> void:
		_mutex.lock()
		_halted = true
		_mutex.unlock()

	func halted() -> bool:
		_mutex.lock()
		var value := _halted
		_mutex.unlock()
		return value

	func run() -> void:
		while not halted():
			if server.is_connection_available():
				var peer := server.take_connection()
				if peer != null:
					peer.put_data(line)
					peer.disconnect_from_host()
			else:
				OS.delay_msec(SERVE_MSEC)
