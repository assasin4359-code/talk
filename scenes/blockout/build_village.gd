extends SceneTree
## Generates res://scenes/village.tscn — the gray-box village for Milestone 01.
##
## While the layout is still moving, edit THIS file and re-run:
##   godot --headless --path . --script res://scenes/blockout/build_village.gd
## Once the layout is locked, stop regenerating and edit village.tscn in the editor.
##
## Layout (handoff §6, docs/02 §2): entrance (south, +Z) -> straight road -> square
## with the well -> ramp up the hill -> castle gate (north, -Z). The gate sits on the
## sightline from the spawn point, so "the gate is closed today" reads instantly.
## 1 unit = 1 m. Everything here is TEMPORARY blockout geometry.

const OUT := "res://scenes/village.tscn"
const FONT := "res://assets/fonts/Pretendard-SemiBold.otf"

# Loaded in _initialize (not preloaded): these scripts use the Narrative autoload,
# which is only registered once the SceneTree is up.
var S_ANCHOR: Script
var S_TARGET: Script
var S_VOLUME: Script
var S_GATE: Script
var S_SIGN: Script
var S_PLAYER: Script
var S_DIRECTOR: Script
var S_VARIANT: Script
var S_RENDER: Script

const PLATEAU_Y := 6.0  # castle hill height
const GATE_Z := -46.0  # centre of the castle wall

var scene_root: Node3D
var mats := {}
var font: Font


func _initialize() -> void:
	S_ANCHOR = load("res://game/world/anchor.gd")
	S_TARGET = load("res://game/world/narrative_target.gd")
	S_VOLUME = load("res://game/world/narrative_volume.gd")
	S_GATE = load("res://game/world/gate_presenter.gd")
	S_SIGN = load("res://game/world/sign_presenter.gd")
	S_PLAYER = load("res://game/player/player.gd")
	S_DIRECTOR = load("res://game/director.gd")
	S_VARIANT = load("res://game/world/variant_presenter.gd")
	S_RENDER = load("res://game/world/render_tuning.gd")
	for sc in [S_ANCHOR, S_TARGET, S_VOLUME, S_GATE, S_SIGN, S_PLAYER, S_DIRECTOR, S_VARIANT, S_RENDER]:
		if sc == null or not sc.can_instantiate():
			push_error("a game script failed to compile; not writing %s" % OUT)
			quit(1)
			return
	font = load(FONT)
	scene_root = Node3D.new()
	scene_root.name = "Village"
	_materials()
	_environment()
	var blockout := _group(scene_root, "Blockout")
	_ground(blockout)
	_square(blockout)
	_tavern(blockout)
	_smithy(blockout)
	_houses_and_market(blockout)
	_entrance(blockout)
	_hill_and_castle(blockout)
	_trees(blockout)
	var targets := _group(scene_root, "Targets")
	_npcs(targets)
	_props(targets)
	_anchors(_group(scene_root, "Anchors"))
	_volumes(scene_root)
	var player := _player(scene_root)
	var director := Node.new()
	director.name = "Director"
	director.set_script(S_DIRECTOR)
	scene_root.add_child(director)
	director.set("player", player)
	_own(scene_root)
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("%s -> %s" % [OUT, error_string(err)])
	scene_root.free()
	quit(0 if err == OK else 1)


# --- helpers ----------------------------------------------------------------

func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = scene_root
		_own(c)


