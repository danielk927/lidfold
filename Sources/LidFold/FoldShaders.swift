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

// Frosted defocus. Taps are spread on a golden-angle spiral, which gives even
// coverage without the ring artefacts a concentric pattern produces, and each
// tap reads from the mip chain so cost stays flat as the radius grows.
static float3 frostedSample(texture2d<float> tex,
                            sampler samp,
                            float2 uv,
                            float radius,
                            float2 texelSize) {
    if (radius < 0.5) {
        return tex.sample(samp, uv, level(0.0)).rgb;
    }

    // Cap the LOD. Left unbounded it climbs into mips whose texels are larger
    // than several screen pixels and the blur turns blocky rather than soft.
    float maxLod = clamp(log2(radius * 0.25), 0.0, 2.0);

    const int taps = 16;
    const float goldenAngle = 2.3999632;

    float3 sum = float3(0.0);
    float total = 0.0;
    for (int i = 0; i < taps; ++i) {
        float t = (float(i) + 0.5) / float(taps);
        float r = sqrt(t);                       // uniform density over the disc
        float a = float(i) * goldenAngle;
        float2 offset = float2(cos(a), sin(a)) * r * radius * texelSize;
        float w = exp(-2.0 * t);
        // Centre taps stay sharp, outer taps blend into coarser mips.
        sum += tex.sample(samp, uv + offset, level(maxLod * r)).rgb * w;
        total += w;
    }
    return sum / total;
}

fragment float4 foldFragment(FoldVertex in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler samp [[sampler(0)]],
                             constant FoldUniforms &u [[buffer(0)]]) {
    const float3 voidColor = float3(0.004, 0.005, 0.006);

    if (u.progress <= 0.0001) {
        return float4(tex.sample(samp, in.uv, level(0.0)).rgb, 1.0);
    }

    // Distance from the hinge: 0 along the bottom edge, 1 at the top.
    float fromHinge = clamp(1.0 - in.uv.y, 0.0, 1.0);

    float theta = u.progress * u.tilt;
    float c = cos(theta);
    float s = sin(theta);

    // Rotate the screen plane about the hinge and divide through by depth.
    // Eye distance is scaled by the inverse aspect so a wide display gets the
    // same apparent vanishing point as a square one.
    float eye = 3.0 * max(1.0 / max(u.aspect, 0.1), 1.0);
    float depth = fromHinge * s * 0.85;
    float persp = eye / max(eye - depth, 0.05);

    float2 src;
    src.y = 1.0 - fromHinge * c * persp;
    src.x = 0.5 + (in.uv.x - 0.5) * persp;

    // Past the edges of the folded panel there is nothing to sample: that is
    // the void the screen is turning into.
    float2 beyond = max(-src, src - 1.0);
    float outside = max(max(beyond.x, beyond.y), 0.0);
    float inside = 1.0 - smoothstep(0.0, fwidth(in.uv.x) * 2.0 + 0.002, outside);

    // Defocus grows with both the fold and the distance from the hinge, so the
    // far edge frosts over first.
    float spread = pow(fromHinge, 1.3);
    float radius = 48.0 * u.blur * u.progress * mix(0.25, 1.0, spread);
    float3 color = frostedSample(tex, samp, clamp(src, 0.0, 1.0), radius, u.texelSize);

    // A soft specular band where a real panel would catch the room light.
    float sheen = exp(-pow((fromHinge - 0.6) / 0.3, 2.0)) * s;
    color += float3(0.80, 0.84, 0.88) * sheen * 0.03;

    // Falloff into the void, then a final blackout as the lid actually shuts.
    float fade = smoothstep(0.15, 1.0, fromHinge) * u.progress;
    color *= 1.0 - 0.85 * fade * u.darkness;
    color *= 1.0 - smoothstep(0.92, 1.0, u.progress);

    return float4(mix(voidColor, color, inside), 1.0);
}
"""
