class_name PlayerInfo
extends RefCounted

var peer_id: int = 1
var player_name: String = "Player"
var team_id: int = 0
var is_ready: bool = false
var round_wins: int = 0
var is_alive: bool = true
var ping_ms: int = 0

func _init(p_peer_id: int = 1, p_name: String = "Player", p_team: int = 0) -> void:
	peer_id = p_peer_id
	player_name = p_name
	team_id = p_team

func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"player_name": player_name,
		"team_id": team_id,
		"is_ready": is_ready,
		"round_wins": round_wins,
		"is_alive": is_alive,
		"ping_ms": ping_ms
	}

static func from_dict(d: Dictionary) -> PlayerInfo:
	var info := PlayerInfo.new(
		d.get("peer_id", 1),
		d.get("player_name", "Player"),
		d.get("team_id", 0)
	)
	info.is_ready = d.get("is_ready", false)
	info.round_wins = d.get("round_wins", 0)
	info.is_alive = d.get("is_alive", true)
	info.ping_ms = d.get("ping_ms", 0)
	return info
