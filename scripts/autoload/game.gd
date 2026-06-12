extends Node
## 全局服务(autoload):输入注册、屏震转发、hitstop、中文 UI 字体。
## 输入用代码注册而不是写在 project.godot 里,方便统一管理死区和双输入(键鼠 + 手柄)。

var camera: Camera2D
var _hitstopping := false
var _ui_font: SystemFont


func _enter_tree() -> void:
	_setup_inputs()


## Godot 默认字体不含中文,用系统字体兜底(macOS 是 PingFang SC)
func ui_font() -> SystemFont:
	if _ui_font == null:
		_ui_font = SystemFont.new()
		_ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC"])
	return _ui_font


func shake(amount: float) -> void:
	if amount > 0.0 and is_instance_valid(camera):
		camera.add_shake(amount)


## 命中停顿:全局时间放慢一瞬再恢复——打击感三件套之一(设计文档 §6:命中 0.05s hitstop)
func hitstop(duration := 0.05) -> void:
	if _hitstopping:
		return
	_hitstopping = true
	Engine.time_scale = 0.05
	# ignore_time_scale = true,否则这个计时器自己也被放慢了
	await get_tree().create_timer(duration, true, false, true).timeout
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
