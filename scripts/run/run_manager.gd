extends Node
## 局流程总控(autoload,设计文档 §10 RunManager):
## 大厅 → [沙盒 → 广播 → 小游戏 → 结算] × N → 决赛 → 结果
## 阶段A:NPC 尚未登场,其他 47 人的淘汰按曲线模拟——
## 这正是 §4.5"抽象层 LOD"的思路,先用在全员身上,阶段D再让近景的人真实起来。

const SCENE_LOBBY := "res://scenes/run/Lobby.tscn"
const SCENE_SANDBOX := "res://scenes/run/Sandbox.tscn"
const SCENE_BRIEFING := "res://scenes/run/Briefing.tscn"
const SCENE_RESULTS := "res://scenes/run/Results.tscn"
const SCENE_REPORT := "res://scenes/run/RoundReport.tscn"

const GAMES := {
	"redlight": {
		"name": "木头人", "scene": "res://scenes/games/RedLight.tscn",
		"rules": "绿灯前进,红灯静止。\n红灯期间移动者,就地淘汰。\n限时 120 秒到达终点线。",
	},
	"guardhunt": {
		"name": "守卫猎杀", "scene": "res://scenes/m0/M0Arena.tscn",
		"rules": "你将被投入迷宫,守卫已获击杀许可。\n找到出口,或者杀出一条路。",
	},
	"chairs": {
		"name": "抢椅子", "scene": "res://scenes/games/Chairs.tscn",
		"rules": "音乐响起时保持移动,站定将被狙击。\n音乐停止后,坐上椅子的人活下来。\n没抢到的,清场弹幕会替你做决定。",
	},
}

const SURVIVOR_CURVE := [48, 30, 18, 10]  # 各轮开始时的存活数
const FINALE_PRIZE_PER_HEAD := 100    # 每淘汰一人入池 100(设计文档 §1.2)

var active := false        # 是否在一局之中(false 时各场景可独立运行调试)
var round_index := 0
var survivors := 48
var prize_pool := 0
var tickets := 0           # 配给券:局内货币,死亡清零(设计文档 §2.7)
var intel_known := false   # 本轮是否买过"下一场是什么"的情报
var champion := false
var rounds_survived := 0
var schedule: Array = []
var last_eliminated := 0  # 上一场淘汰人数(结算插页用)
var last_gain := 0        # 上一场奖金池涨幅


func start_run() -> void:
	active = true
	round_index = 0
	survivors = SURVIVOR_CURVE[0]
	prize_pool = 0
	tickets = 100  # 开局配给 100 券(设计文档 §1.1)
	intel_known = false
	champion = false
	rounds_survived = 0
	schedule = ["redlight", "guardhunt", "chairs"]
	schedule.shuffle()                      # Roguelike:关卡顺序随机
	schedule.append("finale_guardhunt")     # 决赛占位:守卫猎杀加强版,真决赛竞技场后续替换
	_change(SCENE_SANDBOX)


func current_game_id() -> String:
	var id: String = schedule[round_index]
	return "guardhunt" if id == "finale_guardhunt" else id


func current_game() -> Dictionary:
	return GAMES[current_game_id()]


func is_finale() -> bool:
	return active and round_index >= schedule.size() - 1


## 沙盒倒计时归零 → 广播宣读规则
func go_briefing() -> void:
	if active:
		_change(SCENE_BRIEFING)


## 广播读完 → 传送进小游戏
func start_game() -> void:
	if active:
		_change(current_game().scene)


## 小游戏向流程汇报的唯一接口
func minigame_finished(player_alive: bool) -> void:
	if not active:
		return
	if not player_alive:
		active = false
		_change(SCENE_RESULTS)
		return
	rounds_survived += 1
	if is_finale():
		champion = true
		prize_pool = (SURVIVOR_CURVE[0] - 1) * FINALE_PRIZE_PER_HEAD  # 47 人全灭,大池归你
		active = false
		_change(SCENE_RESULTS)
		return
	# 模拟其他参赛者的本轮死亡:存活数沿曲线递减,大池上涨
	var next: int = SURVIVOR_CURVE[round_index + 1]
	last_eliminated = survivors - next
	last_gain = last_eliminated * FINALE_PRIZE_PER_HEAD
	prize_pool += last_gain
	survivors = next
	round_index += 1
	intel_known = false
	_change(SCENE_REPORT)  # 先看煽动性结算,再回沙盒


## 结算插页读完 → 回沙盒
func report_done() -> void:
	if active:
		_change(SCENE_SANDBOX)


func back_to_lobby() -> void:
	active = false
	_change(SCENE_LOBBY)


func _change(path: String) -> void:
	# 延迟切场景:调用方往往正在物理回调里,立刻切会炸
	get_tree().change_scene_to_file.call_deferred(path)
