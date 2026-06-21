# Vulkan sampler2DArray 完整使用流程

基于 `texturearray` 示例，总结从 C++ 端创建纹理数组到 Shader 端采样的完整流程。

## 数据流总览

```
C++ 侧                                     Shader 侧
──────                                     ────────

VkImage (arrayLayers = N)                  sampler2DArray (binding 1)
  └─ VkImageView (2D_ARRAY, N layers)         └─ texture(samplerArray, vec3(u,v,layer))
  └─ VkSampler (过滤/寻址规则)

uniformData.instance[i]
  ├─ model: 第 i 个实例的变换矩阵   ────→   ubo.instance[gl_InstanceIndex].model
  └─ arrayIndex: 第 i 个实例的层号   ────→   ubo.instance[gl_InstanceIndex].arrayIndex
                                                   │
                                                   ▼
                                          outUV = vec3(inUV, arrayIndex)
                                                   │
                                                   ▼
                                          texture(samplerArray, inUV)
```

---

## 一、C++ 代码侧

### 1. 创建 VkImage（声明层数）

关键是将 `arrayLayers` 设置为实际层数：

```188:189:examples/texturearray/texturearray.cpp
        imageCreateInfo.arrayLayers = layerCount;
```

完整创建参数：

| 参数 | 值 | 说明 |
|------|-----|------|
| `imageType` | `VK_IMAGE_TYPE_2D` | 2D 纹理类型 |
| `arrayLayers` | `layerCount` | 致命参数：数组层数 |
| `mipLevels` | `1` | 示例简化，只用 1 级 mip |
| `tiling` | `VK_IMAGE_TILING_OPTIMAL` | 最优布局 |
| `usage` | `TRANSFER_DST \| SAMPLED` | 可作为传输目标 + 可被着色器采样 |
| `initialLayout` | `VK_IMAGE_LAYOUT_UNDEFINED` | 初始状态 |

### 2. 上传每个层的数据

用 `VkBufferImageCopy` 逐层指定从 staging buffer 拷贝到 image 的区域：

```164:181:examples/texturearray/texturearray.cpp
        for (uint32_t layer = 0; layer < layerCount; layer++)
        {
            // Calculate offset into staging buffer for the current array layer
            ktx_size_t offset;
            KTX_error_code ret = ktxTexture_GetImageOffset(ktxTexture, 0, layer, 0, &offset);
            assert(ret == KTX_SUCCESS);
            // Setup a buffer image copy structure for the current array layer
            VkBufferImageCopy bufferCopyRegion = {};
            bufferCopyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            bufferCopyRegion.imageSubresource.mipLevel = 0;
            bufferCopyRegion.imageSubresource.baseArrayLayer = layer;
            bufferCopyRegion.imageSubresource.layerCount = 1;
            bufferCopyRegion.imageExtent.width = ktxTexture->baseWidth;
            bufferCopyRegion.imageExtent.height = ktxTexture->baseHeight;
            bufferCopyRegion.imageExtent.depth = 1;
            bufferCopyRegion.bufferOffset = offset;
            bufferCopyRegions.push_back(bufferCopyRegion);
        }
```

每个 `VkBufferImageCopy` 的关键字段：

- `imageSubresource.baseArrayLayer`：当前正拷贝到第几层
- `imageSubresource.layerCount`：一次拷贝多少层（这里每次 1 层）
- `bufferOffset`：staging buffer 中该层数据的偏移

随后用 `vkCmdCopyBufferToImage` 一次性拷贝所有层。

### 3. 创建 VkImageView（显式声明为数组视图）

```260:265:examples/texturearray/texturearray.cpp
        view.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY;
        view.format = format;
        view.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
        view.subresourceRange.layerCount = layerCount;
```

关键参数：

| 参数 | 值 | 说明 |
|------|-----|------|
| `viewType` | `VK_IMAGE_VIEW_TYPE_2D_ARRAY` | 必须设为数组类型 |
| `subresourceRange.layerCount` | `layerCount` | 暴露给着色器的层数 |

### 4. 创建 VkSampler

与普通 2D 纹理的 sampler 创建完全一致，无特殊处理。

### 5. Descriptor Set 绑定

