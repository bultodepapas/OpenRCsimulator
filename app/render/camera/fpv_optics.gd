## CAM-FPV: resolve the optical pose from the datum already used to draw the vehicle.
extends RefCounted

const Frames := preload("res://render/frames.gd")
const Math3D := preload("res://physics/math3d.gd")


## Positive scale is allowed on structural transforms. A reflected or collapsed
## coordinate frame cannot define the mount's right, up and forward directions.
static func is_valid_frame(frame: Transform3D) -> bool:
	var det := frame.basis.determinant()
	return frame.is_finite() and is_finite(det) and det > 0.0


## Inputs are admitted render frames, with camera forward along -Z and up along +Y.
## The full datum transforms the attachment point. Only rotations turn the lens:
## anisotropic scale on a parent must not skew a tilted camera's optical axes.
static func compose(datum: Transform3D, mount: Transform3D) -> Transform3D:
	var optical := datum.orthonormalized() * mount.orthonormalized()
	optical.origin = datum * mount.origin
	return optical


## Reference for the admitted render frames. Expand the lens axes in the datum
## basis so a flight can compare the complete result against native composition.
static func compose_reference(datum: Transform3D, mount: Transform3D) -> Transform3D:
	var body := datum.basis.orthonormalized()
	var lens := mount.basis.orthonormalized()
	var optical := Basis(_in_axes(body, lens.x), _in_axes(body, lens.y), _in_axes(body, lens.z))
	return Transform3D(optical, datum.origin + _in_axes(datum.basis, mount.origin))


static func _in_axes(axes: Basis, v: Vector3) -> Vector3:
	return axes.x * v.x + axes.y * v.y + axes.z * v.z


## Multirotor mounts are expressed in metres from the CG in FRD. Add their
## offset to the position in float64 before rounding once into render space.
## An invalid pose has a nonfinite origin, so a camera can retain its last view.
static func from_ned(position: PackedFloat64Array, attitude: PackedFloat64Array,
		mount_frd: PackedFloat64Array, tilt_rad: float) -> Transform3D:
	if position.size() != 3 or attitude.size() != 4 or mount_frd.size() != 3 or not is_finite(tilt_rad):
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var norm_squared := attitude[0] * attitude[0] + attitude[1] * attitude[1] \
		+ attitude[2] * attitude[2] + attitude[3] * attitude[3]
	if not is_finite(norm_squared) or norm_squared <= 0.0:
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var q := Math3D.q_normalized(attitude)
	var offset := Math3D.q_rotate(q, mount_frd)
	var lens := Frames.ned_to_render([position[0] + offset[0], position[1] + offset[1], position[2] + offset[2]])
	# NED -> render is a proper rotation, so the quaternion's vector part
	# uses the same frame conversion as a direction. Its scalar part is unchanged.
	var axis := Frames.ned_to_render([q[1], q[2], q[3]])
	var body := Basis(Quaternion(axis.x, axis.y, axis.z, q[0]).normalized())
	return compose(Transform3D(body, lens), Transform3D(Basis(Vector3.RIGHT, tilt_rad), Vector3.ZERO))
