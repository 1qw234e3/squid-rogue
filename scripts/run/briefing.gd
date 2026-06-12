extends Node2D
## 广播宣读(节奏器兼叙事者,设计文档 §1.2):黑屏 + 逐字打出规则,
## 读完自动传送进小游戏。Enter 可跳过打字/立即出发。

const CHAR_TIME := 0.03

var full_text := ""
var shown := 0.0
var done_typing := false
var wait := 1.4
var label: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("0a0c10")
	layer.add_child(bg)
	label = Game.make_label(layer, Vector2(70, 80), 13)
	var g: Dictionary = Run.current_game() if Run.active else {"name": "测试", "rules": "(独立运行预览,不会自动跳转)"}
	var round_name := "决赛" if Run.is_finale() else "第 %d 场游戏" % (Run.round_index + 1)
	full_text = "【广播】\n\n全体参赛者请注意。\n\n%s:%s\n\n%s\n\n祝各位好运。" % [round_name, g.name, g.rules]
	Game.play_sfx("alert", 0.7)  # 广播提示音(占位:低音调的哔哔)


func _process(delta: float) -> void:
	if not done_typing:
		shown += delta / CHAR_TIME
		var n := mini(int(shown), full_text.length())
		label.text = full_text.substr(0, n)
		if n >= full_text.length():
			done_typing = true
	else:
		wait -= delta
		if wait <= 0.0 and Run.active:
			set_process(false)
			Run.start_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if not done_typing:
			label.text = full_text
			done_typing = true
		elif Run.active:
			set_process(false)
			Run.start_game()