func _group(parent: Node, n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	parent.add_child(g)
	return g


func _mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node, n: String, size: Vector3, pos: Vector3, mat: String, rot := Vector3.ZERO, collide := true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = n
	b.size = size
	b.position = pos
	b.rotation_degrees = rot
	b.material = mats[mat]
	b.use_collision = collide
	parent.add_child(b)
	return b


func _sub(parent: Node, n: String, size: Vector3, pos: Vector3) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = n
	b.size = size
	b.position = pos
	b.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(b)
	return b


func _cyl(parent: Node, n: String, radius: float, height: float, pos: Vector3, mat: String, collide := true, cone := false, rot := Vector3.ZERO) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.name = n
	c.radius = radius
	c.height = height
	c.position = pos
	c.rotation_degrees = rot
	c.sides = 16
	c.cone = cone
	c.material = mats[mat]
	c.use_collision = collide
	parent.add_child(c)
	return c


## Walkable slope along -Z: from (z_start, y=0) up to (z_end, y=height), `width` wide, centred on x=0.
func _wedge(parent: Node, n: String, z_start: float, z_end: float, height: float, width: float, mat: String) -> CSGPolygon3D:
	var w := CSGPolygon3D.new()
	w.name = n
	# profile in local XY, extruded along local -Z; rotating 90 deg about Y maps local +X -> world -Z
	# and the extrusion -> world -X, so local x = -world z and the node sits at the +X side.
	w.polygon = PackedVector2Array([Vector2(-z_start, 0), Vector2(-z_end, 0), Vector2(-z_end, height)])
	w.mode = CSGPolygon3D.MODE_DEPTH
	w.depth = width
	w.rotation_degrees = Vector3(0, 90, 0)
	w.position = Vector3(width / 2, 0, 0)
	w.material = mats[mat]
	w.use_collision = true
	parent.add_child(w)
	return w


## Triangular prism roof, ridge along Z. `base` is the centre of the roof's bottom face.
func _gable(parent: Node, n: String, base: Vector3, width: float, depth: float, height: float, mat: String) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	p.name = n
	p.polygon = PackedVector2Array([Vector2(-width / 2, 0), Vector2(0, height), Vector2(width / 2, 0)])
	p.mode = CSGPolygon3D.MODE_DEPTH
	p.depth = depth
	p.position = base + Vector3(0, 0, depth / 2)
	p.material = mats[mat]
	p.use_collision = true
	parent.add_child(p)
	return p


func _light(parent: Node, n: String, pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = n
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	return l


func _label(parent: Node, n: String, text: String, pos: Vector3, size := 48, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 12
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


func _static_shape(parent: Node, shape: Shape3D, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.position = pos
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


func _anchor(parent: Node, id: String, for_target: String, pos: Vector3, yaw := 0.0) -> void:
	var a := Marker3D.new()
	a.name = "%s_%s" % [id, for_target if for_target != "" else "any"]
	a.set_script(S_ANCHOR)
	a.position = pos
	a.rotation_degrees.y = yaw
	parent.add_child(a)
	a.set("anchor_id", id)
	a.set("for_target", for_target)


func _target(parent: Node, n: String, id: String, verb: String, follow: bool, props := PackedStringArray()) -> Node3D:
	var t := Node3D.new()
	t.name = n
	t.set_script(S_TARGET)
	parent.add_child(t)
	t.set("target_id", id)
	t.set("verb", verb)
	t.set("follow_location", follow)
	t.set("watched_props", props)
	return t


# --- look -------------------------------------------------------------------

func _materials() -> void:
	mats = {
		"grass": _mat(Color(0.43, 0.56, 0.31)),
		"grass_hill": _mat(Color(0.38, 0.51, 0.29)),
		"road": _mat(Color(0.64, 0.55, 0.41)),
		"plaza": _mat(Color(0.71, 0.69, 0.64)),
		"plaster": _mat(Color(0.88, 0.82, 0.70)),
		"plaster_b": _mat(Color(0.80, 0.76, 0.66)),
		"wood": _mat(Color(0.46, 0.31, 0.19)),
		"wood_dark": _mat(Color(0.30, 0.20, 0.12)),
		"roof": _mat(Color(0.60, 0.27, 0.21)),
		"roof_b": _mat(Color(0.35, 0.38, 0.48)),
		"stone": _mat(Color(0.60, 0.60, 0.62)),
		"stone_dark": _mat(Color(0.42, 0.42, 0.46)),
		"marble": _mat(Color(0.82, 0.81, 0.78), 0.35),
		"opening": _mat(Color(0.09, 0.08, 0.08)),
		"metal": _mat(Color(0.62, 0.63, 0.67), 0.4, 0.8),
		"leaves": _mat(Color(0.25, 0.44, 0.22)),
		"water": _mat(Color(0.16, 0.24, 0.32), 0.2),
		"bartender": _mat(Color(0.86, 0.52, 0.22)),
		"guard": _mat(Color(0.25, 0.36, 0.66)),
		"cloth": _mat(Color(0.93, 0.92, 0.88)),
		"beer": _mat(Color(0.96, 0.74, 0.18)),
		"awning_a": _mat(Color(0.75, 0.30, 0.28)),
		"awning_b": _mat(Color(0.30, 0.52, 0.62)),
	}


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.86)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.90)
	sky_mat.ground_horizon_color = Color(0.72, 0.80, 0.90)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.79, 0.88)
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.set_script(S_RENDER)  # tones lights down on the web (Compatibility renderer)
	we.environment = env
	scene_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	scene_root.add_child(sun)
	we.set("sun", sun)


# --- village ----------------------------------------------------------------

func _ground(p: Node) -> void:
	_box(p, "Ground", Vector3(320, 1, 320), Vector3(0, -0.5, 0), "grass")
	# main road: entrance -> square
	_box(p, "Road", Vector3(6, 0.04, 80), Vector3(0, 0.02, 26), "road")
	_box(p, "PathTavern", Vector3(12, 0.04, 3), Vector3(-9, 0.02, -2), "road")
	_box(p, "PathSmithy", Vector3(14, 0.04, 3), Vector3(-9, 0.02, 22), "road")


func _square(p: Node) -> void:
	_cyl(p, "Plaza", 14.0, 0.05, Vector3(0, 0.025, 0), "plaza")
	var well := CSGCombiner3D.new()
	well.name = "Well"
	well.use_collision = true
	p.add_child(well)
	_cyl(well, "Rim", 1.3, 0.9, Vector3(0, 0.45, 0), "stone", false)
	var hole := _cyl(well, "Hole", 1.0, 1.0, Vector3(0, 0.6, 0), "stone", false)
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	_cyl(p, "Water", 1.0, 0.05, Vector3(0, 0.3, 0), "water", false)
	_box(p, "WellPostL", Vector3(0.2, 2.4, 0.2), Vector3(-1.1, 1.2, 0), "wood", Vector3.ZERO, false)
	_box(p, "WellPostR", Vector3(0.2, 2.4, 0.2), Vector3(1.1, 1.2, 0), "wood", Vector3.ZERO, false)
	_box(p, "WellBeam", Vector3(2.6, 0.2, 0.2), Vector3(0, 2.4, 0), "wood", Vector3.ZERO, false)


func _tavern(p: Node) -> void:
	var t := CSGCombiner3D.new()
	t.name = "Tavern"
	t.position = Vector3(-21, 0, -2)
	t.use_collision = true
	p.add_child(t)
	_box(t, "Walls", Vector3(12, 6, 10), Vector3(0, 3, 0), "plaster", Vector3.ZERO, false)
	_sub(t, "Inside", Vector3(11.4, 6.2, 9.4), Vector3(0, 2.6, 0))
	_sub(t, "Door", Vector3(1.0, 2.6, 1.8), Vector3(6, 1.3, 0))
	_sub(t, "WindowN", Vector3(1.0, 1.2, 1.4), Vector3(6, 2.4, -3))
	_sub(t, "WindowS", Vector3(1.0, 1.2, 1.4), Vector3(6, 2.4, 3))
	_box(p, "TavernFloor", Vector3(11.4, 0.06, 9.4), Vector3(-21, 0.03, -2), "wood")
	_gable(p, "TavernRoof", Vector3(-21, 6, -2), 13.2, 11, 3.2, "roof")
	# inside
	_box(p, "Counter", Vector3(1, 0.95, 5), Vector3(-23.6, 0.475, -2), "wood_dark")
	_light(p, "TavernLight", Vector3(-21, 4.2, -2), Color(1.0, 0.78, 0.5), 2.2, 11.0)
	_light(p, "FireGlow", Vector3(-19.5, 0.8, -5.2), Color(1.0, 0.5, 0.2), 1.6, 5.0)
	_box(p, "Fireplace", Vector3(2.6, 2.2, 0.8), Vector3(-19.5, 1.1, -6.3), "stone_dark")
	_box(p, "FireplaceMouth", Vector3(1.4, 1.0, 0.1), Vector3(-19.5, 0.6, -5.86), "opening", Vector3.ZERO, false)
	for i in 4:
		var tx := -19.0 + (i % 2) * 3.0
		var tz := -3.0 + int(i / 2) * 3.5
		_box(p, "Table%d" % i, Vector3(1.2, 0.8, 1.2), Vector3(tx, 0.4, tz), "wood")


func _smithy(p: Node) -> void:
	var c := Vector3(-21, 0, 22)
	_box(p, "SmithyBack", Vector3(0.3, 4.5, 8), c + Vector3(-5, 2.25, 0), "plaster_b")
	_box(p, "SmithySideN", Vector3(10, 4.5, 0.3), c + Vector3(0, 2.25, -4), "plaster_b")
	_box(p, "SmithySideS", Vector3(10, 4.5, 0.3), c + Vector3(0, 2.25, 4), "plaster_b")
	_box(p, "SmithyRoof", Vector3(11, 0.4, 9), c + Vector3(0, 4.7, 0), "roof_b")
	_box(p, "Forge", Vector3(2, 1.2, 2), c + Vector3(-3, 0.6, 0), "stone_dark")
	_box(p, "Chimney", Vector3(1, 4.5, 1), c + Vector3(-3.5, 4.5, 0), "stone_dark")
	_box(p, "Anvil", Vector3(0.8, 0.8, 0.4), c + Vector3(1, 0.4, 0), "metal")
	_box(p, "ClosedSignPost", Vector3(0.12, 1.4, 0.12), c + Vector3(5.6, 0.7, -2.6), "wood")
	_box(p, "ClosedSignBoard", Vector3(0.06, 0.6, 1.2), c + Vector3(5.6, 1.4, -2.6), "wood")
	var l := _label(p, "ClosedSignText", "오늘 휴업", c + Vector3(5.65, 1.4, -2.6), 40, false)
	l.rotation_degrees.y = 90


func _house(p: Node, n: String, pos: Vector3, yaw: float, size: Vector3, wall: String, roof: String) -> void:
	var h := _group(p, n)
	h.position = pos
	h.rotation_degrees.y = yaw
	_box(h, "Walls", size, Vector3(0, size.y / 2, 0), wall)
	_gable(h, "Roof", Vector3(0, size.y, 0), size.x + 1.0, size.z + 0.8, 2.6, roof)
	_box(h, "Door", Vector3(1.1, 2.2, 0.1), Vector3(0, 1.1, size.z / 2 + 0.05), "wood_dark", Vector3.ZERO, false)
	_box(h, "WindowL", Vector3(1.0, 1.0, 0.1), Vector3(-size.x / 4 - 0.4, 2.6, size.z / 2 + 0.05), "opening", Vector3.ZERO, false)
	_box(h, "WindowR", Vector3(1.0, 1.0, 0.1), Vector3(size.x / 4 + 0.4, 2.6, size.z / 2 + 0.05), "opening", Vector3.ZERO, false)


func _stall(p: Node, n: String, pos: Vector3, awning: String) -> void:
	var s := _group(p, n)
	s.position = pos
	for x in [-1.4, 1.4]:
		for z in [-1.0, 1.0]:
			_box(s, "Post_%d_%d" % [int(x * 10), int(z * 10)], Vector3(0.15, 2.4, 0.15), Vector3(x, 1.2, z), "wood", Vector3.ZERO, false)
	_box(s, "Awning", Vector3(3.4, 0.12, 2.6), Vector3(0, 2.45, 0), awning, Vector3(0, 0, 0), false)
	_box(s, "Counter", Vector3(3, 0.9, 0.8), Vector3(0, 0.45, -0.6), "wood")


func _houses_and_market(p: Node) -> void:
	_house(p, "HouseE1", Vector3(22, 0, -3), -90, Vector3(10, 5.5, 8), "plaster_b", "roof")
	_house(p, "HouseE2", Vector3(23, 0, 20), -90, Vector3(9, 5, 8), "plaster", "roof_b")
	_house(p, "HouseW3", Vector3(-20, 0, 44), 90, Vector3(9, 5, 8), "plaster", "roof")
	_house(p, "HouseE4", Vector3(16, 0, 46), -90, Vector3(8, 5, 7), "plaster_b", "roof")
	_house(p, "HouseN5", Vector3(26, 0, -24), 180, Vector3(9, 5.5, 8), "plaster", "roof_b")
	_house(p, "HouseN6", Vector3(-26, 0, -24), 180, Vector3(8, 5, 8), "plaster_b", "roof")
	_stall(p, "StallA", Vector3(9, 0, 18), "awning_a")
	_stall(p, "StallB", Vector3(9, 0, 27), "awning_b")


func _entrance(p: Node) -> void:
	_box(p, "ArchPostL", Vector3(0.4, 5, 0.4), Vector3(-4, 2.5, 60), "wood")
	_box(p, "ArchPostR", Vector3(0.4, 5, 0.4), Vector3(4, 2.5, 60), "wood")
	_box(p, "ArchBeam", Vector3(9, 0.5, 0.5), Vector3(0, 5, 60), "wood")
	_box(p, "FenceL", Vector3(26, 1.1, 0.2), Vector3(-17, 0.55, 60), "wood")
	_box(p, "FenceR", Vector3(26, 1.1, 0.2), Vector3(17, 0.55, 60), "wood")


func _hill_and_castle(p: Node) -> void:
	var y := PLATEAU_Y
	_box(p, "Plateau", Vector3(140, y, 70), Vector3(0, y / 2, -75), "grass_hill")
	# ramp from the square's north edge (z=-14, y=0) to the plateau edge (z=-40, y=4..6):
	# an exact wedge, so it meets the ground and the plateau top with no step or lip
	# (a capsule can't climb even a ~10 cm ledge, and there is no jump).
	_wedge(p, "Ramp", -14.0, -40.0, y, 8.0, "road")
	_box(p, "GateRoad", Vector3(6, 0.04, 4.5), Vector3(0, y + 0.02, -42.25), "road")  # starts ON the plateau
	# castle wall with the gate opening (8 wide, 10 high)
	var wall_h := 14.0
	_box(p, "WallL", Vector3(32, wall_h, 3), Vector3(-20, y + wall_h / 2, GATE_Z), "stone")
	_box(p, "WallR", Vector3(32, wall_h, 3), Vector3(20, y + wall_h / 2, GATE_Z), "stone")
	_box(p, "Lintel", Vector3(8, 4, 3), Vector3(0, y + 12, GATE_Z), "stone")
	_box(p, "GateTowerL", Vector3(4, 19, 4), Vector3(-6.5, y + 9.5, GATE_Z + 0.5), "stone_dark")
	_box(p, "GateTowerR", Vector3(4, 19, 4), Vector3(6.5, y + 9.5, GATE_Z + 0.5), "stone_dark")
	# foyer behind the gate
	var fz := GATE_Z - 1.5  # inner face of the wall
	_box(p, "FoyerFloor", Vector3(16, 0.06, 14.5), Vector3(0, y + 0.03, fz - 7.25), "marble")
	_box(p, "FoyerWallW", Vector3(0.4, 11, 14.5), Vector3(-8, y + 5.5, fz - 7.25), "stone")
	_box(p, "FoyerWallE", Vector3(0.4, 11, 14.5), Vector3(8, y + 5.5, fz - 7.25), "stone")
	_box(p, "FoyerBack", Vector3(16, 11, 0.4), Vector3(0, y + 5.5, fz - 14.5), "stone")
	_box(p, "FoyerInnerDoor", Vector3(3, 5, 0.1), Vector3(0, y + 2.5, fz - 14.25), "wood_dark", Vector3.ZERO, false)
	_box(p, "FoyerCeiling", Vector3(16.4, 0.4, 14.9), Vector3(0, y + 11.2, fz - 7.25), "stone_dark")
	# warm light inside: an open gate glows from afar, a closed one is a dark slab
	_light(p, "FoyerLight", Vector3(0, y + 7, fz - 6), Color(1.0, 0.8, 0.52), 6.0, 22.0)
	# keep
	_box(p, "Keep", Vector3(34, 22, 26), Vector3(0, y + 11, -82), "stone")
	for x in [-17.0, 17.0]:
		for z in [-69.0, -95.0]:
			var tag := "%s%s" % ["W" if x < 0 else "E", "S" if z > -80 else "N"]
			_cyl(p, "Tower" + tag, 4.0, 30.0, Vector3(x, y + 15, z), "stone_dark")
			_cyl(p, "TowerRoof" + tag, 4.8, 7.0, Vector3(x, y + 33.5, z), "roof_b", false, true)
	_cyl(p, "Spire", 3.2, 10.0, Vector3(0, y + 27, -86), "stone_dark")
	_cyl(p, "SpireRoof", 4.0, 8.0, Vector3(0, y + 36, -86), "roof_b", false, true)


func _trees(p: Node) -> void:
	var spots := [
		Vector3(-34, 0, 10), Vector3(-31, 0, 52), Vector3(33, 0, 8), Vector3(31, 0, 34),
		Vector3(-9, 0, 72), Vector3(13, 0, 70), Vector3(36, 0, -12), Vector3(-37, 0, -10),
		Vector3(-12, 0, 54), Vector3(-34, 0, 30), Vector3(40, 0, 52), Vector3(-44, 0, 64),
	]
	for i in spots.size():
		var t := _group(p, "Tree%d" % i)
		t.position = spots[i]
		_cyl(t, "Trunk", 0.35, 3.0, Vector3(0, 1.5, 0), "wood")
		var crown := CSGSphere3D.new()
		crown.name = "Crown"
		crown.radius = 2.2 + 0.3 * (i % 3)
		crown.position = Vector3(0, 4.2, 0)
		crown.material = mats["leaves"]
		t.add_child(crown)


# --- story things -----------------------------------------------------------

func _npc_body(t: Node3D, mat: String) -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	_static_shape(t, cap, Vector3(0, 0.9, 0))
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var cm := CapsuleMesh.new()
	cm.radius = 0.32
	cm.height = 1.75
	mesh.mesh = cm
	mesh.material_override = mats[mat]
	mesh.position = Vector3(0, 0.875, 0)
	t.add_child(mesh)
	_box(t, "Nose", Vector3(0.12, 0.12, 0.2), Vector3(0, 1.5, -0.33), mat, Vector3.ZERO, false)


func _npcs(p: Node) -> void:
	var bartender := _target(p, "Bartender", "bartender", "talk", true)
	_npc_body(bartender, "bartender")
	_box(bartender, "Apron", Vector3(0.5, 0.7, 0.05), Vector3(0, 0.75, -0.33), "cloth", Vector3.ZERO, false)
	_label(bartender, "Name", "술집 주인", Vector3(0, 2.15, 0))

	var guard := _target(p, "Guard", "guard", "talk", true)
	_npc_body(guard, "guard")
	_cyl(guard, "Helmet", 0.36, 0.3, Vector3(0, 1.72, 0), "metal", false)
	_cyl(guard, "Spear", 0.03, 2.6, Vector3(0.45, 1.3, 0), "wood", false)
	_cyl(guard, "SpearTip", 0.07, 0.3, Vector3(0.45, 2.75, 0), "metal", false, true)
	_label(guard, "Name", "경비병", Vector3(0, 2.25, 0))


func _props(p: Node) -> void:
	# gate: two leaves hinged at the opening's edges; GatePresenter swings them
	var gate := _target(p, "Gate", "gate", "use", false, PackedStringArray(["state"]))
	gate.position = Vector3(0, PLATEAU_Y, GATE_Z + 1.3)
	var hl := _group(gate, "HingeL")
	hl.position = Vector3(-4, 0, 0)
	_box(hl, "Leaf", Vector3(4, 10, 0.35), Vector3(2, 5, 0), "wood_dark")
	_box(hl, "BandHi", Vector3(4, 0.3, 0.4), Vector3(2, 7.5, 0), "metal", Vector3.ZERO, false)
	_box(hl, "BandLo", Vector3(4, 0.3, 0.4), Vector3(2, 2.5, 0), "metal", Vector3.ZERO, false)
	var hr := _group(gate, "HingeR")
	hr.position = Vector3(4, 0, 0)
	_box(hr, "Leaf", Vector3(4, 10, 0.35), Vector3(-2, 5, 0), "wood_dark")
	_box(hr, "BandHi", Vector3(4, 0.3, 0.4), Vector3(-2, 7.5, 0), "metal", Vector3.ZERO, false)
	_box(hr, "BandLo", Vector3(4, 0.3, 0.4), Vector3(-2, 2.5, 0), "metal", Vector3.ZERO, false)
	var gp := Node.new()
	gp.name = "GatePresenter"
	gp.set_script(S_GATE)
	gate.add_child(gp)
	gp.set("left_hinge", hl)
	gp.set("right_hinge", hr)

	# firewood pile at the smithy
	var fw := _target(p, "Firewood", "firewood", "use", true)
	for row in 3:
		for i in 4 - row:
			_cyl(fw, "Log%d_%d" % [row, i], 0.16, 1.4, Vector3(-0.5 + i * 0.33 + row * 0.16, 0.16 + row * 0.29, 0), "wood", false, false, Vector3(90, 0, 0))
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.0, 1.5)
	_static_shape(fw, box, Vector3(0, 0.5, 0))

	# tavern sign: a projecting board over the door, readable from the main road
	var sign := _target(p, "TavernSign", "tavern_sign", "use", false, PackedStringArray(["state"]))
	sign.position = Vector3(-14.6, 3.4, 1.8)
	_box(sign, "Arm", Vector3(2.3, 0.12, 0.12), Vector3(1.15, 0.85, 0), "wood_dark", Vector3.ZERO, false)
	var board := _group(sign, "Board")
	board.position = Vector3(1.25, 0, 0)
	_box(board, "Plank", Vector3(2.0, 1.4, 0.1), Vector3.ZERO, "wood", Vector3.ZERO, false)
	_box(board, "Mug", Vector3(0.6, 0.75, 0.14), Vector3(-0.35, -0.15, 0), "beer", Vector3.ZERO, false)
	_box(board, "Foam", Vector3(0.72, 0.24, 0.15), Vector3(-0.35, 0.33, 0), "cloth", Vector3.ZERO, false)
	_box(board, "Handle", Vector3(0.16, 0.42, 0.16), Vector3(0.03, -0.15, 0), "beer", Vector3.ZERO, false)
	_label(board, "Text", "술집", Vector3(0.55, 0.0, 0.08), 72, false)
	# tavern firewood basket: low on a normal day, full on a day the player helped
	var basket := _target(p, "TavernBasket", "tavern_basket", "use", false, PackedStringArray(["state"]))
	basket.position = Vector3(-17.6, 0, -6.1)
	_box(basket, "Basket", Vector3(0.9, 0.35, 0.8), Vector3(0, 0.175, 0), "wood_dark", Vector3.ZERO, false)
	var states := _variants(basket, "state", ["low", "full"])
	_logs(states["low"], 1, Vector3(0, 0.3, 0))
	_logs(states["full"], 8, Vector3(0, 0.3, 0))
	_light(states["full"], "FireBurning", Vector3(-1.9, 0.9, 0.9), Color(1.0, 0.55, 0.22), 2.4, 7.0)

	var sp := Node.new()
	sp.name = "SignPresenter"
	sp.set_script(S_SIGN)
	sign.add_child(sp)
	sp.set("board", board)


