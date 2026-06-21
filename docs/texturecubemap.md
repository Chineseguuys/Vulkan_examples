# Vulkan Cubemap 天空盒完整流程

基于 `texturecubemap` 示例，总结从 C++ 端加载 cubemap 纹理到 Shader 端渲染天空盒 + 环境反射的完整流程。

示例使用两套 shader：
- `skybox`：渲染天空盒背景立方体
- `reflect`：渲染带环境反射的物体（球、茶壶等）

---

## 一、C++ 代码侧

### 1. 加载 KTX Cubemap 文件

与普通纹理加载相同，KTX 格式内建了 6 个 face 及 mipmap。

### 2. 创建 VkImage —— 两个致命参数

```161:164:examples/texturecubemap/texturecubemap.cpp
        // Cube faces count as array layers in Vulkan
        imageCreateInfo.arrayLayers = 6;
        // This flag is required for cube map images
        imageCreateInfo.flags = VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `arrayLayers` | `6` | 立方体 6 个面，硬性要求 |
| `flags` | `VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT` | 必须设置，否则后续无法创建 `VK_IMAGE_VIEW_TYPE_CUBE` 视图 |
| `imageType` | `VK_IMAGE_TYPE_2D` | 底层仍是 2D 纹理 |
| `mipLevels` | `cubeMap.mipLevels` | 从 KTX 文件获取 |
| `usage` | `TRANSFER_DST \| SAMPLED` | 常用组合 |
| `tiling` | `VK_IMAGE_TILING_OPTIMAL` | 最优布局 |

### 3. 上传每个 face 和 mip level

双层循环：外层遍历 6 个 face，内层遍历 mip level。用 `ktxTexture_GetImageOffset` 的 `face` 参数定位数据：

```190:203:examples/texturecubemap/texturecubemap.cpp
        for (uint32_t face = 0; face < 6; face++)
        {
            for (uint32_t level = 0; level < cubeMap.mipLevels; level++)
            {
                ktx_size_t offset;
                KTX_error_code ret = ktxTexture_GetImageOffset(ktxTexture, level, 0, face, &offset);
                ...
                bufferCopyRegion.imageSubresource.baseArrayLayer = face;
                bufferCopyRegion.imageSubresource.mipLevel = level;
                ...
            }
        }
```

`baseArrayLayer = face` 将 KTX face 映射到 VkImage 的 array layer。Face 顺序：+X, -X, +Y, -Y, +Z, -Z。

### 4. Image Layout 转换

subresourceRange 必须覆盖全部 6 层和全部 mip：

```207:210:examples/texturecubemap/texturecubemap.cpp
        subresourceRange.layerCount = 6;
```

两次 layout 转换：`UNDEFINED → TRANSFER_DST_OPTIMAL → SHADER_READ_ONLY_OPTIMAL`。

### 5. 创建 Sampler

天空盒通常用 `CLAMP_TO_EDGE` 避免面接缝处出现边缘色带。各向异性过滤可用于改善倾斜角度的采样质量。

### 6. 创建 ImageView —— 类型必须是 CUBE

```263:263:examples/texturecubemap/texturecubemap.cpp
        view.viewType = VK_IMAGE_VIEW_TYPE_CUBE;
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `viewType` | `VK_IMAGE_VIEW_TYPE_CUBE` | cubemap 专用，不是 `2D_ARRAY` |
| `layerCount` | `6` | 全部 6 个面 |
| `levelCount` | `cubeMap.mipLevels` | 全部 mip 级别 |

### 7. Descriptor Set

与普通纹理相同，`VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`，但需要注意 UBO 同时对 vertex 和 fragment shader 可见：

```307:311:examples/texturecubemap/texturecubemap.cpp
            // Binding 0 : Vertex shader uniform buffer
            vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0),
            // Binding 1 : Fragment shader image sampler
            vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT, 1)
```

### 8. 两个 Pipeline 的设置差异

| 设置 | Skybox Pipeline | Reflect Pipeline |
|------|-----------------|------------------|
| Cull Mode | `VK_CULL_MODE_FRONT_BIT` | `VK_CULL_MODE_BACK_BIT` |
| Depth Test | `VK_FALSE` | `VK_TRUE` |
| Depth Write | `VK_FALSE` | `VK_TRUE` |

Skybox 剔除正面（相机在立方体内部看的是背面），关闭深度写入确保天空盒永远在最远。

---

## 二、Shader 设计

### Skybox Shader（天空盒背景）

#### Vertex Shader

