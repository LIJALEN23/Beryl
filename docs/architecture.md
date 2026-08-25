# IM + Local Agent + Cloud Agent 架构

## 1. 总体架构

``` mermaid
flowchart TB
    subgraph ACCESS["用户入口层 User Access Layer"]
        PC["PC<br/>IM Desktop App + Local Agent"]
        MOBILE["移动设备<br/>iOS / Android<br/>IM Mobile App"]
        WEB["Web<br/>IM Web App"]
    end

    subgraph LOCAL["用户本地环境"]
        LA["Local Agent"]
        FS["Local Files / Code / Tools"]
        SESSION_L["Local Sessions"]
        WS["Workspace<br/>Folder"]
        LA --> FS
        LA --> SESSION_L
        SESSION_L --> WS
    end

    subgraph SERVER["IM Server / Backend"]
        GW["Gateway Layer<br/>MTProto / WebSocket / Agent Gateway"]

        subgraph CORE["Core Services"]
            ACCOUNT["Account Service"]
            SESSION["Session Service"]
            MSG["Message Service"]
            GROUP["Group Service"]
            NOTIFY["Notification Service"]
            AGENT["Agent Service"]
            TASK["Task Scheduler"]
            PERM["Permission Service"]
            FILE["File Service"]
        end

        EVENT["Event Bus<br/>Kafka"]
        DATA["Data Access Layer<br/>MySQL / ScyllaDB / Redis / MinIO"]

        AM["Agent Connection Management<br/>Local Agent / Cloud Agent"]
    end

    subgraph CLOUD["Cloud Agent Pool"]
        CA1["Cloud Agent<br/>Session-based"]
        CA2["Cloud Agent<br/>Session-based"]
        CAN["Cloud Agent<br/>..."]
    end

    subgraph SESSIONMODEL["Session-centric Model"]
        USER["User"]
        S["Session"]
        AG["Agent"]
        WORK["Workspace / Folder<br/>Context + Files + Conversation History"]
        USER --> S
        S --> AG
        S <--> WORK
    end

    subgraph GROUPMODEL["Group Collaboration"]
        G["Group"]
        MEMBERS["Human Members"]
        AGENTS["Agent Members<br/>Local / Cloud"]
        G --> MEMBERS
        G --> AGENTS
    end

    PC <--> GW
    MOBILE <--> GW
    WEB <--> GW

    PC <--> LA
    LA <-->|"Authenticated persistent connection"| AM
    AM <--> CA1
    AM <--> CA2
    AM <--> CAN

    GW --> CORE
    CORE --> EVENT
    EVENT --> DATA

    SESSION --> SESSIONMODEL
    AGENT --> SESSIONMODEL
    GROUP --> GROUPMODEL
    GROUPMODEL -->|"@Agent"| AGENT

    GROUPMODEL -. "drive once" .-> TASK
    TASK --> AGENT
```

------------------------------------------------------------------------

## 2. 核心抽象：Session

整个系统最重要的抽象不是单纯的 `Conversation`，而是 **Session**。

``` text
User
 └── Session
      ├── Agent
      │    ├── Local Agent
      │    └── Cloud Agent
      │
      └── Workspace
           ├── Folder
           ├── Files
           ├── Conversation History
           ├── Task Context
           └── Session State
```

一个 Session 可以理解为：

> **一个用户与某个 Agent 围绕一个 Workspace / Task
> 持续工作的上下文单元。**

因此，IM App 最终展示的核心对象可以从传统的：

``` text
Conversation
```

升级为：

``` text
Session
```

Session 内部同时拥有：

-   对话历史
-   Agent 状态
-   Workspace / Folder
-   文件
-   任务状态
-   Agent 执行记录
-   权限与成员关系

------------------------------------------------------------------------

## 3. Local Agent

Local Agent 运行在用户 PC 上，拥有本地环境能力：

``` text
Local Agent
├── File System Access
├── Code Execution
├── Local Knowledge
├── Application Integration
├── Local Tools
└── Session Management
    ├── Session List
    ├── Workspace / Folder
    └── Session State
```

它与 IM Server 建立长期连接。

因此：

``` text
PC
│
├── IM Desktop App
│
└── Local Agent
      │
      │ persistent connection
      ▼
   IM Server
```

IM App 负责用户交互，而 Local Agent 负责真正进入本地计算环境。

------------------------------------------------------------------------

## 4. Cloud Agent

Cloud Agent 是轻量级、短任务导向的 Agent。

它不需要访问用户 PC，可以运行在服务器侧的 Agent Pool：

``` text
Cloud Agent Pool
├── Cloud Agent #1
├── Cloud Agent #2
├── Cloud Agent #3
└── ...
```

Cloud Agent 同样采用 **Session-based** 模型：