## A VariantPresenter under `target`: one child per world value of `prop`.
func _variants(target: Node, prop: String, names: Array) -> Dictionary:
	var vp := Node3D.new()
	vp.name = "Variants"
	vp.set_script(S_VARIANT)
	target.add_child(vp)
	vp.set("prop", prop)
	var out := {}
	for n in names:
		var g := _group(vp, n)
		g.visible = n == names[0]
		out[n] = g
	return out


func _logs(parent: Node, count: int, origin: Vector3, length := 0.7, radius := 0.08) -> void:
	for i in count:
		var row := int(i / 3)
		_cyl(parent, "Log%d" % i, radius, length, origin + Vector3(-radius * 2 + (i % 3) * radius * 2.1, radius + row * radius * 1.8, 0), "wood", false, false, Vector3(90, 0, 0))


func _anchors(p: Node) -> void:
	var y := PLATEAU_Y
	_anchor(p, "entrance", "player", Vector3(0, 0, 63))
	_anchor(p, "entrance", "", Vector3(0, 0, 60))
	_anchor(p, "square", "", Vector3(0, 0, 6))
	_anchor(p, "tavern", "bartender", Vector3(-24.6, 0, -2), -90)
	_anchor(p, "tavern", "", Vector3(-20, 0, -2))
	_anchor(p, "smithy", "firewood", Vector3(-14.2, 0, 24.5), 90)
	_anchor(p, "smithy", "", Vector3(-17, 0, 22))
	_anchor(p, "gate", "guard", Vector3(5.6, y, -41.0), 200)
	_anchor(p, "gate", "", Vector3(0, y, -41))
	_anchor(p, "castle_foyer", "", Vector3(0, y, -51))


