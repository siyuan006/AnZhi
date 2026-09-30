"""API 路由汇总。

main.py 只挂载这一个汇总路由；新增业务模块时在这里加一行 include_router，
避免把路由注册散落到 main.py 里（PROJECT_SPEC 第五十二节）。
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api import auth, chat, health, knowledge

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(knowledge.router)
api_router.include_router(chat.router)
api_router.include_router(auth.router)

# 后续阶段在此追加：
#   第十一阶段 api_router.include_router(favorite.router)    # 收藏
#   第十一阶段 api_router.include_router(history.router)     # 历史记录
#   第十二阶段 api_router.include_router(community.router)   # 社区
#   第十三阶段 api_router.include_router(settings.router)    # 个性化设置
