#！/bin/bash
dxc -spirv -T vs_6_0 -E main -Fo texture3d.vert.spv texture3d.vert
dxc -spirv -T ps_6_0 -E main -Fo texture3d.frag.spv texture3d.frag