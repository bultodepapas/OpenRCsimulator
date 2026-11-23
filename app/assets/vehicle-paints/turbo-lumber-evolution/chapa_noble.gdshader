shader_type spatial;

uniform int part;
uniform mat3 rest_basis;
uniform vec3 rest_origin;
uniform float grow_amount;
uniform bool detail_enabled;
uniform sampler2D brushed_metal : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 skin_position;
varying vec3 skin_normal;

// Linear alloy colour and base roughness.
const vec4 ALUMINUM = vec4(0.56, 0.61, 0.65, 0.37);
const vec4 SATIN = vec4(0.46, 0.49, 0.52, 0.50);
const vec4 FORMED = vec4(0.64, 0.68, 0.71, 0.21);
const vec4 STEEL = vec4(0.30, 0.36, 0.43, 0.23);
const vec4 CHROME = vec4(0.72, 0.77, 0.80, 0.115);
const vec4 BRONZE = vec4(0.49, 0.24, 0.115, 0.31);
const vec4 ANODIZED_GOLD = vec4(0.81, 0.55, 0.16, 0.27);
const vec4 GASKET = vec4(0.040, 0.048, 0.056, 0.72);
const vec4 RUBBER = vec4(0.019, 0.023, 0.027, 0.89);
const float FILTERED_GRAIN = 0.54;

const int COWL = 8;
const int FLAP = 9;
const int AILERON = 10;
const int ELEVATOR = 11;
const int RUDDER = 12;
const int AXLE_HARDWARE = 13;
const int TIRE = 14;
const int EXHAUST = 15;

// Neutral stations from the imported Timber hinge nodes, in metres.
const float WING_HINGE = 0.157726;
const float ELEVATOR_HINGE = 0.704;
const float RUDDER_HINGE = 0.738;

void vertex() {
	skin_position = rest_basis * VERTEX + rest_origin;
	skin_normal = rest_basis * NORMAL;
	VERTEX += NORMAL * grow_amount;
}

float inside(float edge) {
	return clamp(0.5 - edge / max(fwidth(edge), 1e-6), 0.0, 1.0);
}

vec4 overlap(vec4 material, float offset) {
	vec4 c = mix(material, material * vec4(1.16, 1.16, 1.16, 1.0), inside(abs(offset + 0.0015) - 0.0010));
	return mix(c, GASKET, inside(abs(offset) - 0.0006));
}

float inlay(float x, float a, float b) {
	return inside(max(a - x, x - b));
}

vec4 rivet(vec4 material, vec2 offset, float radius, vec4 cap) {
	float edge = length(offset) - radius;
	vec4 c = mix(material, GASKET, inside(edge - 0.00042));
	float glint = inside(length(offset + vec2(0.28, -0.27) * radius) - 0.42 * radius);
	vec4 head = vec4(cap.rgb * (0.80 + 0.42 * glint), cap.a);
	return mix(c, head, inside(edge));
}

float repeat_offset(float x, float pitch) {
	return (fract(x / pitch + 0.5) - 0.5) * pitch;
}


float hash_cell(vec2 p) {
	vec3 q = fract(p.xyx * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float mottling(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), t.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0)), t.x), t.y);
}

float filtered_mottling(vec2 p, float contribution) {
	// Within this range, the cell and its neighbours give finite hash inputs.
	if (contribution == 0.0 && all(lessThanEqual(abs(p), vec2(1048576.0)))) {
		return FILTERED_GRAIN;
	}
	return mix(FILTERED_GRAIN, mottling(p), contribution);
}

// Inputs run aft in x. Cross-flow offset curves quadratically and the tail fades and narrows.
float streak(vec2 offset, float reach, float width, float drift, float grain) {
	float run = clamp(offset.x / reach, 0.0, 1.0);
	float cross = offset.y - drift * run * (0.55 + 0.45 * run);
	float taper = width * mix(1.0, 0.26, smoothstep(0.06, 1.0, run));
	float edge = abs(cross) - taper * (0.65 + 0.65 * grain);
	float feather = max(0.62 * taper, fwidth(cross));
	return smoothstep(-0.14 * width, 0.14 * width, offset.x)
		* (1.0 - smoothstep(-0.25 * taper, feather, edge))
		* (1.0 - smoothstep(0.16, 1.0, run));
}

