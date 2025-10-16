// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).
@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f,
    @builtin(position) fragCoord: vec4f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);

    var totalLightContrib = vec3f(0, 0, 0);

    let viewPos = cameraUniforms.viewMat * vec4f(in.pos, 1.0);
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
        totalLightContrib += calculateLightContrib(light, in.pos, normalize(in.nor));
    }

    var finalColor = diffuseColor.rgb * totalLightContrib;
    return vec4(finalColor, diffuseColor.a);

    // return vec4(f32(numLights) / f32(${maxLightsPerCluster}), 0.0, 0.0, 1.0);


    // let screenUV = in.fragCoord.xy / cameraUniforms.resolution;
    // return vec4(screenUV, 0.0, 1.0);

    // return vec4(f32(clusterX) / f32(${numClustersX}), f32(clusterY) / f32(${numClustersY}), f32(slice) / f32(${numClustersZ}), 1.0);
    // return vec4(0.0, 0.0, f32(slice) / f32(${numClustersZ}), 1.0);
}
