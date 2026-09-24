class_name PauseMenu
extends CanvasLayer

## Внутриигровое меню паузы TANKUS.
## Предоставляет игроку возможность продолжить бой, перезапустить танки,
## открыть сетевое лобби или выйти в Главное Меню.

signal resumed()
signal respawn_requested()
signal open_lan_requested()

@onready var panel_container: PanelContainer = $CenterContainer/Panel
@onready var btn_resume: Button = $CenterContainer/Panel/Margin/VBox/BtnResume
@onready var btn_respawn: Button = $CenterContainer/Panel/Margin/VBox/BtnRespawn
@onready var btn_lan: Button = $CenterContainer/Panel/Margin/VBox/BtnLAN
@onready var btn_main_menu: Button = $CenterContainer/Panel/Margin/VBox/BtnMainMenu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if btn_resume:
		btn_resume.pressed.connect(_on_btn_resume_pressed)
		btn_resume.mouse_entered.connect(_play_hover)
	if btn_respawn:
		btn_respawn.pressed.connect(_on_btn_respawn_pressed)
		btn_respawn.mouse_entered.connect(_play_hover)
	if btn_lan:
		btn_lan.pressed.connect(_on_btn_lan_pressed)
		btn_lan.mouse_entered.connect(_play_hover)
	if btn_main_menu:
		btn_main_menu.pressed.connect(_on_btn_main_menu_pressed)
		btn_main_menu.mouse_entered.connect(_play_hover)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if btn_resume:
		btn_resume.grab_focus()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()

func is_open() -> bool:
	return visible

func _on_btn_resume_pressed() -> void:
	_play_click()
	close()

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

func _play_hover() -> void:
	if SoundManager:
		SoundManager.play_sfx("card_hover", -6.0)

func _play_click() -> void:
	if SoundManager:
		SoundManager.play_sfx("card_select", -2.0)
