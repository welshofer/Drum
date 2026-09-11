#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// All four functions receive SwiftUI's `.boundingRect` argument, which is a
// float4 (x, y, width, height) — not a float2 size. `bounds.zw` is the size.

// Barrel distortion (.distortionEffect). Output position -> source position.
// Out-of-layer samples are transparent = the curved black tube edge.
// Axes curved separately; a wide tube is a cylinder more than a sphere.
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
    float n = fract(sin(dot(float2(uv.y * 173.0, time), float2(12.9898, 78.233))) * 43758.5453);
    c.x += wobble * (0.6 * sin(time * 1.7 + uv.y * 9.0) + 0.4 * (n - 0.5));
    uv = (c + 1.0) * 0.5;
    return uv * size;
}

// Bloom / phosphor glow (.layerEffect). 16-tap ring, tinted, added on top.
[[stitchable]] half4 crtBloom(float2 position, SwiftUI::Layer layer,
                              float radius, float strength, half4 tint)
{
    half4 base = layer.sample(position);
    half4 acc  = half4(0.0);
    const int taps = 16;
    for (int i = 0; i < taps; i++) {
        float a = float(i) * (2.0 * M_PI_F / float(taps));
        float2 off = float2(cos(a), sin(a)) * radius;
        acc += layer.sample(position + off);
        acc += layer.sample(position + off * 0.5) * 0.5h;
    }
    acc /= half(taps) * 1.5h;
    half lum = dot(acc.rgb, half3(0.299h, 0.587h, 0.114h));
    return base + tint * lum * half(strength);
}

// Scanlines + aperture grille + vignette + brightness gain (.colorEffect).
[[stitchable]] half4 crtMask(float2 position, half4 color, float4 bounds,
                             float scale, float lineStrength,
                             float grilleStrength, float vignette,
                             float brightness)
{
    float2 size = bounds.zw;
    float py   = position.y * scale;
    float line = 0.5 + 0.5 * cos(py * M_PI_F);          // 2-px period
    half l     = half(1.0 - lineStrength * line);

    int col = int(position.x * scale) % 3;
    half3 grille = half3(1.0h);
    grille[(col + 1) % 3] = 1.0h - half(grilleStrength);
    grille[(col + 2) % 3] = 1.0h - half(grilleStrength);

    float2 uv = position / size;
    float2 d  = uv * (1.0 - uv);
    half v    = half(pow(clamp(d.x * d.y * 16.0, 0.0, 1.0), vignette));

    return half4(color.rgb * l * grille * v * half(brightness), color.a);
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
