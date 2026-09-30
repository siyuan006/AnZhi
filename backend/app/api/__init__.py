"""路由层：定义 URL 与请求 / 响应形状。

本层只做「解析请求 → 调用 service → 返回响应」，
不写业务规则，不直接操作数据库（docs/ARCHITECTURE.md 第 2 节）。
"""
