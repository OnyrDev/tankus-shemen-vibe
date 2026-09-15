extends Node

signal match_state_changed(new_state: String)
signal round_started(round_number: int)
signal round_ended(winner_team_or_peer: int)
signal match_ended(winner_team_or_peer: int)

var rules: MatchRules = MatchRules.new()
var current_round: int = 0
var is_in_match: bool = false
var match_state: String = "IDLE" # IDLE, LOBBY, PREPARE, COUNTDOWN, PLAYING, ROUND_END, DRAFT, MATCH_END

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

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
