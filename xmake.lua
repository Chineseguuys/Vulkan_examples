-- prerequisites
-- add_requires("spdlog", {system = true})
set_project("vulkan-examples")
set_toolchains("gcc")

-- global definations
add_defines("VK_USE_PLATFORM_XCB_KHR")
-- add_defines("VK_USE_PLATFORM_WAYLAND_KHR")
add_defines("IMGUI_NEW_VERSION_FIX")

if is_mode("Debug") then
    set_symbols("debug")
    set_optimize("none")
    add_defines("DEBUG")
    set_strip("none")
    add_cxflags("-g")
    add_ldflags("-g")
end

includes("base")
includes("external")


target("example")
    set_kind("binary")
    add_files("examples/triangle/triangle.cpp")

    add_deps("base", "external_imgui", "external_ktx")
    add_links("vulkan", "xcb")
