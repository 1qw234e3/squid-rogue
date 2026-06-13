extends Node
## 全局服务(autoload):输入注册、屏震转发、hitstop、中文 UI 字体。
## 输入用代码注册而不是写在 project.godot 里,方便统一管理死区和双输入(键鼠 + 手柄)。

const SFX_PATHS := {
	"shoot": "res://assets/sfx/shoot.wav",
	"shoot_heavy": "res://assets/sfx/shoot_heavy.wav",
	"swing": "res://assets/sfx/swing.wav",
	"melee_hit": "res://assets/sfx/melee_hit.wav",
	"hit": "res://assets/sfx/hit.wav",
	"kill": "res://assets/sfx/kill.wav",
	"roll": "res://assets/sfx/roll.wav",
	"alert": "res://assets/sfx/alert.wav",
}

var camera: Camera2D
var _hitstopping := false
var _ui_font: SystemFont
var _light_tex: GradientTexture2D
var _sfx_players: Array = []
var _sfx_streams := {}
var _sfx_index := 0


func _enter_tree() -> void:
	_setup_inputs()


func _ready() -> void:
	# 一个小播放器池轮转使用,连发时音效不会互相掐断
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_sfx_players.append(p)
	# 启动时全部预载:第一枪不卡顿,加载失败也能在启动时立刻暴露
	for key in SFX_PATHS:
		_sfx_streams[key] = load(SFX_PATHS[key])
		assert(_sfx_streams[key] != null, "音效加载失败: " + SFX_PATHS[key])


## 播放占位音效(无方位,用于玩家自身/UI),带轻微随机变调
func play_sfx(sfx: String, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	p.stream = _sfx_streams[sfx]
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.play()


## 在世界坐标上播放(自动 pan + 距离衰减):守卫的声音都走这里,听声辨位
func play_sfx_at(sfx: String, pos: Vector2, pitch := 1.0) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = _sfx_streams[sfx]
	p.volume_db = -8.0
	p.max_distance = 280.0  # 可听半径,略小于半个屏幕宽;要对齐警觉半径就调这里
	p.attenuation = 1.5
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Godot 默认字体不含中文,用系统字体兜底(macOS 是 PingFang SC)
func ui_font() -> SystemFont:
	if _ui_font == null:
		_ui_font = SystemFont.new()
		_ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC"])
	return _ui_font


## 径向渐变光斑贴图(缓存共享):PointLight2D 通用,中心亮边缘透明
func radial_light_texture() -> GradientTexture2D:
	if _light_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		_light_tex = GradientTexture2D.new()
		_light_tex.gradient = grad
		_light_tex.fill = GradientTexture2D.FILL_RADIAL
		_light_tex.fill_from = Vector2(0.5, 0.5)
		_light_tex.fill_to = Vector2(0.5, 0.0)
		_light_tex.width = 256
		_light_tex.height = 256
	return _light_tex


## 世界坐标处冒一行小字,上浮淡出(拾取/奖励提示通用)
func float_text(pos: Vector2, text: String, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ui_font())
	l.add_theme_font_size_override("font_size", 8)
	l.modulate = color
	get_tree().current_scene.add_child(l)
	l.global_position = pos + Vector2(-20, -18)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 14.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


## UI 快捷:建一个用中文字体的 Label(默认字体不含中文)
func make_label(parent: Node, pos: Vector2, font_size: int, text := "") -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_override("font", ui_font())
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func shake(amount: float) -> void:
	if amount > 0.0 and is_instance_valid(camera):
		camera.add_shake(amount * Tune.shake_scale)


## 命中停顿:全局时间放慢一瞬再恢复——打击感三件套之一(设计文档 §6:命中 0.05s hitstop)
func hitstop() -> void:
	if _hitstopping or Tune.hitstop_duration <= 0.0:
		return
	_hitstopping = true
	Engine.time_scale = 0.05
	# ignore_time_scale = true,否则这个计时器自己也被放慢了
	await get_tree().create_timer(Tune.hitstop_duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstopping = false


func _setup_inputs() -> void:
	# 移动死区 0.15,按设计文档 §3.1 的摇杆死区基准
	_add_action("move_left", 0.15, [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", 0.15, [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("move_up", 0.15, [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("move_down", 0.15, [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("shoot", 0.5, [_mouse(MOUSE_BUTTON_LEFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add_action("roll", 0.5, [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)])
	_add_action("interact", 0.5, [_key(KEY_E), _joy_button(JOY_BUTTON_X)])
	_add_action("restart", 0.5, [_key(KEY_R), _joy_button(JOY_BUTTON_START)])


func _add_action(action: String, deadzone: float, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e
