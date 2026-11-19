extends Node

const MEDIA_DIR := "user://sobosuika/"
const CUSTOM_DIR := MEDIA_DIR + "custom/"
const ORIGINAL_DIR := MEDIA_DIR + "original/"
const MODE_NAME := "mode_suika"
const CFG := "user://sobosuika.cfg"
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
const MESH_PADDING := 3.0
const SMOOTH := 2 # number of subdivisions, lag machine when high lol

var sprite_type := 0
var textures: Dictionary = {}
var regions: Dictionary = {}
var hide_material: ShaderMaterial
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

const HIDE_SHADER_CODE := """
shader_type canvas_item;
void fragment() { COLOR.a = 0.0; }
"""

func _ready() -> void:
	process_priority = 100

	load_config()

	var hide_shader := Shader.new()
	hide_shader.code = HIDE_SHADER_CODE
	hide_material = ShaderMaterial.new()
	hide_material.shader = hide_shader

	var broadcaster = get_tree().root.get_meta("modsettings_broadcaster", null)
	if broadcaster:
		broadcaster.config_changed.connect(_on_config_changed)

	load_textures()
	register_mode()

func load_config() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)

	hide_numbers = bool(cf.get_value("hide_numbers", "value", true))
	sprite_type = int(cf.get_value("sprite_type", "value", 0))

	cf.set_value("meta", "name", "SoboSuika")
	cf.set_value("meta", "description", "Configure your favorite fruit-filled gamemode :3")

	cf.set_value("hide_numbers", "type", "bool")
	cf.set_value("hide_numbers", "label", "hide numbers")
	cf.set_value("hide_numbers", "description", "Hides the number on each fruit")
	cf.set_value("hide_numbers", "value", hide_numbers)

	cf.set_value("sprite_type", "type", "choice")
	cf.set_value("sprite_type", "label", "sprite source")
	cf.set_value("sprite_type", "description", "Swaps which sprites are used")
	cf.set_value("sprite_type", "options", ["Custom", "Original"])
	cf.set_value("sprite_type", "value", sprite_type)

	cf.save(CFG)

func _on_config_changed(path: String, section: String, _value: Variant) -> void:
	if path != CFG:
		return

	var old_type := sprite_type
	load_config()

	if old_type != sprite_type:
		load_textures()
		repatch_sobos()

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
	textures.clear()
	regions.clear()
	bubble_texture = null

	var source_dir := CUSTOM_DIR if sprite_type == 0 else ORIGINAL_DIR

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(source_dir)
	)

	var size := MIN_SIZE
	while size <= MAX_SIZE:
		var path := source_dir + str(size) + ".png"
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

func repatch_sobos() -> void:
	for sobo in patched_sobos.keys():
		if not is_instance_valid(sobo):
			continue

		var mi: MeshInstance2D = patched_sobos[sobo]["mi"]
		if is_instance_valid(mi):
			mi.queue_free()

		sobo.set_material(original_materials.get(sobo))

	patched_sobos.clear()
	original_materials.clear()
	preview_size_shown = -1

func default_region(img_size: Vector2i) -> Rect2:
	var side := mini(img_size.x, img_size.y)
	return Rect2(
		(img_size.x - side) / 2.0,
		img_size.y - side,
		side,
		side
	)

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

func restore_labels() -> void:
	if hidden_labels.is_empty():
		return
	for sobo in hidden_labels.keys():
		if is_instance_valid(sobo) and is_instance_valid(sobo.sobo_label):
			sobo.sobo_label.visible = true
	hidden_labels.clear()

func update_title() -> void:
	if GameModeManager.current_mode_name != MODE_NAME or get_tree().paused:
		return

	if not is_instance_valid(title_label):
		title_label = get_node_or_null(TITLE_PATH)
		if title_label == null:
			return

	if title_label.text != TITLE:
		title_label.text = TITLE

