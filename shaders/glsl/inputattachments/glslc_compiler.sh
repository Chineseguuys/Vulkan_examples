#!/bin/bash
glslc attachmentwrite.vert -o attachmentwrite.vert.spv
glslc attachmentwrite.frag -o attachmentwrite.frag.spv
glslc attachmentread.vert -o attachmentread.vert.spv
glslc attachmentread.frag -o attachmentread.frag.spv