```14:18:shaders/glsl/texturecubemap/skybox.vert
    outUVW = inPos;
    // Convert cubemap coordinates into Vulkan coordinate space
    outUVW.xy *= -1.0;
    // Remove translation from view matrix
    mat4 viewMat = mat4(mat3(ubo.model));
    gl_Position = ubo.projection * viewMat * vec4(inPos.xyz, 1.0);
```

两个关键操作：

1. **剥离 view 矩阵的平移分量**（`mat4(mat3(ubo.model))`）：只保留旋转，去掉位移。天空盒应"无限远"，相机移动时它不跟着动
2. **XY 翻转**（`outUVW.xy *= -1.0`）：GLSL cubemap 坐标系的 +X/+Y 方向与 Vulkan 图像数据布局不同（Vulkan Y 轴向下），需翻转以正确对位

天空盒的顶点坐标 `inPos` 就是一个单位立方体，这个立方体坐标本身也是 cubemap 采样的方向向量。

#### Fragment Shader

```8:10:shaders/glsl/texturecubemap/skybox.frag
    outFragColor = texture(samplerCubeMap, inUVW);
```

`texture(samplerCube, vec3)` 用 3D 方向向量采样，GPU 根据哪个分量最大自动选择对应的 face。

---

### Reflect Shader（环境反射物体）—— 光线反射详解

这个 shader 实现的是**环境贴图反射（Environment Mapping）**：物体表面像镜子一样反射周围环境（天空盒），同时叠加局部 Blinn-Phong 光照。

#### Vertex Shader：空间变换与向量传递

**裁剪空间投影**

```22:22:shaders/glsl/texturecubemap/reflect.vert
    gl_Position = ubo.projection * ubo.model * vec4(inPos.xyz, 1.0);
```

标准 MVP 变换（此处 `model = camera.matrices.view`，camera 无世界位移仅旋转观察方向）。

**世界空间位置和法线**

```24:25:shaders/glsl/texturecubemap/reflect.vert
    outPos = vec3(ubo.model * vec4(inPos, 1.0));
    outNormal = mat3(ubo.model) * inNormal;
```

- `outPos`：视图/世界空间中的顶点位置（相机在原点）
- `outNormal`：`mat3(model)` 只取旋转部分变换法线。此处 model 矩阵无可缩放，`mat3` 等价于 `inverse(transpose(model))`

**光源方向和视线方向**

```27:28:shaders/glsl/texturecubemap/reflect.vert
    vec3 lightPos = vec3(0.0f, -5.0f, 5.0f);
    outLightVec = lightPos.xyz - outPos.xyz;
    outViewVec = -outPos.xyz;
```

- `outLightVec`：表面点指向硬编码光源 `(0, -5, 5)` 的方向
- `outViewVec`：表面点指向相机的方向。相机在世界原点 `(0,0,0)`，所以 `viewDir = cameraPos - outPos = -outPos`

---

#### Fragment Shader：两步计算

#### 第一步：Cubemap 环境反射采样

**1. 计算反射向量**

```24:25:shaders/glsl/texturecubemap/reflect.frag
    vec3 cI = normalize (inPos);
    vec3 cR = reflect(cI, normalize(inNormal));
```

- `cI = normalize(inPos)`：世界空间顶点位置归一化即从相机指向顶点的视线方向（相机在原点）
- `cR = reflect(cI, normal)`：GLSL 内建 `reflect(I, N) = I - 2 * dot(N, I) * N`，视线关于法线的反射方向

物理含义：相机 → 物体表面 → 反射 → 击中天空盒上某一点 → 该点颜色即为物体反射颜色。

```
         天空盒（无限远）
        ┌──────────────┐
        │    ★         │  ← 反射向量 cR 指向这里
        │   ╱          │
        │  ╱           │
        │ ╱            │
  相机 ●──────────→●    │  物体表面
        cI         ╲   │
                    ╲  │
                     ╲ │
                   法线 N
```

**2. 反射向量坐标空间变换**

```27:28:shaders/glsl/texturecubemap/reflect.frag
    cR = vec3(ubo.invModel * vec4(cR, 0.0));
    cR.xy *= -1.0;
```

`invModel` 变换的原因：cubemap 的 6 个面固定不变（相对于环境世界）。反射向量 `cR` 在世界空间中算出，但物体可能旋转过——旋转后物体的"正面"不再对应 cubemap 的 +Z 面。必须把反射向量从世界空间转回**模型本地空间**：`cR_local = invModel * cR_world`。

`vec4(cR, 0.0)` 的 `w=0` 是方向标志，平移分量被忽略，只应用旋转。

`cR.xy *= -1.0`：Vulkan 图像数据的 Y 轴向下，而 GLSL cubemap 采样的 Y 轴向上，需翻转匹配。

**3. 采样 cubemap**

