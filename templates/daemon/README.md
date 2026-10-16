# 构建守护进程 · 使用说明

把 AI 助手的构建搬出它的进程树——这是「构建僵死」的**根治方案**，不是权宜之计。

## 为什么需要它

参见主文第 4 节与 [`../../docs/01-build-hang-postmortem.md`](../../docs/01-build-hang-postmortem.md)。

一句话：**只要构建的祖先进程是 AI 助手，编译进程就可能被它的子进程管控层挂起。**
把构建交给我们自己的常驻进程，问题消失。

## 文件清单

| 文件 | 作用 |
|---|---|
| `build-daemon.cmd` | 常驻守护进程：轮询 `build.request`，收到即构建，结果写 `build.status` |
| `build-daemon-hidden.vbs` | 以**隐藏窗口**拉起守护进程 |
| `build-daemon-autostart.vbs` | 开机自启垫片（清残锁 → 拉起） |
| `install-build-daemon.cmd` | **一次性安装器**：停旧实例 → 清锁 → 装自启 → 立即启动 |
| `build-quiet.cmd` | 实际构建脚本：设环境变量 → reconfigure → 经 `run_ninja.py` 跑 ninja |
| `run_ninja.py` | **关键**：以 `stdin=DEVNULL` 拉起 ninja，规避隐藏控制台的 stdin 继承坑 |

## 安装步骤

```
1. 把 daemon/ 里所有文件拷到你的 ESP-IDF 工程根目录
   （run_ninja.py 需要放到 tools/ 下，或按需改 build-quiet.cmd 里的路径）

2. 用编辑器全局替换所有文件中的 __PLACEHOLDER__：
   __PROJECT_DIR__      你的工程绝对路径
   __IDF_PATH__         ESP-IDF 根目录（如 D:\Espressif\v6.0.1\esp-idf）
   __IDF_TOOLS_PATH__   工具目录（如 C:\Espressif）
   __IDF_VERSION__      如 6.0.1
   __PYTHON_ENV__       IDF 的 python env 目录
   __TOOLCHAIN_BIN__    xtensa 工具链 bin 目录
   __CMAKE_BIN__        cmake bin 目录
   __NINJA_BIN__        ninja 目录

3. 双击 install-build-daemon.cmd   ← 必须由人在沙箱外执行
```

之后每次开机自动在场，**不需要再点任何东西**。

## 日常使用（给 AI 的契约）

```
触发构建：  向 build.request 写入一行     full   或   inc
读取结果：  build.status                  RUNNING ... / DONE ... exit=rc
读取日志：  build.log                     完整编译输出，末尾 EXIT=code
判断存活：  build-daemon.heartbeat        每约 20 秒刷新的时间戳
```

**AI 侧只做「写文件 + 读文件」，绝不要拉起任何进程。**

## 两个必须知道的坑

### 1. 必须由人在沙箱外启动

如果从 AI 助手的后台拉起守护进程，它**仍然继承沙箱**，问题照旧。
正确方式：人双击 `install-build-daemon.cmd`，或由 `Startup` 文件夹在登录时自动拉起。

### 2. ninja 必须经 `run_ninja.py` 拉起

**不要**把 `python run_ninja.py -C build` 改回 `ninja -C build` 直调。
隐藏控制台会被 ninja 当作 stdin 继承，导致 `ldgen` 步骤静默死于 `errorcode -1`。

## 自检

```
1. build-daemon.heartbeat 的时间戳是否在刷新      → 守护进程活着
2. 写 build.request = inc                          → 是否 1-2 秒内变 RUNNING
3. 等 build.status 变成 DONE exit=0                → 构建成功
4. 看 build.log 末尾是否 [N/N] 完成 + EXIT=0        → 端到端通过
```
