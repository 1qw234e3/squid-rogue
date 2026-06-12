extends Area2D
## 子弹:直线飞行的 Area2D。命中可受伤目标时触发 hitstop——
## 打击感三件套之一(设计文档 §6)。撞墙即消失。

var dir := Vector2.RIGHT
var speed := 280.0
var damage := 1
var life := 1.2
var color := Color.WHITE
var shooter_group := ""


func _ready() -> void:
	collision_layer = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 2.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


## 由武器在 add_child 之后调用,一次性注入全部参数
func launch(pos: Vector2, ang: float, stats: Dictionary, group: String, mask: int) -> void:
	global_position = pos
	rotation = ang
	dir = Vector2.from_angle(ang)
	speed = stats.bullet_speed
	damage = stats.damage
	color = stats.color
	shooter_group = group
	collision_mask = mask
	queue_redraw()


func _physics_process(delta: float) -> void:
	position += dir * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _draw() -> void:
	draw_rect(Rect2(-3, -1.5, 6, 3), color)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(shooter_group):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, dir)
		Game.hitstop()
	_spawn_hit_fx()
	queue_free()


func _spawn_hit_fx() -> void:
	var fx := ColorRect.new()
	fx.size = Vector2(6, 6)
	fx.color = Color(1, 1, 1, 0.9)
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position - Vector2(3, 3)
	var tw := fx.create_tween()
	tw.tween_property(fx, "modulate:a", 0.0, 0.12)
	tw.tween_callback(fx.queue_free)
