extends Node

func _ready() -> void:
	print("--- TEST MUSIC MANAGER STARTUP ---")

	assert(MusicManager != null, "MusicManager autoload должен существовать")
	print("[PASS] MusicManager существует")

	var bus_idx := AudioServer.get_bus_index("Music")
	assert(bus_idx != -1, "Шина 'Music' должна быть зарегистрирована в AudioServer")
	print("[PASS] Шина 'Music' зарегистрирована с индексом: %d" % bus_idx)

	assert(MusicManager.get_current_stream() != null, "Тема меню должна быть загружена")
	print("[PASS] Аудиопоток меню загружен: %s" % MusicManager.get_current_stream().resource_path)

	if MusicManager.get_current_stream() is AudioStreamOggVorbis:
		var ogg := MusicManager.get_current_stream() as AudioStreamOggVorbis
		assert(ogg.loop == true, "Файл OGG должен иметь включенный луп")
		print("[PASS] Зацикливание (loop) включено на стриме")

	# Проверяем методы громкости
	MusicManager.set_music_volume_linear(0.5)
	var vol := MusicManager.get_music_volume_linear()
	assert(abs(vol - 0.5) < 0.05, "Громкость музыки должна корректно выставляться в шине")
	print("[PASS] Регулировка громкости шины работает (vol=%f)" % vol)

	# Проверяем остановку и повторный запуск
	MusicManager.stop_music(0.1)
	await get_tree().create_timer(0.2).timeout
	assert(not MusicManager.is_playing(), "После stop_music музыка должна остановиться")
	print("[PASS] stop_music корректно останавливает трек")

	MusicManager.play_menu_music(0.1)
	await get_tree().create_timer(0.2).timeout
	assert(MusicManager.is_playing(), "После play_menu_music музыка должна играть")
	print("[PASS] play_menu_music корректно запускает трек")

	print("\n>>> ВСЕ ТЕСТЫ MUSIC MANAGER УСПЕШНО ПРОЙДЕНЫ! <<<\n")
	get_tree().quit(0)
