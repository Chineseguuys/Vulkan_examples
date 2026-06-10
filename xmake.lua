-- prerequisites
-- add_requires("spdlog", {system = true})
set_project("vulkan-examples")
set_toolchains("gcc")

-- control the window system to use
-- use wayland, it can not be captured by renderdoc
-- renderdoc does not support wayland yet
local use_wayland = false 
-- use xcb, it can be captured by renderdoc
local use_xcb = true 

-- global definations
if use_xcb then
    add_defines("VK_USE_PLATFORM_XCB_KHR")
end
if use_wayland then
    add_defines("VK_USE_PLATFORM_WAYLAND_KHR")
end
add_defines("IMGUI_NEW_VERSION_FIX")
add_defines("YJH_STABILITY_FIX")

-- perfetto systrace print
add_defines("PERFETTO_SYSTRACE_PRINT")

if is_mode("Debug") then
    set_symbols("debug")
    set_optimize("none")
    add_defines("DEBUG")
    set_strip("none")
    add_cxflags("-g")
    add_ldflags("-g")
end

includes("external")
includes("base")


target("example")
    set_kind("binary")
    add_files("examples/texture/texture.cpp")

    add_deps("base", "external_imgui", "external_ktx", "external_wayland-protocols", "external_perfetto_sdk")
    if use_xcb then
        -- if use xcb, you need to link xcb
        add_links("vulkan", "xcb")
    end
    if use_wayland then
        -- if use wayland, you need to link wayland-client
        add_links("vulkan", "wayland-client")
    end
