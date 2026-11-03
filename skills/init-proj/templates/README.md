# 模板使用

模板扩展名为 `.md.tmpl`，避免被扫描器当作实际 AGENTS/CLAUDE 指令文件。只能在读取现有文件并确认授权后填实；不要直接覆盖或留占位符。最小init先建立入口与共享目录说明，有实际需要才增加角色/记忆。

- [共享入口](agents-entry.md.tmpl)
- [共享目录说明](workspace-readme.md.tmpl)
- [Claude入口](claude-entry.md.tmpl)
- [共享角色](role.md.tmpl)
- [Claude角色适配](claude-role.md.tmpl)
- [项目记忆导航](project-memory.md.tmpl)

`{{...}}` 表示需核对/填写的值，不由脚本自动推断。本文相对路径是包内模板导航；填实后的文件引用按目标目录重新计算。Git忽略规则应依据已有配置制定，故不提供整份覆盖模板。