```30:30:shaders/glsl/texturecubemap/reflect.frag
    vec4 color = texture(samplerColor, cR, ubo.lodBias);
```

`texture(samplerCube, dir, bias)`：GPU 根据 `dir` 三分量中绝对值最大者决定采哪个 face，用另外两个分量做 UV。`lodBias` 对 LOD 加偏移 → 值越大纹理越模糊 → 模拟粗糙表面。

---

#### 第二步：Blinn-Phong 局部光照

在环境反射基色上叠加局部光源的漫反射和高光：

**环境光**

```32:33:shaders/glsl/texturecubemap/reflect.frag
    vec3 ambient = vec3(0.5) * color.rgb;
```

cubemap 颜色 × 0.5，提供恒定的基础亮度。

**漫反射（Lambert）**

```33:34:shaders/glsl/texturecubemap/reflect.frag
    vec3 diffuse = max(dot(N, L), 0.0) * vec3(1.0);
```

`max(dot(normal, lightDir), 0)`：法线与光源方向夹角越小（越正对光源），漫反射越亮。`× vec3(1.0)` 表示光源颜色为白色。

**镜面高光（Phong）**

```35:35:shaders/glsl/texturecubemap/reflect.frag
    vec3 specular = pow(max(dot(R, V), 0.0), 16.0) * vec3(0.5);
```

- `R = reflect(-L, N)`：光源方向关于法线的反射
- 视线 `V` 与反射方向 `R` 越接近 → `dot(R, V)` 越大 → 高光越亮
- 指数 `16.0` 控制高光集中度，值越大光斑越小
- `× 0.5` 控制高光强度

**合成**

```36:36:shaders/glsl/texturecubemap/reflect.frag
    outFragColor = vec4(ambient + diffuse * color.rgb + specular, 1.0);
```

最终颜色 = 环境 + 漫反射 × cubemap 颜色 + 高光。漫反射乘 `color.rgb` 表示物体表面"本色"由 cubemap 决定。

---

#### 坐标系变换总结

```
模型本地坐标 (vertex buffer inPos, inNormal)
    │
    │ ubo.model (= camera.matrices.view)
    ▼
世界/视图空间 (outPos, outNormal)
    │
    │ normalize(inPos) → 视线 cI
    │ reflect(cI, normal) → 反射向量 cR (世界空间)
    │
    │ ubo.invModel (= inverse(view))
    ▼
模型本地空间 (cR_local)
    │
    │ cR.xy *= -1.0  (Vulkan Y轴适配)
    ▼
Cubemap 采样空间
    │
    │ texture(samplerCube, cR, lodBias)
    ▼
cubemap 基色 → Blinn-Phong 光照 → 最终像素

---

## 三、整体数据流

```
C++ 侧：
  KTX 文件 → staging buffer
  → VkImage (arrayLayers=6, CUBE_COMPATIBLE_BIT)
  → 每 face × 每 mip 设置 VkBufferImageCopy
  → layout 转换
  → VkImageView (type=VK_IMAGE_VIEW_TYPE_CUBE)
  → VkSampler (CLAMP_TO_EDGE)
  → Descriptor Set (COMBINED_IMAGE_SAMPLER, binding 1)

Shader 侧（skybox）：
  Vertex: inPos 即是 cubemap 方向 → 剥离平移 + XY 翻转
  Fragment: texture(samplerCube, uvw)

Shader 侧（reflect）：
  Vertex: 传世界坐标/法线/视线
  Fragment: reflect() + invModel变换 + XY翻转 + lodBias
  → texture(samplerCube, direction, lodBias)
  → Blinn-Phong 光照
```

## 四、关键注意事项

1. **`VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT` 必须设置**，否则 `VK_IMAGE_VIEW_TYPE_CUBE` 视图创建会失败
2. **`arrayLayers` 必须是 6**，这是硬件层面的硬性要求。Cubemap 在 Vulkan 底层仍是 2D array image
3. **ImageView 类型区别**：单个 cubemap 用 `VK_IMAGE_VIEW_TYPE_CUBE`；cubemap 数组用 `VK_IMAGE_VIEW_TYPE_CUBE_ARRAY`。如果错误用了 `VK_IMAGE_VIEW_TYPE_2D_ARRAY`，shader 中 `samplerCube` 无法工作
4. **Skybox 的 view 矩阵必须剥离平移**，否则天空盒会跟随相机移动
5. **XY 翻转**是 Vulkan 特有的：GLSL 的 Y 轴向上，Vulkan 图像数据的 Y 轴向下，cubemap 采样时必须翻转以匹配
6. **Reflect 的反射向量需要经 `invModel` 从世界空间转回模型本地空间**，因为 cubemap 的颜色代表环境对本地坐标系的贡献