将 `VkImageView` + `VkSampler` 作为 `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` 绑定到 shader 的对应 binding 点：

```365:374:examples/texturearray/texturearray.cpp
        VkDescriptorImageInfo textureDescriptor = vks::initializers::descriptorImageInfo(textureArray.sampler, textureArray.view, textureArray.imageLayout);

        VkDescriptorSetAllocateInfo allocInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
        for (auto i = 0; i < uniformBuffers.size(); i++) {
            VK_CHECK_RESULT(vkAllocateDescriptorSets(device, &allocInfo, &descriptorSets[i]));
            std::vector<VkWriteDescriptorSet> writeDescriptorSets = {
                vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 0, &uniformBuffers[i].descriptor),
                vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, &textureDescriptor),
            };
            vkUpdateDescriptorSets(device, static_cast<uint32_t>(writeDescriptorSets.size()), writeDescriptorSets.data(), 0, nullptr);
        }
```

DSL 布局声明：

```356:359:examples/texturearray/texturearray.cpp
            vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_VERTEX_BIT, 0),
            // Binding 1 : Fragment shader image sampler
            vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT, 1)
```

### 6. 准备每实例数据（配合 gl_InstanceIndex）

为每个实例填入独立的模型矩阵和层索引：

```436:439:examples/texturearray/texturearray.cpp
        for (uint32_t i = 0; i < layerCount; i++) {
            // ...
            uniformData.instance[i].arrayIndex = (float)i;
```

### 7. Draw Call

`instanceCount` 参数决定实例数量：

```503:503:examples/texturearray/texturearray.cpp
        vkCmdDrawIndexed(cmdBuffer, indexCount, layerCount, 0, 0, 0);
```

`vkCmdDrawIndexed(indexCount, instanceCount, firstIndex, vertexOffset, firstInstance)` —— `instanceCount = layerCount` 告诉 GPU 将同一套顶点数据画 N 次。

---

## 二、Shader 侧

### Vertex Shader

UBO 中包含实例数组，用 `gl_InstanceIndex` 做下标：

```7:20:shaders/glsl/texturearray/instancing.vert
struct Instance
{
    mat4 model;
    float arrayIndex;
};

layout (binding = 0) uniform UBO 
{
    mat4 projection;
    mat4 view;
    Instance instance[8];
} ubo;

layout (location = 0) out vec3 outUV;
```

顶点着色器 main 函数：

```23:25:shaders/glsl/texturearray/instancing.vert
    outUV = vec3(inUV, ubo.instance[gl_InstanceIndex].arrayIndex);
    mat4 modelView = ubo.view * ubo.instance[gl_InstanceIndex].model;
    gl_Position = ubo.projection * modelView * vec4(inPos, 1.0);
```

要点：
- `outUV` 是 `vec3` 类型（不是 `vec2`），第三个分量 Z 承载层索引
- `gl_InstanceIndex` 由 GPU 硬件自动递增，范围 [0, instanceCount-1]
- 用 `gl_InstanceIndex` 从 UBO 数组中取出当前实例的 `model` 和 `arrayIndex`

### Fragment Shader

```3:10:shaders/glsl/texturearray/instancing.frag
layout (binding = 1) uniform sampler2DArray samplerArray;

layout (location = 0) in vec3 inUV;

void main() 
{
    outFragColor = texture(samplerArray, inUV);
}
```

要点：
- 采样器类型必须是 `sampler2DArray`（不是 `sampler2D`）
- `texture(samplerArray, inUV)` 的三维坐标中，`inUV.z` 即为层索引
- `inUV.z` 取整数值：0 采第 0 层，1 采第 1 层，依此类推

---

## 三、gl_InstanceIndex 配合流程

