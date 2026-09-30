"""AI 服务子包。

按 docs/ARCHITECTURE.md 第 4 节的演进路线渐进式实现，
**未实现的模块必须明确标注，不能留下看似可用的空壳**：

    chat_service.py    调用 DeepSeek 生成结构化回答   —— 第八阶段实现
    safety_guard.py    回答安全审查（三级风险策略）     —— 第九阶段实现

    agent_service.py   问题分类                        —— V2.0
    risk_service.py    风险等级判断                    —— V2.0
    rag_service.py     知识库检索增强                  —— V2.0（第十四阶段）

V1.0（第八阶段）只实现 ChatService。
"""
