# Vulkan Input Attachments 示例解析

源码位置：`vulkan_examples/examples/inputattachments/inputattachments.cpp`

## 整体架构

本示例演示 Vulkan 的 Input Attachment 机制：在同一个 RenderPass 内，后一个 Subpass 可以零延迟读取前一个 Subpass 写入的附件内容（同像素位置），避免显存往返。

```
        Subpass 0 (写)              Subpass 1 (读 → 输出)
      +-----------------+          +---------------------------+
      | 写入 offscreen  |          | 读取 offscreen color/depth |
      | color (att#1)   │──依赖──▶│ 作为 input attachments      |
      | depth (att#2)   |          │ 输出到 swapchain (att#0)    |
      +-----------------+          +---------------------------+
           场景渲染                      全屏后处理 (亮度/对比度/深度可视化)
```

三层附件角色：

| 索引 | 来源 | 角色 |
|------|------|------|
| `attachments[0]` | swapchain.imageViews[i] | 最终呈现到屏幕的颜色附件，Subpass 1 写入 |
| `attachments[1]` | offscreen Image（`attachments.color`） | Subpass 0 写入场景颜色，Subpass 1 作为 input attachment 读 |
| `attachments[2]` | offscreen Image（`attachments.depth`） | Subpass 0 写入场景深度，Subpass 1 作为 input attachment 读 |

---

## 1. 离屏渲染 Attachments

### 1.1 为什么需要离屏附件

本示例的 offscreen color/depth 附件不同于基础类中直接写入 swapchain 的做法——它们是专为演示 input attachment 机制而存在的中间附件。场景先渲染到 offscreen，后处理阶段再读取 offscreen 内容、输出到 swapchain。

格式选择：offscreen color 刻意使用 `VK_FORMAT_R8G8B8A8_UNORM`（线性 8 位）而非 swapchain 常用的 sRGB，是为了让后处理 shader 在线性空间做亮度/对比度计算，避免非线性 sRGB 空间下的颜色偏差。

### 1.2 `createAttachment()` 做了什么

```cpp
void createAttachment(VkFormat format, VkImageUsageFlags usage, FrameBufferAttachment *attachment)
```

创建一个完整的 FrameBufferAttachment，包含三步：

1. **创建 VkImage**：尺寸 = 窗口宽高，`samples = 1`（无 MSAA），`tiling = OPTIMAL`，`usage` 自动附加 `VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT`（这是 input attachment 能被读取的硬件前提）
2. **分配 + 绑定 Device Local Memory**：`VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT`，GPU 端私有内存
3. **创建 VkImageView**：根据 usage 决定 aspectMask（color / depth）

### 1.3 两处调用点的区别

代码中有两处 `createAttachment()` 调用，属于互斥的生命周期路径：

**第一处**：`setupRenderPass()` 中的初始创建

```cpp
createAttachment(colorFormat, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, &attachments.color);
createAttachment(depthFormat, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, &attachments.depth);
```

在 `prepare()` 流程中首次执行。RenderPass 必须先于 Framebuffer 创建，而 Framebuffer 需要引用 ImageView，所以 offscreen attachment 必须在 RenderPass 创建时就分配好。

**第二处**：`setupFrameBuffer()` 中的 resize 重建

```cpp
if (attachmentSize.width != width || attachmentSize.height != height) {
    clearAttachment(&attachments.color);
    clearAttachment(&attachments.depth);
    createAttachment(colorFormat, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, &attachments.color);
    createAttachment(depthFormat, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, &attachments.depth);
    // 销毁依赖 ImageView 的派生资源，然后重建
    setupDescriptors();
}
```

VkImage 尺寸在创建时就固定了。窗口尺寸变化时，必须销毁旧 Image 后用新尺寸重建。resize 路径比初始创建多做一件事：销毁依赖 attachment ImageView 的所有派生资源（PipelineLayout、DescriptorSetLayout、DescriptorPool），然后重新 `setupDescriptors()`——因为 DescriptorSet 里的 input attachment 绑定引用了 ImageView，ImageView 被销毁后这些 DescriptorSet 就悬空了。

### 1.4 swapchain color 为什么不需要在这里创建

swapchain 的 Image 由 `VulkanExampleBase::createSwapChain()` 统一分配，受 present engine 管理生命周期，示例代码只能引用 `swapChain.imageViews[i]`，不能自行分配。

---

## 2. RenderPass 和 Subpass

### 2.1 RenderPass 结构：3 Attachment + 2 Subpass

```cpp
std::array<VkAttachmentDescription, 3> attachments{};
std::array<VkSubpassDescription, 2> subpassDescriptions{};
std::array<VkSubpassDependency, 3> dependencies{};
```

### 2.2 附件描述

