// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.

@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;

@group(1) @binding(0) var albedoNormalTexture: texture_2d<u32>;
@group(1) @binding(1) var depthTexture: texture_depth_2d;

fn reconstructPosition(uv: vec2f, depth: f32) -> vec3f {
    var ndc = vec4f(uv * 2.0 - 1.0, depth, 1.0);
    ndc.y *= -1.0; // +Y up
    let pos = cameraUniforms.invViewProjMat * ndc;
    return (pos / pos.w).xyz;
}

struct FragmentInput {
    @builtin(position) fragCoord: vec4f,
    @location(0) uv: vec2f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f {
    let uv = in.uv;

    let pixelPosition = vec2i(uv * cameraUniforms.resolution);

    let rawValue = textureLoad(albedoNormalTexture, pixelPosition, 0);
    let albedo = unpack4x8unorm(rawValue.x);
    let normal = vec3<f32>(
        bitcast<f32>(rawValue.y),
        bitcast<f32>(rawValue.z),
        bitcast<f32>(rawValue.w)
    );

    let depth: f32 = textureLoad(depthTexture, pixelPosition, 0);

    let position = reconstructPosition(uv.xy, depth);

    var totalLightContrib = vec3f(0, 0, 0);

    let viewPos = cameraUniforms.viewMat * vec4f(position, 1.0);
    let slice = u32(f32(${numClustersZ}) / log(cameraUniforms.farZ / cameraUniforms.nearZ) * log(-viewPos.z / cameraUniforms.nearZ));

    let pixelsPerCluster = cameraUniforms.resolution / vec2f(${numClustersX}, ${numClustersY});
    let clusterX = u32(floor(in.fragCoord.x / pixelsPerCluster.x));
    // Clusters were computed with +Y up, but fragCoord has +Y down
    let tempY = u32(clamp(((cameraUniforms.resolution.y - in.fragCoord.y) / cameraUniforms.resolution.y) * f32(${numClustersY}), 0.0, f32(${numClustersY} - 1)));
    let clusterY = ${numClustersY} - 1 - tempY;
    let clusterIdx = clusterX + clusterY * ${numClustersX} + slice * ${numClustersX} * ${numClustersY};
    
    let numLights = clusterSet.clusters[clusterIdx].numLights;
    for (var i = 0u; i < numLights; i++) {
        let lightIdx = clusterSet.clusters[clusterIdx].lightIndices[i];
        let light = lightSet.lights[lightIdx];
        totalLightContrib += calculateLightContrib(light, position, normalize(normal.xyz));
    }

    var finalColor = albedo.rgb * totalLightContrib;

    // return vec4(f32(numLights) / f32(${maxLightsPerCluster}), 0.0, 0.0, 1.0);
    // return vec4(albedo.rgb, 1.0);
    // return vec4(position, 1.0);
    return vec4(finalColor, albedo.a);
}
