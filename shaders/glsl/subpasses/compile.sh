#!/bin/bash

for file in *.vert *.frag; do
    echo "Compiling $file"
    glslc -o $file.spv $file
    echo "    Generated $file.spv"
done