#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Barrel, mask and flyback receive `.boundingRect` as float4 (x, y, w, h);
// use bounds.zw for size. Match each SwiftUI call's argument types and order.
// Bloom receives radius, strength, tint and colour mode, without bounds.

// Barrel distortion (.distortionEffect). Output position -> source position.
// Out-of-layer samples are transparent = the curved black tube edge.
// Axes curved separately; a wide tube is a cylinder more than a sphere.
// Integer noise is shared with TerminalPointerMap. fract(sin()*largeValue)
// magnifies CPU/GPU rounding enough to target a different terminal column.
float syncNoise(float row, float time)
{
    uint n = uint(clamp(floor(row), 0.0, 65535.0))
        ^ (uint(floor(max(time, 0.0) * 60.0)) * 747796405u) ^ 2891336453u;
    n ^= n >> 16; n *= 2246822519u;
    n ^= n >> 13; n *= 3266489917u;
    n ^= n >> 16;
    return float(n >> 8) / 16777216.0;
}

[[stitchable]] float2 crtBarrel(float2 position, float4 bounds,
                                float strengthX, float strengthY,
                                float wobble, float time)
{
    float2 size = bounds.zw;
    float2 uv = position / size;
    float2 c  = uv * 2.0 - 1.0;
    float r2  = dot(c, c);
    c.x *= 1.0 + strengthX * r2;
    c.y *= 1.0 + strengthY * r2;
    float n = syncNoise(position.y, time);
    c.x += wobble * (0.6 * sin(time * 1.7 + uv.y * 9.0) + 0.4 * (n - 0.5));
    uv = (c + 1.0) * 0.5;
    return uv * size;
}

// Shared by both sampling qualities. Monochrome retains its original arithmetic;
// colour mode adds neighbouring RGB light without recolouring it to the phosphor.
half4 bloomOutput(half4 base, half4 acc, float strength, half4 tint, float preserveColours)
{
    if (preserveColours > 0.5) {
        half4 result = base + acc * half(strength);
        return half4(result.rgb, saturate(result.a));
    }
    half lum = dot(acc.rgb, half3(0.299h, 0.587h, 0.114h));
    return base + tint * lum * half(strength);
}

// Two rings of phosphor glow. A compile-time tap count keeps both variants
// free of per-pixel quality branches; the normal 33-sample appearance is intact.
template<int taps>
half4 bloom(float2 position, SwiftUI::Layer layer,
            float radius, float strength, half4 tint, float preserveColours)
{
    half4 base = layer.sample(position);
    half4 acc  = half4(0.0);
    for (int i = 0; i < taps; i++) {
        float a = float(i) * (2.0 * M_PI_F / float(taps));
        float2 off = float2(cos(a), sin(a)) * radius;
        acc += layer.sample(position + off);
        acc += layer.sample(position + off * 0.5) * 0.5h;
    }
    acc /= half(taps) * 1.5h;
    return bloomOutput(base, acc, strength, tint, preserveColours);
}

[[stitchable]] half4 crtBloom(float2 position, SwiftUI::Layer layer,
                              float radius, float strength, half4 tint, float preserveColours)
{
    return bloom<16>(position, layer, radius, strength, tint, preserveColours);
}

// Live resize uses 17 samples, returning to full quality as soon as the drag ends.
[[stitchable]] half4 crtBloomFast(float2 position, SwiftUI::Layer layer,
                                  float radius, float strength, half4 tint, float preserveColours)
{
    return bloom<8>(position, layer, radius, strength, tint, preserveColours);
}

// Monochrome tube: scanlines + aperture grille + vignette + brightness gain,
// with every input colour reduced to a brightness and painted in the phosphor
// (.colorEffect). A P3 tube had no colour, so 24-bit and 256-colour escapes
// from applications cannot leak colour onto the screen. Brightness is a blend
// of normalised luminance (tube-like) and the brightest channel (readable),
// so saturated blues do not vanish.
[[stitchable]] half4 crtMask(float2 position, half4 color, float4 bounds,
                             float scale, float lineStrength,
                             float grilleStrength, float vignette,
                             float brightness, half4 phosphor, float preserveColours)
{
    float2 size = bounds.zw;

    // Scanlines: 2 device-pixel period, dark on odd rows. Sampled per device
    // row (not with a cosine — pixel-centred positions sit on its zeros).
    float py   = position.y * scale;
    float line = step(0.5, fract(py * 0.5));
    half l     = half(1.0 - lineStrength * line);

    int col = int(position.x * scale) % 3;
    half3 grille = half3(1.0h);
    grille[(col + 1) % 3] = 1.0h - half(grilleStrength);
    grille[(col + 2) % 3] = 1.0h - half(grilleStrength);

    float2 uv = position / size;
    float2 d  = uv * (1.0 - uv);
    half v    = half(pow(clamp(d.x * d.y * 16.0, 0.0, 1.0), vignette));

    if (preserveColours > 0.5) {
        return half4(color.rgb * l * grille * v * half(brightness), color.a);
    }

    const half3 w = half3(0.299h, 0.587h, 0.114h);
    half lum  = dot(color.rgb, w) / max(dot(phosphor.rgb, w), 0.05h);
    half peak = max(color.r, max(color.g, color.b));
    half b    = mix(lum, peak, 0.6h);

    return half4(phosphor.rgb * b * l * grille * v * half(brightness), color.a);
}

// Flyback line for power-on (.colorEffect on a black overlay).
// progress 0->1: bright line collapses to a dot, then fades.
[[stitchable]] half4 crtFlyback(float2 position, half4 color, float4 bounds,
                                float progress, half4 tint)
{
    float2 size = bounds.zw;
    float2 uv = position / size;
    float2 c  = abs(uv * 2.0 - 1.0);
    float h   = mix(0.004, 0.0, smoothstep(0.6, 1.0, progress));
    float w   = mix(1.0, 0.0, smoothstep(0.0, 0.7, progress));
    float on  = step(c.y, h) * step(c.x, w);
    float fade = 1.0 - smoothstep(0.85, 1.0, progress);
    return tint * half(on * fade * 3.0);
}
