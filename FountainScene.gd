extends Node3D

const UDP_PORT = 4242
const MAX_PARTICLES_PER_EMITTER = 8192  # Total particles = 16384
const PARTICLE_LIFETIME = 4.0
const ARCH_HEIGHT = 10.0
const ARCH_DISTANCE_FROM_CENTER = 5.0

# Pedestrian constants
const PEDESTRIAN_RADIUS = 10.0
const PEDESTRIAN_SPEED = 2.0

# Sound paths
const SQUEAL_SOUND_PATH = "res://sounds/squeal.wav"
const AMBIENT_SOUND_PATH = "res://sounds/ambient.wav"
const PEDESTRIAN_SOUND_PATH = "res://sounds/pedestrian.wav"

# Physics constants
const GRAVITY_VALUE = 9.8

var udp_server = UDPServer.new()
var particle_count = 0
var pedestrians = {}

# Player movement
var player_velocity = Vector3.ZERO
const PLAYER_SPEED = 5.0
const JUMP_VELOCITY = 4.5

# Camera state
var current_camera = 0  # 0: First Person, 1: Third Person, 2: Overview

# Node references
@onready var player_body = $PlayerBody
@onready var camera_pivot = $PlayerBody/CameraPivot
@onready var camera_first_person = $PlayerBody/CameraPivot/CameraFirstPerson
@onready var camera_third_person = $PlayerBody/CameraPivot/CameraThirdPerson
@onready var overview_camera = $OverviewCamera
@onready var status_display = $StatusDisplay
@onready var squeal_player = $PlayerBody/CameraPivot/CameraFirstPerson/SquealPlayer
@onready var ambient_sound_player = $AmbientSoundPlayer
@onready var pedestrian_sound_player = $PedestrianSoundPlayer
@onready var emitters_node = $Emitters

var emitter_left: GPUParticles3D
var emitter_right: GPUParticles3D

func _ready():
	# Setup UDP server
	var err = udp_server.listen(UDP_PORT)
	if err != OK:
		printerr("Failed to start UDP server on port %d. Error: %s" % [UDP_PORT, error_string(err)])
		return

	# Setup sounds (NOTE: Commented out as files are missing)
	# ambient_sound_player.stream = load(AMBIENT_SOUND_PATH)
	# ambient_sound_player.play()
	# ambient_sound_player.volume_db = -10
	# squeal_player.stream = load(SQUEAL_SOUND_PATH)
	# pedestrian_sound_player.stream = load(PEDESTRIAN_SOUND_PATH)

	# Setup input and camera
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_first_person.make_current()

	# Create and configure the fountain emitters
	setup_fountain_emitters()

func setup_fountain_emitters():
	# Physics calculation for the arch
	var v0y = sqrt(2 * GRAVITY_VALUE * ARCH_HEIGHT)
	var v0x = ARCH_DISTANCE_FROM_CENTER * sqrt(GRAVITY_VALUE / (2 * ARCH_HEIGHT))
	var initial_velocity = sqrt(pow(v0x, 2) + pow(v0y, 2))

	# Create left emitter
	emitter_left = GPUParticles3D.new()
	emitter_left.position = Vector3(-ARCH_DISTANCE_FROM_CENTER, 0.1, 0)
	emitter_left.amount = 1 # Must be at least 1
	emitter_left.lifetime = PARTICLE_LIFETIME
	emitter_left.process_material = create_arch_particle_material(Vector3(v0x, v0y, 0).normalized(), initial_velocity)
	emitter_left.draw_pass_1 = create_particle_mesh()
	emitter_left.emitting = false # Start turned off
	emitters_node.add_child(emitter_left)

	# Create right emitter
	emitter_right = GPUParticles3D.new()
	emitter_right.position = Vector3(ARCH_DISTANCE_FROM_CENTER, 0.1, 0)
	emitter_right.amount = 1 # Must be at least 1
	emitter_right.lifetime = PARTICLE_LIFETIME
	emitter_right.process_material = create_arch_particle_material(Vector3(-v0x, v0y, 0).normalized(), initial_velocity)
	emitter_right.draw_pass_1 = create_particle_mesh()
	emitter_right.emitting = false # Start turned off
	emitters_node.add_child(emitter_right)

func create_particle_mesh() -> Mesh:
	var mesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	return mesh

func create_arch_particle_material(direction: Vector3, initial_velocity: float) -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	
	mat.direction = direction
	mat.spread = 5.0  # A bit of spread for a more natural look
	
	mat.initial_velocity_min = initial_velocity * 0.95
	mat.initial_velocity_max = initial_velocity * 1.05
	
	mat.gravity = Vector3(0, -GRAVITY_VALUE, 0)
	
	mat.scale_min = 0.8
	mat.scale_max = 1.2
	
	# Optional: Add some color variation
	mat.color = Color(0.7, 0.8, 1.0, 0.8)
	mat.hue_variation_min = -0.1
	mat.hue_variation_max = 0.1
	
	return mat