```
vkCmdDrawIndexed(indexCount, layerCount=8, ...)
         │
         ▼
    GPU 硬件迭代 8 次
         │
    ┌────┴────┐
    │ 第0遍   │  第1遍  │  ...  │  第7遍  │
    │ idx=0   │  idx=1  │       │  idx=7  │
    └────┬────┘───┬─────┘───────┴───┬─────┘
         │        │                 │
         ▼        ▼                 ▼
   ubo.instance[0]  ubo.instance[1]  ubo.instance[7]
   model: 左移1.5   model: 左移0    model: 右移9
   arrayIndex: 0.0  arrayIndex: 1.0 arrayIndex: 7.0
         │        │                 │
         ▼        ▼                 ▼
   outUV.z = 0.0  outUV.z = 1.0   outUV.z = 7.0
         │        │                 │
         ▼        ▼                 ▼
   texture(samplerArray, vec3(u,v,0.0))
   → 采样 layer 0
                  texture(samplerArray, vec3(u,v,1.0))
                  → 采样 layer 1
                                    texture(samplerArray, vec3(u,v,7.0))
                                    → 采样 layer 7
```

每个实例的顶点数据相同（来自同一个 vertex buffer），但：
- **模型矩阵不同** → cube 出现在不同位置（排成一列）
- **层索引不同** → cube 显示不同纹理图案

一个 draw call、一套顶点数据、一张纹理数组，完成 8 个不同 cube 的渲染。

---

## 四、KTX 多层纹理存储格式

### 文件头部

KTX 文件头部 `numberOfArrayElements` 字段声明纹理层数。libktx 解析后映射为 `ktxTexture->numLayers`。值为 0 表示单层非数组纹理。

```538:538:external/ktx/include/ktx.h
    ktx_uint32_t numberOfArrayElements;
```

### 数据布局

像素数据区域按 **"mip level → layer"** 的顺序排列，同一 mip level 内所有层连续存放：

```
KTX 文件数据区
─────────────
mip level 0:
  ┌─ layer 0  ──┬── layer 1  ──┬── ... ──┬── layer N-1  ──┐
  │  像素数据 (宽×高)   │   像素数据    │          │   像素数据       │
  └─────────────┴──────────────┴─────────┴─────────────────┘
mip level 1 (宽高减半):
  ┌─ layer 0  ──┬── layer 1  ──┬── ... ──┬── layer N-1  ──┐
  │  像素数据    │   像素数据    │          │   像素数据       │
  └─────────────┴──────────────┴─────────┴─────────────────┘
...
```

cubemap 同理，6 个 face 本质上也是 6 层。

### offset 计算

`ktxTexture_GetImageOffset(texture, level, layer, face, &offset)` 计算指定层的字节偏移：

```1620:1624:external/ktx/lib/texture.c
    *pOffset = ktxTexture_dataSize(This, level);
    
    if (layer != 0) {
        ktx_size_t layerSize;
        layerSize = ktxTexture_layerSize(This, level);
        *pOffset += layer * layerSize;
    }
```

逻辑：**跳过前面所有 mip level 的总数据量**，然后加上 `layer × 单层大小`。同一 mip level 内所有层尺寸相同，所以偏移量按倍增计算。

### 上传时的对应

`bufferOffset` 从 KTX 文件中定位到正确的层数据，`baseArrayLayer` 指定写入 VkImage 的哪一层：

```164:181:examples/texturearray/texturearray.cpp
        for (uint32_t layer = 0; layer < layerCount; layer++)
        {
            ktx_size_t offset;
            KTX_error_code ret = ktxTexture_GetImageOffset(ktxTexture, 0, layer, 0, &offset);
            ...
            bufferCopyRegion.imageSubresource.baseArrayLayer = layer;
            bufferCopyRegion.bufferOffset = offset;
            ...
        }
```

### 查看 KTX 文件的工具

| 工具 | 平台 | 说明 |
|------|------|------|
| **PVRTexTool** | Win/Mac/Linux | 最常用 KTX/KTX2 查看器，图形界面逐层切换浏览 |
| **AMD Compress** (原 Compressonator) | Win/Linux | AMD 开源工具，支持查看和编辑 |
| **toktx / ktxinfo** (Khronos KTX-Software) | Win/Mac/Linux | 官方 CLI 工具，`ktxinfo` 查看文件元信息，`toktx` 将 PNG 合成为多层 KTX |
| **Mali Texture Compression Tool** | Win/Mac/Linux | ARM 出品，支持 KTX 查看 |
| **DirectXTex texconv** | Win | Microsoft 纹理工具，支持 KTX/KTX2 读写 |
| **NVIDIA Texture Tools Exporter** | Win | NVIDIA 纹理工具，支持导出/查看 |