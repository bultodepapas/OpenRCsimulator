## SCENERY-PLAN SC-22 and SC-03: named views of the field. The first five are the Home "postcards" offered to the menu
## track (fixed, still compositions with the sun behind or beside the camera); the rest are the evidence views the
## scenery captures and budget checks use. Positions in NED metres (down negative = up), FOV in degrees (vertical).
extends RefCounted

const VIEWS := {
	# --- postcards (SC-22) ---
	"postcard_club": {eye = [26.0, 64.0, -24.0], at = [-24.0, 0.0, -3.0], fov = 38.0, postcard = true,
		note = "The club from above the runway's east end, like the owner's photo"},
	"postcard_pits": {eye = [-6.0, -52.0, -2.6], at = [-19.0, -30.0, -1.4], fov = 42.0, postcard = true,
		note = "Under the west shelter: tables, stands, the parked fleet"},
	"postcard_pavilion": {eye = [-4.0, 14.0, -1.7], at = [-21.0, -2.0, -2.0], fov = 46.0, postcard = true,
		note = "The pavilion, flag and benches from the pilot line"},
	"postcard_meadow": {eye = [30.0, 40.0, -6.0], at = [140.0, 150.0, -1.0], fov = 40.0, postcard = true,
		note = "Bales and wildflowers in the meadow, treeline beyond"},
	"postcard_farm": {eye = [12.0, 0.0, -1.7], at = [597.0, 345.0, -6.0], fov = 9.0, postcard = true,
		note = "The farmstead through the NNE gap with a long lens"},
	# --- evidence views ---
	"pilot_north": {eye = [0.0, 0.0, -1.7], at = [300.0, 0.0, -8.0], fov = 50.0, note = "The flight view: the meadow, hedge, treeline"},
	"pilot_south": {eye = [0.0, 0.0, -1.7], at = [-30.0, 0.0, -1.5], fov = 50.0, note = "Turning round: the club"},
	"pilot_east": {eye = [0.0, 0.0, -1.7], at = [0.0, 1000.0, -12.0], fov = 20.7, note = "East corridor: paddock, pylons, wind farm"},
	"pilot_west": {eye = [0.0, 0.0, -1.7], at = [160.0, -2100.0, -8.0], fov = 20.7, note = "West corridor: the village and church"},
	"car_park": {eye = [-30.0, 8.0, -3.0], at = [-39.0, -12.0, -0.5], fov = 45.0, note = "The car row, gravel and trees"},
	"aerial_overview": {eye = [140.0, 160.0, -140.0], at = [-20.0, 0.0, 0.0], fov = 50.0, note = "Raised overview (contact shadows, G-1 interim)"},
	"fleet_close": {eye = [-11.5, -33.0, -1.8], at = [-18.0, -31.0, -0.4], fov = 50.0, note = "The parked fleet under the west shelter"},
	"birds_watch": {eye = [0.0, 0.0, -1.7], at = [420.0, -260.0, -32.0], fov = 20.7, note = "Toward the optional flock (--scenery_birds=on)"},
	"turbines_zoom": {eye = [0.0, 0.0, -1.7], at = [690.0, 3980.0, -70.0], fov = 6.0, note = "The wind farm at 4 km, long lens"},
}


static func names(postcards_only := false) -> Array[String]:
	var out: Array[String] = []
	for k: String in VIEWS:
		if not postcards_only or VIEWS[k].get("postcard", false):
			out.append(k)
	return out
