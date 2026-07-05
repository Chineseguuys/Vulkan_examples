#!/bin/bash
# 顶点着色器
slangc uioverlay.slang \
  -target spirv \
  -entry vertexMain \
  -stage vertex \
  -o uioverlay.vert.spv \
  -force-glsl-scalar-layout

# 片段着色器
slangc uioverlay.slang \
  -target spirv \
  -entry fragmentMain \
  -stage fragment \
  -o uioverlay.frag.spv \
  -force-glsl-scalar-layout