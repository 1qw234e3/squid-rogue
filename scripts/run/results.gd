extends Node2D
## 结算画面:夺冠或淘汰。个人账户/局外养成(阶段E)接入前,先把信息摆清楚。


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("0a0c10")
	layer.add_child(bg)
	var title: Label
	var body: Label
	if Run.champion:
		title = Game.make_label(layer, Vector2(0, 100), 24, "冠 军")
		title.modulate = Color("ffd86b")
		body = Game.make_label(layer, Vector2(0, 150), 11,
			"47 名参赛者已离场。\n奖金 %d 已汇入你的账户。" % Run.prize_pool)
	else:
		title = Game.make_label(layer, Vector2(0, 100), 24, "你被淘汰了")
		title.modulate = Color("ff6b6b")
		body = Game.make_label(layer, Vector2(0, 150), 11,
			"存活轮次:%d\n你离场时奖金池:%d\n(死亡可带走的个人账户,阶段E接入)" % [Run.rounds_survived, Run.prize_pool])
	for l in [title, body]:
		l.size = Vector2(640, 80)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := Game.make_label(layer, Vector2(0, 290), 10, "按 Enter 返回大厅")
	hint.size = Vector2(640, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.6


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		Run.back_to_lobby()
