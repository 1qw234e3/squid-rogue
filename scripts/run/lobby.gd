extends Node2D
## 大厅(占位):标题 + 报名进岛。局外养成(阶段E:角色解锁、设施)将挂在这里。


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("10141c")
	layer.add_child(bg)
	var title := Game.make_label(layer, Vector2(0, 110), 32, "孤  岛  4 8")
	title.size = Vector2(640, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := Game.make_label(layer, Vector2(0, 160), 10, "48 人登岛,一人离开。")
	sub.size = Vector2(640, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.7
	var prompt := Game.make_label(layer, Vector2(0, 230), 12, "—— 按 Enter 报名进岛 ——")
	prompt.size = Vector2(640, 20)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 呼吸闪烁,廉价但有效的"按我"暗示
	var tw := prompt.create_tween().set_loops()
	tw.tween_property(prompt, "modulate:a", 0.25, 0.8)
	tw.tween_property(prompt, "modulate:a", 1.0, 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		Run.start_run()
