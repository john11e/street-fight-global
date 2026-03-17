# combo_text.gd
# Attach to: res://scenes/vfx/ComboText.tscn (Node3D)
# Billboard Label3D that pops up over a fighter showing combo count.
# Scales in, floats upward, fades out.

extends Node3D

@onready var label : Label3D = $Label3D

const FLOAT_SPEED   := 1.2    # upward drift m/s
const FADE_DURATION := 0.9
const SCALE_IN_TIME := 0.12

var _timer : float = 0.0
var _active: bool  = false

const COMBO_COLORS := [
	Color(1.0, 1.0, 1.0),   # 1–2  white
	Color(1.0, 0.85, 0.0),  # 3–4  yellow
	Color(1.0, 0.5,  0.0),  # 5–6  orange
	Color(1.0, 0.15, 0.0),  # 7–9  red
	Color(0.8, 0.0,  1.0),  # 10+  purple
]

func _ready() -> void:
	if not label:
		label        = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		label.outline_size = 8
		add_child(label)
	visible = false

func set_combo(count: int) -> void:
	match count:
		1, 2:  label.text = "%d HIT" % count
		3, 4:  label.text = "%d HIT  NICE!" % count
		5, 6:  label.text = "%d HIT  GREAT!" % count
		7, 8, 9: label.text = "%d HIT  AMAZING!" % count
		_:     label.text = "%d HIT  LEGENDARY!" % count

	var color_idx := clamp((count - 1) / 2, 0, COMBO_COLORS.size() - 1)
	label.modulate = COMBO_COLORS[color_idx]
	label.outline_modulate = Color(0, 0, 0, 0.9)

func play() -> void:
	visible  = true
	_active  = true
	_timer   = 0.0
	scale    = Vector3.ONE * 0.1
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, SCALE_IN_TIME).set_trans(Tween.TRANS_BACK)

func _process(delta: float) -> void:
	if not _active:
		return
	_timer      += delta
	position.y  += FLOAT_SPEED * delta
	# Fade out after half duration
	if _timer > FADE_DURATION * 0.5:
		var fade_progress := (_timer - FADE_DURATION * 0.5) / (FADE_DURATION * 0.5)
		label.modulate.a  = clamp(1.0 - fade_progress, 0.0, 1.0)
	if _timer >= FADE_DURATION:
		_active  = false
		visible  = false
		set_process(false)
