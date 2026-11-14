extends SceneClassic
class_name SceneSuika

const BLOCKED_SPAWN_SIZES: Array[int] = [1, 2]
const FALLBACK_SIZE := 4
const MAX_SIZE := 4096
const POP_SHAKE := 50.0
const POP_ZOOM := -5
const POP_VALUE := MAX_SIZE * 2
const PAD_SPEED := 500.0
const PAD_MARGIN := 100.0

signal next_size_changed(size: int)

var next_size := -1
var popped_count := 0
var popping: Array = []
var achievements_before := false
var target_x := 0.0
var marker: Sprite2D

func _ready() -> void:
	super()
	float_bar.inwards_force = 0.0
	for size: int in BLOCKED_SPAWN_SIZES:
		spawn_pool.merges_required_to_unlock.erase(size)
	spawn_pool.current_spawn_pool.clear()
	spawn_pool.current_spawn_pool.append(FALLBACK_SIZE)
	roll_next_size()
	set_online_blocked(true)
	SignalBus.on_game_over.connect(_on_game_over)
	setup_marker()

func _physics_process(dt: float) -> void:
	if makes_decisions() and sobos_selectable.size() == 1 and PlayerInput.get_gameplay_input_device() == PlayerInput.InputDevice.GAMEPAD:
		hovered_sobo = sobos_selectable[0]
	super(dt)

func _process(delta: float) -> void:
	super._process(delta)
	var device := PlayerInput.get_gameplay_input_device()

	if device == PlayerInput.InputDevice.MOUSE:
		marker.hide()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			target_x = PlayerInput.cursor_pos.x
	elif device == PlayerInput.InputDevice.GAMEPAD:
		marker.show()
		if makes_decisions() and PlayerInput.accepting_in_game_input():
			var stick: Vector2 = PlayerInput.right_stick if SettingsManager.settings.swap_sticks else PlayerInput.left_stick
			target_x += stick.rotated(Cam._0.rotation).x * PAD_SPEED * delta
			var rect: Rect2 = world_play_area.get_global_rect()
			target_x = clampf(target_x, rect.position.x + PAD_MARGIN, rect.end.x - PAD_MARGIN)
		marker.global_position = Vector2(target_x, float_bar.global_position.y)
		marker.rotation = -Cam._0.rotation
	else:
		marker.hide()
		return

	for sobo: Sobo in float_bar.sobos:
		for suba: Suba in sobo.subas:
			suba.apply_central_force(Vector2((target_x - suba.global_position.x) * 5.0, 0.0))

func _on_game_over() -> void:
	ScoreManager.add_local_score("suika", ScoreManager.current_score)

func _exit_tree() -> void:
	if StyleManager.style_changed.is_connected(refresh_marker_texture):
		StyleManager.style_changed.disconnect(refresh_marker_texture)
	set_online_blocked(false)
	super()

func hover_sobo_in_dir(_dir: Vector2) -> void:
	pass

func setup_marker() -> void:
	marker = Sprite2D.new()
	marker.centered = false
	marker.scale = Vector2(0.75, 0.75)
	marker.z_as_relative = false
	marker.z_index = -1
	marker.visible = false
	add_child(marker)
	StyleManager.style_changed.connect(refresh_marker_texture)
	refresh_marker_texture()

func refresh_marker_texture() -> void:
	if marker == null:
		return
	marker.texture = StyleManager.current_style.cursor_texture
	var hotspot: Vector2 = ProjectSettings.get_setting("display/mouse_cursor/custom_image_hotspot")
	marker.offset = -hotspot

func set_online_blocked(blocked: bool) -> void:
	var connected: bool = SignalBus.on_game_over.is_connected(ScoreManager.on_game_over)
	if blocked:
		achievements_before = AchievementTracker.disable_achievements
		AchievementTracker.disable_achievements = true
		if connected:
			SignalBus.on_game_over.disconnect(ScoreManager.on_game_over)
	else:
		AchievementTracker.disable_achievements = achievements_before
		if not connected:
			var others: Array = SignalBus.on_game_over.get_connections()
			for c: Dictionary in others:
				SignalBus.on_game_over.disconnect(c.callable)
			SignalBus.on_game_over.connect(ScoreManager.on_game_over)
			for c: Dictionary in others:
				SignalBus.on_game_over.connect(c.callable, c.flags)

func apply_game_state(new_state: GameState) -> void:
	super(new_state)
	popped_count = 0
	popping.clear()
	var board_sum := calculate_score()
	popped_count = maxi(ScoreManager.current_score - board_sum, 0) / POP_VALUE
	roll_next_size()

func pop_camera_kick() -> void:
	Cam._0.vibrate(POP_SHAKE)
	Cam._0.push_zoom(POP_ZOOM)

func calculate_score() -> int:
	popping = popping.filter(is_instance_valid)
	var sum := popped_count * POP_VALUE
	for s: Sobo in SoboManager.all_sobos:
		if s.merged == false: continue
		if s.merged_this_frame: continue
		if popping.has(s): continue
		sum += s.data.size
	return sum

func on_clutter_spawned(sobo: Sobo) -> void:
	if sobo.data.size in BLOCKED_SPAWN_SIZES:
		sobo.queue_free()
		return
	super(sobo)

func roll_next_size() -> void:
	var rolled := spawn_pool.get_size(BLOCKED_SPAWN_SIZES)
	if rolled == -1:
		rolled = FALLBACK_SIZE
	next_size = rolled
	next_size_changed.emit(next_size)

func take_next_size() -> int:
	if next_size == -1:
		roll_next_size()
	var taken := next_size
	roll_next_size()
	return taken

func get_safety_spawn_size() -> int:
	return take_next_size()

func spawn_sobo_on_side(side: ClassicSide, size := -1, replay_id := 0) -> Sobo:
	if makes_decisions():
		if float_bar.sobos.size() > 0:
			return null
		if size == -1:
			size = take_next_size()
	return super(side, size, replay_id)

func on_sobo_merge(old_sobo0: Sobo, old_sobo1: Sobo, new_sobo: Sobo) -> void:
	if old_sobo0.data.size >= MAX_SIZE and old_sobo1.data.size >= MAX_SIZE:
		if launching_sobo == old_sobo0 or launching_sobo == old_sobo1:
			launching_sobo = null
			launching = false
			Ui._0.mouse_hovering_disabled = false
		if hovered_sobo == old_sobo0 or hovered_sobo == old_sobo1:
			hovered_sobo = null
		remove_from_role_lists(old_sobo0)
		remove_from_role_lists(old_sobo1)
		pop_camera_kick()
		popping.append_array([old_sobo0, old_sobo1, new_sobo])
		new_sobo.queue_free()
		popped_count += 1
		var new_score := calculate_score()
		if new_score != ScoreManager.current_score:
			SignalBus.on_gain_score.emit(new_score - ScoreManager.current_score)
		return
	super(old_sobo0, old_sobo1, new_sobo)