```cpp
// Swap chain image color attachment
attachments[0].format = swapChain.colorFormat;
attachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;       // 要呈现到屏幕
attachments[0].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
attachments[0].finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR; // 最终布局

// Offscreen color attachment（Subpass 0 写入，Subpass 1 读取）
attachments[1].format = colorFormat;
attachments[1].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;    // 仅 RenderPass 内有效
attachments[1].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
attachments[1].finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

// Offscreen depth attachment
attachments[2].format = depthFormat;
attachments[2].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
attachments[2].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
```

关键差异：

- `attachments[0]`（swapchain）：`storeOp = STORE`，因为要呈现到屏幕；`finalLayout = PRESENT_SRC_KHR`
- `attachments[1]` 和 `attachments[2]`（offscreen）：`storeOp = DONT_CARE`——整个生命周期在 RenderPass 内部完成，离开 RenderPass 后内容不再需要，驱动可以优化掉写回

### 2.3 Subpass 0：场景渲染（写入附件）

```cpp
VkAttachmentReference colorReference = { 1, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
VkAttachmentReference depthReference = { 2, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };

subpassDescriptions[0].pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
subpassDescriptions[0].colorAttachmentCount = 1;
subpassDescriptions[0].pColorAttachments = &colorReference;
subpassDescriptions[0].pDepthStencilAttachment = &depthReference;
```

Subpass 0 正常写入 offscreen color（att#1）和 offscreen depth（att#2），和普通渲染完全一样。

### 2.4 Subpass 1：后处理（读取 input attachment + 输出到 swapchain）

```cpp
VkAttachmentReference colorReferenceSwapchain = { 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };

subpassDescriptions[1].pColorAttachments = &colorReferenceSwapchain;  // 输出到 swapchain

VkAttachmentReference inputReferences[2];
inputReferences[0] = { 1, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
inputReferences[1] = { 2, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };

subpassDescriptions[1].inputAttachmentCount = 2;
subpassDescriptions[1].pInputAttachments = inputReferences;  // 读取 offscreen color/depth
```

这是 input attachment 的核心机制：

- `pColorAttachments` 指向 `attachments[0]`（swapchain），输出目标改为 swapchain
- `pInputAttachments` 声明 Subpass 1 要在 Fragment Shader 里读 `attachments[1]` 和 `attachments[2]`——layout 设为 `SHADER_READ_ONLY_OPTIMAL`
- 这个布局转换完全由 SubpassDependency 驱动自动完成，不需要手动 barrier

硬件保证：对于 tile-based GPU（如移动端 Mali、PowerVR），如果所有附件的 tile 数据都在片上缓存中，input attachment 的读取就是零代价片上访问，不会有显存往返——这是使用 input attachments 而不是手动 barrier + 纹理采样的核心优势。

### 2.5 三条 SubpassDependency

```cpp
// Dep[0]: EXTERNAL → Subpass 0
dependencies[0].srcSubpass = VK_SUBPASS_EXTERNAL;
dependencies[0].dstSubpass = 0;
dependencies[0].srcStageMask = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;  // 保守：等全部结束
dependencies[0].dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
dependencies[0].dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT;

// Dep[1]: Subpass 0 → Subpass 1（核心：input attachment 布局转换）
dependencies[1].srcSubpass = 0;
dependencies[1].dstSubpass = 1;
dependencies[1].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
dependencies[1].dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
dependencies[1].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
dependencies[1].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
dependencies[1].dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT;

// Dep[2]: Subpass 0 → EXTERNAL
dependencies[2].srcSubpass = 0;
dependencies[2].dstSubpass = VK_SUBPASS_EXTERNAL;
dependencies[2].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
dependencies[2].dstStageMask = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;  // 保守：数据一直有效到底
dependencies[2].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
dependencies[2].dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
dependencies[2].dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT;
```

三条依赖形成完整的三段式同步链路：

| 依赖 | 方向 | Stage 转换 | 含义 |
|------|------|-----------|------|
| Dep[0] | EXTERNAL → Subpass 0 | BOTTOM_OF_PIPE → COLOR_OUTPUT \| EARLY_FRAGMENT | 外部操作全部完成后方可开始写入 offscreen 附件 |
| Dep[1] | Subpass 0 → Subpass 1 | COLOR_OUTPUT → FRAGMENT_SHADER | **核心**：Subpass 0 写入完毕后，Subpass 1 的 fragment shader 才能以 input attachment 方式读取 |
| Dep[2] | Subpass 0 → EXTERNAL | COLOR_OUTPUT → BOTTOM_OF_PIPE | Subpass 0 写入完成后，外部才能访问 |

`BOTTOM_OF_PIPE` 的含义：

- 作为 `srcStageMask`（Dep[0]）：外部生产者类型未知，只能保守地等所有阶段全结束——"信任屏障"
- 作为 `dstStageMask`（Dep[2]）：外部消费者类型未知，让数据一直有效到管线末端，一揽子兜底

