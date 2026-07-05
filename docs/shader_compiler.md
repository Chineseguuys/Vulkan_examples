# Shader 编译器参考

## GLSL

### 来源与发展

**GLSL**（OpenGL Shading Language）是 Khronos Group 为 OpenGL 设计的着色语言，首次随 OpenGL 2.0（2004 年）发布。2016 年 Vulkan 发布后，GLSL 版本演进为 `#version 450` 及更高版本，直接对应 SPIR-V 规格。

| 时期 | 里程碑 |
|------|--------|
| 2004 | GLSL 1.10 随 OpenGL 2.0 发布 |
| 2012 | GLSL 4.50 对应 OpenGL 4.5 |
| 2016 | Vulkan 采用 GLSL 作为标准着色语言，编译为 SPIR-V |
| 2020+ | 通过 `GL_EXT_debug_printf` 等扩展持续增强调试能力 |

在 Vulkan 生态中，GLSL 仍是使用最广泛的着色语言，直接映射 GPU 管线模型，配合编译器产生 SPIR-V。常用的 GLSL 编译器有两个——**glslc**（Google shaderc，Vulkan SDK 推荐）和 **glslangValidator**（Khronos 参考编译器）。两者底层都基于 glslang，主要区别在于命令行接口。

### 编译命令

#### glslc（推荐）

`glslc` 是 Google shaderc 项目提供的编译器，采用类 GCC/Clang 的命令行风格，被 Vulkan SDK 官方收录。

```bash
# 顶点着色器（.vert → .vert.spv）
glslc -fshader-stage=vert shader.vert -o shader.vert.spv

# 片段着色器（.frag → .frag.spv）
glslc -fshader-stage=frag shader.frag -o shader.frag.spv

# 计算着色器（.comp → .comp.spv）
glslc -fshader-stage=comp shader.comp -o shader.comp.spv
```

| 参数 | 含义 |
|------|------|
| `-fshader-stage=<stage>` | 指定 shader 阶段：vert / frag / comp / geom / tesc / tese / mesh / task 等 |
| `-o <file>` | 输出文件路径 |
| `-g` | 生成调试信息（GCC 风格，等价 `-gline-tables-only`） |
| `-O` | 优化生成的 SPIR-V（调用 spirv-opt） |
| `-O0` | 不优化（默认） |
| `-MD` / `-MF <file>` | 生成依赖文件（`.d`），适合 Makefile 集成 |
| `-DSYMBOL=VALUE` | 定义预处理器宏，支持 `-D` 多次指定 |
| `-I<dir>` | 添加 include 搜索路径 |
| `-Werror` | 将警告视为错误 |
| `--target-env=vulkan1.3` | 指定目标 Vulkan 环境 |

#### glslangValidator

`glslangValidator` 是 Khronos glslang 项目的独立编译器，使用自有的命令行风格。

```bash
# 顶点着色器（.vert → .vert.spv）
glslangValidator -V shader.vert -o shader.vert.spv

# 片段着色器（.frag → .frag.spv）
glslangValidator -V shader.frag -o shader.frag.spv

# 计算着色器（.comp → .comp.spv）
glslangValidator -V shader.comp -o shader.comp.spv
```

| 参数 | 含义 |
|------|------|
| `-V` | 生成 Vulkan 兼容的 SPIR-V（必需） |
| `-o <file>` | 输出文件路径 |
| `-S <stage>` | 手动指定 shader stage（vert / frag / comp 等），省略时根据文件扩展名推断 |
| `-g` | 生成调试信息（带 `OpLine` / `OpSource`） |
| `-Os` | 优化生成的 SPIR-V |
| `-D<name>` / `-D<name>=<value>` | 定义预处理器宏 |
| `-I<dir>` | 添加 include 搜索路径 |

### 安装编译器

**glslc（shaderc）**

```bash
# Arch / Manjaro
sudo pacman -S shaderc

# Ubuntu / Debian
sudo apt install glslc

# 随 Vulkan SDK 安装（所有平台）
# Vulkan SDK 默认包含 glslc：
# https://vulkan.lunarg.com/sdk/home

# 源码编译
git clone https://github.com/google/shaderc.git
cd shaderc && ./utils/git-sync-deps
cmake -B build && cmake --build build --target install
```

**glslangValidator**

```bash
# Arch / Manjaro
sudo pacman -S glslang

# Ubuntu / Debian
sudo apt install glslang-tools

# 源码编译
git clone https://github.com/KhronosGroup/glslang.git
cd glslang && cmake -B build && cmake --build build --target install
```

---

## HLSL

### 来源与发展

**HLSL**（High-Level Shader Language）由 Microsoft 与 NVIDIA 合作开发，随 Direct3D 9（2002 年）首次发布。2016 年，微软开源了 **DXC**（DirectX Shader Compiler），将 HLSL 编译目标从 DXIL 扩展到 SPIR-V，使 HLSL 成为 Vulkan/D3D12 跨平台的着色语言。