func _process(delta):
	udp_server.poll()
	handle_input(delta)
	handle_udp()
	update_status_display()
	update_pedestrians(delta)

func _physics_process(delta):
	# Player gravity
	if not player_body.is_on_floor():
		player_velocity.y -= GRAVITY_VALUE * delta
	
	# Get input and move player
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (player_body.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		player_velocity.x = direction.x * PLAYER_SPEED
		player_velocity.z = direction.z * PLAYER_SPEED
	else:
		player_velocity.x = move_toward(player_velocity.x, 0, PLAYER_SPEED * delta)
		player_velocity.z = move_toward(player_velocity.z, 0, PLAYER_SPEED * delta)
		
	player_body.velocity = player_velocity
	player_body.move_and_slide()

func handle_input(_delta):
	if Input.is_action_just_pressed("toggle_camera"):
		current_camera = (current_camera + 1) % 3
		update_camera()
	
	if Input.is_action_just_pressed("overview_camera"):
		current_camera = 2
		update_camera()

	if Input.is_action_just_pressed("jump") and player_body.is_on_floor():
		player_velocity.y = JUMP_VELOCITY

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player_body.rotate_y(-event.relative.x * 0.002)
		camera_pivot.rotate_x(-event.relative.y * 0.002)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI/2, PI/2)

func update_camera():
	camera_first_person.current = (current_camera == 0)
	camera_third_person.current = (current_camera == 1)
	overview_camera.current = (current_camera == 2)

func handle_udp():
	while udp_server.is_packet_available():
		var packet = udp_server.get_packet()
		var data = packet.get_string_from_utf8()
		var json = JSON.parse_string(data)

		if json:
			if json.has("eeg_power"):
				update_fountain(json.eeg_power)
			if json.has("pedestrian_positions"):
				update_pedestrian_positions(json.pedestrian_positions)

func update_fountain(eeg_power: float):
	var target_particles = int(eeg_power * MAX_PARTICLES_PER_EMITTER)

	if not is_instance_valid(emitter_left) or not is_instance_valid(emitter_right):
		return

	if target_particles > 0:
		var needs_restart = not emitter_left.emitting
		emitter_left.amount = target_particles
		emitter_right.amount = target_particles
		emitter_left.emitting = true
		emitter_right.emitting = true
		if needs_restart:
			emitter_left.restart()
			emitter_right.restart()
	else:
		emitter_left.emitting = false
		emitter_right.emitting = false
			
	particle_count = target_particles * 2

func update_pedestrian_positions(positions):
	var active_ids = []
	for id_str in positions:
		var id = int(id_str)
		active_ids.append(id)
		var pos_data = positions[id_str]
		var pos = Vector3(pos_data[0], pos_data[1], pos_data[2])
		if not pedestrians.has(id):
			var pedestrian_mesh = CSGBox3D.new()
			pedestrian_mesh.size = Vector3(0.5, 1.8, 0.5)
			# Add a simple material to see them better
			var material = StandardMaterial3D.new()
			material.albedo_color = Color.DARK_SLATE_GRAY
			pedestrian_mesh.material = material
			pedestrians[id] = pedestrian_mesh
			$Pedestrians.add_child(pedestrians[id])
		pedestrians[id].position = pos

	# Remove pedestrians that are no longer in the data
	var ids_to_remove = []
	for id in pedestrians:
		if not id in active_ids:
			ids_to_remove.append(id)
	for id in ids_to_remove:
		pedestrians[id].queue_free()
		pedestrians.erase(id)


func update_pedestrians(_delta):
	# This function seems to have a simple wandering logic.
	# The python script is the source of truth for positions, so this might not be needed.
	# I'll keep it commented out to adhere to the original logic from the python script.
	# for id in pedestrians:
	#     var p = pedestrians[id]
	#     var direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	#     p.position += direction * PEDESTRIAN_SPEED * delta
	#     if p.position.length() > PEDESTRIAN_RADIUS:
	#         p.position = p.position.normalized() * PEDESTRIAN_RADIUS
		
	#     if randf() < 0.01: # Play sound occasionally
	#         pedestrian_sound_player.position = p.position
	#         pedestrian_sound_player.play()
	pass


func update_status_display():
	status_display.text = "Particles: %d\n" % particle_count
	status_display.text += "Camera: %s\n" % ["First Person", "Third Person", "Overview"][current_camera]
	status_display.text += "Position: %.2f, %.2f, %.2f" % [player_body.position.x, player_body.position.y, player_body.position.z]

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		udp_peer.close()
		get_tree().quit()