``` text
Session
   │
   └── Cloud Agent
          │
          ├── Task
          ├── Context
          └── Result
```

因此 Local Agent 与 Cloud Agent 在产品模型上可以保持一致。

差异主要在执行环境：

             Local Agent          Cloud Agent
  ---------- -------------------- ------------------
  执行位置   用户 PC              Cloud
  文件访问   本地 Workspace       Cloud Workspace
  长任务     强                   中
  本地工具   强                   弱
  轻量任务   可以                 非常适合
  网络依赖   与 Server 保持连接   Server 内部
  成本       用户承担计算资源     平台承担计算资源

------------------------------------------------------------------------

## 5. Group + Agent

Group 不再只包含人，也可以包含 Agent。

``` text
Group
├── User A
├── User B
├── User C
├── Local Agent
└── Cloud Agent
```

用户可以：

``` text
@LocalAgent
```

或者：

``` text
@CloudAgent
```

来驱动 Agent。

例如：

``` text
User A:
@LocalAgent 帮我检查这个项目的代码

Local Agent:
正在执行...

User B:
@CloudAgent 总结一下这个项目的 README

Cloud Agent:
执行完成。
```

这样 Group 就同时成为：

> **IM + Human Collaboration + Agent Collaboration**

------------------------------------------------------------------------

## 6. 一次 @ 只允许驱动一次

Agent 应当具有明确的运行状态：

``` text
IDLE
  │
  │ @Agent
  ▼
RUNNING
  │
  │ completed
  ▼
IDLE
```

如果 Agent 已经处于：

``` text
RUNNING
```

再次：

``` text
@Agent
```

则不能创建第二个并发任务，而应该表现为：

``` text
BUSY
```

即：

``` text
@Agent
   │
   ▼
┌─────────────┐
│ Agent       │
│ RUNNING     │
└─────────────┘
       │
       │ another @
       ▼
    BUSY
```

这实际上形成了一个非常简单的 **Agent Execution State Machine**：

``` text
IDLE
 ↓ @mention
RUNNING
 ↓ success / failure / cancellation
IDLE
```

------------------------------------------------------------------------

## 7. ToC Chat 与协同办公

这个架构比较有价值的一点，是它不需要为 ToC 和协同办公建立两套完全不同的
Agent 产品。

### ToC

``` text
User
  │
  ▼
Session
  │
  └── Cloud Agent
```

典型场景：

-   个人 AI 助手
-   知识问答
-   文件总结
-   内容生成
-   轻量任务执行

### 协同办公

``` text
Group
├── User A
├── User B
├── User C
├── Local Agent
└── Cloud Agent
```

典型场景：

-   项目管理
-   团队协作
-   代码协作
-   文件处理
-   自动化任务
-   Agent 辅助决策

所以二者实际上共享同一套底层模型：

``` text
IM
 │
 └── Session
       │
       └── Agent
             ├── Local
             └── Cloud
```

区别主要只是 **Session 所处的上下文**：

``` text
ToC
User → Session → Agent

Collaboration
Group → Session / Task → Agent
```

------------------------------------------------------------------------

## 8. 推荐的系统分层

``` text
┌───────────────────────────────────────────────┐
│              User Access Layer                │
│                                               │
│   PC + Local Agent   Mobile   Web             │
└───────────────────────┬───────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────┐
│                 Gateway Layer                 │
│                                               │
│ MTProto Gateway / WebSocket / Agent Gateway   │
└───────────────────────┬───────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────┐
│                  Core Services                │
│                                               │
│ Account / Session / Message / Group           │
│ Agent / Task / Permission / File / Notify     │
└───────────────────────┬───────────────────────┘
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
       Event Bus              Agent Layer
         Kafka              ┌─────────────┐
              │             │ Local Agent │
              ▼             │ Cloud Agent │
        Data Layer          └─────────────┘
```

------------------------------------------------------------------------

## 9. 最关键的产品模型

最终可以把整个系统压缩成四个核心对象：

``` text
User
  │
  ▼
Session
  │
  ├── Workspace
  │
  ├── Conversation
  │
  └── Agent
       ├── Local Agent
       └── Cloud Agent
```

然后把 Group 作为多人协作容器：

``` text
Group
├── Users
└── Agents
     ├── Local Agents
     └── Cloud Agents
```

因此整个产品的核心可以概括成：

> **An IM system where Users and Agents are first-class participants,
> and Session is the fundamental unit of context, workspace, and
> execution.**

这比单纯在传统 IM 上"外挂一个 AI Chat"更统一：**IM 负责连接人与
Agent，Session 负责承载上下文与工作，Local/Cloud Agent 负责执行，Group
负责多人 + 多 Agent 协作。**
