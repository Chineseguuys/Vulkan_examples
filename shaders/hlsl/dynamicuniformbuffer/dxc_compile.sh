#！/bin/bash
dxc -spirv -T vs_6_0 -E main -Fo base.vert.spv base.vert
dxc -spirv -T ps_6_0 -E main -Fo base.frag.spv base.frag