func _volumes(p: Node) -> void:
	var v := Area3D.new()
	v.name = "CastleFoyerVolume"
	v.set_script(S_VOLUME)
	v.position = Vector3(0, PLATEAU_Y + 1.5, GATE_Z - 5.0)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var b := BoxShape3D.new()
	b.size = Vector3(12, 3, 3)
	cs.shape = b
	v.add_child(cs)
	p.add_child(v)
	v.set("volume_id", "castle_foyer")


func _player(p: Node) -> CharacterBody3D:
	var pl := CharacterBody3D.new()
	pl.name = "Player"
	pl.set_script(S_PLAYER)
	pl.position = Vector3(0, 0, 63)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.875, 0)
	pl.add_child(cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.62, 0)
	pl.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 72
	cam.current = true
	head.add_child(cam)
	var ray := RayCast3D.new()
	ray.name = "InteractRay"
	cam.add_child(ray)
	# what the player is carrying, shown in hand (world value player.carrying)
	var held := _target(cam, "Held", "player", "use", false, PackedStringArray(["carrying"]))
	var items := _variants(held, "carrying", ["nothing", "firewood"])
	_logs(items["firewood"], 5, Vector3(0.32, -0.42, -0.62), 0.55, 0.07)
	p.add_child(pl)
	return pl
