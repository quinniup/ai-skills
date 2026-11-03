# 通用结构与职责

## 推荐布局（按需创建）

```text
project/
├── AGENTS.md                         # 跨工具共享入口
├── CLAUDE.md                         # 可选：Claude 导入适配
├── CLAUDE.local.md                   # 可选：个人配置，忽略
├── .agents/
│   ├── README.md                    # 项目约定、加载与维护说明
│   ├── rules/                       # 跨工具强制约束
│   ├── roles/                       # 工具无关职责正文
│   ├── workflows/                   # 通用操作与协作流程
│   ├── memory/project.md            # 记忆来源及更新路由
│   └── skills/<name>/
│       ├── SKILL.md
│       ├── scripts/                 # 需要实际自动化时才添加
│       └── references/              # 按任务展开的详细资料
├── .claude/                         # 仅实际使用 Claude 时建立
│   ├── agents/<name>.md             # frontmatter + 实际读取共享角色的指令
│   ├── workflows/orchestration.md   # Claude 专用编排偏好
│   ├── rules/                       # 按路径限定加载适配，不复制共享规则
│   ├── settings.json                # 审查后的共享工具配置
│   └── settings.local.json          # 个人权限与设置，忽略
└── docs/                            # 人与工具共用的工程文档
    ├── development/
    ├── design/
    └── ops/
```

这不是全量脚手架。最小初始化只需真实的 AGENTS.md 和 .agents/README.md；其他文件按项目已有内容、用户需要与工具能力建立。不要生成虚构规则、角色、命令、知识库或部署状态。

## 任务资料（按需接入）

有任务管理需要时，实际读取[任务生命周期](todo-lifecycle.md)及项目现有规则。沿用已有资料路径；无约定时可用`notes/todos/`、`notes/archive/`与`notes/README.md`，不预建空目录或任务。

- todos保存当前可执行状态，archive保存已验收任务或明确分类的历史证据，索引分三类导航；它们是项目资料，不移入`.agents`。
- `.agents/rules/todo-lifecycle.md`仅维护项目约束；AGENTS按相关任务要求实际读取规则与当前任务，不把历史导入默认上下文。
- 任务留当前结论/下一步/验收/必要回滚，资产留当前事实，CHANGELOG留每日1–3条摘要；过程留会话临时证据，不持续追加多份副本。

## 放置判据

| 问题 | 去哪 | 不应放什么 |
|---|---|---|
| 开工先读什么 | AGENTS.md | 全量设计、全部 persona、现场快照 |
| 必须遵守什么 | .agents/rules | 未确认建议、个人偏好；现有铁律准入判据应保留 |
| 谁负责、谁不负责 | .agents/roles | 工具 permissions/model、完整架构副本 |
| 任务怎么推进 | .agents/workflows 或 skill | 把角色名称当可重复能力 |
| 长期知识从哪读、怎么维护 | .agents/memory | 外部知识全文副本、未决问题当事实 |
| 专项任务怎样重复执行 | .agents/skills | 无触发条件的全仓常驻规则 |
| 工具如何发现/执行 | .claude 等实际工具目录 | 再维护一份共享正文 |
| 构建、代码风格、设计、运维 | docs 或已有 CONTRIBUTING/README | 为集中而重复搬运人用文档 |
| 本机在哪、可操作什么 | 忽略的本机配置 | 共享凭据、宽权限名单 |

## 工具适配

根 CLAUDE 可采用 `@AGENTS.md`，但应先验证入口真实文件与链接目标，避免AGENTS→CLAUDE→AGENTS循环。其他工具的导入机制不一定相同。

Claude 角色 frontmatter 仅放该工具支持的字段（name/description，以及按当前版本实际支持的模型/工具限制等），正文明确要求读取 `.agents/roles/<name>.md`。不要假设把共享角色写进 skills 就能注册角色。

具体路径应按文件目录实际计算：`.claude/agents/x.md` 到 `.agents/roles/x.md` 是 `../../.agents/roles/x.md`；不要凭直觉数层级。符号链接可用但不是默认方案，需考虑 Git、Windows 与扫描器。

## Git 与本机边界

- 共享入口、规则、角色、工作流、已审查技能应该被跟踪，而不仅解除忽略。
- 若工具目录含历史权限或其他未审查产物，优先白名单；解除整个目录忽略前逐项审查。
- `!<dir>/` 不能保证所有嵌套内容都不被其他规则忽略，需真实 `git check-ignore` 验证。
- `CLAUDE.local.md`、settings.local.json、凭据、缓存应忽略。保留原文件，不复制它们的授权到共享设置。
- 旧 `.soul/` 可保留短兼容入口指向新rules，规则正文只维护一份；不抹去事故的历史路径。

## 标准与参考的边界

- [AGENTS.md](https://agents.md/)：入口约定，不规定本技能全部目录。
- [Claude 项目记忆](https://code.claude.com/docs/en/memory)：Claude 特有加载与导入机制，版本需核对。
- [Claude subagents](https://code.claude.com/docs/en/sub-agents)：角色发现与工具配置。
- [Agent Skills](https://agentskills.io/)：能力包格式；并不代表所有工具都扫描同一物理路径。
- [Anthropic skills](https://github.com/anthropics/skills)：能力包范例，许可逐包确认。

`.agents/rules/roles/workflows/memory` 是本项目组织约定，不是上述标准共同规定的默认自动加载路径。
