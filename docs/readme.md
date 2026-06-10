# 参考
[Perfetto Tracing SDK](https://perfetto.dev/docs/instrumentation/tracing-sdk)

# Vulkan Layer 集成到系统中

用户目录下 vulkan layer 的配置目录位于 
```
/home/<user name>/.local/share/vulkan/implicit_layer.d/
```
将 `perfetto_layer_x86_64.json` 拷贝到该目录下。

在下一次启动 vulkan 应用时，vulkan 应用会自动加载该 layer。

# 调试方法

命令行中启用 vulkan layer 调试层：
```bash
export VK_INSTANCE_LAYERS=VK_LAYER_perfetto_layer
```

# 抓取方法

1. 启动 tracebox traced 服务

```bash
tracebox traced
```
没有异常的话，可以看到类似下面的输出：
```
[884.781]          service.cc:249 Started traced, listening on /tmp/perfetto-producer /tmp/perfetto-consumer
```

2. 启动 perfetto websocket 服务

```bash
tracebox websocket_bridge
```
没有异常的话，可以看到类似下面的输出：

```
[889.233]  websocket_bridge.cc:90 [WSBridge] adb server socket is:127.0.0.1:5037.
[889.233]       http_server.cc:67 [HTTP] Starting HTTP server on 127.0.0.1:8037
[889.233]       http_server.cc:78 [HTTP] Starting HTTP server on [::1]:8037
[889.233] websocket_bridge.cc:101 [WSBridge] Listening on 127.0.0.1:8037
```

3. 打开 perfetto dev 网站，配置抓取选项

[perfetto record](https://ui.perfetto.dev/#!/record)

在下面的 record 界面，点击刷新按钮：
![record 界面](./docs/images/perfetto_record_image_1.png)

在 websocket server 正常启动的情况下，会看到下面的结果：

![server 启动成功](./docs/images/perfetto_record_image_2.png)

其他的如下的配置项，可以自由更改：

![配置项](./docs/images/perfetto_record_image_3.png)

**重点在下面的步骤，切换到 Perfetto SDK 界面，打开 Trace events 抓取的开关，在 Additional categories 中填入 gpu 字段**

![trace_event抓取](./docs/images/perfetto_record_image_4.png)

在完成了所有的配置项之后，回到 Overview 界面，点击顶部的 start tracing 按钮开始抓取 trace event,抓取完毕之后，点击 Open 即可

![开始抓取](./docs/images/perfetto_record_image_5.png)

4. 查看trace内容

一切正常的话，应该可以看到 vulkan 的渲染线程中打印出来的 trace event 信息了

![trace信息](./docs/images/perfetto_record_image_6.png)