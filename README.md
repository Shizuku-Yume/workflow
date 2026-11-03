# Workflow

[English](README_EN.md) | 简体中文

面向 AI 编程智能体与开发者的轻量级项目工作流工具。通过 `workflow init` 将规则、技能（Skills）、文档模板与任务调度 CLI 直接写入目标 Git 仓库，减少日常开发中的沟通和上下文管理开销。

---

## 设计要点

- **随仓库提交**：规则、技能与 CLI 保存在仓库内（`.workflow/`、`.agents/` 及可选的 `.claude/`），克隆即可使用，无需全局配置。
- **先查代码再提问**：提问前先查代码、配置与提交历史；可逆细节选合理默认值，只把方向性决定或高成本取舍交给用户。
- **真实路径验证**：每个任务附带可执行的 `Check` 验证命令。修复 Bug 先复现失败，交付前在真实 CLI 或服务入口跑通验证。
- **克制实现**：优先复用现有代码与标准库；处理真实可达的问题，不写臆想场景的防御逻辑、空封装或未要求的兼容开关。
- **独立上下文审查**：由独立上下文的 `workflow-reviewer` 检查需求落实与代码质量；涉及鉴权、外部输入等安全边界时运行 `security-reviewer`。
- **并行隔离与决策留痕**：`workflow next` 调度任务并提示文件冲突；并行任务在独立 Git worktree 中执行；难以回退的技术决定记入 `.workflow/decisions.md`，项目术语维护在 `glossary.md`。

---

## 日常怎么用

按改动规模与确定性选择最短路径，不需要每次走完完整流程：

1. **小改动 / 普通 Bug**：直接改代码 → 跑测试和真实入口验证 → 提交。不建任务卡，不走审查流程。
2. **明确的 1–3 个任务**：`flow-break` 拆任务卡 → `flow-implement` 完成并归档。不写 Spec，不走 `flow-close`。
3. **多任务复杂功能 / 涉及接口或数据结构变更**：`flow-spec` → `flow-break` → `flow-implement` → `flow-close`。

**需求或方案未定时**（无论规模大小），先运行 `flow-grill` 理清取舍，再进入上面对应的路径；需要跨会话摸索的未知问题记入 `maps/<slug>.md`，`workflow next` 会持续提示。

---

## 9 个工作流技能（Skills）

日常开发大部分时候只用到 2–4 个技能。技能分为**日常主流程**与**按需辅助**两类：

### 日常主流程技能

| 技能 | 适用场景 | 作用 |
| :--- | :--- | :--- |
| `flow-start` | 新开会话 / 恢复工作 / 不确定下一步干什么 | 读取项目标准与任务队列，给出下一步建议或推进任务。 |
| `flow-grill` | 需求未定 / 新功能起步 | 查清代码现状与需求取舍。方案明确后转入 `flow-spec` 或 `flow-break`；需跨会话摸索的记入 `maps/<slug>.md`。 |
| `flow-spec` | 方案未定 / 多任务复杂功能 | 将确认的设计整理为精简技术方案（`specs/<effort>.md`）；1–3 个明确任务直接跳过。 |
| `flow-break` | 拆解可执行任务卡 | 把技术方案或明确需求拆为带依赖（`Blocked by`）和验证命令（`Check`）的任务卡片。 |
| `flow-implement` | 执行单个任务或整组任务 | 完成单个任务或整组任务的编码、验证、审查与归档；传入 `<effort>` 时按依赖波次调度。 |
| `flow-verify` | 合并前代码审查 | 启动独立上下文的 `workflow-reviewer` 审查需求落实与代码质量，按需触发安全审查。 |

### 按需辅助技能

