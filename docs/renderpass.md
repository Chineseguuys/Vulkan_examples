# Vulkan RenderPass 创建流程

以 `VulkanExampleBase::setupRenderPass()`（基础类实现，2 个 Attachment + 1 个 Subpass 的典型场景）为例，总结 Vulkan 中创建一个 RenderPass 的基本流程。

源码位置：`vulkan_examples/base/vulkanexamplebase.cpp:2625`

## 整体数据流

```
AttachmentDescription[]  ──┐
                           │
AttachmentReference[]   ──┤
                           │
SubpassDescription[]    ──┼──▶ VkRenderPassCreateInfo ──▶ vkCreateRenderPass()
                           │
SubpassDependency[]     ──┘
```

RenderPass 本质上是一份"渲染目标配置说明书"：告诉驱动这个渲染过程会用哪些附件、每个子通道怎么读写它们、子通道之间如何同步和做布局转换。它本身不分配内存，也不绑定具体资源——具体的 Image/ImageView 由 Framebuffer 在 RenderPass 之上再绑定。

## 6 个步骤

### 1. 动态渲染判断（可选的前置守卫）

```cpp
void VulkanExampleBase::setupRenderPass() {
    if (useDynamicRendering) {
        // When dynamic rendering is enabled, render passes are no longer required
        renderPass = VK_NULL_HANDLE;
        return;
    }
    // ...
}
```

Vulkan 1.3 引入的 Dynamic Rendering（`vkCmdBeginRenderingKHR`）可以完全替代传统 RenderPass。如果启用了该特性，这里直接把 `renderPass` 置空并返回，后续命令录制用 `beginDynamicRendering` 代替。这是两条互斥的渲染路径。

### 2. 描述附件（`VkAttachmentDescription`）

附件是 RenderPass 对"一张 Image 在这个渲染过程中如何被使用"的抽象描述。这里定义了两个附件：颜色附件和深度附件。

```cpp
std::array<VkAttachmentDescription, 2> attachments{
    // Color attachment
    VkAttachmentDescription{.format = swapChain.colorFormat,
                            .samples = VK_SAMPLE_COUNT_1_BIT,
                            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
                            .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
                            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
                            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                            .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR},
    // Depth attachment
    VkAttachmentDescription{.format = depthFormat,
                            .samples = VK_SAMPLE_COUNT_1_BIT,
                            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
                            .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
                            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
                            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
                            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                            .finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL}};
```

每个关键字段的作用：

| 字段 | 含义 |
|------|------|
| `format` | 附件的像素格式，必须和后续绑定到 Framebuffer 的 View 格式一致 |
| `samples` | MSAA 采样数，`1_BIT` 表示不做多重采样 |
| `loadOp` | 子通道开始时对附件内容做什么——`CLEAR` 清为指定值 |
| `storeOp` | 子通道结束时是否写回——`STORE` 保留结果供后续读取/present |
| `stencilLoadOp` / `stencilStoreOp` | 模板分量的加载/存储策略（深度附件专用） |
| `initialLayout` | 进入 RenderPass 时驱动预期该 Image 的布局；`UNDEFINED` 表示不关心原始内容，允许驱动直接丢弃，省一次布局转换 |
| `finalLayout` | 退出 RenderPass 时 Image 应转换到的布局；颜色附件设为 `PRESENT_SRC_KHR` 以便 swapchain 呈现，深度附件设为 `DEPTH_STENCIL_ATTACHMENT_OPTIMAL` |

`loadOp` 就像一个隐式的"进入屏障"，驱动会在子通道开始前自动把布局从 `initialLayout` 切换到子通道引用中声明的布局。

### 3. 引用附件（`VkAttachmentReference`）

引用把"附件在数组中的索引"和"在子通道中用到的布局"绑定在一起。

```cpp
VkAttachmentReference colorReference{.attachment = 0, .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
VkAttachmentReference depthReference{.attachment = 1, .layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
```

`.attachment` 是上一步 `attachments` 数组的下标（0 = 颜色, 1 = 深度）；`.layout` 指定在该子通道执行期间这张 Image 应该处于什么布局。驱动据此安排从 `initialLayout` → 引用布局 → `finalLayout` 的自动转换时机。

### 4. 描述子通道（`VkSubpassDescription`）

子通道是 RenderPass 的一次"绘制阶段"，GPU 在该阶段内对附件做实际的渲染写操作。

```cpp
VkSubpassDescription subpassDescription{
    .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
    .colorAttachmentCount = 1,
    .pColorAttachments = &colorReference,
    .pDepthStencilAttachment = &depthReference,
};
```