`VK_DEPENDENCY_BY_REGION_BIT`：同步只需保证同一像素区域的顺序，不同区域间不需要全局屏障。对 tile-based 架构至关重要——允许 GPU 在 Subpass 0 完成一个 tile 后立即开始 Subpass 1 处理同一 tile，实现 tile 级流水线。

### 2.6 运行时命令录制

```cpp
vkCmdBeginRenderPass(cmdBuffer, &renderPassBeginInfo, VK_SUBPASS_CONTENTS_INLINE);
// 触发 Dep[0]：EXTERNAL → Subpass 0 的屏障

// === Subpass 0：场景渲染 ===
vkCmdBindPipeline(..., pipelines.attachmentWrite);
scene.draw(cmdBuffer);   // 写入 offscreen color (att#1) + depth (att#2)

vkCmdNextSubpass(cmdBuffer, VK_SUBPASS_CONTENTS_INLINE);
// 触发 Dep[1]：Subpass 0 → Subpass 1 的屏障
// ⇒ offscreen attachments 布局从 "color/depth attachment 可写"
//   转换为 "shader read only"

// === Subpass 1：后处理 ===
vkCmdBindPipeline(..., pipelines.attachmentRead);
vkCmdDraw(cmdBuffer, 3, 1, 0, 0);   // 全屏三角形，fragment shader 内 subpassLoad 读取 input attachments

drawUI(cmdBuffer);   // UI overlay 也在 Subpass 1 里

vkCmdEndRenderPass(cmdBuffer);
// 触发 Dep[2]：Subpass 0 → EXTERNAL 的屏障
// ⇒ swapchain image 转为 PRESENT_SRC_KHR，可被 present
```

`vkCmdNextSubpass` 是多 Subpass RenderPass 内部的"分阶段开关"：让驱动按 Subpass 顺序向前推进，并自动应用 SubpassDependency 屏障——开发者不需要手动写任何 `vkCmdPipelineBarrier`。

---

## 3. Shader 中使用 Input Attachment

### 3.1 `attachmentwrite` 系列：Subpass 0 的场景渲染

**Vertex Shader**（`attachmentwrite.vert`）：

```glsl
layout (location = 0) in vec3 inPos;
layout (location = 1) in vec3 inColor;
layout (location = 2) in vec3 inNormal;

layout (binding = 0) uniform UBO {
    mat4 projection;
    mat4 model;
    mat4 view;
} ubo;

void main() {
    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(inPos, 1.0);
    outColor = inColor;
    outNormal = inNormal;
    outLightVec = vec3(0.0f, 5.0f, 15.0f) - inPos;
    outViewVec = -inPos.xyz;
}
```

标准的 MVP 变换 + 传递颜色、法线、光照向量到 fragment。

**Fragment Shader**（`attachmentwrite.frag`）：

```glsl
void main() {
    // Toon shading color attachment output
    float intensity = dot(normalize(inNormal), normalize(inLightVec));
    float shade = 1.0;
    shade = intensity < 0.5 ? 0.75 : shade;
    shade = intensity < 0.35 ? 0.6 : shade;
    shade = intensity < 0.25 ? 0.5 : shade;
    shade = intensity < 0.1 ? 0.25 : shade;

    outColor.rgb = inColor * 3.0 * shade;
    // Depth attachment does not need to be explicitly written
}
```

Toon shading（卡通渲染）：根据光照强度分段量化为 4 个色阶，输出到 offscreen color attachment。深度由硬件光栅化自动写入，不需要显式赋值。

### 3.2 `attachmentread` 系列：Subpass 1 的全屏后处理

**Vertex Shader**（`attachmentread.vert`）——程序化全屏三角形：

```glsl
void main() {
    gl_Position = vec4(vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2) * 2.0f - 1.0f, 0.0f, 1.0f);
}
```

不读取任何顶点数据，靠 `gl_VertexIndex` 生成 3 个顶点覆盖整个屏幕：

| VertexIndex | x | y |
|---|---|---|
| 0 | -1 | -1 |
| 1 | 3 | -1 |
| 2 | -1 | 3 |

一个覆盖 NDC `[-1, 1]` 的大三角形，超出部分被裁剪。比传统两个三角形组成的 quad 少一个顶点。C++ 侧对应 `vkCmdDraw(cmdBuffer, 3, 1, 0, 0)`，且 Pipeline 的 VertexInputState 为空。

**Fragment Shader**（`attachmentread.frag`）——input attachment 读取 + 后处理：

