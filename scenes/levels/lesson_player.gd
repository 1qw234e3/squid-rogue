# 声明本脚本附加在 CharacterBody2D 节点上:这是 Godot 专为"代码控制移动 + 需要碰撞"设计的角色基类
extends CharacterBody2D

# 声明一个自定义信号:它本身不做任何事,只是一个"广播频道",按下 J 键时由下面的代码发出
signal flash_requested

# 移动速度常量(单位:像素/秒):写成常量放在顶部,想调手感时只改这一处
const SPEED := 200.0

# 缓存子节点 BodyRect(小人的 32x32 色块)的引用:@onready 表示等节点进入场景树后才取值,否则会取到空
@onready var body_rect: ColorRect = $BodyRect


# _ready 由引擎在节点第一次进入场景树时调用、只调用一次:适合做"开场前的准备工作"
func _ready() -> void:
	# 把信号连接到下面的处理函数:从此每次 flash_requested 被发出,_on_flash_requested 就会被自动调用
	flash_requested.connect(_on_flash_requested)


# _physics_process 由引擎每个物理帧调用(默认每秒 60 次):移动和碰撞逻辑放这里节奏最稳定
func _physics_process(_delta: float) -> void:
	# 读取四个方向键(ui_left 等是 Godot 内置动作,默认绑定方向键),合成一个长度不超过 1 的方向向量
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# 方向 × 速度 = 本帧想要的移动速度:velocity 是 CharacterBody2D 自带属性,供下一行使用
	velocity = direction * SPEED
	# 按 velocity 移动并自动处理碰撞:撞到墙(StaticBody2D)时引擎会把小人挡住,这就是"碰墙停下"的来源
	move_and_slide()


# _unhandled_input 由引擎在每次出现"没被界面消化掉"的输入事件时调用:适合处理一次性按键
func _unhandled_input(event: InputEvent) -> void:
	# 过滤事件:必须是键盘事件、是"按下"而非松开、不是按住不放时系统自动重复(echo)、且按的是 J 键
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		# 发出自定义信号:这一行只负责"喊一嗓子",具体做什么由连接了信号的函数决定——这就是信号解耦的意义
		flash_requested.emit()


# 信号处理函数:平时永远不会执行,只有 flash_requested 被 emit 的那一刻才会被调用
func _on_flash_requested() -> void:
	# 按任务要求打印到控制台:证明信号确实被发出、也确实被接收到了
	print("信号已发出")
	# 创建一个补间(Tween)动画器:用于在指定时长内平滑地修改某个属性,实现"闪烁"
	var tween := create_tween()
	# 第一步:用 0.1 秒把色块的 modulate(整体颜色滤镜)的透明度降到 0.2,小人变得几乎看不见
	tween.tween_property(body_rect, "modulate", Color(1, 1, 1, 0.2), 0.1)
	# 第二步:再用 0.1 秒恢复完全不透明,与上一步连起来就是"闪烁一次"(Tween 的步骤默认按顺序执行)
	tween.tween_property(body_rect, "modulate", Color(1, 1, 1, 1), 0.1)