| 技能 | 适用场景 | 作用 |
| :--- | :--- | :--- |
| `flow-close` | 技术方案（Spec）整组收尾验收 | 在真实交付构建上跑通 Spec 检查与主流程，经用户确认后记录验收结论并归档。 |
| `flow-retro` | 会话卡壳 / 协作摩擦复盘 | 复盘会话卡壳与协作摩擦，提炼为自动化检查、规则精简或配置补充（需用户同意）。 |
| `flow-architect` | 改动阻力大 / 排查技术债 | 排查高频修改模块中的冗余、死代码与过度封装，整理并跟踪可执行清理项。 |

---

## 安装与初始化

### 1. 安装 CLI

通过 npm 全局安装：

```bash
npm install --global @shizuku-yume/workflow
```

或克隆本仓库后直接调用 `bin/workflow`。

### 2. 初始化目标项目

在目标 Git 仓库根目录运行：

```bash
workflow init
```

常用参数：
- `--claude`：同时生成 Claude Code 适配目录（`.claude/` 与 `CLAUDE.md`；仓库已有相关文件时自动开启）。
- `--no-claude`：仅生成通用 `.agents/` 与 `AGENTS.md`。
- `--force`：强制覆盖本地修改过的受管模板文件。

### 3. 安装提交前校验钩子（可选）

提交前自动检查任务卡片格式与依赖关系：

```bash
workflow hook install
```

---

## CLI 命令速查

可在全局运行 `workflow <command>`，也可直接运行项目内的 `.workflow/bin/workflow <command>`。

### 日常调度与检查

- `workflow next [--effort SLUG] [--all] [--brief] [--format text|json]`
  按优先级列出可开工任务、进行中/暂停/阻塞任务，并提示共用文件冲突；`--brief` 输出精简简报，空闲时不输出。
- `workflow validate [--strict] [--format text|json]`
  检查 `tasks/`、`done/`、`specs/` 与 `decisions.md` 的字段格式和依赖完整性。
- `workflow doctor`
  检查工作流文件是否齐全、分支版本是否同步，并运行 `validate`。
- `workflow hook install|uninstall|status [--force|--append]`
  管理 Git `pre-commit` 自动校验钩子。
- `workflow version`
  查看版本号。

### 安装与维护

- `workflow init [--force] [--claude|--no-claude]`：在当前项目安装工作流文件与 CLI。
- `workflow update [--force] [--claude|--no-claude]`：升级受管技能、规则与 CLI，保留本地改写过的内容。
- `workflow uninstall`：移除未改动的受管工作流文件，保留项目自身配置、任务与决策记录。

---

## 目录结构

执行 `workflow init` 后的目录结构：

```
AGENTS.md                        # Agent 入口规则（带 workflow 标记块）
.agents/
  skills/<name>/SKILL.md         # 9 个工作流技能步骤
  agents/workflow-reviewer.md    # 需求与代码质量审查规则
  agents/security-reviewer.md    # 安全边界审查规则
.workflow/
  bin/workflow                   # 随仓库提交的 CLI（Bash）
  bin/workflow-core.py           # 校验与任务队列脚本（Python 3 标准库）
  CONVENTIONS.md                 # 工作流通用规则
  STYLE.md                       # 表达与汇报风格规则
  standards.md                   # 项目命令、目录说明与分支合入方式
  glossary.md                    # 项目术语表（Git union merge）
  decisions.md                   # 架构与技术决策记录（Git union merge）
  technical-debt.md              # 待清理技术债记录
  specs/<effort>.md              # 多任务功能的技术方案（Spec）
  tasks/<effort>/<NN>-<slug>.md  # 待完成任务卡片
  maps/<slug>.md                 # 跨会话未决问题记录（由 flow-grill 写入）
  done/<effort>/                 # 已归档任务与验收记录
```

---

## 环境要求

- **系统**：Linux / macOS（POSIX 环境）
- **Shell**：Bash 3.2+（兼容 macOS 自带 Bash）
- **Python**：Python 3.8+（仅用标准库，供 `validate` 与 `next` 使用）
- **Git**：版本控制与分支状态读取
- **Node.js**（可选）：Node.js 14+（仅通过 npm 全局安装时需要）

---

## 许可证

MIT
