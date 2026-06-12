extends Node2D
## 掉在地上的武器:玩家走近按 E 拾取。换下来的旧枪会原地放回,允许反悔。
## 不参与物理,纯靠距离判定,省掉一层碰撞配置。

var stats := {}
var box: ColorRect
var label: Label


func _ready() -> void:
	add_to_group("weapon_pickup")
	box = ColorRect.new()
	box.size = Vector2(10, 6)
	box.position = Vector2(-5, -3)
	add_child(box)
	label = Label.new()
	label.add_theme_font_override("font", Game.ui_font())
	label.add_theme_font_size_override("font_size", 8)
	label.position = Vector2(-16, -16)
	add_child(label)
	_refresh()


func setup(s: Dictionary) -> void:
	stats = s
	if box:
		_refresh()


func swap_to(old_stats: Dictionary) -> void:
	stats = old_stats
	_refresh()


func _refresh() -> void:
	box.color = stats.get("color", Color.WHITE)
	label.text = str(stats.get("name", "?"))
