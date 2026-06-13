extends Node2D
## 武器:挂在持有者身上,负责开火节奏、子弹生成和手感三件套里的
## 屏震 + 枪口火光 + 抛壳(设计文档 §6:开火 2px 屏震、火光 2 帧)。
## 玩家和守卫共用这个类,只是参数表和子弹掩码不同。

const Bullet := preload("res://scripts/combat/bullet.gd")
const NoiseRing := preload("res://scripts/combat/noise_ring.gd")
const SlashFx := preload("res://scripts/combat/slash_fx.gd")

# noise = 噪音半径(设计议题 1.3):圈内守卫会赶来查看。
# 近战 noise=0 —— 无声击杀流的核心,与潜行系统直接挂钩
const PISTOL := {
	"name": "手枪", "fire_rate": 4.0, "bullets": 1, "spread": 0.06,
	"bullet_speed": 280.0, "damage": 1, "shake": 1.5, "noise": 130.0,
	"sfx": "shoot", "color": Color("ffe07a"),
}
const SMG := {
	"name": "冲锋枪", "fire_rate": 9.0, "bullets": 1, "spread": 0.16,
	"bullet_speed": 300.0, "damage": 1, "shake": 1.2, "noise": 110.0,
	"sfx": "shoot", "color": Color("8aff9e"),
}
const SHOTGUN := {
	"name": "霰弹枪", "fire_rate": 1.6, "bullets": 5, "spread": 0.38,
	"bullet_speed": 250.0, "damage": 1, "shake": 4.0, "noise": 180.0,
	"sfx": "shoot_heavy", "color": Color("ff9e6b"),
}
const RIFLE := {
	# 定位:最强连射枪。DPS 11 > 冲锋枪 9,且高弹速高精度;代价是噪音全场第二响
	"name": "步枪", "fire_rate": 5.5, "bullets": 1, "spread": 0.03,
	"bullet_speed": 420.0, "damage": 2, "shake": 2.0, "noise": 160.0,
	"sfx": "shoot_heavy", "color": Color("9ecbff"),
}
const GUARD_RIFLE := {
	"name": "守卫步枪", "fire_rate": 1.3, "bullets": 1, "spread": 0.1,
	"bullet_speed": 190.0, "damage": 1, "shake": 0.0, "noise": 0.0,
	"sfx": "shoot_heavy", "color": Color("ff5a5a"),
}
const KNIFE := {
	"name": "小刀", "type": "melee", "fire_rate": 3.5, "damage": 1,
	"range": 24.0, "arc": PI * 0.7, "shake": 1.0, "noise": 0.0, "color": Color("d8dee6"),
}
const AXE := {
	"name": "消防斧", "type": "melee", "fire_rate": 1.1, "damage": 3,
	"range": 30.0, "arc": PI * 0.9, "shake": 3.0, "noise": 0.0, "color": Color("ff6b6b"),
}

var stats := PISTOL
var shooter_group := ""
var bullet_mask := 0
## 近战目标组覆写:默认玩家打守卫;抢椅子关设为 "chairs_npcs"
var melee_target_group := ""
var cooldown := 0.0
var barrel: ColorRect
var flash_rect: ColorRect
var flash_light: PointLight2D


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
	# 枪口闪光灯:黑暗关里开枪会真的照亮一瞬——也照亮你自己的位置
	flash_light = PointLight2D.new()
	flash_light.texture = Game.radial_light_texture()
	flash_light.texture_scale = 0.6
	flash_light.energy = 0.0
	flash_light.color = Color(1.0, 0.9, 0.6)
	flash_light.position = Vector2(12, 0)
	add_child(flash_light)


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
	if str(stats.get("type", "gun")) == "melee":
		_melee_attack()
		return
	for i in int(stats.bullets):
		var ang: float = rotation + randf_range(-stats.spread, stats.spread)
		var b := Bullet.new()
		get_tree().current_scene.add_child(b)
		b.launch(global_position + Vector2.from_angle(ang) * 12.0, ang, stats, shooter_group, bullet_mask)
	Game.shake(stats.shake)
	var sfx := str(stats.get("sfx", "shoot"))
	if shooter_group == "guards":
		Game.play_sfx_at(sfx, global_position, 0.85)  # 守卫枪声:带方位 + 低音调
	else:
		Game.play_sfx(sfx)
	# 枪声广播噪音事件,并给玩家画出"这一枪谁能听见"的可视化圈
	var noise := float(stats.get("noise", 0.0))
	if noise > 0.0:
		EventBus.noise_emitted.emit(global_position, noise, shooter_group)
		if shooter_group != "guards":
			var ring := NoiseRing.new()
			ring.max_radius = noise
			get_tree().current_scene.add_child(ring)
			ring.global_position = global_position
	_muzzle_flash()
	_eject_shell()


## 近战:扇形范围内、未被墙挡住的敌人全部吃伤害。无枪口火光无抛壳无噪音
func _melee_attack() -> void:
	var enemy_group := melee_target_group
	if enemy_group == "":
		enemy_group = "guards" if shooter_group == "player" else "player"
	var dir := Vector2.from_angle(rotation)
	var reach: float = float(stats.range) + 10.0  # 容差:目标有体积
	for body in get_tree().get_nodes_in_group(enemy_group):
		if not (body is Node2D) or not body.has_method("take_damage"):
			continue
		var to: Vector2 = body.global_position - global_position
		if to.length() > reach or absf(dir.angle_to(to)) > float(stats.arc) / 2.0:
			continue
		# 不能隔墙砍
		var params := PhysicsRayQueryParameters2D.create(global_position, body.global_position, 1)
		if not get_world_2d().direct_space_state.intersect_ray(params).is_empty():
			continue
		# 刀不被椅子挡:目标若实现了 stabbed(安全区免疫绕过),优先走它
		if body.has_method("stabbed"):
			body.stabbed(stats.damage, to.normalized())
		else:
			body.take_damage(stats.damage, to.normalized())
		Game.blood_burst(body.global_position, 4)
		Game.hitstop()
		Game.play_sfx("melee_hit")
	Game.shake(stats.shake)
	Game.play_sfx("swing")
	var slash := SlashFx.new()
	slash.arc = stats.arc
	slash.range_px = stats.range
	slash.color = stats.color
	get_tree().current_scene.add_child(slash)
	slash.global_position = global_position
	slash.rotation = rotation


func _muzzle_flash() -> void:
	flash_rect.visible = true
	flash_light.energy = 1.2
	# 用信号连接而不是 await:武器若中途被释放,连接会自动断开,不会报错
	get_tree().create_timer(0.06).timeout.connect(_hide_flash)


func _hide_flash() -> void:
	flash_rect.visible = false
	flash_light.energy = 0.0


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
