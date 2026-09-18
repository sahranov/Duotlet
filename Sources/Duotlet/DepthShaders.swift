import Foundation

enum DepthShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms {
        float4 column0;
        float4 column1;
        float4 column2;
        float4 screenAndOrigin;
        float4 paddedAndBlur;
        float4 shape;
        float4 light;
    };

    kernel void reduceForBlur(texture2d<float, access::sample> source [[texture(0)]],
                             texture2d<float, access::write> target [[texture(1)]],
                             uint2 p [[thread_position_in_grid]]) {
        if (p.x >= target.get_width() || p.y >= target.get_height()) { return; }
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        float2 uv = (float2(p) + 0.5) / float2(target.get_width(), target.get_height());
        // Four bilinear samples average all 16 native pixels of each 4x4
        // footprint, preserving thin lines instead of skipping them.
        float2 offset = 0.25 / float2(target.get_width(), target.get_height());
        float4 colour = source.sample(linearSampler, uv + float2(-offset.x, -offset.y))
            + source.sample(linearSampler, uv + float2(offset.x, -offset.y))
            + source.sample(linearSampler, uv + float2(-offset.x, offset.y))
            + source.sample(linearSampler, uv + offset);
        target.write(colour * 0.25, p);
    }

    float4 linePixel(texture2d<float, access::sample> source, uint line, int index, uint axis) {
        int length = axis == 0 ? source.get_width() : source.get_height();
        uint j = uint(clamp(index, 0, length - 1));
        return source.read(axis == 0 ? uint2(j, line) : uint2(line, j));
    }

    // Short overlapping segments run in parallel. Three dense box passes
    // approximate a Gaussian without the rings created by sparse taps.
    kernel void denseBlur(texture2d<float, access::sample> source [[texture(0)]],
                          texture2d<float, access::write> target [[texture(1)]],
                          constant Uniforms &u [[buffer(0)]],
                          constant uint &axis [[buffer(1)]],
                          constant uint &segmentLength [[buffer(2)]],
                          uint index [[thread_position_in_grid]]) {
        uint lineCount = axis == 0 ? target.get_height() : target.get_width();
        uint line = index % lineCount;
        uint segment = index / lineCount;
        int length = axis == 0 ? target.get_width() : target.get_height();
        int first = int(segment * segmentLength);
        int end = min(first + int(segmentLength), length);
        if (first >= length) { return; }
        int low = first, high = first - 1;
        float4 sum = 0.0;
        for (int j = first; j < end; ++j) {
            uint2 p = axis == 0 ? uint2(j, line) : uint2(line, j);
            float y = u.screenAndOrigin.w + (1.0 - (float(p.y) + 0.5) / float(target.get_height())) * u.paddedAndBlur.y;
            float height = clamp(y / u.screenAndOrigin.y, 0.0, 1.0);
            float sigma = 0.5 * u.paddedAndBlur.z * u.paddedAndBlur.w * (u.shape.x + (1.0 - u.shape.x) * height);
            float radius = max(sqrt(sigma * sigma + 0.25) - 0.5, 0.0);
            int whole = int(floor(radius));
            float fraction = radius - float(whole);
            int nextLow = j - whole, nextHigh = j + whole;
            while (low > nextLow) { sum += linePixel(source, line, --low, axis); }
            while (high < nextHigh) { sum += linePixel(source, line, ++high, axis); }
            while (low < nextLow) { sum -= linePixel(source, line, low++, axis); }
            while (high > nextHigh) { sum -= linePixel(source, line, high--, axis); }
            float4 edges = linePixel(source, line, low - 1, axis) + linePixel(source, line, high + 1, axis);
            target.write((sum + fraction * edges) / (float(2 * whole + 1) + 2.0 * fraction), p);
        }
    }

    vertex float4 depthVertex(uint vertexID [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[vertexID], 0.0, 1.0);
    }
    fragment float4 depthFragment(float4 position [[position]],
                                   constant Uniforms &uniforms [[buffer(0)]],
                                   texture2d<float> picture [[texture(0)]],
                                   texture2d<float> original [[texture(1)]]) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        float2 screenSize = uniforms.screenAndOrigin.xy;
        float2 screenPoint = float2(position.x / uniforms.shape.z, screenSize.y - position.y / uniforms.shape.z);
        float3x3 inverse = float3x3(uniforms.column0.xyz, uniforms.column1.xyz, uniforms.column2.xyz);
        float3 mapped = inverse * float3(screenPoint, 1.0);
        float opacity = uniforms.light.w;
        if (abs(mapped.z) < 1e-6) { return float4(0.0, 0.0, 0.0, opacity); }
        float2 point = mapped.xy / mapped.z;
        float2 unit = (point - uniforms.screenAndOrigin.zw) / uniforms.paddedAndBlur.xy;
        if (any(unit < 0.0) || any(unit > 1.0)) { return float4(0.0, 0.0, 0.0, opacity); }
        float height = clamp(point.y / screenSize.y, 0.0, 1.0);
        float sigma = 0.5 * uniforms.paddedAndBlur.z * uniforms.paddedAndBlur.w
            * (uniforms.shape.x + (1.0 - uniforms.shape.x) * height);
        float2 uv = float2(unit.x, 1.0 - unit.y);
        float4 sharp = original.sample(linearSampler, uv, level(0.0));
        float4 soft = picture.sample(linearSampler, uv, level(0.0));
        float4 colour = mix(sharp, soft, smoothstep(0.4, 1.5, sigma));
        float spread = smoothstep(0.0, max(uniforms.light.z, 0.02), height);
        float fade = uniforms.light.y * (uniforms.light.x + (1.0 - uniforms.light.x) * spread);
        colour.rgb *= pow(1.0 - uniforms.shape.y * fade, 2.2);
        // Encode first, then premultiply for the window compositor.
        float3 encoded = select(12.92 * colour.rgb,
            1.055 * pow(max(colour.rgb, 0.0), float3(1.0 / 2.4)) - 0.055,
            colour.rgb > 0.0031308);
        return float4(encoded * opacity, opacity);
    }
    """
}