// Raised fasteners trap a minute crescent and leave a short, intermittent wake behind the head.
vec4 fastener_wake(vec4 sheet, vec2 offset, vec2 station, float strength) {
	float seed = hash_cell(floor(station * 1000.0 + 0.5));
	float wake = streak(offset - vec2(0.0014, 0.0), mix(0.004, 0.027, seed),
		mix(0.00085, 0.00155, seed), (seed - 0.38) * 0.004, seed);
	return mix(sheet, vec4(0.10, 0.084, 0.073, 0.70), strength * smoothstep(0.42, 0.92, seed) * wake);
}

vec4 lap_deposit(vec4 sheet, float aft, float cross) {
	float irregular = mottling(vec2(aft * 95.0, cross * 280.0));
	float edge = smoothstep(-0.0002, 0.0018, aft) * (1.0 - smoothstep(0.0015, 0.008, aft));
	return mix(sheet, vec4(0.095, 0.083, 0.070, 0.70), edge * (0.12 + 0.38 * irregular));
}

vec4 wing(vec3 p) {
	float span = abs(p.x);
	float chord = p.z;
	float front_spar = chord - 0.043;
	float rear_spar = chord - (WING_HINGE - 0.020);
	vec4 c = mix(ALUMINUM, SATIN, max(inlay(span, 0.181, 0.362), inlay(span, 0.543, 0.696)));
	c = mix(c, SATIN, inside(-rear_spar));
	c = mix(c, FORMED, max(inside(front_spar), inside(0.696 - span)));
	c = mix(c, FORMED, inlay(span, 0.051, 0.081));
	if (span < 0.696) {
		c = lap_deposit(lap_deposit(c, front_spar, p.x), rear_spar, p.x);
		c = overlap(overlap(c, front_spar), rear_spar);
		float rib = repeat_offset(span, 0.181);
		if (chord > 0.045 && chord < WING_HINGE - 0.023 && span > 0.085) {
			c = overlap(c, rib);
			vec2 fastener = vec2(rib - 0.005, repeat_offset(chord - 0.008, 0.021));
			c = fastener_wake(c, fastener.yx, vec2(chord - fastener.y, sign(p.x) * (span - fastener.x)), 0.31);
			c = rivet(c, fastener, 0.0015, FORMED);
		}
		if (span > 0.085) {
			float fastener_row = abs(front_spar) < abs(rear_spar) ? front_spar - 0.005 : rear_spar + 0.005;
			vec2 fastener = vec2(repeat_offset(span - 0.012, 0.026), fastener_row);
			c = fastener_wake(c, fastener.yx, vec2(chord - fastener.y, sign(p.x) * (span - fastener.x)), 0.52);
			c = rivet(c, fastener, 0.0017, FORMED);
		}
	}
	if (chord > 0.031 && chord < 0.128) {
		c = rivet(c, vec2(span - 0.075, repeat_offset(chord, 0.021)), 0.0017, FORMED);
	}
	return c;
}

