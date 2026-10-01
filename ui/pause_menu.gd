class_name PauseMenu
extends CanvasLayer

## Внутриигровое меню паузы TANKUS.
## Предоставляет игроку возможность продолжить бой, настроить звуки/графику,
## перезапустить танки, открыть сетевое лобби или выйти в Главное Меню.

signal resumed()
signal respawn_requested()
signal open_lan_requested()

# --- Контейнеры меню ---
@onready var panel_container: PanelContainer = $CenterContainer/Panel
@onready var main_vbox: VBoxContainer = %MainVBox
@onready var settings_vbox: VBoxContainer = %SettingsVBox

# --- Главные кнопки ---
@onready var btn_resume: Button = %BtnResume
@onready var btn_settings: Button = %BtnSettings
@onready var btn_respawn: Button = %BtnRespawn
@onready var btn_lan: Button = %BtnLAN
@onready var btn_main_menu: Button = %BtnMainMenu

# --- Элементы настроек ---
@onready var slider_game_sfx: HSlider = %SliderGameSFX
@onready var lbl_game_sfx_val: Label = %LblGameSFXVal
@onready var slider_menu_sfx: HSlider = %SliderMenuSFX
@onready var lbl_menu_sfx_val: Label = %LblMenuSFXVal
@onready var slider_music: HSlider = %SliderMusic
@onready var lbl_music_val: Label = %LblMusicVal
@onready var chk_fullscreen: CheckBox = %ChkFullscreen
@onready var chk_vsync: CheckBox = %ChkVSync
@onready var btn_settings_back: Button = %BtnSettingsBack

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_connect_signals()
	_setup_button_audio_recursively(self)
	_sync_settings()
	_show_main_view()

func _connect_signals() -> void:
	if btn_resume:
		btn_resume.pressed.connect(_on_btn_resume_pressed)
	if btn_settings:
		btn_settings.pressed.connect(_on_btn_settings_pressed)
	if btn_respawn:
		btn_respawn.pressed.connect(_on_btn_respawn_pressed)
	if btn_lan:
		btn_lan.pressed.connect(_on_btn_lan_pressed)
	if btn_main_menu:
		btn_main_menu.pressed.connect(_on_btn_main_menu_pressed)
	if btn_settings_back:
		btn_settings_back.pressed.connect(_on_btn_settings_back_pressed)

	if slider_game_sfx:
		slider_game_sfx.value_changed.connect(_on_game_sfx_slider_changed)
	if slider_menu_sfx:
		slider_menu_sfx.value_changed.connect(_on_menu_sfx_slider_changed)
	if slider_music:
		slider_music.value_changed.connect(_on_music_slider_changed)
	if chk_fullscreen:
		chk_fullscreen.toggled.connect(_on_fullscreen_toggled)
	if chk_vsync:
		chk_vsync.toggled.connect(_on_vsync_toggled)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main_view()
	if btn_resume:
		btn_resume.grab_focus()

func close() -> void:
	visible = false
	_show_main_view()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()

func handle_cancel() -> void:
	if settings_vbox and settings_vbox.visible:
		_play_click()
		_show_main_view()
	else:
		close()

func is_open() -> bool:
	return visible

func _show_main_view() -> void:
	if main_vbox:
		main_vbox.visible = true
	if settings_vbox:
		settings_vbox.visible = false
	if btn_resume and visible:
		btn_resume.grab_focus()

func _show_settings_view() -> void:
	_sync_settings()
	if main_vbox:
		main_vbox.visible = false
	if settings_vbox:
		settings_vbox.visible = true
	if btn_settings_back and visible:
		btn_settings_back.grab_focus()

