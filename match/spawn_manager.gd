class_name SpawnManager
extends RefCounted

## Менеджер интеллектуального распределения спавнов TANKUS.
## Реализует алгоритм максимального взаимного разведения (Farthest Point Sampling / Max-Min Distance)
## для режима FFA и кластеризацию баз для командных режимов.

static func assign_spawns(players: Array, spawn_points: Array[Marker3D], is_team_mode: bool) -> Dictionary:
	var result: Dictionary = {} # peer_id: int -> Transform3D
	if players.is_empty() or spawn_points.is_empty():
		return result

	var valid_players: Array[PlayerInfo] = []
	for p in players:
		if p is PlayerInfo:
			valid_players.append(p)

	if valid_players.is_empty():
		return result

	if not is_team_mode:
		return _assign_spawns_ffa(valid_players, spawn_points)
	else:
		return _assign_spawns_teams(valid_players, spawn_points)

## Алгоритм Farthest Point Sampling для FFA
static func _assign_spawns_ffa(players: Array[PlayerInfo], spawn_points: Array[Marker3D]) -> Dictionary:
	var result: Dictionary = {}
	var n_players := players.size()
	var n_points := spawn_points.size()

	var selected_indices: Array[int] = []

	# Первый игрок берет нулевую точку (или фиксированную первую)
	selected_indices.append(0)

	# Жадный выбор каждой последующей точки с максимизацией минимальной дистанции до уже выбранных
	while selected_indices.size() < n_players and selected_indices.size() < n_points:
		var best_idx := -1
		var best_min_dist_sq := -1.0

		for cand_idx in range(n_points):
			if selected_indices.has(cand_idx):
				continue

			var cand_pos := spawn_points[cand_idx].global_position

			# Ищем минимальную дистанцию от кандидата до всех уже выбранных точек
			var min_dist_sq := INF
			for sel_idx in selected_indices:
				var sel_pos := spawn_points[sel_idx].global_position
				var d_sq := cand_pos.distance_squared_to(sel_pos)
				if d_sq < min_dist_sq:
					min_dist_sq = d_sq

			if min_dist_sq > best_min_dist_sq:
				best_min_dist_sq = min_dist_sq
				best_idx = cand_idx

		if best_idx >= 0:
			selected_indices.append(best_idx)
		else:
			break

	# Назначаем игрокам выбранные спавны
	for i in range(players.size()):
		var pt_idx := selected_indices[i % selected_indices.size()]
		result[players[i].peer_id] = spawn_points[pt_idx].global_transform

	return result

## Кластеризация баз для командного режима (Teams)
static func _assign_spawns_teams(players: Array[PlayerInfo], spawn_points: Array[Marker3D]) -> Dictionary:
	var result: Dictionary = {}
	var n_points := spawn_points.size()

	# Группируем игроков по командам
	var teams: Dictionary = {} # team_id: int -> Array[PlayerInfo]
	for p in players:
		if not teams.has(p.team_id):
			teams[p.team_id] = []
		teams[p.team_id].append(p)

	var team_ids: Array = teams.keys()
	team_ids.sort()

	# Находим противоположные опорные точки для команд (максимально удаленные центры баз)
	var team_base_indices: Dictionary = {} # team_id -> int
	var used_points: Array[int] = []

	# Для 1-й команды база — точка 0
	if not team_ids.is_empty():
		team_base_indices[team_ids[0]] = 0
		used_points.append(0)

	# Для остальных команд находим максимально удаленные точки от предыдущих баз
	for t_idx in range(1, team_ids.size()):
		var current_tid = team_ids[t_idx]
		var best_idx := -1
		var best_dist_sq := -1.0

		for cand_idx in range(n_points):
			if used_points.has(cand_idx):
				continue

			var min_d_sq := INF
			for base_tid in team_base_indices.keys():
				var base_idx: int = team_base_indices[base_tid]
				var d_sq := spawn_points[cand_idx].global_position.distance_squared_to(spawn_points[base_idx].global_position)
				if d_sq < min_d_sq:
					min_d_sq = d_sq

			if min_d_sq > best_dist_sq:
				best_dist_sq = min_d_sq
				best_idx = cand_idx

		if best_idx >= 0:
			team_base_indices[current_tid] = best_idx
			used_points.append(best_idx)
		else:
			team_base_indices[current_tid] = t_idx % n_points

	# Для каждого игрока команды подбираем ближайшие точки к базе его команды
	var assigned_points: Array[int] = []

	for tid in team_ids:
		var base_idx: int = team_base_indices[tid]
		var base_pos := spawn_points[base_idx].global_position
		var team_players: Array = teams[tid]

		# Сортируем все точки карты по близости к базе этой команды
		var sorted_indices: Array[int] = []
		for i in range(n_points):
			sorted_indices.append(i)

		sorted_indices.sort_custom(func(a: int, b: int) -> bool:
			var da := spawn_points[a].global_position.distance_squared_to(base_pos)
			var db := spawn_points[b].global_position.distance_squared_to(base_pos)
			return da < db
		)

		# Выбираем ближайшие свободные точки для участников команды
		for player in team_players:
			var chosen_idx := -1
			for idx in sorted_indices:
				if not assigned_points.has(idx):
					chosen_idx = idx
					break

			if chosen_idx == -1:
				chosen_idx = sorted_indices[0] # fallback

			assigned_points.append(chosen_idx)
			result[player.peer_id] = spawn_points[chosen_idx].global_transform

	return result

## Вспомогательный метод для одиночного режима или fallback
static func get_fallback_transform(slot: int, spawn_points: Array[Marker3D]) -> Transform3D:
	if spawn_points.is_empty():
		return Transform3D.IDENTITY
	return spawn_points[slot % spawn_points.size()].global_transform
