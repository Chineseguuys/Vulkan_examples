#!/bin/bash
# 顶点着色器
slangc texture3d.slang \
  -target spirv \
  -entry vertexMain \
  -stage vertex \
  -o texture3d.vert.spv \
  -force-glsl-scalar-layout

# 片段着色器
slangc texture3d.slang \
  -target spirv \
  -entry fragmentMain \
  -stage fragment \
  -o texture3d.frag.spv \
  -force-glsl-scalar-layout