func _sync_settings() -> void:
	if SettingsManager:
		if slider_game_sfx:
			slider_game_sfx.value = SettingsManager.get_sfx_volume() * 100.0
			if lbl_game_sfx_val:
				lbl_game_sfx_val.text = "%d%%" % int(slider_game_sfx.value)

		if slider_menu_sfx:
			slider_menu_sfx.value = SettingsManager.get_ui_volume() * 100.0
			if lbl_menu_sfx_val:
				lbl_menu_sfx_val.text = "%d%%" % int(slider_menu_sfx.value)

		if slider_music:
			slider_music.value = SettingsManager.get_music_volume() * 100.0
			if lbl_music_val:
				lbl_music_val.text = "%d%%" % int(slider_music.value)

		if chk_fullscreen:
			chk_fullscreen.button_pressed = SettingsManager.is_fullscreen()
		if chk_vsync:
			chk_vsync.button_pressed = SettingsManager.is_vsync()
	else:
		# Fallback
		var sfx_bus := AudioServer.get_bus_index("SFX")
		if sfx_bus != -1 and slider_game_sfx:
			var db := AudioServer.get_bus_volume_db(sfx_bus)
			slider_game_sfx.value = db_to_linear(db) * 100.0
			if lbl_game_sfx_val:
				lbl_game_sfx_val.text = "%d%%" % int(slider_game_sfx.value)

		var ui_bus := AudioServer.get_bus_index("UI")
		if ui_bus != -1 and slider_menu_sfx:
			var db := AudioServer.get_bus_volume_db(ui_bus)
			slider_menu_sfx.value = db_to_linear(db) * 100.0
			if lbl_menu_sfx_val:
				lbl_menu_sfx_val.text = "%d%%" % int(slider_menu_sfx.value)

		var music_bus := AudioServer.get_bus_index("Music")
		if music_bus != -1 and slider_music:
			var db := AudioServer.get_bus_volume_db(music_bus)
			slider_music.value = db_to_linear(db) * 100.0
			if lbl_music_val:
				lbl_music_val.text = "%d%%" % int(slider_music.value)

		if chk_fullscreen:
			chk_fullscreen.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
		if chk_vsync and DisplayServer.get_name() != "headless":
			chk_vsync.button_pressed = (DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)

func _on_game_sfx_slider_changed(val: float) -> void:
	if SettingsManager:
		SettingsManager.set_sfx_volume(val / 100.0)
	elif SoundManager:
		SoundManager.set_sfx_volume_linear(val / 100.0)
	if lbl_game_sfx_val:
		lbl_game_sfx_val.text = "%d%%" % int(val)

func _on_menu_sfx_slider_changed(val: float) -> void:
	if SettingsManager:
		SettingsManager.set_ui_volume(val / 100.0)
	elif SoundManager:
		SoundManager.set_ui_volume_linear(val / 100.0)
	if lbl_menu_sfx_val:
		lbl_menu_sfx_val.text = "%d%%" % int(val)

func _on_music_slider_changed(val: float) -> void:
	if SettingsManager:
		SettingsManager.set_music_volume(val / 100.0)
	elif MusicManager:
		MusicManager.set_music_volume_linear(val / 100.0)
	if lbl_music_val:
		lbl_music_val.text = "%d%%" % int(val)

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	_play_click()
	if SettingsManager:
		SettingsManager.set_fullscreen(toggled_on)
	elif toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(toggled_on: bool) -> void:
	_play_click()
	if SettingsManager:
		SettingsManager.set_vsync(toggled_on)
	elif DisplayServer.get_name() != "headless":
		var vsync_mode := DisplayServer.VSYNC_ENABLED if toggled_on else DisplayServer.VSYNC_DISABLED
		DisplayServer.window_set_vsync_mode(vsync_mode)

func _on_btn_resume_pressed() -> void:
	_play_click()
	close()

func _on_btn_settings_pressed() -> void:
	_play_click()
	_show_settings_view()

func _on_btn_settings_back_pressed() -> void:
	_play_click()
	_show_main_view()

func _on_btn_respawn_pressed() -> void:
	_play_click()
	respawn_requested.emit()
	close()

func _on_btn_lan_pressed() -> void:
	_play_click()
	visible = false
	open_lan_requested.emit()

func _on_btn_main_menu_pressed() -> void:
	_play_click()
	visible = false
	Game.return_to_main_menu()

func _setup_button_audio_recursively(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var btn := child as Button
			if not btn.mouse_entered.is_connected(_play_hover):
				btn.mouse_entered.connect(_play_hover)
		_setup_button_audio_recursively(child)

func _play_hover() -> void:
	if SoundManager:
		SoundManager.play_sfx("card_hover", -6.0)

func _play_click() -> void:
	if SoundManager:
		SoundManager.play_sfx("card_select", -2.0)
