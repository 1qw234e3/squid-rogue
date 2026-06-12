extends StaticBody2D
## 房间门:关闭时挡路、挡子弹、挡视线(守卫的 LOS 射线)、挡光(夜战遮光体)。
## 玩家 E 开关——关上身后的门能掐断追兵视线;守卫走近会自动推开(2s 后回弹)。

var door_size := Vector2(32, 6)
var open := false
var auto_close := 0.0
var visual: ColorRect
var shape: CollisionShape2D
var occluder: LightOccluder2D


func setup(size_: Vector2) -> void:
	door_size = size_


func _ready() -> void:
	add_to_group("doors")
	collision_layer = 1  # 与墙同层:挡移动/子弹/视线射线
	collision_mask = 0
	shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = door_size
	shape.shape = rect
	add_child(shape)
	occluder = LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	var half := door_size / 2.0
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	occluder.occluder = poly
	add_child(occluder)
	visual = ColorRect.new()
	visual.size = door_size
	visual.position = -door_size / 2.0
	visual.color = Color("9a7b4f")  # 门板:比墙亮,黑暗里贴近也认得出
	add_child(visual)


func _physics_process(delta: float) -> void:
	if open:
		auto_close -= delta
		if auto_close <= 0.0 and not _doorway_blocked():
			_set_open(false)
	else:
		# 守卫走近自动推开(他们不讲礼貌)
		for g in get_tree().get_nodes_in_group("guards"):
			if g.global_position.distance_to(global_position) < 18.0:
				_set_open(true)
				auto_close = 2.0
				break
	# 玩家 E 开关
	if Input.is_action_just_pressed("interact"):
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.global_position.distance_to(global_position) < 22.0:
			if open and _doorway_blocked():
				return  # 门口有人,关不上
			_set_open(not open)
			auto_close = 6.0 if open else 0.0  # 玩家开的门多留一会儿


func _set_open(v: bool) -> void:
	if open == v:
		return
	open = v
	shape.set_deferred("disabled", v)
	occluder.visible = not v       # 开门 = 不再遮光/遮视线
	visual.modulate.a = 0.25 if v else 1.0
	Game.play_sfx_at("melee_hit", global_position, 1.6 if v else 1.2)


func _doorway_blocked() -> bool:
	var margin := maxf(door_size.x, door_size.y) / 2.0 + 10.0
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.global_position.distance_to(global_position) < margin:
		return true
	for g in get_tree().get_nodes_in_group("guards"):
		if g.global_position.distance_to(global_position) < margin:
			return true
	return false