```glsl
layout (input_attachment_index = 0, binding = 0) uniform subpassInput inputColor;
layout (input_attachment_index = 1, binding = 1) uniform subpassInput inputDepth;

layout (binding = 2) uniform UBO {
    vec2 brightnessContrast;
    vec2 range;
    int attachmentIndex;
} ubo;

layout (location = 0) out vec4 outColor;

vec3 brightnessContrast(vec3 color, float brightness, float contrast) {
    return (color - 0.5) * contrast + 0.5 + brightness;
}

void main() {
    // 模式 0：颜色附件 + 亮度/对比度调节
    if (ubo.attachmentIndex == 0) {
        vec3 color = subpassLoad(inputColor).rgb;
        outColor.rgb = brightnessContrast(color, ubo.brightnessContrast[0], ubo.brightnessContrast[1]);
    }

    // 模式 1：深度附件可视化
    if (ubo.attachmentIndex == 1) {
        float depth = subpassLoad(inputDepth).r;
        outColor.rgb = vec3((depth - ubo.range[0]) * 1.0 / (ubo.range[1] - ubo.range[0]));
    }
}
```

### 3.3 `subpassInput` vs 普通 `sampler2D`

| 维度 | `subpassInput` | 普通 `sampler2D` |
|------|---------------|------------------|
| 坐标 | 无需坐标，`subpassLoad()` 自动读当前像素位置 | 需显式传 `vec2 uv` |
| 过滤 | 不支持，单像素单读 | 可选 linear/mipmap 过滤 |
| 跨像素 | 禁止——硬件仅保证同一位置读写可见 | 可任意位置采样 |
| 同步 | 由 SubpassDependency 隐式保证 | 需手动 barrier |
| 性能 | tile-based GPU 上为片上零延迟访问 | 需访问外部显存 |

声明中的 `input_attachment_index` 对应 RenderPass 中 `pInputAttachments` 数组的下标：

```cpp
// C++ 侧
inputReferences[0] = { 1, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };  // → input_attachment_index = 0
inputReferences[1] = { 2, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };  // → input_attachment_index = 1
```

### 3.4 `subpassLoad()` 的两种用法

**模式 0：颜色 + 亮度/对比度**

```glsl
vec3 color = subpassLoad(inputColor).rgb;
outColor.rgb = brightnessContrast(color, ubo.brightnessContrast[0], ubo.brightnessContrast[1]);
// out = (in - 0.5) * contrast + 0.5 + brightness
```

从 Subpass 0 写入的 offscreen color attachment 读当前像素位置的 toon shaded 颜色，做标准亮度/对比度变换。

**模式 1：深度可视化**

```glsl
float depth = subpassLoad(inputDepth).r;
outColor.rgb = vec3((depth - ubo.range[0]) * 1.0 / (ubo.range[1] - ubo.range[0]));
```

从 offscreen depth attachment 读当前像素深度值（`[0, 1]`），按用户设置的 `[range.x, range.y]` 区间线性映射到 `[0, 1]` 灰度。用户通过 UI 滑动条调节可见深度区间，突出指定深度范围的几何细节。

### 3.5 Descriptor 绑定

C++ 侧的 DescriptorSet 配置与 shader 声明严格对应：

```cpp
// DescriptorSetLayout bindings:
// binding 0: VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT (color)
// binding 1: VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT (depth)
// binding 2: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER (params)

std::vector<VkDescriptorImageInfo> descriptors = {
    vks::initializers::descriptorImageInfo(VK_NULL_HANDLE, attachments.color.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL),
    vks::initializers::descriptorImageInfo(VK_NULL_HANDLE, attachments.depth.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
};
```

注意 input attachment 的 ImageInfo 中 `sampler = VK_NULL_HANDLE`——input attachment 不需要 sampler，因为不做过滤采样。

---

## 4. 整体数据流

```
attachmentwrite.vert + attachmentwrite.frag  (Subpass 0)
    读取: inPos, inColor, inNormal + UBO(projection, model, view)
    计算: Toon shading（分段光照）
    输出: outColor → offscreen color (att#1)
          depth 隐式写入 offscreen depth (att#2)

  ↓ SubpassDependency[1] 自动布局转换 ↓

attachmentread.vert + attachmentread.frag    (Subpass 1)
    生成: 3 顶点的全屏三角形，无输入属性
    读取: subpassLoad(inputColor)   ← att#1（toon shaded color）
          subpassLoad(inputDepth)   ← att#2（场景深度）
          UBO(brightnessContrast, range, attachmentIndex)
    处理: 亮度/对比度调节   或   深度区间可视化
    输出: outColor → swapchain color (att#0) → 呈现到屏幕
```

## 5. 一句话总结

Input attachment 的 RenderPass 本质上是将"同一个 RenderPass 内的多阶段渲染"紧凑地表达为多个 Subpass，通过 SubpassDependency 实现 **Subpass 0 的写入 → Subpass 1 的读取** 这一生产者-消费者同步链，让 Fragment Shader 能以 `subpassInput` 的方式零延迟（tile 级）读取前一个 Subpass 的输出，避免了在 RenderPass 外跑多趟调度和显存往返的开销。