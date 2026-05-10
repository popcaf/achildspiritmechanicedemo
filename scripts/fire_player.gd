extends "res://scripts/stance_player.gd"


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for fire-themed animations.
	# Add an AnimationPlayer/AnimatedSprite2D as a sibling of FlipRoot and drive it here.
	# Example:
	#     match state:
	#         "idle":   $AnimationPlayer.play("fire_idle")
	#         "run":    $AnimationPlayer.play("fire_run")
	#         "jump":   $AnimationPlayer.play("fire_jump")
	#         "fall":   $AnimationPlayer.play("fire_fall")
	#         "dash":   $AnimationPlayer.play("fire_dash")
	#         "attack": $AnimationPlayer.play("fire_attack")
	#         "heavy":  $AnimationPlayer.play("fire_heavy")
	pass