func _process(_delta: float) -> void:
	var scene = GameModeManager.current_scene
	var active: bool = scene != null and GameModeManager.current_mode_name == MODE_NAME

	update_preview(scene, active)
	update_title()

	if not active:
		return

	if hide_numbers:
		hide_labels()
	else:
		restore_labels()

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
				var mi: MeshInstance2D = patched_sobos[sobo]["mi"]
				if is_instance_valid(mi):
					mi.queue_free()
			patched_sobos.erase(sobo)
			original_materials.erase(sobo)
			continue
		update_mesh(sobo, patched_sobos[sobo])

func patch_sobo(sobo: Sobo, tex: Texture2D, region: Rect2) -> void:
	original_materials[sobo] = sobo.get_material()
	sobo.set_material(hide_material)

	var mi := MeshInstance2D.new()
	mi.top_level = true
	mi.texture = tex
	mi.mesh = ArrayMesh.new()
	var outline_z := 0
	if SoboOutline._0 is CanvasItem:
		outline_z = (SoboOutline._0 as CanvasItem).z_index
	mi.z_as_relative = false
	mi.z_index = outline_z + 1
	sobo.add_child(mi)

	var d := {"mi": mi, "tex": tex, "region": region, "flip": null}
	patched_sobos[sobo] = d
	build_uvs(sobo, d)

func to_tex_uv(uv: Vector2, region: Rect2, tex_size: Vector2) -> Vector2:
	return (region.position + uv * region.size) / tex_size

func ring_spline(ctrl: PackedVector2Array) -> PackedVector2Array:
	var points := ctrl.duplicate()

	for _i in SMOOTH:
		var smooth := PackedVector2Array()
		smooth.resize(points.size() * 2)

		for i in points.size():
			var p1 := points[i]
			var p2 := points[(i + 1) % points.size()]

			smooth[i * 2] = p1.lerp(p2, 0.25)
			smooth[i * 2 + 1] = p1.lerp(p2, 0.75)

		points = smooth

	return points

func build_uvs(sobo: Sobo, d: Dictionary) -> void:
	var rest = sobo.data.circular_positions
	var n: int = sobo.subas.size()
	var tex: Texture2D = d["tex"]
	var region: Rect2 = d["region"]
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	var flip: bool = SettingsManager.settings.flipped_screen
	var hw: float = sobo.visual_half_width
	var r: float = rest[0].length() + hw

	var ctrl := PackedVector2Array()
	ctrl.resize(n)
	for i in n:
		var rp: Vector2 = rest[i]
		var uv := Vector2(0.5, 0.5) + (rp + rp.normalized() * hw) / (2.0 * r)
		if flip:
			uv = Vector2.ONE - uv
		ctrl[i] = uv
	var ring := ring_spline(ctrl)
	var m := ring.size()

	var uvs := PackedVector2Array()
	uvs.resize(m + 1)
	uvs[0] = to_tex_uv(Vector2(0.5, 0.5), region, tex_size)
	var idx := PackedInt32Array()
	for j in m:
		uvs[j + 1] = to_tex_uv(ring[j], region, tex_size)
		idx.append_array([0, 1 + j, 1 + (j + 1) % m])
	d["uvs"] = uvs
	d["idx"] = idx
	d["flip"] = flip
	d["n"] = n

func update_mesh(sobo: Sobo, d: Dictionary) -> void:
	if d["flip"] != SettingsManager.settings.flipped_screen:
		build_uvs(sobo, d)
	var pos = sobo.get_positions()
	var n: int = pos.size()
	if n == 0 or n != d["n"]:
		return
	var center := sobo.get_visual_center()
	var hw: float = sobo.visual_half_width
	var ctrl := PackedVector2Array()
	ctrl.resize(n)
	for i in n:
		var p: Vector2 = pos[i]
		ctrl[i] = p + (p - center).normalized() * (hw + MESH_PADDING)
	var verts := PackedVector2Array([center])
	verts.append_array(ring_spline(ctrl))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = d["uvs"]
	arrays[Mesh.ARRAY_INDEX] = d["idx"]
	var mesh: ArrayMesh = (d["mi"] as MeshInstance2D).mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
