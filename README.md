# Workflow

[English](README_EN.md) | 简体中文

面向 AI 编程智能体（Coding Agents）与开发者的项目本地化工作流套件。

通过将规范、技能（Skills）、文档结构与任务调度 CLI 直接注入目标 Git 仓库，使 Coding Agent 具备严谨的工程化规划、分解、实现、验证与复盘能力。

---

## 核心特性

- **项目本地化（Project-Local）**：所有规范、技能、模板与调度工具均拷贝并提交至仓库根目录（`.workflow/`、`.agents/`，以及可选的 `.claude/`）。任何克隆该仓库的协作者、CI 或云端智能体无需在全局环境安装依赖或配置 PATH，即可获得完全一致的工作流。
- **事实与证据先于提问（§0、§1）**：智能体在打扰用户前，必须自主在代码库中检索证据（模式、现有行为、接口与配置）；仅当涉及用户决策所有权（目标、偏好、范围、无法逆转的权衡）时才批量向用户提问。
- **依赖拓扑与任务调度（DAG Queue）**：复杂工作通过 `flow-break` 拆解为单会话可交付的独立任务文件（`.workflow/tasks/<effort>/`），通过 `workflow next` 自动按优先级和依赖关系输出就绪任务。
- **严格的可观测验证（§2.1、§8）**：所有任务均要求具备明确的验证命令（`Check`）。功能与 Bugfix 必须在修改前复现或确认失败、修改后通过验证，严禁无证据交付。
- **不可逆决策日志（Decisions Log）**：重大技术决策在 `.workflow/decisions.md` 中以结构化要素（`Decided`, `Instead of`, `Because`, `Mine`, `Revisit when`）追加记录。通过 Git union merge 属性杜绝多分支合并冲突。
- **双重视角独立审查（§7）**：内置 `workflow-reviewer` 审查智能体，分别从交付规范一致性与代码实现质量两个独立维度进行把关。

---

## 安装与初始化

### 1. 全局安装 CLI

推荐使用 npm 全局安装：

```bash
npm install --global @shizuku-yume/workflow
```

或克隆本仓库后使用源码路径 `bin/workflow`。

### 2. 初始化项目

进入需要应用工作流的 Git 仓库根目录，运行：

```bash
workflow init
```

常用选项：
- `--claude`：强制安装 Claude Code 适配层（写入 `.claude/skills/`、`.claude/agents/` 并创建导入配置的 `CLAUDE.md`）。若项目中已存在 `CLAUDE.md` 或 `.claude/` 目录，则默认开启。
- `--no-claude`：仅安装标准 `.agents/` 目录与 `AGENTS.md`。
- `--force`：覆盖已修改的受管模板文件。

### 3. 安装 Pre-commit 检查钩子（可选）

为防止格式错误或依赖断裂的任务文件被意外提交：

```bash
workflow hook install
```

---

## 技能全景 (Skills)

套件提供 9 个标准技能，分别应对开发流程的不同阶段（按 §5 路由）：

| 技能 | 适用场景 | 说明 |
| :--- | :--- | :--- |
| `flow-start` | 会话开始 / 上下文丢失 / 恢复工作 | 加载项目标准与规范，对请求分流（日常问答、小型任务或复杂规划）。 |
| `flow-grill` | 需求模糊 / 设计方案待定 | 澄清需求并推导细节，按分类筛选问题，批量向用户提问并沉淀架构决策。 |
| `flow-map` | 目标迷茫 / 跨多个会话的复杂探索 | 为具有大片未知区域（Fog）的项目绘制开放性探索地图与问题依赖。 |
| `flow-spec` | 方案已定 / 需要落地规约文档 | 将讨论共识整理为格式化的技术规约文档（`.workflow/specs/<effort>.md`）。 |
| `flow-break` | 规约需要拆解为具体开发任务 | 将 Spec 拆解为带有依赖项（`Blocked by`）和验证命令（`Check`）的任务文件。 |
| `flow-implement` | 执行具体任务（Feature / Bugfix / Refactor / Spike） | 端到端完成单项任务：排查脏文件、实现代码、运行验证、文档更新与任务归档。 |
| `flow-verify` | 代码审查 / 提交前验收 | 调用 `workflow-reviewer` 代理，对完成的代码和交付过程进行双重审查。 |
| `flow-close` | 某项 Effort 的所有任务均已合并 | 对照 Spec 进行全量验收与功能演示，撰写复盘文档并标记 Spec 完成。 |
| `flow-architect` | 代码库存在技术债 / 变更阻力大 | 审计代码异味、重复逻辑、冗余封装与脆弱模块，记录技术债务。 |

