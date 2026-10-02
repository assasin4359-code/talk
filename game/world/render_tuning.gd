extends WorldEnvironment
## The web build runs on the Compatibility renderer (WebGL 2). The same light energies
## come out far brighter there and clip to white, so on that renderer the scene's
## lights are scaled down. Values picked by comparing captures side by side.

@export var sun: DirectionalLight3D
@export var compat_ambient_energy := 0.08
@export var compat_sun_energy := 0.3
@export var compat_light_scale := 0.65  ## omni/spot lights (tavern, foyer, fire)


func _ready() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	environment = environment.duplicate()
	environment.ambient_light_energy = compat_ambient_energy
	if sun != null:
		sun.light_energy = compat_sun_energy
	for light in get_parent().find_children("*", "Light3D", true, false):
		if light != sun:
			light.light_energy *= compat_light_scale
