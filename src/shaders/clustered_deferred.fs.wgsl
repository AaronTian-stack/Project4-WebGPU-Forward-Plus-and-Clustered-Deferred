// TODO-3: implement the Clustered Deferred G-buffer fragment shader

// This shader should only store G-buffer information and should not do any shading.
@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput {
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4<u32> {
    let albedo = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    let normal = vec4f(normalize(in.nor), 1.0);

    let packedAlbedo : u32 = pack4x8unorm(clamp(albedo, vec4(0.0), vec4(1.0)));

    let n = normalize(in.nor);
    let nx = bitcast<u32>(n.x);
    let ny = bitcast<u32>(n.y);
    let nz = bitcast<u32>(n.z);

    return vec4<u32>(packedAlbedo, nx, ny, nz);
}
