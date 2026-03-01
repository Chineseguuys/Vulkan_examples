From [Vulkan C++ examples and demos](https://github.com/SaschaWillems/Vulkan)



# 问题处理

## xdg-shell-client-protocol.h 头文件找不到的问题

1,。 先安装 wayland-protocols

```bash
sudo pacman -S wayland-protocols
```

2. 生成头文件

```bash
wayland-scanner private-code < /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml > xdg-shell-protocol.c
wayland-scanner client-header < /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml > xdg-shell-client-protocol.h
```

> 参考 [Wayland Cmake generate fails when using Wayland_WSI](https://github.com/SaschaWillems/Vulkan/issues/567)

> 参考 [wayland scanner](https://wayland-book.com/libwayland/wayland-scanner.html)
