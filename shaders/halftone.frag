#version 460 core
#include <flutter/runtime_effect.glsl>

// Halftone gradient fill.
//
// Produces a lattice of dots whose radius is driven by a gradient's local
// "amount". amount = 0 -> no dot (pure background); amount = 1 -> the dot
// fully covers its lattice cell (pure foreground). The amount along the
// gradient axis is looked up from a 1D piecewise-linear curve (uAmountLUT),
// which encodes the user's stops.

precision highp float;

// Gradient axis, in the same pixel space as FlutterFragCoord (local to the
// slice being drawn). A cell centre is projected onto this axis to get t.
uniform vec2 uAxisStart;
uniform vec2 uAxisEnd;

// Lattice spacing in pixels (user-specified "grid size").
uniform float uGridSize;

// Phase offset in pixels, applied along the gradient normal. Lets two slices
// drawn in their own local coordinates be nudged until their dots line up
// across a shared seam.
uniform float uOffset;

// Lattice rotation ("screen angle") in radians.
uniform float uScreenAngle;

// The two fill colours (premultiplied-alpha-agnostic; straight RGBA 0..1).
uniform vec4 uForeground;
uniform vec4 uBackground;

// 1D lookup of amount vs. t (read from the red channel). Encodes the stops.
uniform sampler2D uAmountLUT;

out vec4 fragColor;

// Half the diagonal of a unit cell: the radius at which a dot centred in the
// cell just covers the corners, i.e. amount = 1 => solid foreground.
const float INV_SQRT2 = 0.70710678118;
const float AA = 0.75;

// Radius (px) of the dot on lattice cell [index]: its centre is mapped back to
// screen space, projected onto the gradient axis, and looked up in the LUT.
// [c]/[s] are cos/sin of the screen angle; [axis]/[len2]/[normal] describe the
// gradient axis.
float radiusAt(vec2 index, float c, float s, vec2 axis, float len2, vec2 normal) {
    vec2 centre = (index + 0.5) * uGridSize;
    // Undo rotation then the phase-offset shift to get the screen position.
    vec2 back = vec2(c * centre.x - s * centre.y, s * centre.x + c * centre.y);
    vec2 screenPos = back + uOffset * normal;
    float t = (len2 > 0.0)
        ? clamp(dot(screenPos - uAxisStart, axis) / len2, 0.0, 1.0)
        : 0.0;
    float amount = texture(uAmountLUT, vec2(t, 0.5)).r;
    // Push full coverage past the cell corner so amount = 1 reads as solid.
    return amount * (uGridSize * INV_SQRT2 + AA);
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    vec2 axis = uAxisEnd - uAxisStart;
    float len2 = dot(axis, axis);
    vec2 dir = (len2 > 0.0) ? normalize(axis) : vec2(0.0, 1.0);
    vec2 normal = vec2(-dir.y, dir.x);

    // Into lattice space: shift by the phase offset along the gradient normal,
    // then rotate by the screen angle.
    float c = cos(uScreenAngle);
    float s = sin(uScreenAngle);
    vec2 q0 = p - uOffset * normal;
    vec2 q = vec2(c * q0.x + s * q0.y, -s * q0.x + c * q0.y);

    vec2 cellIndex = floor(q / uGridSize);

    // A dot can grow past its own cell and overlap its neighbours, so test the
    // 3x3 block of surrounding cells and keep the greatest coverage. Without
    // this the dots would be clipped square to their own cells.
    float coverage = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 index = cellIndex + vec2(float(dx), float(dy));
            float radius = radiusAt(index, c, s, axis, len2, normal);
            if (radius <= 0.0) continue;
            vec2 centre = (index + 0.5) * uGridSize;
            float dist = length(q - centre);
            coverage = max(coverage, 1.0 - smoothstep(radius - AA, radius + AA, dist));
        }
    }

    fragColor = mix(uBackground, uForeground, coverage);
}
