/// Metal source for the fold, compiled at runtime.
///
/// SwiftPM doesn't build `.metal` files in a plain executable target, and
/// shipping a precompiled `.metallib` would mean a resource bundle that the
/// `swift build` path and the `.app` path resolve differently. Compiling this
/// string once at startup costs a few milliseconds and works identically in
/// both, which is worth more here than the editor's syntax highlighting.
let foldShaderSource = """
#include <metal_stdlib>
using namespace metal;

constant float3 kVoid = float3(0.004, 0.005, 0.006);
constant float  kGoldenAngle = 2.3999632;
constant int    kTaps = 32;

struct FoldUniforms {
    float2 texelSize;   // 1 / texture size, so blur offsets are in texels
    float  aspect;      // view width / height
    float  progress;    // 0 = flat, 1 = fully folded
    float  tilt;        // hinge angle at full fold, radians
    float  blur;
    float  darkness;
};

struct FoldVertex {
    float4 position [[position]];
    float2 uv;
};

// One full-screen quad. uv origin is top-left, so uv.y == 1 is the hinge
// running along the bottom edge of the screen.
vertex FoldVertex foldVertex(uint id [[vertex_id]]) {
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
    };
    float2 p = corners[id];
    FoldVertex out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return out;
}

// Frosted defocus.
//
// Taps sit on a golden-angle spiral, which covers the disc evenly without the
// rings a concentric pattern leaves behind, and each tap reads from the mip
// chain so widening the radius costs nothing extra.
static float3 frosted(texture2d<float> tex,
                      sampler samp,
                      float2 uv,
                      float radius,
                      float2 texelSize,
                      float2 screenPos) {
    if (radius < 0.75) {
        return tex.sample(samp, uv, level(0.0)).rgb;
    }

    // Cap the LOD. Unbounded it runs off the end of the mip chain into a
    // handful of texels stretched over the screen. The cap is deliberately
    // generous: reading a coarse mip is where the heavy frost comes from, and
    // it costs the same as reading a fine one.
    float maxLod = clamp(log2(radius * 0.20), 0.0, 5.0);

    // Rotate the whole pattern per pixel. A fixed spiral prints faint rings
    // across flat gradients; jittering scatters them into noise the eye reads
    // as grain in the glass.
    float hash = fract(sin(dot(screenPos, float2(12.9898, 78.233))) * 43758.5453);
    float angle = (hash - 0.5) * 0.7;
    float ca = cos(angle);
    float sa = sin(angle);

    float3 sum = float3(0.0);
    float total = 0.0;
    for (int i = 0; i < kTaps; ++i) {
        float t = (float(i) + 0.5) / float(kTaps);
        float r = sqrt(t);                        // even area density
        float a = float(i) * kGoldenAngle;
        float2 dir = float2(cos(a), sin(a));
        dir = float2(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

        float w = exp(-2.3 * t);
        // Even the centre taps sit well up the mip chain, so the whole disc is
        // soft rather than a sharp core ringed by blur; outer taps go coarser
        // still, which is what reads as depth of field across the panel.
        float lod = mix(maxLod * 0.45, maxLod, smoothstep(0.0, 0.9, r));
        float2 at = clamp(uv + dir * r * radius * texelSize, 0.0, 1.0);
        sum += tex.sample(samp, at, level(lod)).rgb * w;
        total += w;
    }

    // Frosted glass scatters a little ambient light; without this the blur
    // reads as merely out of focus rather than as a surface.
    return sum / total + 0.012 * smoothstep(0.0, 24.0, radius);
}

fragment float4 foldFragment(FoldVertex in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler samp [[sampler(0)]],
                             constant FoldUniforms &u [[buffer(0)]]) {
    float turn = clamp(u.progress, 0.0, 1.0);
    if (turn <= 0.0001) {
        return float4(tex.sample(samp, in.uv, level(0.0)).rgb, 1.0);
    }

    // Distance from the hinge: 0 along the bottom edge, 1 at the top.
    float fromHinge = clamp(1.0 - in.uv.y, 0.0, 1.0);

    float theta = turn * u.tilt;
    float c = cos(theta);
    float s = sin(theta);

    // Rotate the screen plane about the hinge, then divide through by depth.
    // This runs backwards — it maps a destination pixel to the source texel
    // that lands there — so a scale above 1 squeezes the image inward, which
    // is what gives the far edge its taper. Eye distance is in screen heights:
    // lower is a shorter lens and a harder taper, and much below 2 the near
    // edge starts to bow.
    const float eye = 2.0;
    float depth = fromHinge * s;
    float persp = eye / max(eye - depth, 0.05);

    float2 src;
    src.y = 1.0 - fromHinge * c * persp;
    src.x = 0.5 + (in.uv.x - 0.5) * persp;

    // Signed distance to the panel's edge in source space: negative inside it,
    // positive past it, where there is nothing left to sample.
    float2 beyond = max(-src, src - 1.0);
    float edgeDist = max(beyond.x, beyond.y);

    // Dissolve the silhouette over a real distance instead of anti-aliasing a
    // hard cut. A two-pixel edge reads as a decal pasted onto the desktop,
    // which is jarring against how soft everything inside it is. The fade
    // starts well inside the panel and finishes just past it, and widens as
    // the fold deepens so the panel loses its outline as it falls away.
    // The width has to start at nothing. With a floor it doesn't matter how
    // small the fold is: the fade is already almost complete at the boundary,
    // so a black vignette snaps onto every edge of the screen the instant the
    // overlay appears. Scaled by turn, the edge begins as a plain antialiased
    // border indistinguishable from the desktop and opens up from there.
    float aa = fwidth(in.uv.x) * 1.5 + 0.0008;
    // Width and inward bite ramp separately. Scaling the width alone still
    // rushes: the fade's midpoint sits inside the panel, so it eats most of the
    // border within the first few percent of travel. Squaring the inward reach
    // holds the edge crisp through the start of the close and softens it late.
    float feather = 0.13 * turn;
    float inside = 1.0 - smoothstep(-feather * turn, feather * 0.3 + aa, edgeDist);
    inside = inside * inside * (3.0 - 2.0 * inside);   // gentler shoulder

    // Defocus grows with the fold and with distance from the hinge, so the far
    // edge frosts over first while the near edge stays legible.
    float spread = pow(smoothstep(0.0, 0.9, fromHinge), 1.2);
    float radius = 260.0 * u.blur * turn * mix(0.30, 1.0, spread);
    float3 color = frosted(tex, samp, src, radius, u.texelSize, in.position.xy);

    // The tipped panel turns away from the light, with a sheen band where it
    // would catch the room.
    color *= 1.0 - 0.22 * s * pow(fromHinge, 1.5);
    float sheen = exp(-pow((fromHinge - 0.62) / 0.32, 2.0)) * s;
    color += float3(0.82, 0.85, 0.88) * sheen * 0.05;

    // Falloff into the void, then the final blackout as the lid actually shuts.
    float fade = clamp((fromHinge - 0.18) / 0.82, 0.0, 1.0);
    color *= 1.0 - 0.88 * u.darkness * turn * fade;

    float shut = 1.0 - smoothstep(0.90, 1.0, turn);
    color *= shut;

    return float4(mix(kVoid, color, inside * shut), 1.0);
}
"""
