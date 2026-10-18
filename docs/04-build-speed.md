# 构建提速：从「每次全清 5-8 分钟」到「9 秒一轮」

> 主文第 4 节的展开。回答一个问题：**AI 写代码的速度早就不是瓶颈了，构建才是。**
> 这篇记录我把固件构建从「改一个字符也要全清重建」压到「UI 改动 9 秒看到画面」的完整过程，
> 以及一次「AI 给的优化建议，一半是错的」的验证实录。

---

## 一、先说结论：一张实测数据表

全部数字来自本项目（ESP32-S3，ESP-IDF v6.0.1，Windows，构建守护进程链路）：

| 场景 | 优化前 | 优化后 | 瓶颈真相 |
|---|---|---|---|
| 无改动增量构建（no-op） | ~60-90s | **1.6-3.5s** | 时间被 reconfigure 白吃 |
| 改 1 个 `.c` 文件 | ~5min（被迫全清） | **35s** | 其中链接 ~28s，**不可省** |
| 全量构建 | 5-8min | 5-8min（ccache 下更短） | 编译器总数摆在那 |
| UI 改动的验证闭环 | 烧录真机人眼看 | **9.4s**（模拟器编译+6 屏截图+像素自检+黄金图回归） | 主战场换地方了 |

三个关键认知：

1. **增量快的障碍根本不是编译器**，是每次构建前面白付的 `reconfigure`（60-90s）和 `ldgen`（~30s）。
2. **链接时间（~28s）是硬底**，换 sccache/RAMDisk/`-j16` 都动不了它——别在这上面浪费人生。
3. **UI 迭代的最优解不是「更快的固件构建」，是「根本不去构建固件」**——搬进 PC 模拟器，一轮 9.4 秒。

---

## 二、赢项一：ccache（最大单项，但前提是你没在全清）

```bat
set IDF_CCACHE_ENABLE=1
```

一行的事。社区基准（ESPRESSIF 官方博客与多个项目实测）：增量 **218s → 1.8s**、全量 **12.7min → 5.1min**；我的实测与这个量级一致。

**但这里有个陷阱，我亲眼见过：**

> 「每次被迫 full clean」不是 CMake 的错，**是自己选的**。

我的构建守护进程把请求字 `full` 映射成了 `clean`（先全清再全建），而我有段时间默认就写 `full`——于是 ccache 缓存每次都被亲手抹掉，还在抱怨「为什么每次都要 5-8 分钟」。ccache 早就生效了（build.log 里 `-- ccache will be used for faster recompilation` 一直在），只是它的缓存被我主动清空。

**纪律**：请求字默认 `inc`；`full`/`clean` 只在「改了 CMake 结构、换了工具链、怀疑构建树损坏」时用。写完 `full` 之前问自己：这次真的需要全清吗？

---

## 三、赢项二：门控 reconfigure（每次白付 60-90s 的那层）

ESP-IDF 的 `idf.py build` 每次都做一次 CMake reconfigure——即使什么都没改。在 v6.0.1 上这一步要 **60-90 秒**，而且它还有个**必崩的 bug**（见下）。

做法：写一个 `need_cfg.py`，遍历工程找这些文件的变更：

```
CMakeLists.txt / sdkconfig / sdkconfig.defaults / Kconfig.projbuild
 partitions.csv / 组件增减 / version.txt(git describe)
```

有变更才 reconfigure，否则直接驱动 ninja。**效果：no-op 构建从 60-90s 掉到 1.6-3.5s。**

> 顺带一个反直觉收益：**少 reconfigure = 少踩 IDF 的 reconfigure bug**（见第五节）。有些上游 bug 你躲着它就够，不用修它。

---

## 四、赢项三：门控 ldgen（每次白重链 30s 的那层）

`Generating sections.ld` 这一步由 ninja 每次重跑，而它输出文件的 mtime 处理有问题——**内容没变也会让下游认为链接器脚本变了，触发一次完整重链（~30s）**。

做法同样是一个门控小脚本（`pre_ldgen.py`）：ldgen 产物已存在且输入没变 → 跳过并**保住产物 mtime**。ninja 看到依赖没动，就不重链。

> 模式和第三节完全同构：**构建系统的「每次全查」在大型工程上就是纯浪费，用 mtime 快照把「没变」证明出来。**

---

## 五、字体生成的依赖：CMake 接法被 IDF bug 堵死，改用构建前守卫

