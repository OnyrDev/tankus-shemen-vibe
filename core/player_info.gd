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
