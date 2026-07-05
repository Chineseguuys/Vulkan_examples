# Vulkan vkMapMemory / vkUnmapMemory

## API 功能

- **`vkMapMemory`**：将一块 GPU 已分配的显存（`VkDeviceMemory`）映射到 **CPU 虚拟地址空间**，返回一个 CPU 可以直接读写的 `void*` 指针。
- **`vkUnmapMemory`**：取消映射，释放 CPU 地址空间的映射关系。之后原来的 `void*` 指针失效，不能再访问。

## 项目中的封装

`vks::Buffer` 类中对这两个 API 做了薄封装：

```25:26:base/VulkanBUffer.cpp
    VkResult Buffer::map(VkDeviceSize size, VkDeviceSize offset)
    {
        return vkMapMemory(device, memory, offset, size, 0, &mapped);
    }
```

```35:39:base/VulkanBUffer.cpp
    void Buffer::unmap()
    {
        if (mapped)
        {
            vkUnmapMemory(device, memory);
            mapped = nullptr;
        }
    }
```

map 后 `this->mapped` 指向 GPU 内存的 CPU 可访问地址；unmap 后置 `nullptr`。

`vkMapMemory` 参数含义：
- `offset`：从内存块起始位置的字节偏移
- `size`：要映射的字节数，`VK_WHOLE_SIZE` 映射全部
- `flags`：保留参数，传 0
- `ppData`：输出参数，接收 CPU 虚拟地址指针

---

## 底层实际做了什么

### vkMapMemory 在不同硬件架构上的行为

**前置条件**：内存必须从带 `VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` 的类型中分配。`DEVICE_LOCAL` 内存通常不可 map。

**集成显卡（iGPU，如 Intel/AMD APU）**：
- 显存就是系统 RAM 的一部分，GPU 和 CPU 共享同一物理内存
- map 只是让驱动返回这块物理内存对应的 CPU 虚拟地址指针
- 几乎没有额外开销，指针读写就是直接的内存访问

**独立显卡（dGPU，如 NVIDIA/AMD 独显）**：
- VRAM 在显卡上，CPU 无法直接访问
- 驱动通过 PCIe BAR（Base Address Register）窗口机制，在 CPU 地址空间中划出一段窗口，映射到 VRAM 的指定区域
- CPU 的读写通过 PCIe 总线透明地路由到 GPU 显存
- BAR 窗口大小有限，`offset` 和 `size` 参数指定具体映射哪一段
- 返回的 `void*` 指针经过 PCIe 才能到达实际显存，延迟高于本地内存

### vkUnmapMemory 的实际操作

1. 撤销 CPU 地址空间的映射关系
2. 如果是一块 PCIe BAR 窗口被占用，unmap 后释放回窗口池供其他映射使用
3. `mapped = nullptr` 防止后续误用悬空指针

---

## Coherent vs Non-Coherent 内存

CPU 和 GPU 之间的数据可见性取决于内存类型：

```
HOST_VISIBLE | HOST_COHERENT:
  Map → CPU 写入 → 自动对 GPU 可见 → Unmap → 完成

HOST_VISIBLE (非 coherent):
  Map → CPU 写入(仍在CPU cache) → 必须 vkFlushMappedMemoryRanges → Unmap → GPU 可见

HOST_VISIBLE (非 coherent, GPU→CPU):
  Map → vkInvalidateMappedMemoryRanges → CPU 读取(拿到GPU最新数据) → Unmap

DEVICE_LOCAL (不可 map):
  vkMapMemory 直接失败 → 只能用 vkCmdCopyBuffer 中转
```

### flush 和 invalidate 的区别

- **flush**（CPU → GPU）：CPU 写完后调用，把 CPU cache 中的数据刷到 GPU 可见区域
- **invalidate**（GPU → CPU）：GPU 写完后，CPU 读取前调用，使 CPU cache 失效，强制从内存重新加载

项目中 `vks::Buffer` 也封装了这两个操作：

```91:96:base/VulkanBUffer.cpp
    VkResult Buffer::flush(VkDeviceSize size, VkDeviceSize offset)
    {
        VkMappedMemoryRange mappedRange{
            .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = memory,
            .offset = offset,
            .size = size
        };
        return vkFlushMappedMemoryRanges(device, 1, &mappedRange);
    }
```

```106:112:base/VulkanBUffer.cpp
    VkResult Buffer::invalidate(VkDeviceSize size, VkDeviceSize offset)
    {
        VkMappedMemoryRange mappedRange{
            .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = memory,
            .offset = offset,
            .size = size
        };
        return vkInvalidateMappedMemoryRanges(device, 1, &mappedRange);
    }
```

---

## 典型使用序列

```c
// 1. 分配 HOST_VISIBLE 内存
VkMemoryAllocateInfo allocInfo = { ... };
VkDeviceMemory memory;
vkAllocateMemory(device, &allocInfo, nullptr, &memory);

// 2. Map 获取 CPU 指针
void* data;
vkMapMemory(device, memory, 0, VK_WHOLE_SIZE, 0, &data);

// 3. 写入数据
memcpy(data, sourceData, dataSize);

// 4. 如果非 coherent → flush
if (!(memoryPropertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
    VkMappedMemoryRange range = {
        .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = memory,
        .offset = 0,
        .size = VK_WHOLE_SIZE
    };
    vkFlushMappedMemoryRanges(device, 1, &range);
}

// 5. Unmap（HOST_COHERENT 内存自动 flush）
vkUnmapMemory(device, memory);
```

## 一句话总结

`vkMapMemory` 把 GPU 内存"借"给 CPU 用，`vkUnmapMemory` "还"回去。对于 coherent 内存，写入直接对 GPU 可见；对于非 coherent 内存，需要手动 flush/invalidate 保证数据一致性。