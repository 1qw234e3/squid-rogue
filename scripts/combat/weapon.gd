extends Node2D
## 武器:挂在持有者身上,负责开火节奏、子弹生成和手感三件套里的
## 屏震 + 枪口火光 + 抛壳(设计文档 §6:开火 2px 屏震、火光 2 帧)。
## 玩家和守卫共用这个类,只是参数表和子弹掩码不同。

const Bullet := preload("res://scripts/combat/bullet.gd")

const PISTOL := {
	"name": "手枪", "fire_rate": 4.0, "bullets": 1, "spread": 0.06,
	"bullet_speed": 280.0, "damage": 1, "shake": 1.5, "color": Color("ffe07a"),
}
const SMG := {
	"name": "冲锋枪", "fire_rate": 9.0, "bullets": 1, "spread": 0.16,
	"bullet_speed": 300.0, "damage": 1, "shake": 1.2, "color": Color("8aff9e"),
}
const SHOTGUN := {
	"name": "霰弹枪", "fire_rate": 1.6, "bullets": 5, "spread": 0.38,
	"bullet_speed": 250.0, "damage": 1, "shake": 4.0, "color": Color("ff9e6b"),
}
const GUARD_RIFLE := {
	"name": "守卫步枪", "fire_rate": 1.3, "bullets": 1, "spread": 0.1,
	"bullet_speed": 190.0, "damage": 1, "shake": 0.0, "color": Color("ff5a5a"),
}

var stats := PISTOL
var shooter_group := ""
var bullet_mask := 0
var cooldown := 0.0
var barrel: ColorRect
var flash_rect: ColorRect


func _ready() -> void:
	barrel = ColorRect.new()
	barrel.size = Vector2(10, 3)
	barrel.position = Vector2(2, -1.5)
	barrel.color = stats.color
	add_child(barrel)
	flash_rect = ColorRect.new()
	flash_rect.size = Vector2(6, 6)
	flash_rect.position = Vector2(12, -3)
	flash_rect.color = Color(1.0, 1.0, 0.8)
	flash_rect.visible = false
	add_child(flash_rect)


func setup(s: Dictionary, group: String, mask: int) -> void:
	stats = s
	shooter_group = group
	bullet_mask = mask
	if barrel:
		barrel.color = stats.color


func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)


func set_aim(direction: Vector2) -> void:
	rotation = direction.angle()


func try_fire() -> void:
	if cooldown > 0.0:
		return
	cooldown = 1.0 / (float(stats.fire_rate) * Tune.fire_rate_scale)
	for i in int(stats.bullets):
		var ang: float = rotation + randf_range(-stats.spread, stats.spread)
		var b := Bullet.new()
		get_tree().current_scene.add_child(b)
		b.launch(global_position + Vector2.from_angle(ang) * 12.0, ang, stats, shooter_group, bullet_mask)
	Game.shake(stats.shake)
	Game.play_sfx("shoot", 0.8 if shooter_group == "guards" else 1.0)  # 守卫枪声调低,听声辨位
	_muzzle_flash()
	_eject_shell()


func _muzzle_flash() -> void:
	flash_rect.visible = true
	# 用信号连接而不是 await:武器若中途被释放,连接会自动断开,不会报错
	get_tree().create_timer(0.06).timeout.connect(_hide_flash)


func _hide_flash() -> void:
	flash_rect.visible = false


func _eject_shell() -> void:
	var shell := ColorRect.new()
	shell.size = Vector2(2, 2)
	shell.color = Color("d8b45a")
	get_tree().current_scene.add_child(shell)
	shell.global_position = global_position
	# 弹壳往枪身侧面弹出,落地停留再淡出
	var side := Vector2.from_angle(rotation + PI / 2.0 * (1.0 if randf() < 0.5 else -1.0))
	var tw := shell.create_tween()
	tw.tween_property(shell, "global_position", shell.global_position + side * randf_range(6.0, 12.0), 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(shell, "modulate:a", 0.0, 0.3)
	tw.tween_callback(shell.queue_free)
