shader_type sky;

// Night sky for the city: gradient + light-pollution horizon glow,
// twinkling star layers, a soft milky-way band, two spiral galaxies
// and periodic shooting stars. TIME drives twinkle + meteors.

uniform vec3 top_color : source_color = vec3(0.006, 0.012, 0.038);
uniform vec3 horizon_color : source_color = vec3(0.045, 0.055, 0.095);
uniform vec3 city_glow_color : source_color = vec3(0.9, 0.55, 0.25);
uniform vec3 debug_arc = vec3(0.0); // when non-zero: meteor 0 flies through this direction

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1033, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 star_layer(vec3 dir, float scale, float density, float sharp) {
	vec3 g = dir * scale;
	vec3 id = floor(g);
	vec3 r = hash33(id);
	if (r.z > density) {
		return vec3(0.0);
	}
	vec3 pos = id + 0.5 + (r - 0.5) * 0.6;
	float d = length(g - pos);
	float b = exp(-d * d * sharp);
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.5 + 2.0 * r.x) + r.y * 6.28);
	return vec3(b * twinkle * (0.5 + 0.5 * r.y));
}

vec3 stars(vec3 dir) {
	vec3 col = vec3(0.0);
	col += star_layer(dir, 90.0, 0.35, 60.0) * 1.0;
	col += star_layer(dir, 170.0, 0.28, 90.0) * 0.7;
	col += star_layer(dir, 340.0, 0.22, 140.0) * 0.45;
	return col;
}

vec3 milkyway(vec3 dir) {
	vec3 n = normalize(vec3(0.35, 0.72, -0.35));
	float d = dot(dir, n);
	float band = exp(-d * d / 0.024);
	return vec3(0.55, 0.6, 0.8) * band * 0.09;
}

vec3 galaxy(vec3 dir, vec3 center, vec3 tint, float size, float arms) {
	float ang = acos(clamp(dot(dir, center), -1.0, 1.0));
	if (ang > size * 2.5) {
		return vec3(0.0);
	}
	vec3 t1 = normalize(cross(center, vec3(0.2, 1.0, 0.13)));
	vec3 t2 = cross(center, t1);
	vec2 p = vec2(dot(dir, t1), dot(dir, t2));
	float rho = length(p);
	float theta = atan(p.y, p.x) + rho * 5.5;
	float arm = 0.5 + 0.5 * cos(theta * arms);
	float core = exp(-pow(rho / (size * 0.22), 2.0));
	float disk = exp(-pow(rho / size, 2.2));
	float b = disk * (0.28 + 0.72 * pow(arm, 1.6)) + core * 1.2;
	return tint * b;
}

vec3 meteor_arc(float fi, float cycle, float prog) {
	// deterministic arc endpoints per meteor + cycle (kept low over the skyline)
	vec3 a = normalize(vec3(
		hash13(vec3(fi, cycle, 1.0)) - 0.5,
		0.04 + 0.18 * hash13(vec3(fi, cycle, 2.0)),
		hash13(vec3(fi, cycle, 3.0)) - 0.5));
	vec3 b = normalize(a + vec3(
		hash13(vec3(fi, cycle, 4.0)) - 0.5,
		(hash13(vec3(fi, cycle, 5.0)) - 0.5) * 0.3,
		hash13(vec3(fi, cycle, 6.0)) - 0.5) * 0.9);
	return normalize(mix(a, b, prog));
}

vec3 meteors(vec3 dir) {
	vec3 col = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float period = 12.0;
		float offset = 0.005 + fi * 0.2;
		float phase = fract(TIME / period + offset);
		if (phase > 0.16) {
			continue;
		}
		float prog = phase / 0.16;
		float cycle = floor(TIME / period + offset);
		if (fi < 0.5 && debug_arc != vec3(0.0)) {
			cycle = 0.0;
		}
		float fade = smoothstep(0.0, 0.2, prog) * (1.0 - smoothstep(0.55, 1.0, prog));
		float glow = 0.0;
		for (int k = 0; k < 4; k++) {
			float t = max(prog - float(k) * 0.05, 0.0);
			vec3 p = meteor_arc(fi, cycle, t);
			if (fi < 0.5 && debug_arc != vec3(0.0)) {
				vec3 da = normalize(debug_arc);
				vec3 db = normalize(da + vec3(0.35, 0.05, -0.1));
				p = normalize(mix(da, db, t));
			}
			float d = acos(clamp(dot(dir, p), -1.0, 1.0));
			glow += exp(-pow(d / 0.009, 2.0)) * (3.6 / (1.0 + float(k) * 1.6));
		}
		col += vec3(0.9, 0.95, 1.0) * glow * fade;
	}
	return col;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, clamp(h * 1.4 + 0.1, 0.0, 1.0));
	col += city_glow_color * exp(-pow(max(h, 0.0) / 0.03, 2.0)) * 0.01;
	col = mix(col, horizon_color * 0.4, smoothstep(0.0, -0.25, h));
	col += milkyway(dir);
	col += galaxy(dir, normalize(vec3(-0.55, 0.42, 0.4)), vec3(0.5, 0.38, 0.85), 0.16, 2.0) * 1.1;
	col += galaxy(dir, normalize(vec3(0.6, 0.28, -0.55)), vec3(0.35, 0.6, 0.8), 0.11, 3.0) * 0.9;
	col += stars(dir);
	col += meteors(dir);
	COLOR = col;
}
