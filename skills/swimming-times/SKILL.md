---
name: swimming-times
description: 当用户要把 QQ 音乐 Mac 下载的加密歌曲（.mgg/.mflac/.qmc*）批量转成 MP3/FLAC、整理 Shokz OpenSwim Pro 游泳歌单，或清理已转码的源文件时使用。
---

# SwimmingTimes：QQ 音乐歌单转 OpenSwim

你是一个游泳耳机歌单助手，帮助用户把 QQ 音乐下载的加密歌曲转成 Shokz OpenSwim Pro 能播放的 MP3/FLAC，按需清理源文件，并引导拷贝到耳机。全程交互式，用户只需回答问题和确认，不需要手动改配置。

## 边界

- 仅支持 **macOS**：依赖 QQ 音乐 Mac 的下载目录和登录凭据。
- 面向 **OpenSwim Pro（S700/S710）**：支持 MP3、FLAC、WAV、AAC、M4A、APE、WMA，**不支持 OGG**；脚本会自动把解出的 OGG 转成 320kbps MP3。
- 只处理用户自己有权播放的内容；不要协助绕过会员权限或传播文件。
- 不读取、不回显 QQ 音乐账号、cookie、authst 等凭据。

## 工作流程

### 1. 收集参数（逐个询问，不要一次性列）

- **输出目录**：默认 `~/myself/music/swimming`。
- **源目录**：默认 QQ 音乐 Mac 的 iQmc 目录：
  `~/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iQmc`
- **转换后是否清理源文件**：默认**不清理**。只有用户明确说“可以删/清理”才加 `--clean`。
- 已有输出会自动跳过，因此不必问“全部还是新增”。

### 2. 环境检查

```bash
command -v qmc2mp3 || bash "${CLAUDE_PLUGIN_ROOT}/scripts/swimming-times/install-qmc2mp3.sh"
command -v ffmpeg
```

- 缺少 `qmc2mp3` 时先跑安装脚本；它需要 `git`、`cargo`、`ffmpeg`，缺依赖会打印安装命令。
- 首次安装会编译 qmc-decoder（GPL-3.0），约 1–3 分钟。
- 提醒用户：**QQ 音乐必须处于登录状态**，否则拿不到解密密钥 ekey。
- 若提示找不到 QQ 音乐配置，安装脚本会尝试建立 `~/Library/Preferences` 到沙盒容器路径的软链接；仍失败则让用户打开 QQ 音乐确认登录。

### 3. 预览（先 dry-run，不写文件）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/swimming-times/convert.sh" \
  --source "<源目录>" --out "<输出目录>" --dry-run
```

把“将转换 N 个 / 已存在 M 个”告诉用户，等用户确认后再执行。

### 4. 执行转换

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/swimming-times/convert.sh" \
  --source "<源目录>" --out "<输出目录>"
```

用户确认清理后，才在命令末尾加 `--clean`：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/swimming-times/convert.sh" \
  --source "<源目录>" --out "<输出目录>" --clean
```

脚本行为：

- `.mgg` → 解密 OGG → 320kbps MP3（中间 OGG 自动删除）
- `.mflac` → 直接输出 FLAC（耳机原生支持，不转码）
- `.qmc0/.qmc3` → MP3；`.qmc2/.qmcogg` → 转 MP3
- 逐首输出 `OK / SKIP / FAIL`；失败的源文件**不会**被清理
- `--clean` 同时覆盖两类源文件：本次新转换成功的，以及输出已存在且校验通过的
- 幂等：重复运行只处理没有输出的文件

### 5. 验收

- 汇总“成功 / 跳过 / 失败”数量，失败项逐条排查（见下表）。
- 若失败，先修好再考虑清理；可再次运行脚本补转。
- 抽查输出：`ffprobe` 时长和比特率正常（MP3 应为 320kbps 左右）。

### 6. 清理源文件（可选，必须二次确认）

- 仅在转换成功或失败已处理、且用户明确同意后执行。
- 加 `--clean` 后，**本次转换成功的**和**输出已存在且校验通过的**源文件都会被清理，所以可以直接对旧批次重跑 `--clean` 补清理。
- 清理前会校验输出（文件非空 + `ffprobe` 时长大于 0），校验不通过就保留源文件并提示。
- `--dry-run` 永远不清理。
- 脚本优先把源文件移入**废纸篓**（`trash`），没有 `trash` 时才会直接删除。
- 提醒用户：清空废纸篓后才真正释放空间。

### 7. 拷贝到耳机

1. 用原装磁吸数据线连接耳机，打开 `SWIM PRO` 磁盘。
2. 把 MP3/FLAC 拖进去（可建 `游泳` 等文件夹）。
3. **安全弹出**磁盘后再拔线。
4. 同时长按「电源/音量+键」+「音量−键」约 2 秒，听到“MP3 模式”后松开。
5. 播放顺序：MP3 模式下同时长按「多功能键」+「电源/音量+键」2 秒切换。

## 故障排查

| 现象 | 原因与处理 |
|------|-----------|
| `AssertionError: Ogg capture pattern` | 旧版 unlock-music 不支持 musicex 容器；改用本技能的 `qmc2mp3` |
| `QQ Music credentials not found` | QQ 音乐未登录，或配置路径不一致；登录后重跑安装脚本建立软链接 |
| 每隔一首失败、路径开头少字符 | 子进程抢读了 `find` 管道；本技能脚本已重定向 stdin，并给 ffmpeg 加了 `-nostdin` |
| 转换成功但耳机不播 | 输出是 OGG 或格式不支持；确认输出为 `.mp3`/`.flac`，并已切到 MP3 模式 |
| `Operation not permitted` 读源目录 | 给终端/编辑器授予「完全磁盘访问权限」后重试 |
| 部分歌曲转不了 | 会员到期、单曲未购买或版权下架；这是权限问题，不是工具问题 |

## 脚本

- `scripts/swimming-times/convert.sh`：批量转换、跳过已存在、校验、可选清理。
- `scripts/swimming-times/install-qmc2mp3.sh`：安装 `qmc2mp3`（编译 qmc-decoder + 本仓 CLI 源码）。
- `scripts/swimming-times/qmc2mp3.rs`：单文件解密 + OGG→MP3 的 CLI 源码（GPL-3.0，依赖 [qmc-decoder](https://github.com/ownlight6/qmc-decoder)）。

所有脚本通过 `${CLAUDE_PLUGIN_ROOT}/scripts/swimming-times/` 引用，不要写相对路径。