vec4 fuselage(vec3 p, vec3 n) {
	float waist = p.y + 0.025 * p.z;
	vec4 c = mix(ALUMINUM, SATIN, inlay(p.z, 0.243, 0.465));
	c = mix(c, SATIN, inside(waist + 0.047));
	float section = p.z - (p.z < 0.354 ? 0.243 : 0.465);
	c = lap_deposit(c, section, p.y + 0.13 * p.x);
	float stain = mottling(vec2(p.z * 62.0, p.x * 80.0));
	float under_lap = inlay(waist, -0.058, -0.047) * smoothstep(0.29, 0.77, stain);
	c = mix(c, vec4(0.17, 0.14, 0.11, 0.66), 0.40 * under_lap);
	c = overlap(overlap(c, section), waist + 0.047);
	if (abs(n.x) > 0.54 && p.z > -0.133 && p.z < 0.639) {
		vec2 section_rivet = vec2(section - 0.0048, repeat_offset(p.y, 0.023));
		vec2 lap_rivet = vec2(repeat_offset(p.z, 0.032), waist + 0.040);
		c = fastener_wake(c, section_rivet, p.zy - section_rivet, 0.54);
		c = fastener_wake(c, lap_rivet, vec2(p.z - lap_rivet.x, sign(p.x) * 0.06), 0.41);
		c = rivet(c, section_rivet, 0.0016, FORMED);
		c = rivet(c, lap_rivet, 0.0017, FORMED);
		vec2 plate = vec2(p.z - 0.366, p.y + 0.010);
		float rim = max(abs(plate.x) - 0.057, abs(plate.y) - 0.025);
		float clipped = max(rim, (abs(plate.x) + abs(plate.y) - 0.074) * 0.707);
		c = mix(c, GASKET, inside(clipped - 0.0013));
		c = mix(c, ALUMINUM, inside(clipped));
		vec2 washer = abs(plate) - vec2(0.044, 0.015);
		c = rivet(c, washer, 0.0029, ANODIZED_GOLD);
		c = mix(c, STEEL, inside(length(washer) - 0.0015));
	}
	return c;
}

float heat_shield(vec3 p) {
	return length(vec2((p.z + 0.178) / 0.030, (p.y + 0.009) / 0.015)) - 1.0;
}

vec4 cowl(vec3 p, vec3 n) {
	// Heat shields cover the sheet around the original pipes.
	float shield = heat_shield(p);
	vec4 c = mix(FORMED, STEEL, inside(shield) * smoothstep(0.52, 0.84, abs(n.x)));
	float flange = p.z + 0.161;
	c = overlap(lap_deposit(c, flange, p.y + p.x), flange);
	float around = atan(p.y + 0.006, p.x * 0.73) * 0.044;
	vec2 fastener = vec2(flange + 0.006, repeat_offset(around, 0.031));
	c = fastener_wake(c, fastener, vec2(p.z, around) - fastener, 0.50);
	return rivet(c, fastener, 0.0025, STEEL);
}

vec4 fixed_tail(vec2 p, float hinge) {
	float rail = p.y - hinge + 0.015;
	vec4 c = mix(ALUMINUM, SATIN, inside(-rail));
	c = overlap(c, rail);
	return rivet(c, vec2(repeat_offset(p.x - 0.010, 0.023), rail + 0.006), 0.0015, FORMED);
}

vec4 control(vec2 p, float hinge, vec4 sheet) {
	// The skin and fasteners stay with the actual moving mesh, including its leading cove.
	float seam = p.y - hinge - 0.012;
	vec4 c = lap_deposit(mix(sheet, FORMED, inside(seam)), seam, p.x);
	vec2 fastener = vec2(repeat_offset(p.x - 0.005, 0.024), seam - 0.005);
	c = fastener_wake(c, fastener.yx, p.yx - fastener.yx, 0.43);
	return rivet(overlap(c, seam), fastener, 0.0015, FORMED);
}

vec2 wheel_axis(float z) {
	return z > 0.58 ? vec2(-0.112, 0.759) : vec2(-0.198, 0.008);
}

vec4 wheel(vec3 p, vec3 n) {
	bool tailwheel = p.z > 0.58;
	vec2 hub = p.yz - wheel_axis(p.z);
	float r = length(hub);
	vec4 c = mix(RUBBER, FORMED, inside(r - (tailwheel ? 0.0038 : 0.018)));
	c = mix(c, BRONZE, inside(r - (tailwheel ? 0.0029 : 0.009)));
	c = mix(c, CHROME, inside(r - (tailwheel ? 0.0018 : 0.0056)));
	return mix(RUBBER, c, smoothstep(0.40, 0.72, abs(n.x)));
}


