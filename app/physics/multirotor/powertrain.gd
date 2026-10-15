# DR-05a (foundation slice): one first-order motor per rotor. The commanded speed is the ESC duty times the
# full-duty speed and the shaft follows it with the measured time constant (Agilicious τ = 39.1 ms on a load
# cell, DR-01 §1.3). The drone plan's full powertrain (back-EMF, pack voltage, synchronous ESC, battery) is DR-05;
# this rung keeps the duty-to-speed path explicit so the controller work (DR-07) can start on a known plant.
extends RefCounted


## Duty clamped to the ESC's idle floor and output limit.
static func duty(command: float, motor: Dictionary) -> float:
	return clampf(command, float(motor.idle_duty), float(motor.output_limit))


## Rotor speed derivative (rad/s²) toward the duty's steady speed.
static func omega_rate(omega: float, duty_value: float, motor: Dictionary) -> float:
	return (duty_value * float(motor.full_duty_speed_rad_s) - omega) / float(motor.time_constant_s)


## The duty that holds `omega` steady.
static func duty_for_speed(omega: float, motor: Dictionary) -> float:
	return omega / float(motor.full_duty_speed_rad_s)
