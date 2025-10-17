import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
    // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
    // you may need extra uniforms such as the camera view matrix and the canvas resolution

    sceneBindGroupLayout: GPUBindGroupLayout;
    sceneBindGroup: GPUBindGroup;
    materialBindGroupLayout: GPUBindGroupLayout;
    materialBindGroup: GPUBindGroup;

    gBufferPipeline: GPURenderPipeline;
    lightingPipeline: GPURenderPipeline;
    clusterComputePipeline: GPUComputePipeline;

    depthTexture: GPUTexture;
    depthTextureView: GPUTextureView;
    gBufferTextures: GPUTexture[];
    gBufferTextureViews: GPUTextureView[];

    constructor(stage: Stage) {
        super(stage);

        // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass
        
        this.depthTexture = renderer.device.createTexture({
            label: "depth texture",
            size: { width: renderer.canvas.width, height: renderer.canvas.height, depthOrArrayLayers: 1 },
            format: "depth32float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.depthTextureView = this.depthTexture.createView();

        this.gBufferTextures = [];
        this.gBufferTextureViews = [];
        const gBufferLabels: string[] = ["Albedo", "Normal"];
        const gBufferFormats: GPUTextureFormat[] = ["rgba8unorm", "rgba16float"];
        for (let i = 0; i < gBufferFormats.length; i++) {
            const gBufferTexture = renderer.device.createTexture({
                label: gBufferLabels[i],
                size: { width: renderer.canvas.width, height: renderer.canvas.height, depthOrArrayLayers: 1 },
                format: gBufferFormats[i],
                usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
            });
            this.gBufferTextures.push(gBufferTexture);
            this.gBufferTextureViews.push(gBufferTexture.createView());
        }
        
        this.sceneBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "scene uniforms bind group layout",
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT | GPUShaderStage.COMPUTE,
                    buffer: { type: "uniform" }
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.COMPUTE,
                    buffer: { type: "read-only-storage" }
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.COMPUTE,
                    buffer: { type: "storage" }
                }
            ]
        });

        this.sceneBindGroup = renderer.device.createBindGroup({
            label: "scene uniforms bind group",
            layout: this.sceneBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.lights.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: { buffer: this.lights.clusterSetStorageBuffer }
                }
            ]
        });
        
        this.materialBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "gbuffer bind group layout",
            entries: [
                { // Albedo
                    binding: 0,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {
                        sampleType: "float",
                        viewDimension: "2d",
                        multisampled: false
                    }
                },
                { // Normal
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {
                        sampleType: "float",
                        viewDimension: "2d",
                        multisampled: false
                    }
                },
                { // Depth
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {
                        sampleType: "depth",
                        viewDimension: "2d",
                        multisampled: false
                    }
                }
            ]
        });

        this.materialBindGroup = renderer.device.createBindGroup({
            label: "gbuffer bind group",
            layout: this.materialBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: this.gBufferTextureViews[0]
                },
                {
                    binding: 1,
                    resource: this.gBufferTextureViews[1]
                },
                {
                    binding: 2,
                    resource: this.depthTextureView
                }
            ]
        });

        this.gBufferPipeline = renderer.device.createRenderPipeline({
            label: "G-buffer pipeline",
            layout: renderer.device.createPipelineLayout({
                label: "G-buffer pipeline layout",
                bindGroupLayouts: [
                    this.sceneBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout
                ]
            }),
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "G-buffer vertex shader",
                    code: shaders.naiveVertSrc
                }),
                entryPoint: "main",
                buffers: [ renderer.vertexBufferLayout ]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "G-buffer fragment shader",
                    code: shaders.clusteredDeferredFragSrc
                }),
                entryPoint: "main",
                targets: [
                    {
                        format: gBufferFormats[0],
                        blend: {
                            color: {
                                srcFactor: "src-alpha",
                                dstFactor: "one-minus-src-alpha",
                                operation: "add"
                            },
                            alpha: {
                                srcFactor: "one",
                                dstFactor: "one-minus-src-alpha",
                                operation: "add"
                            }
                        }
                    },
                    {
                        format: gBufferFormats[1],
                        blend: undefined
                    }
                ]
            },
            primitive: {
                topology: "triangle-list",
                cullMode: "back"
            },
            depthStencil: {
                format: "depth32float",
                depthWriteEnabled: true,
                depthCompare: "less"
            }
        });

        this.lightingPipeline = renderer.device.createRenderPipeline({
            label: "lighting pipeline",
            layout: renderer.device.createPipelineLayout({
                label: "lighting pipeline layout",
                bindGroupLayouts: [
                    this.sceneBindGroupLayout,
                    this.materialBindGroupLayout
                ]
            }),
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "lighting vertex shader",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                }),
                entryPoint: "main"
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "lighting fragment shader",
                    code: shaders.clusteredDeferredFullscreenFragSrc
                }),
                entryPoint: "main",
                targets: [
                    {
                        format: renderer.canvasFormat,
                        blend: undefined
                    }
                ]
            },
            primitive: {
                topology: "triangle-list",
                cullMode: "front"
            }
        });

        this.clusterComputePipeline = renderer.device.createComputePipeline({
            label: "cluster compute pipeline",
            layout: renderer.device.createPipelineLayout({
                label: "cluster compute pipeline layout",
                bindGroupLayouts: [ this.sceneBindGroupLayout ]
            }),
            compute: {
                module: renderer.device.createShaderModule({
                    label: "cluster compute shader",
                    code: shaders.clusteringComputeSrc
                }),
                entryPoint: "main"
            }
        });
    }

    override draw() {
        // TODO-3: run the Forward+ rendering pass:
        // - run the clustering compute shader
        // - run the G-buffer pass, outputting position, albedo, and normals
        // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations

        const encoder = renderer.device.createCommandEncoder();
        this.lights.doLightClustering(encoder);
        const canvasTextureView = renderer.context.getCurrentTexture().createView();
        const renderPass = encoder.beginRenderPass({
            label: "clustered deferred render pass",
            colorAttachments: [
                {
                    view: this.gBufferTextureViews[0],
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.gBufferTextureViews[1],
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });
        // G-buffer pass
        renderPass.setPipeline(this.gBufferPipeline);
        renderPass.setBindGroup(0, this.sceneBindGroup);
        this.scene.iterate(node => {
            renderPass.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
        }, material => {
            renderPass.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
        }, primitive => {
            renderPass.setVertexBuffer(0, primitive.vertexBuffer);
            renderPass.setIndexBuffer(primitive.indexBuffer, 'uint32');
            renderPass.drawIndexed(primitive.numIndices);
        });
        renderPass.end();
        // Fullscreen pass
        const lightingPass = encoder.beginRenderPass({
            label: "lighting render pass",
            colorAttachments: [
                {
                    view: canvasTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ]
        });
        lightingPass.setPipeline(this.lightingPipeline);
        lightingPass.setBindGroup(0, this.sceneBindGroup);
        lightingPass.setBindGroup(1, this.materialBindGroup);
        lightingPass.draw(3);
        lightingPass.end();
        renderer.device.queue.submit([encoder.finish()]);
    }
}