vec4 body_weather(vec3 p, vec3 n, vec3 grain) {
	// The two pipes end at z = -0.134. The plume starts there and fans towards the tail.
	float port = step(p.x, 0.0);
	float side = smoothstep(0.20, 0.66, abs(n.x));
	vec2 flow = vec2(p.z + 0.134, p.y + 0.009);
	float soot = 0.56 * streak(flow, mix(0.223, 0.189, port), 0.015, -0.015, grain.x);
	float filaments = 0.74 * streak(flow - vec2(0.001, -0.001), 0.142, 0.0064, -0.009, grain.y);
	filaments = max(filaments, 0.61 * streak(flow - vec2(0.009, 0.006), 0.179, 0.0033, -0.007, grain.y));
	filaments = max(filaments, 0.51 * streak(flow - vec2(0.006, -0.005), 0.098, 0.0029, -0.013, grain.z));
	soot = (soot + filaments * (0.29 + 0.34 * grain.y)) * side;

	// Worn seals catch runoff in the bottom corners of the actual side panes.
	// There is a small vertical component at the source and a longer fade aft.
	vec2 flank = p.zy;
	float window = 0.27 * streak(flank - vec2(0.077, -0.002), 0.055, 0.0024, -0.008, grain.y);
	window = max(window, 0.36 * streak(flank - vec2(0.151, -0.002), 0.073, 0.0030, -0.013, grain.y));
	window = max(window, 0.22 * streak(flank - vec2(0.244, 0.052), 0.059, 0.0022, -0.009, grain.y));
	float sill = 1.0 - smoothstep(0.001, 0.005, abs(p.y + 0.004));
	float panes = max(inlay(p.z, 0.017, 0.077), inlay(p.z, 0.086, 0.151));
	float trailing_jamb = abs(p.z - (p.z < 0.115 ? 0.077 : 0.151));
	float gasket = (1.0 - smoothstep(0.0008, 0.0055, trailing_jamb)) * inlay(p.y, -0.006, 0.048);
	window = max(window, max(sill * panes, gasket) * (0.10 + 0.24 * grain.x));

	float down = smoothstep(0.10, 0.75, -n.y);
	vec2 belly = vec2(p.z + 0.156, p.x);
	float oil = 0.67 * streak(belly - vec2(0.0, 0.003), 0.36, 0.0038, 0.023, grain.y);
	oil = max(oil, 0.40 * streak(belly - vec2(0.002, -0.004), 0.24, 0.0025, -0.018, grain.z));
	oil = max(oil, 0.39 * streak(belly - vec2(0.006, 0.003), 0.24, 0.0021, 0.009, grain.y));
	oil = max(oil, 0.19 * streak(belly, 0.28, 0.019, 0.013, grain.x));
	oil = max(oil, 0.52 * side * streak(flank - vec2(-0.154, -0.037), 0.20, 0.0026, -0.022, grain.y));
	oil = max(oil, 0.35 * side * streak(flank - vec2(-0.153, -0.042), 0.18, 0.0019, -0.025, grain.z));
	float road_grime = mottling(p.zx * vec2(26.0, 75.0));
	float dust = down * (0.035 + 0.28 * road_grime)
		* (1.0 - smoothstep(0.07, 0.39, abs(p.z - 0.135)));
	dust = max(dust, down * 0.30 * streak(vec2(p.z - 0.023, abs(p.x) - 0.039),
		0.27, 0.014, -0.020, grain.y));
	return vec4(max(soot, window * side), oil * max(side, down) * (0.70 + 0.30 * grain.z), dust, 0.0);
}

vec4 exhaust_weather(vec3 p, vec3 n, vec3 grain) {
	float rim = smoothstep(-0.149, -0.135, p.z);
	// The inward tube normals oppose the radial direction. Darken the bore, including its lower wall.
	vec2 radial = vec2(abs(p.x) - 0.06185, p.y + 0.009);
	float inside_wall = 1.0 - smoothstep(-0.70, -0.12, dot(normalize(radial + vec2(0.00001)), vec2(sign(p.x) * n.x, n.y)));
	float bore = max(inside_wall, smoothstep(0.10, 0.79, n.z)) * rim;
	float deposits = max(bore * 0.91, rim * (0.24 + 0.30 * grain.y));
	float oxide = smoothstep(-0.167, -0.150, p.z) * (1.0 - smoothstep(-0.145, -0.135, p.z));
	return vec4(deposits, 0.0, 0.0, oxide * (0.10 + 0.48 * grain.z));
}

