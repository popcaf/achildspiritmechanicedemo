extends "res://scripts/entities/player/stance_player.gd"


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for water-themed animations.
	# Add an AnimationPlayer/AnimatedSprite2D as a sibling of FlipRoot and drive it here.
	# Example:
	#     match state:
	#         "idle":   $AnimationPlayer.play("water_idle")
	#         "run":    $AnimationPlayer.play("water_run")
	#         "jump":   $AnimationPlayer.play("water_jump")
	#         "fall":   $AnimationPlayer.play("water_fall")
	#         "dash":   $AnimationPlayer.play("water_dash")
	#         "attack": $AnimationPlayer.play("water_attack")
	#         "heavy":  $AnimationPlayer.play("water_heavy")
	pass
