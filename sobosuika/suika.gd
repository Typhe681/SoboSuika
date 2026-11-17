extends Node

const MEDIA_DIR := "user://sobosuika/"
const MODE_NAME := "mode_suika"
const CFG := "user://suika.cfg"
const BUBBLE_PATH := "user://sobosuika/bubble.png"

const TITLE_PATH := "/root/Main/Ui/MainHBox/LeftSidePanel/Control/DftLabel"
const TITLE := "sobosuika"

const MIN_SIZE := 4
const MAX_SIZE := 4096

const PREVIEW_SIZE := 100
const PREVIEW_OFFSET_X := 45
const PREVIEW_OFFSET_Y := 20
const PREVIEW_Z := 100
const PREVIEW_FILL := 0.5

var textures: Dictionary = {}
var regions: Dictionary = {}
var shader: Shader
var mode_res: GameMode
var patched_sobos: Dictionary = {}
var original_materials: Dictionary = {}

var preview: Control
var preview_image: TextureRect
var bubble_texture: Texture2D
var title_label: Node
var hide_numbers := true
var hidden_labels: Dictionary = {}
var preview_size_shown := -1

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D sobo_texture;
uniform vec2 uv_offset;
uniform vec2 uv_scale;
uniform bool flipped_screen;
uniform vec2 sobo_center;
uniform vec2 sobo_bounds_size;
uniform float sobo_rotation;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 local_position = world_position - sobo_center;

	if (flipped_screen) {
		local_position = -local_position;
	}

	float c = cos(-sobo_rotation);
	float s = sin(-sobo_rotation);
	local_position = mat2(vec2(c, -s), vec2(s, c)) * local_position;

	vec2 rotated_bounds = vec2(
		abs(c) * sobo_bounds_size.x + abs(s) * sobo_bounds_size.y,
		abs(s) * sobo_bounds_size.x + abs(c) * sobo_bounds_size.y
	);

	float side = max(rotated_bounds.x, rotated_bounds.y);
	vec2 uv = local_position / side + vec2(0.5);

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		discard;
	}
	COLOR = texture(sobo_texture, uv_offset + uv * uv_scale);
}
"""

func _ready() -> void:
	process_priority = 100

	load_config()

	shader = Shader.new()
	shader.code = SHADER_CODE
	load_textures()
	register_mode()

func load_config() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	hide_numbers = bool(cf.get_value("suika", "hide_numbers", true))
	cf.set_value("suika", "hide_numbers", hide_numbers)
	cf.save(CFG)

func register_mode() -> void:
	mode_res = GameMode.new()
	mode_res.scene_path = "res://game_mode/game_modes/suika/scene_suika.tscn"
	mode_res.description = "Classic, but with fruit!"
	mode_res.leaderboard_id = "suika"
	mode_res.horizontal = true
	mode_res.allows_start_clutter = true
	mode_res.take_over_path("res://game_mode/game_modes/suika/%s.tres" % MODE_NAME)
	GameModeManager.game_modes.append(mode_res)
	GameModeManager.game_modes_by_name[MODE_NAME] = mode_res
	Console.add_suggestion(MODE_NAME, "game mode")

func load_textures() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(MEDIA_DIR)
	)

	var size := MIN_SIZE
	while size <= MAX_SIZE:
		var path := MEDIA_DIR + str(size) + ".png"
		if not FileAccess.file_exists(path):
			push_warning("SoboSuika: missing " + path)
		else:
			var image := Image.load_from_file(path)
			if image == null:
				push_error("SoboSuika: failed to load image: " + path)
			else:
				textures[size] = ImageTexture.create_from_image(image)
				regions[size] = default_region(image.get_size())
		size *= 2

	if not FileAccess.file_exists(BUBBLE_PATH):
		push_warning("SoboSuika: missing " + BUBBLE_PATH)
	else:
		var image := Image.load_from_file(BUBBLE_PATH)
		if image == null:
			push_error("SoboSuika: failed to load image: " + BUBBLE_PATH)
		else:
			bubble_texture = ImageTexture.create_from_image(image)

func default_region(img_size: Vector2i) -> Rect2:
	var side := mini(img_size.x, img_size.y)
	return Rect2(
		(img_size.x - side) / 2.0,
		img_size.y - side,
		side,
		side
	)

func get_sobo_local_bounds(sobo: Sobo) -> Dictionary:
	var points = sobo.get_draw_polygon_points()
	if points.is_empty():
		return {"center": sobo.get_visual_center(), "size": Vector2.ZERO}

	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]

	for point: Vector2 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)

	var rect := Rect2(min_point, max_point - min_point).grow(10.0)

	return {
		"center": rect.get_center(),
		"size": rect.size
	}

func preview_thing(scene: Node) -> bool:
	if is_instance_valid(preview) and preview.get_parent() == scene:
		return true
	if is_instance_valid(preview):
		preview.queue_free()

	preview = Control.new()
	preview.name = "SuikaNextSobo"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.pivot_offset = preview.size * 0.5
	preview.z_index = PREVIEW_Z
	scene.add_child(preview)

	preview_image = TextureRect.new()
	preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_SCALE
	preview.add_child(preview_image)

	if bubble_texture != null:
		var bubble := TextureRect.new()
		bubble.name = "Bubble"
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.texture = bubble_texture
		bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.add_child(bubble)
		bubble.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	preview_size_shown = -1
	return true

func place_preview(scene: Node) -> void:
	var rect: Rect2 = scene.world_play_area.get_global_rect()
	var box := Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	var center := Vector2(
		rect.end.x + PREVIEW_OFFSET_X,
		rect.position.y + PREVIEW_OFFSET_Y
	) + box * 0.5
	var flipped: bool = SettingsManager.settings.flipped_screen
	if flipped:
		center = rect.get_center() * 2.0 - center
	preview.rotation = PI if flipped else 0.0
	preview.position = (scene as Node2D).to_local(center) - box * 0.5

func layout_preview(size: int) -> void:
	var tex: Texture2D = textures[size]
	var region: Rect2 = regions[size]
	var scale := PREVIEW_SIZE * PREVIEW_FILL / region.size.x
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	preview_image.texture = tex
	preview_image.size = tex_size * scale
	preview_image.position = Vector2(PREVIEW_SIZE, PREVIEW_SIZE) * 0.5 - region.get_center() * scale

func update_preview(scene: Node, active: bool) -> void:
	var want := -1
	if active and "next_size" in scene and "world_play_area" in scene:
		want = scene.next_size

	if want == -1 or not textures.has(want):
		if is_instance_valid(preview):
			preview.hide()
		return

	if not preview_thing(scene):
		return
	preview.show()
	place_preview(scene)
	if preview_size_shown != want:
		layout_preview(want)
		preview_size_shown = want

func hide_labels() -> void:
	for sobo in SoboManager.all_sobos:
		if not is_instance_valid(sobo) or not is_instance_valid(sobo.sobo_label):
			continue
		if sobo.sobo_label.visible:
			sobo.sobo_label.visible = false
			hidden_labels[sobo] = true

func restore_labels() -> void: #for possible setting toggle later
	if hidden_labels.is_empty():
		return
	for sobo in hidden_labels.keys():
		if is_instance_valid(sobo) and is_instance_valid(sobo.sobo_label):
			sobo.sobo_label.visible = true
	hidden_labels.clear()

func update_title() -> void:
	if not is_instance_valid(title_label):
		title_label = get_node_or_null(TITLE_PATH)
		if title_label == null:
			return
	if title_label.get("text") != TITLE:
		title_label.set("text", TITLE)

func _process(_delta: float) -> void:
	var scene = GameModeManager.current_scene
	var active: bool = scene != null and GameModeManager.current_mode_name == MODE_NAME

	update_preview(scene, active)
	update_title()

	if not active:
		return

	if hide_numbers:
		hide_labels()

	if textures.is_empty():
		return

	for sobo in SoboManager.all_sobos:
		if not is_instance_valid(sobo):
			continue
		if patched_sobos.has(sobo):
			continue
		var size: int = sobo.data.size
		if textures.has(size):
			patch_sobo(sobo, textures[size], regions[size])

	for sobo in patched_sobos.keys():
		if not is_instance_valid(sobo) or not SoboManager.all_sobos.has(sobo):
			if is_instance_valid(sobo):
				sobo.set_material(original_materials.get(sobo))
			patched_sobos.erase(sobo)
			original_materials.erase(sobo)
			continue

		var mat: ShaderMaterial = patched_sobos[sobo]
		var rotation := 0.0
		var positions = sobo.get_positions()
		if not positions.is_empty():
			var relative: Vector2 = positions[0] - sobo.get_visual_center()
			rotation = relative.angle()
		mat.set_shader_parameter("sobo_rotation", rotation)

		var b := get_sobo_local_bounds(sobo)
		mat.set_shader_parameter("sobo_center", b.center)
		mat.set_shader_parameter("sobo_bounds_size", b.size)
		mat.set_shader_parameter("flipped_screen", SettingsManager.settings.flipped_screen)

func patch_sobo(sobo: Sobo, tex: Texture2D, region: Rect2) -> void:
	original_materials[sobo] = sobo.get_material()

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("sobo_texture", tex)
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	mat.set_shader_parameter("uv_offset", region.position / tex_size)
	mat.set_shader_parameter("uv_scale", region.size / tex_size)
	sobo.set_material(mat)
	patched_sobos[sobo] = mat
