extends CanvasLayer
## F1 调参面板(autoload):手感参数做成滑条、实时生效,把迭代从"改码重启"
## 变成"边玩边拖"。挂成 autoload 是为了按 R 重开局后调好的值不丢。
## 调满意后点"打印当前值",把数值抄回设计文档 §12。

var player_speed := 90.0
var shake_scale := 1.0
var hitstop_duration := 0.05
var fire_rate_scale := 1.0
var bullet_speed_scale := 1.0
var knockback_scale := 1.0
# —— 撤离模式(图纸起手值,依§12 调)——
var threat_shot := 1.0      # 枪声威胁(0.5s 节流窗内只记一次)
var threat_kill := 2.0
var drip_interval := 20.0   # 90s 后的被动滴漏间隔
var t1_squad := 2.0         # 各档增援人数
var t2_squad := 3.0
var t3_squad := 2.0
var extract_time := 5.0     # 撤离引导秒数
var pickup_blue := 0.5
var pickup_gold := 1.0

var panel: PanelContainer
var _dragging := false  # 滑条抓着鼠标时为真,即使鼠标甩出了面板边缘


func _ready() -> void:
	layer = 100
	visible = false
	panel = PanelContainer.new()
	panel.position = Vector2(8, 50)
	add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "调参面板(F1 开关)"
	_style(title, 10)
	vbox.add_child(title)
	_add_slider(vbox, "移动速度", 50.0, 160.0, 1.0, player_speed, func(v: float) -> void: player_speed = v)
	_add_slider(vbox, "屏震幅度 x", 0.0, 3.0, 0.05, shake_scale, func(v: float) -> void: shake_scale = v)
	_add_slider(vbox, "hitstop 秒", 0.0, 0.15, 0.005, hitstop_duration, func(v: float) -> void: hitstop_duration = v)
	_add_slider(vbox, "射速 x", 0.5, 2.5, 0.05, fire_rate_scale, func(v: float) -> void: fire_rate_scale = v)
	_add_slider(vbox, "子弹速度 x", 0.5, 2.0, 0.05, bullet_speed_scale, func(v: float) -> void: bullet_speed_scale = v)
	_add_slider(vbox, "击退力度 x", 0.0, 3.0, 0.05, knockback_scale, func(v: float) -> void: knockback_scale = v)
	_add_slider(vbox, "威胁/枪声", 0.0, 5.0, 0.5, threat_shot, func(v: float) -> void: threat_shot = v)
	_add_slider(vbox, "威胁/击杀", 0.0, 6.0, 0.5, threat_kill, func(v: float) -> void: threat_kill = v)
	_add_slider(vbox, "滴漏间隔 s", 5.0, 60.0, 1.0, drip_interval, func(v: float) -> void: drip_interval = v)
	_add_slider(vbox, "T1 增援", 0.0, 6.0, 1.0, t1_squad, func(v: float) -> void: t1_squad = v)
	_add_slider(vbox, "T2 增援", 0.0, 6.0, 1.0, t2_squad, func(v: float) -> void: t2_squad = v)
	_add_slider(vbox, "T3 续援", 0.0, 6.0, 1.0, t3_squad, func(v: float) -> void: t3_squad = v)
	_add_slider(vbox, "撤离引导 s", 3.0, 8.0, 0.5, extract_time, func(v: float) -> void: extract_time = v)
	_add_slider(vbox, "蓝货拾取 s", 0.0, 3.0, 0.1, pickup_blue, func(v: float) -> void: pickup_blue = v)
	_add_slider(vbox, "金货拾取 s", 0.0, 3.0, 0.1, pickup_gold, func(v: float) -> void: pickup_gold = v)
	var btn := Button.new()
	btn.text = "打印当前值到控制台"
	_style(btn, 9)
	btn.pressed.connect(_print_values)
	vbox.add_child(btn)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		visible = not visible


## 鼠标悬在面板上、或正拖着滑条(哪怕甩出面板边缘)时,玩家停火
func mouse_over_panel() -> bool:
	return visible and (_dragging or panel.get_global_rect().has_point(panel.get_global_mouse_position()))


func _style(control: Control, font_size: int) -> void:
	control.add_theme_font_override("font", Game.ui_font())
	control.add_theme_font_size_override("font_size", font_size)


func _add_slider(vbox: VBoxContainer, text: String, minv: float, maxv: float, step: float, initial: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	vbox.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(80, 0)
	_style(name_label, 9)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(130, 12)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.drag_started.connect(func() -> void: _dragging = true)
	slider.drag_ended.connect(func(_changed: bool) -> void: _dragging = false)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = _fmt(initial)
	value_label.custom_minimum_size = Vector2(40, 0)
	_style(value_label, 9)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		value_label.text = _fmt(v)
	)


func _fmt(v: float) -> String:
	return ("%.3f" % v).rstrip("0").rstrip(".")


func _print_values() -> void:
	print("=== 手感参数(抄回设计文档 §12)===")
	print("移动速度: %.0f px/s" % player_speed)
	print("屏震幅度: x%.2f" % shake_scale)
	print("hitstop: %.3f s" % hitstop_duration)
	print("射速: x%.2f" % fire_rate_scale)
	print("子弹速度: x%.2f" % bullet_speed_scale)
	print("击退力度: x%.2f" % knockback_scale)
