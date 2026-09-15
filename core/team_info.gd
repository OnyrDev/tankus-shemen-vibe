class_name TeamInfo
extends RefCounted

var team_id: int = 0
var team_name: String = "Team 1"
var team_color: Color = Color(0.2, 0.6, 1.0)
var round_wins: int = 0

func _init(p_id: int = 0, p_name: String = "Team 1", p_color: Color = Color.DODGER_BLUE) -> void:
	team_id = p_id
	team_name = p_name
	team_color = p_color