### 5.1 误诊 vs 真相

曾经有个流传很广的诊断（来自某 AI 助手，我差点信了）：

> 「你每次被迫 full clean，是因为 CMake 不知道 `home_app.c` 依赖字体生成产物，改字体后增量编译不会重编 → 符号缺失 → 只能全清重建。」

**方向对了一半，根因诊断是错的。** 真相是：

- 增量不重编字体不是问题——字体 `.c` 是提交进 git 的**源文件**，不是每次现场生成的；
- 真正的脚枪是「**固件在字体 `.c` 生成之前就开始构建**」（我真实踩过：符号在 `.map` 里缺失，只能全清重建来「修复」）；
- 所以正确目标不是「让增量重编字体」，而是「**构建前保证字体不缺失、不过期**」。

### 5.2 CMake 正路为什么走不通（IDF v6.0.1 的 reconfigure bug）

标准做法是在组件 `CMakeLists.txt` 里：

```cmake
add_custom_command(
    OUTPUT fonts/dada_label_20.c
    COMMAND ${Python3_EXECUTABLE} gen_fonts.py
    DEPENDS gen_fonts.py assets/fonts/xxx.ttf
)
```

**在 ESP-IDF v6.0.1 上这条路必崩**，而且崩得很难看：

```
build_properties.temp.cmake:8: syntax error
set(COMPILE_DEFINITIONS "...IDF_VER="v6.0.1"")   ← 内层引号没转义
```

根因：IDF 把 `IDF_VER="v6.0.1"`（带引号）塞进 `COMPILE_DEFINITIONS`，序列化时内层引号未转义。**任何组件 CMakeLists 里的 `add_custom_command` 都会触发 reconfigure 重新生成这个文件，从而踩中。**

**定位手法是唯一变量隔离测试**（主文 4.2 的手法，这次原样复用）：

| 组件 CMakeLists 内容 | reconfigure 结果 |
|---|---|
| 原版（无自定义命令） | ✅ 通过 |
| 原版 + 惰性 `add_custom_target(dada_dummy)`（无 OUTPUT） | ✅ 通过 |
| 原版 + `add_custom_command`（OUTPUT 是 SRCS 里的字体 `.c`） | ❌ 崩 |

**触发点定案：`add_custom_command`。** `add_custom_target` 不触发。

### 5.3 替代方案：构建前守卫（模板已给）

不碰组件 CMakeLists，在 ninja 之前插一个守卫脚本 [`templates/daemon/ensure_fonts.py`](../templates/daemon/ensure_fonts.py)：

```bat
"%PY%" "%PROJ%\tools\ensure_fonts.py" >> "%LOG%" 2>&1
if errorlevel 1 goto font_fail     :: 字体坏 = 拒绝构建，绝不带病编译
```

行为（三条路径都实测过）：

| 路径 | 行为 | 耗时 |
|---|---|---|
| 字体最新 | 打印 `all fonts up to date` 直接过 | ~0（纯 mtime 检查，不调 npx） |
| 字体缺失/过期 | 自动重生成 → 继续构建 | 一次生成时间 |
| 重生成失败 | **以 EXIT=98 拒绝构建** | —— |

**为什么用「拒绝构建」而不是「警告后继续」**：带着坏字体编译出来的固件，界面全是豆腐块，而这个问题要到烧录后才暴露——那时你已经付出了烧录+人眼验证的全部成本。在最早的出口拦下它。

### 5.4 守卫自身踩的坑：IDF python 没有 fontTools

守卫第一次自动重生成就失败了，报错：

```
Font "assets/fonts/SourceHanSansSC-Regular.ttf" doesn't have any characters included in range 0x2192-0x2192
```

根因链：

1. 生成器用 `fontTools.ttLib.TTFont.getBestCmap()` 过滤「TTF 不支持的字符」（如 `→` U+2192），避免 `lv_font_conv` 报错；
2. 守卫由**构建守护进程用 IDF python** 拉起，而 **IDF python 环境没装 fontTools** → `HAVE_FT=False` → 跳过 cmap 过滤 → 把不支持的字符直接喂给 `lv_font_conv` → 失败；
3. 同机器上系统 Python312 有 fontTools，手动跑一直成功——**差别只在「用哪个 python 跑」**。

修法：守卫加一个 `find_fonts_python()`——按候选列表找第一个能 `import fontTools` 的解释器，找不到才 fallback 到 `sys.executable`。

