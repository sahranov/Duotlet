import simd

struct DepthUniforms {
    var column0: SIMD4<Float>
    var column1: SIMD4<Float>
    var column2: SIMD4<Float>
    var screenAndOrigin: SIMD4<Float>
    var paddedAndBlur: SIMD4<Float>
    var shape: SIMD4<Float>
    var light: SIMD4<Float>
}
