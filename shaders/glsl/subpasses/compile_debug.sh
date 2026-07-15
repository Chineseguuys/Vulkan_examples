#!/bin/bash

for file in *.vert *.frag; do
    echo "Compiling $file"
    # if you want to see the raw shader code in Renderdoc or
    # other debug tools, you can use the -g flag to output the raw shader code.
    glslangValidator -V -gVS $file -o $file.spv
    echo "    Generated $file.spv"
done