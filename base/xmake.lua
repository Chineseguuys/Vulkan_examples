-- prerequisites
-- do not use system installed, use which we built
-- add_requires("spdlog", {system = true})

set_project("base")
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

target("base")
    set_kind("static")
    add_files("./*.cpp")
    -- Do not need to use add_includedirs, use add_deps instead
    -- deps has been added in present xmake lua, so sub can use it directly
    add_deps("external_wayland-protocols", "external_imgui", "external_ktx", "external_spdlog", "external_tinygltf")
    add_includedirs("./", {public = true})