vec4 hinge_weather(vec2 offset, vec3 grain, float down) {
	float contact = 1.0 - smoothstep(0.19, 1.0, length(offset / vec2(0.017, 0.010 + 0.004 * grain.x)));
	float rust = contact * (0.27 + 0.55 * grain.z) * down;
	float oil = 0.40 * streak(offset, 0.077, 0.0034, 0.006, grain.y) * down;
	float dirt = 0.28 * streak(offset, 0.10, 0.011, 0.011, grain.x);
	return vec4(0.0, oil, dirt, rust);
}

// Dry soot, wet oil, dust and local iron oxide have independent roughness.
vec4 weather(vec3 p, vec3 n, vec3 grain) {
	if (part == 1 || part == COWL) {
		vec4 marks = body_weather(p, n, grain);
		if (part == COWL) {
			float shield_edge = heat_shield(p);
			float rim = (1.0 - smoothstep(0.01, 0.18, abs(shield_edge + 0.12))) * inside(shield_edge);
			float hotspot = mottling(p.zy * 100.0) * mix(0.39, 1.0, smoothstep(-0.195, -0.156, p.z));
			marks.w = rim * smoothstep(0.31, 0.79, hotspot) * grain.z * smoothstep(0.32, 0.78, abs(n.x)) * 0.65;
		}
		return marks;
	}
	if (part == EXHAUST) {
		return exhaust_weather(p, n, grain);
	}
	if (part == AXLE_HARDWARE || part == 6 || part == TIRE || part == 5) {
		float hub_distance = length(p.yz - wheel_axis(p.z));
		float lower = p.z > 0.58 ? -0.092 : -0.151;
		float grit = mottling(p.yz * 75.0 + p.x * 43.0);
		float splash = (1.0 - smoothstep(lower - 0.041, lower + 0.009, p.y)) * (0.05 + 0.30 * grit);
		float rust = 0.0;
		if (part == AXLE_HARDWARE) {
			rust = (1.0 - smoothstep(0.004, 0.014, hub_distance)) * grain.z * 0.72;
		}
		return vec4(0.0, 0.0, splash, rust);
	}
	float down = 1.0 - smoothstep(-0.85, 0.30, n.y);
	if (part == 0 || part == FLAP || part == AILERON) {
		float station = abs(p.x) < 0.39 ? 0.24025 : 0.56202;
		vec2 hinge = vec2(p.z - WING_HINGE, abs(p.x) - station);
		vec4 marks = hinge_weather(hinge, grain, 0.35 + 0.65 * down);
		float lap = 0.18 * streak(vec2(p.z - 0.043, abs(p.x) - 0.075), 0.14, 0.011, 0.008, grain.y);
		marks.z = max(marks.z, lap * (0.20 + 0.80 * down));
		return marks;
	}
	bool horizontal = part == 2 || part == ELEVATOR;
	float pivot = horizontal ? ELEVATOR_HINGE : RUDDER_HINGE;
	float transverse = horizontal ? abs(p.x) - 0.018 : p.y - 0.0538;
	return hinge_weather(vec2(p.z - pivot, transverse), grain, horizontal ? 0.40 + 0.60 * down : 0.74);
}