| 时期 | 里程碑 |
|------|--------|
| 2002 | HLSL 随 Direct3D 9 首次发布（SM 1.0） |
| 2009 | Shader Model 5.0（Direct3D 11），引入 compute shader |
| 2016 | DXC 开源，支持 HLSL → SPIR-V 编译 |
| 2021+ | Shader Model 6.6+，支持 Wave Intrinsics、mesh shader 等 |

在 Vulkan 中使用 HLSL 时，通过 `[[vk::location(N)]]`、`[[vk::binding(N)]]` 等属性将 HLSL 语法映射到 Vulkan 的资源模型。

### 编译命令

```bash
# 顶点着色器（.vert → .vert.spv）
dxc -spirv -T vs_6_0 -E main -Fo shader.vert.spv shader.vert

# 像素/片段着色器（.frag → .frag.spv）
dxc -spirv -T ps_6_0 -E main -Fo shader.frag.spv shader.frag

# 计算着色器（.comp → .comp.spv）
dxc -spirv -T cs_6_0 -E main -Fo shader.comp.spv shader.comp
```

#### Shader Profile 映射

| `-T` 参数 | Vulkan Stage |
|-----------|-------------|
| `vs_6_0` | `VK_SHADER_STAGE_VERTEX_BIT` |
| `ps_6_0` | `VK_SHADER_STAGE_FRAGMENT_BIT` |
| `cs_6_0` | `VK_SHADER_STAGE_COMPUTE_BIT` |
| `gs_6_0` | `VK_SHADER_STAGE_GEOMETRY_BIT` |
| `ms_6_0` | `VK_SHADER_STAGE_MESH_BIT_EXT` |
| `as_6_0` | `VK_SHADER_STAGE_TASK_BIT_EXT` |

#### 常用参数

| 参数 | 含义 |
|------|------|
| `-spirv` | 输出 SPIR-V（Vulkan 目标） |
| `-T <profile>` | Shader profile（见上表） |
| `-E <name>` | 入口函数名（HLSL 不强制 `main`，需显式指定） |
| `-Fo <file>` | 输出文件路径 |
| `-Zi` | 生成调试信息 |
| `-O0` / `-O3` | 优化等级 |
| `-fspv-target-env=vulkan1.3` | 指定目标 Vulkan 版本 |

#### 安装编译器

```bash
# Arch / Manjaro
sudo pacman -S dxc

# Ubuntu 22.04+
sudo apt install dxc

# 从 GitHub 获取预编译二进制
# https://github.com/microsoft/DirectXShaderCompiler/releases

# 源码编译
git clone https://github.com/microsoft/DirectXShaderCompiler.git
cd DirectXShaderCompiler
cmake -B build -C cmake/caches/PredefinedParams.cmake
cmake --build build --target install
```

---

## Slang

### 来源与发展