> **通用教训**：守护进程/CI 里跑生成脚本，**不要假设 `sys.executable` 就是那个「能跑脚本」的解释器**。
> 「我的机器上手动能跑」和「守护进程里能跑」之间，差的往往就是一个包。
> 而这类失败**好在是响亮的**（守卫拒绝了构建）——比安静地产出坏产物好一万倍。

---

## 六、AI 给的优化建议怎么验（一次完整实录）

某 AI 助手给了我一份 ESP-IDF 构建提速建议（三类优先级），核心论点：

> 「最关键的优化刚好就是解决你现在这个字体问题，以后不用每次都跑 5~8 分钟 full clean」

我逐条对照官方文档和本项目实测核验了一遍。结论：**方向对一半、根因诊断错、漏了已经落地的大赢项。**

| 它的建议 | 核验结果 |
|---|---|
| P1「CMake 依赖修复」（`add_custom_command` 接字体生成） | ❌ **在 IDF v6.0.1 上被上述 bug 堵死**；且目标本身是误诊（见 5.1） |
| P2「迁移 WSL2 提速」 | ❌ 来源是 SEO 软文；本机工具链全钉死 Windows，迁移成本极高、收益存疑 |
| P2「Ninja `-j N` 并行」 | ❌ 冗余：守护进程早已驱动 ninja，`idf.py -j` 语法本身就不存在 |
| P3「LVGL 配置裁剪」 | ❌ 高危：与自研 chrome 架构、封闭词表字体、VI 铁律全面冲突，省几 KB 不值 |
| （它没提的）**ccache** | ✅ **早已落地生效**，才是增量提速的真正主力 |
| （它没提的）**reconfigure/ldgen 门控** | ✅ 本次新增，no-op 从 60-90s → 1.6-3.5s |

**沉淀下来的验证纪律**（这条比上面任何一条都值钱）：

1. **AI 的建议先当假设，不当结论。** 它的「根因诊断」部分最可能是错的——因为它没读过你的构建日志，只读了你的描述。
2. **每条建议问三个问题**：① 我的机器上实测过吗？② 和已落地的基建冲突吗？③ 收益能量化吗？
3. **识别软文来源**：来源是个人技术博客/CSDN 类 SEO 内容，先降权；来源是官方文档/官方博客，才值得花时间。
4. **用隔离测试定案触发点**（5.2 那次）：不要接受「应该是 X 导致的」，构造对照组把它钉死。

> 这不是说 AI 的建议没价值——**P1 的方向（把生成接进构建系统）是对的**，只是它的实现路径和根因判断都错了。有价值的部分 + 错误的部分，要分开结算。

---

## 七、明确不跟的（避免过度工程）

| 候选 | 不跟的理由 |
|---|---|
| sccache / RAMDisk | no-op 已 1.6-3.5s，瓶颈在链接（28s 不可省），收益趋零 |
| Docker/Sandbox + RFC2217 串口透传 | 解决「沙箱摸不到 USB」；我们的守护进程模式已解决同一问题且更快 |
| LVGL Pro CLI（可视化编辑器） | 收费；与自研 chrome 架构 + VI 铁律 + 封闭词表字体冲突（调研结论维持不变） |
| 「可视化拖拽生成 UI」引入主线 | 同上，且违反「设计语言先行、人拍板」的分工 |

---

## 八、本节 Checklist

- [ ] `IDF_CCACHE_ENABLE=1`，且**请求字默认 `inc`**（`full`/`clean` 是主动选择，不是默认值）
- [ ] reconfigure 有门控（`need_cfg.py` 类）：CMakeLists/sdkconfig 没变就不 reconfigure
- [ ] ldgen 有门控（`pre_ldgen.py` 类）：产物在且输入没变就跳过并保 mtime
- [ ] 生成的源码（字体/资源）有**构建前守卫**：缺失/过期自动重生，失败则**拒绝构建**（独立退出码）
- [ ] 守护进程里跑生成脚本，先确认解释器有依赖包（别假设 `sys.executable`）
- [ ] UI 迭代主战场在 PC 模拟器，固件构建只做最终集成
- [ ] AI 给的优化建议：先当假设，实测+量化+查冲突，三问过了再落地

---

*下一篇：[`05-visual-regression.md`](05-visual-regression.md)——黄金图回归门，以及「门第一次失灵」的两个 PIL/时钟坑。*