void fragment() {
	vec3 p = skin_position;
	vec3 n = normalize(skin_normal);
	vec4 material;
	vec2 brush;
	if (part == 0) {
		material = wing(p);
		brush = vec2(p.z, abs(p.x)) * vec2(3.0, 1.6);
	} else if (part == FLAP || part == AILERON) {
		vec2 panel = vec2(abs(p.x), p.z);
		material = control(panel, WING_HINGE, part == FLAP ? SATIN : ALUMINUM);
		brush = panel * vec2(2.0, 5.4);
	} else if (part == 1 || part == COWL) {
		material = part == COWL ? cowl(p, n) : fuselage(p, n);
		brush = vec2(p.y + abs(p.x) * 0.40, p.z) * vec2(4.1, 2.3);
	} else if (part == 2 || part == 3 || part == ELEVATOR || part == RUDDER) {
		bool horizontal = part == 2 || part == ELEVATOR;
		vec2 panel = vec2(horizontal ? abs(p.x) : p.y, p.z);
		float hinge = horizontal ? ELEVATOR_HINGE : RUDDER_HINGE;
		material = part == ELEVATOR || part == RUDDER ? control(panel, hinge, SATIN) : fixed_tail(panel, hinge);
		brush = panel.yx * vec2(5.4, 2.8);
	} else if (part == EXHAUST) {
		material = mix(STEEL, vec4(0.39, 0.27, 0.16, 0.43), smoothstep(-0.171, -0.139, p.z) * 0.63);
		brush = p.yz * vec2(5.0, 2.2);
	} else {
		material = part == AXLE_HARDWARE ? CHROME : ALUMINUM;
		if (part == 6) {
			material = wheel(p, n);
		} else if (part == TIRE) {
			material = RUBBER;
		}
		brush = p.yz * 4.8;
	}
	float metal = 1.0 - smoothstep(0.56, 0.82, material.a);
	float brushed = 0.0;
	vec2 airflow = vec2(p.z, p.y + 0.74 * p.x);
	vec3 grain = vec3(mottling(airflow * vec2(34.0, 184.0)), FILTERED_GRAIN, FILTERED_GRAIN);
	if (detail_enabled) {
		brushed = (texture(brushed_metal, brush).r - 0.469) * metal * smoothstep(0.13, 0.43, material.a);
		vec2 striations = airflow * vec2(48.0, 710.0) + vec2(3.5, grain.x * 2.8);
		vec2 flakes = airflow * 960.0;
		// Evaluate both footprints before entering either fragment-varying guard.
		vec2 striation_rate = max(abs(dFdx(striations)), abs(dFdy(striations)));
		vec2 flake_rate = max(abs(dFdx(flakes)), abs(dFdy(flakes)));
		grain.y = filtered_mottling(striations, 1.0 - smoothstep(0.36, 1.2, max(striation_rate.x, striation_rate.y)));
		grain.z = filtered_mottling(flakes, 1.0 - smoothstep(0.34, 1.0, max(flake_rate.x, flake_rate.y)));
	}
	vec4 marks = clamp(weather(p, n, grain), vec4(0.0), vec4(1.0));
	vec3 sheen = mix(material.rgb, vec3(0.69, 0.67, 0.61), marks.z * 0.13 * metal);
	vec3 rust = mix(vec3(0.075, 0.023, 0.013), vec3(0.31, 0.091, 0.030), grain.z);
	vec3 worn = mix(sheen, rust, marks.w);
	worn = mix(worn, vec3(0.17, 0.129, 0.092), marks.z);
	worn = mix(worn, vec3(0.013, 0.011, 0.010), marks.x);
	worn = mix(worn, vec3(0.018, 0.011, 0.007), marks.y);
	float residue = max(max(marks.x, marks.y), max(marks.z, marks.w));
	metal *= 1.0 - residue * 0.90;
	float surface_roughness = mix(material.a, 0.83, max(marks.x, max(marks.z, marks.w)));
	surface_roughness = mix(surface_roughness, 0.27, marks.y);
	vec3 reflected = mat3(INV_VIEW_MATRIX) * reflect(-VIEW, normalize(NORMAL));
	// Keep a reflected horizon on the bright alloys in scenes with no sky probe.
	float sky = smoothstep(-0.06, 0.18 + 0.63 * surface_roughness, reflected.y);
	float polish = metal * (1.0 - surface_roughness);
	vec3 tone = mix(vec3(0.56, 0.58, 0.62), vec3(1.05, 1.12, 1.20), sky);
	ALBEDO = worn * mix(vec3(1.0), tone, 0.66 * polish) * (1.0 + 0.69 * brushed);
	ROUGHNESS = clamp(surface_roughness + 0.48 * brushed, 0.07, 0.96);
	float sheet_finish = mix(0.63, 1.0, smoothstep(-0.72, -0.14, n.y));
	METALLIC = metal * mix(0.61, 0.76, 1.0 - surface_roughness) * sheet_finish;
	SPECULAR = mix(0.28, 0.53, metal);
}