**Slang**（Shader Language）由 NVIDIA 研究院于 2017 年首次发布，2022 年以 [shader-slang/slang](https://github.com/shader-slang/slang) 独立开源。它是 HLSL 的超集，在完全兼容 HLSL 语法的前提下，引入现代编程语言特性：

| 特性 | 说明 |
|------|------|
| 泛型与接口 | 类似 C++ template / Rust trait 的参数化多态 |
| 模块系统 | `import` 语句、多文件组合编译 |
| 联合入口模型 | 一个 `.slang` 文件同时包含 vertex + fragment，通过 `[shader("vertex")]` / `[shader("fragment")]` 标记 |
| 自动微分 | 原生支持前向/反向自动微分（用于 ML/微分渲染） |
| 参数化微分 | `[Differentiable]` 标记，编译时生成梯度传递代码 |

| 时期 | 里程碑 |
|------|--------|
| 2017 | NVIDIA 发布 Slang 论文及初始版本 |
| 2022 | 完全独立开源，移出 NVIDIA 仓库，建立 shader-slang 组织 |
| 2023+ | 广泛支持 Vulkan / D3D12 / Metal / CUDA / OptiX 后端 |
| 2024+ | 增强模块系统、自动微分、调试工具（slangd LSP server） |

Slang 的突出优势在于 **"一次编写，多后端输出"** —— 同一份 `.slang` 源码可编译为 SPIR-V、DXIL、Metal IR、PTX、CUDA，适合需要跨图形 API 部署的项目。

### 编译命令

Slang 的一个 `.slang` 文件包含多个入口（vertex + fragment），编译时分别指定入口函数和 stage：

```bash
# 顶点着色器（vertexMain 入口 → .vert.spv）
slangc shader.slang \
  -target spirv \
  -entry vertexMain \
  -stage vertex \
  -o shader.vert.spv \
  -force-glsl-scalar-layout

# 片段着色器（fragmentMain 入口 → .frag.spv）
slangc shader.slang \
  -target spirv \
  -entry fragmentMain \
  -stage fragment \
  -o shader.frag.spv \
  -force-glsl-scalar-layout

# 计算着色器（computeMain 入口 → .comp.spv）
slangc shader.slang \
  -target spirv \
  -entry computeMain \
  -stage compute \
  -o shader.comp.spv \
  -force-glsl-scalar-layout
```

#### 常用参数

| 参数 | 含义 |
|------|------|
| `-target spirv` | 输出 SPIR-V（也可选 dxil / metal / ptx / cuda） |
| `-entry <name>` | 入口函数名（对应 `[shader("...")]` 标记的函数） |
| `-stage <stage>` | 管线阶段：vertex / fragment / compute / mesh / task 等 |
| `-o <file>` | 输出文件路径 |
| `-force-glsl-scalar-layout` | 强制 GLSL 标量布局（Vulkan UBO 兼容性关键参数） |
| `-g` | 生成调试信息 |
| `-O<0\|1\|2\|3>` | 优化等级 |
| `-matrix-layout-row-major` | 矩阵行主序布局 |
| `-matrix-layout-column-major` | 矩阵列主序布局（默认） |
| `-profile <level>` | 对应 HLSL profile（如 `glsl_450` / `sm_6_0`） |
| `-output-includes` / `-output-deps` | 输出头文件依赖信息 |

#### Vulkan 运行时要求

Slang 生成的 SPIR-V 使用 **SPIR-V 1.4+ 特性**，需要：

- Vulkan API 版本 ≥ 1.1
- `VK_KHR_spirv_1_4` 设备扩展
- `VK_KHR_shader_float_controls` 设备扩展
- `VK_KHR_shader_draw_parameters` 设备扩展

#### 安装编译器

```bash
# Arch / Manjaro（AUR）
yay -S slang

# 从 GitHub 获取预编译二进制
# https://github.com/shader-slang/slang/releases
# 解压后包含 slangc（编译器）、slangd（LSP 服务）、slang-reflection（反射工具）

# 源码编译
git clone https://github.com/shader-slang/slang.git
cd slang
cmake --preset default
cmake --build --preset release
```

---

## 语法速查对比

以 `texture3d` 着色器为例，三种语言的核心差异点：

| 特性 | GLSL | HLSL | Slang |
|------|------|------|-------|
| **版本声明** | `#version 450` | 无（通过 `-T` 指定 profile） | 无 |
| **入口函数** | `void main()`（固定名） | 任意名（用 `-E` 指定） | 任意名 + `[shader("vertex")]` 标注 |
| **顶点输入** | `layout(location=0) in vec3 inPos;` | struct + `[[vk::location(0)]]` | struct + 自动推导 |
| **Uniform** | `layout(binding=0) uniform UBO { … }` | `cbuffer ubo : register(b0) { … }` | `ConstantBuffer<UBO> ubo;` |
| **采样** | `texture(sampler3D, uv)` | `texture.Sample(sampler, uv)` | 同 HLSL |
| **纹理声明** | 采样器组合型：`uniform sampler3D` | `Texture3D` + `SamplerState` 分离 | `Sampler3D`（自动推导类型） |
| **文件结构** | 单个入口单文件（.vert / .frag 分离） | 单个入口单文件（.vert / .frag 分离） | 多入口单文件（.slang） |
| **编译器** | `glslangValidator` | `dxc` | `slangc` |
| **输出** | SPIR-V | SPIR-V / DXIL | SPIR-V / DXIL / Metal IR / PTX / CUDA |

---

## 项目中的运行时使用

本项目的 `VulkanExampleBase` 通过 `--shaders` 命令行参数在三种 shader 格式间切换：

```bash
# GLSL（默认）
./example --shaders glsl

# HLSL
./example --shaders hlsl

# Slang
./example --shaders slang
```

三种 shader 的源文件目录结构：

```
shaders/
├── glsl/
│   ├── texture3d/
│   │   ├── texture3d.vert          # GLSL 顶点着色器源文件
│   │   ├── texture3d.frag          # GLSL 片段着色器源文件
│   │   ├── texture3d.vert.spv      # 编译产物
│   │   └── texture3d.frag.spv      # 编译产物
│   └── base/
│       └── uioverlay.*.spv
├── hlsl/
│   ├── texture3d/
│   │   ├── texture3d.vert          # HLSL 顶点着色器源文件
│   │   ├── texture3d.frag          # HLSL 片段着色器源文件
│   │   └── dxc_compile.sh          # 编译脚本
│   └── ...
└── slang/
    ├── texture3d/
    │   ├── texture3d.slang         # Slang 联合源文件（含 vertex + fragment）
    │   └── slang_compiler.sh       # 编译脚本
    └── base/
        └── uioverlay.slang
```

无论源语言是哪种，最终都生成同名 `.spv` 文件，由 `VulkanExampleBase::loadShader()` 统一加载——Vulkan 驱动只认 SPIR-V，不关心源语言。