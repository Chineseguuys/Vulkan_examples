#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include "perfetto.h"

extern "C" {
VKAPI_ATTR VkResult VKAPI_CALL vkCreateInstance(const VkInstanceCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator,
    VkInstance* pInstance) {
    TRACE_EVENT("rendering", "vkCreateInstance");

    VkLayerInstanceCreateInfo* chain_info = get_chain_info(pCreateInfo, VK_LAYER_LINK_INFO);
}
}