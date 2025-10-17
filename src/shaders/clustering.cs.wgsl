// TODO-2: implement the light clustering compute shader

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

// ------------------------------------
// Assigning lights to clusters:
// ------------------------------------
// For each cluster:
//     - Initialize a counter for the number of lights in this cluster.

//     For each light:
//         - Check if the light intersects with the cluster’s bounding box (AABB).
//         - If it does, add the light to the cluster's light list.
//         - Stop adding lights if the maximum number of lights is reached.

//     - Store the number of lights assigned to this cluster.

@group(0) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(0) @binding(1) var<storage, read> lightSet: LightSet;
@group(0) @binding(2) var<storage, read_write> clusterSet: ClusterSet;

var<workgroup> sharedLights: array<Light, ${clusterWorkgroupSize}>;

fn screenToView(screenPos: vec2f) -> vec4f {
    var ndcPos = vec4f(screenPos / cameraUniforms.resolution * 2.0 - 1.0, 0.0, 1.0);
    ndcPos.y *= -1; // +Y up
    var view = cameraUniforms.invProjMat * ndcPos;
    return view / view.w;
}

fn lineIntersectionZPlane(a: vec3f, b: vec3f, zDistance: f32) -> vec3f {
    let direction = b - a;
    let t = (-zDistance - a.z) / direction.z; // -Z is in front of the camera in WebGPU so use -zDistance
    return a + t * direction;
}

fn sphereIntersectsAABB(sphereCenter: vec3f, sphereRadius: f32, aabb: AABB) -> bool {
    let closest = clamp(sphereCenter, aabb.min, aabb.max);
    let dist = dot(closest - sphereCenter, closest - sphereCenter);
    return dist <= sphereRadius * sphereRadius;
}

fn buildAABB(clusterIdx: u32, globalIdx: vec3u) -> AABB {
    let pixelsPerCluster = cameraUniforms.resolution / vec2f(${numClustersX}, ${numClustersY});

    let maxScreenSpace = vec2f(f32(globalIdx.x + 1u) * pixelsPerCluster.x, f32(globalIdx.y + 1u) * pixelsPerCluster.y);
    let minScreenSpace = vec2f(globalIdx.xy) * pixelsPerCluster;

    let maxViewSpace = screenToView(maxScreenSpace).xyz;
    let minViewSpace = screenToView(minScreenSpace).xyz;

    let farDivNear = cameraUniforms.farZ / cameraUniforms.nearZ;
    let minZ = cameraUniforms.nearZ * pow(farDivNear, f32(globalIdx.z) / f32(${numClustersZ}));
    let maxZ = cameraUniforms.nearZ * pow(farDivNear, f32(globalIdx.z + 1u) / f32(${numClustersZ}));

    let eyePos = vec3f(0.0, 0.0, 0.0);

    let minPointNear = lineIntersectionZPlane(eyePos, minViewSpace, minZ);
    let minPointFar  = lineIntersectionZPlane(eyePos, minViewSpace, maxZ);
    let maxPointNear = lineIntersectionZPlane(eyePos, maxViewSpace, minZ);
    let maxPointFar  = lineIntersectionZPlane(eyePos, maxViewSpace, maxZ);

    let aabbMinXY = vec2f(
        min(minPointNear.x, minPointFar.x),
        min(minPointNear.y, minPointFar.y)
    );
    let aabbMin = vec3f(
        aabbMinXY.x,
        aabbMinXY.y,
        -maxZ
    );

    let aabbMaxXY = vec2f(
        max(maxPointNear.x, maxPointFar.x),
        max(maxPointNear.y, maxPointFar.y)
    );
    let aabbMax = vec3f(
        aabbMaxXY.x,
        aabbMaxXY.y,
        -minZ
    );

    // Bloat the AABB size to try and hide seams between clusters
    let bloatRadius = 2.0 * 0.2;
    let bloatedMin = aabbMin - vec3f(bloatRadius, bloatRadius, bloatRadius);
    let bloatedMax = aabbMax + vec3f(bloatRadius, bloatRadius, bloatRadius);

    return AABB(bloatedMin, bloatedMax);
}

fn assignLights(clusterIdx: u32, aabb: AABB) {

    clusterSet.clusters[clusterIdx].numLights = 0u;
    var visibleLightCount = 0u;

    for (var lightIdx = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        let light = lightSet.lights[lightIdx];
        let lightPosView = (cameraUniforms.viewMat * vec4f(light.pos, 1.0)).xyz;
        if (sphereIntersectsAABB(lightPosView, 2.0, aabb)) {
            if (visibleLightCount < ${maxLightsPerCluster}) {
                clusterSet.clusters[clusterIdx].lightIndices[visibleLightCount] = lightIdx;
                visibleLightCount++;
            }
        }
    }

    clusterSet.clusters[clusterIdx].numLights = visibleLightCount;
}

@compute @workgroup_size(${clusterWorkgroupSize})
fn main(@builtin(global_invocation_id) globalIdx: vec3u) {
    if (globalIdx.x >= ${numClustersX} || globalIdx.y >= ${numClustersY} || globalIdx.z >= ${numClustersZ}) {
        return;
    }
    let clusterIdx = globalIdx.x + globalIdx.y * ${numClustersX} + globalIdx.z * ${numClustersX} * ${numClustersY};
    let aabb = buildAABB(clusterIdx, globalIdx);
    assignLights(clusterIdx, aabb);
}
