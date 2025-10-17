// TODO-3: implement the Clustered Deferred fullscreen vertex shader

// This shader should be very simple as it does not need all of the information passed by the the naive vertex shader.

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f
}

@vertex
fn main(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput
{
    // https://wallisc.github.io/rendering/2021/04/18/Fullscreen-Pass.html
    let uv = vec2f(f32((vertexIndex << 1) & 2), f32(vertexIndex & 2));
    return VertexOutput (
        vec4f(uv * vec2f(2.0, -2.0) + vec2f(-1.0, 1.0), 0.0, 1.0),
        uv
    );
}
