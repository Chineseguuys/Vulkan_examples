-- prerequisites
-- add_requires("spdlog", {system = true})
set_project("vulkan-examples")
set_toolchains("gcc")

-- global definations

if is_mode("Debug") then
    set_symbols("debug")
    set_optimize("none")
    add_defines("DEBUG")
    set_strip("none")
    add_cxflags("-g")
    add_ldflags("-g")
end

target("external_imgui")
    set_kind("static")
    add_files("imgui/imgui_draw.cpp")
    add_files("imgui/imgui_tables.cpp")
    add_files("imgui/imgui_widgets.cpp")
    add_files("imgui/imgui.cpp")

    add_files("imgui/backends/imgui_impl_vulkan.cpp")

    add_includedirs("imgui", {public = true})
    add_includedirs("imgui/backends", {public = true})

target("external_ktx")
    set_kind("static")
    add_files("ktx/lib/*.c")

    add_defines("KTX_OPENGL")

    add_includedirs("ktx/include/", {public = true})

target("external_spdlog")
    set_kind("static")
    add_includedirs("spdlog/include/", {public = true})

target("external_wayland-protocols")
    set_kind("static")
    add_files("wayland-protocols/xdg-shell-protocol.c")
    add_includedirs("wayland-protocols/", {public = true})

target("external_tinygltf")
    set_kind("headeronly")
    add_includedirs("tinygltf/", {public = true})