---

## CLI 命令速查

可在安装了全局 CLI 的环境下运行 `workflow <command>`，或在已初始化的项目内直接调用提交的 `.workflow/bin/workflow <command>`。

### 日常调度与校验

- `workflow next [--format text|json]`
  分析当前任务依赖拓扑，按优先级输出最多 5 个可立即执行的就绪任务，同时展示处于暂停中（paused）或阻塞（blocked）状态的任务。
- `workflow validate [--strict] [--format text|json]`
  静态校验所有任务文件（`tasks/` 与 `done/`）、Spec（`specs/`）和决策记录（`decisions.md`）的语法与依赖完整性。
- `workflow doctor`
  全面诊断工作流安装健康状况，检查受管文件完整性、软链接安全、AGENTS 标记配对、术语表格式及任务依赖死锁。
- `workflow hook install|uninstall|status [--force]`
  管理 Git pre-commit 钩子，拦截存在校验错误的代码提交。
- `workflow version`
  显示当前工作流工具版本号。

### 项目维护命令

- `workflow init [--force] [--claude|--no-claude]`
  将工作流骨架、规则文档与 CLI 复制到当前项目。
- `workflow update [--force] [--claude|--no-claude]`
  在工具链版本升级后，重新同步受管技能、规则模板及项目内 CLI，保留用户自定义内容。
- `workflow uninstall`
  安全清理项目内的工作流受管文件，不损伤用户的业务代码与未清理的项目文档。

---

## 项目目录结构

在项目内运行 `workflow init` 后生成的布局如下（详见 §2）：

```
AGENTS.md                          # Agent 规则总入口（workflow 标记块）
.agents/
  skills/<name>/SKILL.md           # 9 个工作流技能实现步骤
  agents/workflow-reviewer.md      # 代码与规范审查 Agent Brief
.workflow/
  bin/workflow                     # 随项目提交的 CLI 入口（Bash 实现）
  bin/workflow-core.py             # 随项目提交的验证与队列引擎（Python 3 标准库）
  CONVENTIONS.md                   # 全套工作流规范守则
  STYLE.md                         # 交流与产出文本风格指引
  standards.md                     # 项目专用配置（构建/测试命令、代码布局、合入策略）
  glossary.md                      # 业务领域词汇表（Git union merge）
  decisions.md                     # 架构决策日志（Git union merge）
  technical-debt.md                # 架构设计与技术债务清单
  merge-strategy.md                # 分支、工作树与合入策略
  phase-boundaries.md              # 智能体上下文切换与阶段控制
  spike-tasks.md                   # 探索性任务指南
  specs/<effort>.md                # 具体 Effort 的规约文档
  tasks/<effort>/<NN>-<slug>.md    # 待执行任务卡片
  maps/<slug>.md                   # 迷茫区域长期探索地图
  done/<effort>/                   # 已完结任务与复盘报告归档
```

---

## 环境要求

- **操作系统**：POSIX 兼容环境（Linux / macOS）。
- **Shell**：Bash 3.2+（兼容 macOS 默认 Bash）。
- **Python**：Python 3.8+（仅需标准库，用于 `validate` 与 `next`）。
- **Git**：用于版本管理及路径解析。
- **Node.js**（可选）：Node.js 14+（仅使用全局 npm 安装分发包时需要）。

---

## 许可证

本项目依据 MIT 许可证开源。
