#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A short bounce settles before the launch overlay fades.
[[ stitchable ]] half4 rallyBallMotion(float2 position, SwiftUI::Layer layer, float2 size, float time) {
    float bounce = abs(sin(5.7 * time)) * exp(-1.7 * time) * size.y * 0.10;
    return layer.sample(position + float2(0.0, bounce));
}