- `pipelineBindPoint` 决定这个子通道绑定哪种 Pipeline（图形 = `GRAPHICS`）。
- `pColorAttachments` / `pDepthStencilAttachment` 指向第 3 步的引用，声明本子通道会以"可写"方式使用哪些附件。
- 多 pass 技术（如 G-Buffer、后处理）会在同一个 RenderPass 里描述多个 Subpass，每个 Subpass 通过 `pInputAttachments` 读取前一个 Subpass 的输出，实现片上 tile 内存复用，避免多余的全局内存往返。

### 5. 声明子通道依赖（`VkSubpassDependency`）

依赖描述的是 RenderPass 内外子通道之间的执行顺序和内存屏障，让驱动知道何时做布局切换、何时做 cache 刷新才安全。

```cpp
std::array<VkSubpassDependency, 2> dependencies{
    VkSubpassDependency{
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .srcAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
    },
    VkSubpassDependency{
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_COLOR_ATTACHMENT_READ_BIT,
    }};
```

两条依赖的作用：

**第一条（深度）**：外部 → 子通道 0。保证深度/模板写操作在子通道开始前完成可见性转换，避免上一帧的深度写和当前帧的深度读之间出现 hazard。

**第二条（颜色）**：外部 → 子通道 0。声明颜色附件在 `COLOR_ATTACHMENT_OUTPUT` 阶段会被写。这个依赖还有一个隐含的重要作用：它正是 swapchain 语义信号量 `VK_KHR_swapchain` 所需的同步点——rendering 必须 wait 在 `presentCompleteSemaphore` 的 `COLOR_ATTACHMENT_OUTPUT` 阶段，与这条 dependency 的 stage mask 对齐，才能安全写入 swapchain image。

`srcSubpass = VK_SUBPASS_EXTERNAL` 表示"RenderPass 之前的外部操作"，`dstSubpass = 0` 表示"第一个子通道"；如果有多个子通道，依赖会写 `0 → 1`、`1 → 2` 这样的序列。

### 6. 汇总并创建（`vkCreateRenderPass`）

把前几步的产品汇总成 `VkRenderPassCreateInfo`，调用 API 生成不可变的 RenderPass 对象。

```cpp
VkRenderPassCreateInfo renderPassInfo{
    .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    .attachmentCount = static_cast<uint32_t>(attachments.size()),
    .pAttachments = attachments.data(),
    .subpassCount = 1,
    .pSubpasses = &subpassDescription,
    .dependencyCount = static_cast<uint32_t>(dependencies.size()),
    .pDependencies = dependencies.data(),
};
VK_CHECK_RESULT(vkCreateRenderPass(device, &renderPassInfo, nullptr, &renderPass));
```

返回的 `renderPass` 句柄后续会被两处使用：

- `setupFrameBuffer()` 中创建 `VkFramebuffer`，把 RenderPass 的附件抽象绑定到具体的 `VkImageView`（swapchain 图片 view + 深度 view）。
- 创建 `VkGraphicsPipeline` 时也需要传入 RenderPass，让 pipeline 知道它将运行在哪种附件配置上（`VK_DYNAMIC_RENDERING` 路径例外，可用 `VK_KHR_dynamic_rendering` 免除 RenderPass 约束）。

## 在渲染管线中的位置

`prepare()` 流程揭示了这个调用的上下游：

```cpp
createSurface();
createCommandPool();
createSwapChain();
createCommandBuffers();
createSynchronizationPrimitives();
setupDepthStencil();
setupRenderPass();      // ← 在此
createPipelineCache();
setupFrameBuffer();
```

RenderPass 依赖 `setupDepthStencil()` 确定的 `depthFormat` 和 swapchain 已确定的 `colorFormat`，先行于 Framebuffer 和 Pipeline 创建。所以 RenderPass 是"渲染目标资源"与"图形管线"之间的契约层。

## 一句话总结

创建 RenderPass 的本质是：用 **Attachment** 声明"渲染目标是什么样"，用 **AttachmentReference + Subpass** 声明"哪个绘制阶段怎么用它"，用 **SubpassDependency** 声明"阶段之间怎么同步和做布局转换"，最后把这三层信息汇总给 `vkCreateRenderPass` 得到一个不可变的对象，作为 Framebuffer 和 Pipeline 的共同依据。它关注"格式+布局+依赖"的静态契约，不涉及具体的 Image 内存或 Shader。