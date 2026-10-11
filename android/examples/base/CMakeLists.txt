file(GLOB BASE_SRC "../../../base/*.cpp" "../../../external/imgui/*.cpp")

add_library(libbase SHARED ${BASE_SRC})


option(BASE_ENABLE_PERFETTO "Enable Perfetto system tracing (PERFETTO_SYSTRACE_PRINT)" OFF)
if(BASE_ENABLE_PERFETTO)
    # perfetto.h 需要 C++17，PUBLIC 让所有包含 vulkanexamplebase.h 的目标一起生效
    target_compile_features(libbase PUBLIC cxx_std_17)
    target_include_directories(libbase PUBLIC ${EXTERNAL_DIR}/perfetto/sdk)
    target_compile_definitions(libbase PUBLIC PERFETTO_SYSTRACE_PRINT)

    # 对应桌面 xmake 里的 external_perfetto_sdk：SDK 实现必须编进来，否则链接失败
    add_library(external_perfetto STATIC ../../../external/perfetto/sdk/perfetto.cc)
    target_compile_features(external_perfetto PRIVATE cxx_std_17)
    target_include_directories(external_perfetto PRIVATE ${EXTERNAL_DIR}/perfetto/sdk)
    target_link_libraries(libbase external_perfetto)
endif()

# 注意：这里必须用 target_include_directories(libbase PUBLIC ...) 而不是目录级的
# include_directories()。include_directories() 只作用于当前目录（base）里定义的目标，
# 而示例的 native-lib 定义在 examples/<name>/ 目录下，只能通过链接 libbase 继承这些
# 头文件搜索路径。少了 PUBLIC 导出，示例代码 include "VulkanglTFModel.h" 就会找不到
# tiny_gltf.h 等第三方头文件。
target_include_directories(libbase PUBLIC
	${BASE_DIR}
	../../../external
	../../../external/glm
	../../../external/gli
	../../../external/imgui
	${EXTERNAL_DIR}/tinygltf
	# Khronos Vulkan-Headers: must be on the include path of every target so that the
	# NDK sysroot copy (VK_HEADER_VERSION 275) is shadowed, including for example sources
	${EXTERNAL_DIR}/Vulkan-Headers/include
	${EXTERNAL_DIR}/perfetto/sdk
	${EXTERNAL_DIR}/spdlog/include
	${ANDROID_NDK}/sources/android/native_app_glue
)

set(KTX_DIR ../../../external/ktx)
set(KTX_SOURCES
	${KTX_DIR}/lib/texture.c
	${KTX_DIR}/lib/hashlist.c
	${KTX_DIR}/lib/checkheader.c
	${KTX_DIR}/lib/swap.c
	${KTX_DIR}/lib/memstream.c
	${KTX_DIR}/lib/filestream.c
	${KTX_DIR}/lib/vkloader.c
)
set(KTX_INCLUDE
	${KTX_DIR}/include
	${KTX_DIR}/lib
	${KTX_DIR}/other_include
)

add_library(libktx ${KTX_SOURCES})
# ktxvulkan.h 是公开头文件并 include <vulkan/vulkan.h>，所以 Vulkan-Headers 也要 PUBLIC 传递
target_include_directories(libktx PUBLIC ${KTX_INCLUDE} ${EXTERNAL_DIR}/Vulkan-Headers/include)
set_property(TARGET libktx PROPERTY FOLDER "external")


target_link_libraries(
	libbase
	android
	log
	z
	libktx
)
