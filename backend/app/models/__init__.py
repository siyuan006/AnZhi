"""数据库模型层：SQLAlchemy 表结构定义与关系。

本层只描述表结构与索引，不做业务判断。

建表进度（PROJECT_SPEC 第三十三节，**不要一次性建完**）：

    第 1 批（阶段 6-1）✅  User / Category / Knowledge
    第 2 批（阶段 6-2）⬜  Favorite / History
    第 3 批（阶段 6-3）⬜  Post / Comment / Like / UserSettings

用一个地方集中导入所有模型，保证 `Base.metadata` 拿到完整的表定义 ——
`create_all` 只能看到已经被导入的模型。
"""

from app.models.category import Category
from app.models.knowledge import Knowledge, RISK_LEVELS
from app.models.user import User

__all__ = ["Category", "Knowledge", "RISK_LEVELS", "User"]
