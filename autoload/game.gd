extends Node

signal match_state_changed(new_state: String)
signal round_started(round_number: int)
signal round_ended(winner_team_or_peer: int)
signal match_ended(winner_team_or_peer: int)
signal camera_shake_requested(intensity: float)

var rules: MatchRules = MatchRules.new()
var current_round: int = 0
var is_in_match: bool = false
var is_solo_practice: bool = false
var match_state: String = "IDLE" # IDLE, LOBBY, PREPARE, COUNTDOWN, PLAYING, ROUND_END, DRAFT, MATCH_END

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func return_to_main_menu() -> void:
	is_solo_practice = false
	is_in_match = false
	current_round = 0
	set_match_state("IDLE")
	if Network.is_multiplayer_active() or Network.is_host:
		Network.disconnect_session()
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://ui/main_menu.tscn")

func set_match_state(new_state: String) -> void:
	match_state = new_state
	match_state_changed.emit(new_state)

func start_new_match(p_rules: MatchRules = null) -> void:
	if p_rules:
		rules = p_rules
	current_round = 0
	is_in_match = true
	set_match_state("PREPARE")

func reset_match() -> void:
	current_round = 0
	is_in_match = false
	set_match_state("LOBBY")

func shake_camera(intensity: float = 0.5) -> void:
	camera_shake_requested.emit(intensity)
