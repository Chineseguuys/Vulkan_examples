# Vulkan Cubemap Array 流程

基于 `texturecubemaparray` 示例，总结 `samplerCubeArray` 的使用流程，重点分析 `cubeMapIndex` 如何在 shader 中选择不同的 cubemap。

---

## 一、什么是 Cubemap Array

单个 Cubemap 包含 6 个面（+X/-X/+Y/-Y/+Z/-Z），用 `samplerCube` 采样时只需 `vec3` 方向向量，GPU 自动选 face。

Cubemap Array 是**多个 cubemap 放在一张 image 中**。采样时除了方向向量，还需要一个额外分量指定"第几个 cubemap"：

| 采样器类型 | 方向向量 | 说明 |
|-----------|---------|------|
| `samplerCube` | `vec3(x, y, z)` | 单 cubemap，方向选 face |
| `samplerCubeArray` | `vec4(x, y, z, layer)` | cubemap 数组，xyz 选 face，w 选层 |

---

## 二、VkImage 底层布局

一个 cubemap 占 6 层（6 个 face）。多个 cubemap 连续排列：

```166:166:examples/texturecubemaparray/texturecubemaparray.cpp
        imageCreateInfo.arrayLayers = 6 * cubeMapArray.layerCount;
```

ImageView 类型为 cubemap 数组：

```274:274:examples/texturecubemaparray/texturecubemaparray.cpp
        view.viewType = VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
```

底层数据布局：

```
VkImage (arrayLayers = 6 × N):

  Cubemap 0:  face0  face1  face2  face3  face4  face5    ← cubeMapIndex = 0
  Cubemap 1:  face0  face1  face2  face3  face4  face5    ← cubeMapIndex = 1
  Cubemap 2:  face0  face1  face2  face3  face4  face5    ← cubeMapIndex = 2
  ...
```

---

## 三、cubeMapIndex 详解

### UBO 定义

C++ 端：

```30:37:examples/texturecubemaparray/texturecubemaparray.cpp
    struct UniformData {
        glm::mat4 projection;
        glm::mat4 modelView;
        glm::mat4 inverseModelview;
        float lodBias = 0.0f;
        // Used by the fragment shader to select the cubemap from the array cubemap
        int cubeMapIndex = 1;
    } uniformData;
```

Shader 端（reflect.frag）：

```6:12:shaders/glsl/texturecubemaparray/reflect.frag
layout (binding = 0) uniform UBO
{
    mat4 projection;
    mat4 model;
    mat4 invModel;
    float lodBias;
    int cubeMapIndex;
} ubo;
```

### Shader 中的使用

**Skybox Fragment Shader**：

```18:18:shaders/glsl/texturecubemaparray/skybox.frag
    outFragColor = textureLod(samplerCubeMapArray, vec4(inUVW, ubo.cubeMapIndex), ubo.lodBias);
```

**Reflect Fragment Shader**：

```29:29:shaders/glsl/texturecubemaparray/reflect.frag
    vec4 color = textureLod(samplerCubeMapArray, vec4(cR, ubo.cubeMapIndex), ubo.lodBias);
```

`vec4(cR, cubeMapIndex)` 中：
- `cR.xyz`：反射方向，GPU 根据最大分量自动选择采样哪一个 face
- `w = cubeMapIndex`：选择数组中的第几个 cubemap（0 = 第一个，1 = 第二个，...）

### 为什么需要 w 分量

如果只有 `vec3` 方向，驱动无法区分"方向指向 cubemap 0 的 +Z 面"和"方向指向 cubemap 1 的 +Z 面"——两者的方向向量完全相同，但 face 内容不同。w 分量（cubemap 层索引）解除了这个歧义。

对比：

```
// 单 cubemap：方向即能唯一确定采样点
texture(samplerCube, vec3(0, 0, 1))  // 永远是唯一 cubemap 的 +Z 面

// cubemap 数组：方向 + 层索引 才唯一确定
texture(samplerCubeArray, vec4(0, 0, 1, 0))  // cubemap 0 的 +Z 面
texture(samplerCubeArray, vec4(0, 0, 1, 1))  // cubemap 1 的 +Z 面
texture(samplerCubeArray, vec4(0, 0, 1, 2))  // cubemap 2 的 +Z 面
```

---

## 四、运行时切换

C++ 端通过 ImGui 滑块让用户实时切换不同 cubemap：

```476:476:examples/texturecubemaparray/texturecubemaparray.cpp
            overlay->sliderInt("Cube map", &uniformData.cubeMapIndex, 0, cubeMapArray.layerCount - 1);
```

滑块范围 `[0, layerCount - 1]`，`cubeMapIndex` 通过 UBO 传入 shader。两个 shader（skybox 和 reflect）共用同一个 `cubeMapIndex`，保证天空盒和物体反射看到的是同一套环境。

---

## 五、完整数据流

```
C++ 侧：
  KTX 文件 × N → staging buffer
  → VkImage (arrayLayers = 6 × N, CUBE_COMPATIBLE_BIT)
  → VkImageView (type = VK_IMAGE_VIEW_TYPE_CUBE_ARRAY, layerCount = 6 × N)
  → VkSampler
  → UBO: cubeMapIndex (ImGui 可调)

Shader 侧（skybox）：
  Vertex: inPos → outUVW (XY翻转)
  Fragment: vec4(outUVW, cubeMapIndex) → textureLod(samplerCubeArray, ...)

Shader 侧（reflect）：
  Vertex: 传世界坐标/法线
  Fragment: reflect() + invModel + YZ翻转 → vec4(cR, cubeMapIndex) → textureLod(...)
  → Blinn-Phong 光照

ImGui 滑块：
  cubeMapIndex: 0 → cubemap 0 (layers 0~5)
  cubeMapIndex: 1 → cubemap 1 (layers 6~11)
  cubeMapIndex: 2 → cubemap 2 (layers 12~17)
  ...
```

每个 cubemap 包含 6 个 face，多个 cubemap 组成数组，运行时一个 `int` 切换整个环境。skybox 和 reflect shader 同步切换，视觉上天空盒和物体反射始终保持一致。