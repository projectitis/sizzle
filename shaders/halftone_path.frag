#version 460 core
#include <flutter/runtime_effect.glsl>

// Halftone gradient fill masked to a path by DOT, not by pixel.
//
// Identical to halftone.frag (gradient amount, lattice, angle, growth, overlap)
// except a dot is kept only if its cell CENTRE lands inside the path, and then
// it is drawn in its entirety — circles spill past the boundary rather than
// being clipped. Path membership is read from a rasterised mask (white inside).

precision highp float;

uniform vec2 uAxisStart;
uniform vec2 uAxisEnd;
uniform float uGridSize;
// Phase offset in pixels (x, y), shifting the dot lattice in screen space.
uniform vec2 uOffset;
uniform float uRotation;
uniform vec4 uForeground;
uniform vec4 uBackground;

// Fill size in pixels, to normalise mask lookups.
uniform vec2 uSize;

uniform sampler2D uAmountLUT;
// Path mask: red channel >= 0.5 means "inside the path".
uniform sampler2D uPathMask;

out vec4 fragColor;

const float INV_SQRT2 = 0.70710678118;
const float AA = 0.75;

// Radius (px) of the dot on lattice cell [index], or 0 if excluded. The dot's
// centre is looked up in the (optionally feathered) path mask: full membership
// inside, tapering to 0 through the soft band just outside the path, so edge
// dots shrink smoothly rather than popping off — an antialiased silhouette.
float radiusAt(vec2 index, float c, float s, vec2 axis, float len2) {
    vec2 centre = (index + 0.5) * uGridSize;
    // Cell centre back in screen space (undo rotation, then the phase offset).
    vec2 back = vec2(c * centre.x - s * centre.y, s * centre.x + c * centre.y);
    vec2 screenPos = back + uOffset;

    vec2 muv = clamp(screenPos / uSize, 0.0, 1.0);
    // Membership >= 0.5 (inside) keeps the dot full; below that it tapers to 0
    // over the feathered outer band. A crisp mask makes this a hard cutoff.
    float scale = smoothstep(0.0, 0.5, texture(uPathMask, muv).r);
    if (scale <= 0.0) return 0.0;

    float t = (len2 > 0.0)
        ? clamp(dot(screenPos - uAxisStart, axis) / len2, 0.0, 1.0)
        : 0.0;
    float amount = texture(uAmountLUT, vec2(t, 0.5)).r;
    return amount * (uGridSize * INV_SQRT2 + AA) * scale;
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    vec2 axis = uAxisEnd - uAxisStart;
    float len2 = dot(axis, axis);

    float c = cos(uRotation);
    float s = sin(uRotation);
    vec2 q0 = p - uOffset;
    vec2 q = vec2(c * q0.x + s * q0.y, -s * q0.x + c * q0.y);

    vec2 cellIndex = floor(q / uGridSize);

    // 3x3 neighbourhood so dots overlap as circles; excluded dots (radius 0)
    // simply don't contribute, so an included dot near the border draws whole.
    float coverage = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 index = cellIndex + vec2(float(dx), float(dy));
            float radius = radiusAt(index, c, s, axis, len2);
            if (radius <= 0.0) continue;
            vec2 centre = (index + 0.5) * uGridSize;
            float dist = length(q - centre);
            coverage = max(coverage, 1.0 - smoothstep(radius - AA, radius + AA, dist));
        }
    }

    // Background is bounded by the path (transparent outside); dots are painted
    // over it and are NOT bounded — a spilled dot keeps its own colour against
    // transparency rather than mixing with the (absent) background. Output is
    // premultiplied alpha.
    // Background stays bounded by the path itself (the mask's 0.5 contour),
    // independent of how wide the dot-feather band is.
    float insidePixel =
        smoothstep(0.4, 0.6, texture(uPathMask, clamp(p / uSize, 0.0, 1.0)).r);
    vec4 baseP = vec4(uBackground.rgb * uBackground.a, uBackground.a) * insidePixel;
    float da = uForeground.a * coverage;
    vec4 dotP = vec4(uForeground.rgb * da, da);
    fragColor = dotP + baseP * (1.0 - dotP.a);
}
