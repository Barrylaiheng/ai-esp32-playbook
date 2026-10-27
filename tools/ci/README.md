# tools/ci

存放 GitHub Actions 工作流的**待启用**版本。

## 为什么不放 `.github/workflows/`

GitHub 规定：创建或修改 `.github/workflows/*` 需要 token 带独立的
`workflow` scope。本机 gh 会话的 scope 只有 `gist, read:org, repo`，
缺 `workflow` 时所有写操作一律返回 **404（不是 403）**，很容易误判成
"仓库没有写权限"——实际上同一个仓库的其它路径都能正常推送。

受影响的不仅是 contents API：`git/trees` 只要待创建的那棵树里含有
`.github/workflows/*` 路径，整棵树都会创建失败；GraphQL 的
`createCommitOnBranch` 也一样报 FORBIDDEN。

## 怎么启用

任选其一：

1. **补 scope 后搬回去**（推荐）
   ```
   gh auth refresh -h github.com -s workflow
   git mv tools/ci/docs-check.yml .github/workflows/docs-check.yml
   ```
   `gh auth refresh` 走的是 OAuth 设备码流程，端点在 `github.com` 主机上，
   在受限沙箱里会被代理掐断（`Bad Gateway` / `unexpected EOF`），
   需要在普通终端窗口里执行。

2. **网页端直接建**
   在 GitHub 网页上 Add file → `.github/workflows/docs-check.yml`，
   粘贴本目录里的文件内容即可（浏览器会话不受 token scope 限制）。

## 检查项

`docs-check.yml` 做两件事：

- `tools/check_links.py`：校验 Markdown 里的相对链接是否可达；
- 扫描 `templates/` 下的 `.cmd` / `.vbs` 是否纯 ASCII——中文 Windows 按 GBK
  解析批处理文件，任何非 ASCII 字节都会被当成命令执行。
