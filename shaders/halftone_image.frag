#version 460 core
#include <flutter/runtime_effect.glsl>

// Halftone reproduction of a source image.
//
// Same lattice/angle/growth/anti-aliasing as halftone.frag, but the per-dot
// "amount" comes from the source image's luminance sampled at each lattice
// cell centre (so every dot is a uniform tone), remapped through a tone LUT.

precision highp float;

// Source image size in pixels (== output size), used to normalise sample uvs.
uniform vec2 uImageSize;

// Lattice spacing in pixels.
uniform float uGridSize;

// Phase offset in pixels (x, y), shifting the dot lattice (for tiling
// alignment).
uniform vec2 uOffset;

// Lattice rotation in radians.
uniform float uRotation;

// Dot colour and field colour.
uniform vec4 uForeground;
uniform vec4 uBackground;

// The image being reproduced.
uniform sampler2D uSource;

// Tone curve: luminance (0..1) -> radius fraction (red channel). Encodes the
// stops + growth, exactly like the gradient shader's amount LUT.
uniform sampler2D uToneLUT;

out vec4 fragColor;

const float INV_SQRT2 = 0.70710678118;
// Rec. 709 luma weights.
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float AA = 0.75;

// The dot centred on lattice cell [index], from the source sampled at that
// cell's centre: x = radius in px, y = source alpha (ink is scaled by it, so a
// transparent source leaves no dot). [c]/[s] are cos/sin of the angle.
vec2 dotAt(vec2 index, float c, float s) {
    vec2 centre = (index + 0.5) * uGridSize;
    // Map the cell centre back into image space to sample the source there.
    vec2 back = vec2(c * centre.x - s * centre.y, s * centre.x + c * centre.y);
    vec2 uv = clamp((back + uOffset) / uImageSize, 0.0, 1.0);
    vec4 src = texture(uSource, uv);
    float lum = dot(src.rgb, LUMA);
    float frac = texture(uToneLUT, vec2(lum, 0.5)).r;
    // Push full coverage past the cell corner so the darkest tones read solid.
    return vec2(frac * (uGridSize * INV_SQRT2 + AA), src.a);
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    float c = cos(uRotation);
    float s = sin(uRotation);

    // Into lattice space: shift by the phase offset, then rotate.
    vec2 q0 = p - uOffset;
    vec2 q = vec2(c * q0.x + s * q0.y, -s * q0.x + c * q0.y);

    vec2 cellIndex = floor(q / uGridSize);

    // A dot can grow past its own cell and overlap its neighbours, so test the
    // 3x3 block of surrounding cells and keep the greatest coverage. This is
    // what makes the dots merge as circles (with concave gaps between them)
    // instead of being clipped square to their cells.
    float coverage = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 index = cellIndex + vec2(float(dx), float(dy));
            vec2 dot = dotAt(index, c, s);
            float radius = dot.x;
            if (radius <= 0.0) continue;
            vec2 centre = (index + 0.5) * uGridSize;
            float dist = length(q - centre);
            float cov = (1.0 - smoothstep(radius - AA, radius + AA, dist)) * dot.y;
            coverage = max(coverage, cov);
        }
    }

    fragColor = mix(uBackground, uForeground, coverage);
}
