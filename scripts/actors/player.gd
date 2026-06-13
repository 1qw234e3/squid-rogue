extends CharacterBody2D
## 玩家:双摇杆操控(设计文档 §6)。
## 左摇杆/WASD 移动,右摇杆/鼠标瞄准,按住开火;翻滚 0.4s 无敌帧、CD 1.5s。

const Weapon := preload("res://scripts/combat/weapon.gd")

const ROLL_SPEED := 230.0
const ROLL_TIME := 0.4
const ROLL_CD := 1.5
const MAX_HP := 6

var hp := MAX_HP
## 沙盒/木头人等场景关掉战斗:收枪、禁射击、禁拾取
var combat_enabled := true:
	set(v):
		combat_enabled = v
		if weapon:
			weapon.visible = v
## 木头人关:0.3s 惯性滑行,预判松杆是手感核心(设计文档 §3.1)
var use_inertia := false
## 外部授予的无敌(如抢椅子关:坐上椅子=安全区)
var invulnerable := false
var rolling := false
var roll_dir := Vector2.ZERO
var roll_timer := 0.0
var roll_cd := 0.0
var knockback := Vector2.ZERO
var weapon: Node2D
var body_rect: ColorRect


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4  # 撞墙 + 撞守卫
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 14)
	shape.shape = rect
	add_child(shape)
	body_rect = ColorRect.new()
	body_rect.size = Vector2(12, 18)
	body_rect.position = Vector2(-6, -11)
	body_rect.color = Color("7fd1ff")
	add_child(body_rect)
	weapon = Weapon.new()
	weapon.setup(Weapon.PISTOL, "player", 1 | 4)  # 玩家子弹打墙和守卫
	weapon.visible = combat_enabled
	add_child(weapon)
	EventBus.player_hp_changed.emit(hp, MAX_HP)
	EventBus.weapon_equipped.emit(weapon.stats)


func _physics_process(delta: float) -> void:
	roll_cd = maxf(roll_cd - delta, 0.0)
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if rolling:
		roll_timer -= delta
		velocity = roll_dir * ROLL_SPEED
		if roll_timer <= 0.0:
			rolling = false
			body_rect.modulate.a = 1.0
	else:
		if use_inertia:
			# 380 px/s²:从满速到停约 0.24s 滑行
			velocity = velocity.move_toward(move * Tune.player_speed, 380.0 * delta) + knockback
		else:
			velocity = move * Tune.player_speed + knockback  # 移速走调参面板,F1 实时调
		if Input.is_action_just_pressed("roll") and roll_cd <= 0.0 and move != Vector2.ZERO:
			rolling = true
			roll_dir = move.normalized()
			roll_timer = ROLL_TIME
			roll_cd = ROLL_CD
			body_rect.modulate.a = 0.45  # 半透明 = 无敌帧的视觉提示
			Game.play_sfx("roll")
	knockback = knockback.move_toward(Vector2.ZERO, 600.0 * delta)
	move_and_slide()
	_update_aim()
	# 鼠标悬在调参面板上时停火,不然拖滑条会一直放枪
	if combat_enabled and not rolling and Input.is_action_pressed("shoot") and not Tune.mouse_over_panel():
		weapon.try_fire()
	if combat_enabled and Input.is_action_just_pressed("interact"):
		_try_pickup()


func _update_aim() -> void:
	# 手柄右摇杆优先;摇杆没动就跟随鼠标
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var dir: Vector2
	if stick.length() > 0.3:
		dir = stick.normalized()
	else:
		dir = (get_global_mouse_position() - global_position).normalized()
	if dir != Vector2.ZERO:
		weapon.set_aim(dir)


func _try_pickup() -> void:
	for node in get_tree().get_nodes_in_group("weapon_pickup"):
		if node.global_position.distance_to(global_position) < 18.0:
			var old: Dictionary = weapon.stats
			weapon.setup(node.stats, "player", 1 | 4)
			EventBus.weapon_equipped.emit(weapon.stats)
			node.swap_to(old)  # 旧枪原地放回,可以反悔
			return


func heal(amount: int) -> void:
	if hp <= 0:
		return
	hp = mini(hp + amount, MAX_HP)
	EventBus.player_hp_changed.emit(hp, MAX_HP)


## 被捅:刀无视"安全区无敌"(椅子防弹不防刀),但翻滚无敌帧仍可闪避
func stabbed(dmg: int, from_dir: Vector2) -> void:
	if rolling or hp <= 0:
		return
	var was_invulnerable := invulnerable
	invulnerable = false
	take_damage(dmg, from_dir)
	invulnerable = was_invulnerable


func take_damage(dmg: int, from_dir: Vector2) -> void:
	if rolling or invulnerable or hp <= 0:
		return  # 翻滚无敌帧 / 安全区免伤
	hp -= dmg
	knockback = from_dir * 140.0 * Tune.knockback_scale
	EventBus.player_hp_changed.emit(hp, MAX_HP)
	Game.shake(3.0)
	Game.play_sfx("hit", 0.6)  # 低音调区分"我挨打"和"我打中"
	modulate = Color(3, 3, 3)  # 受击白闪
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.15)
	if hp <= 0:
		visible = false
		set_physics_process(false)
		EventBus.player_died.emit()
