"""建表与种子数据。

用法：
    cd backend
    .venv\\Scripts\\python.exe -m app.database.init_db

可重复执行：已存在的分类不会重复插入。

注意：本模块**只写入六大分类**这类结构性数据。
知识卡片属于内容，必须走「AI 生成初稿 → 人工审核 → 发布」流程
（PROJECT_SPEC 第十五节），不在建库时自动灌入。
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

# 必须导入 models 包，Base.metadata 才会包含全部表定义
import app.models  # noqa: F401
from app.database.base import Base
from app.database.session import DATABASE_URL, SessionLocal, engine
from app.models.category import Category


@dataclass(frozen=True)
class CategorySeed:
    """一个分类的种子数据。"""

    id: int
    name: str
    slug: str
    icon: str
    color: str
    description: str
    sort_order: int


#: V1.0 固定六大分类（PROJECT_SPEC 第四节）。
#:
#: ⚠️ 这里的 id / name / slug / color 必须与
#:    frontend/lib/core/app_constants.dart 中的 `kCategories` 严格一致，
#:    否则前端按 id 过滤会取不到数据。tests 中有对应的一致性测试。
CATEGORY_SEEDS: tuple[CategorySeed, ...] = (
    CategorySeed(
        id=1,
        name="消防安全",
        slug="fire",
        icon="local_fire_department",
        color="#E53935",
        description="火灾预防、灭火器使用、火场逃生",
        sort_order=1,
    ),
    CategorySeed(
        id=2,
        name="用电安全",
        slug="electric",
        icon="bolt",
        color="#FB8C00",
        description="插座安全、电动车充电、触电急救",
        sort_order=2,
    ),
    CategorySeed(
        id=3,
        name="交通安全",
        slug="traffic",
        icon="directions_car",
        color="#1E88E5",
        description="行人、骑行、驾驶与事故处理",
        sort_order=3,
    ),
    CategorySeed(
        id=4,
        name="校园安全",
        slug="campus",
        icon="school",
        color="#43A047",
        description="宿舍、实验室、体育运动安全",
        sort_order=4,
    ),
    CategorySeed(
        id=5,
        name="网络与反诈安全",
        slug="cyber",
        icon="shield",
        color="#8E24AA",
        description="电信诈骗、钓鱼网站、隐私保护",
        sort_order=5,
    ),
    CategorySeed(
        id=6,
        name="自然灾害与应急",
        slug="disaster",
        icon="tsunami",
        color="#00897B",
        description="地震、洪水、台风与应急避险",
        sort_order=6,
    ),
)


def seed_categories(db: Session) -> int:
    """写入缺失的分类，返回本次新增的条数。

    以 `slug` 作为天然主键来判断是否已存在，因此可重复调用。
    """
    existing_slugs: set[str] = set(db.scalars(select(Category.slug)).all())

    added = 0
    for seed in CATEGORY_SEEDS:
        if seed.slug in existing_slugs:
            continue
        db.add(
            Category(
                id=seed.id,
                name=seed.name,
                slug=seed.slug,
                icon=seed.icon,
                color=seed.color,
                description=seed.description,
                sort_order=seed.sort_order,
            )
        )
        added += 1

    return added


def init_db() -> None:
    """建表并写入分类种子数据。可重复执行。"""
    from app.config.logging_config import setup_logging

    logger = setup_logging()

    logger.info("数据库地址：%s", DATABASE_URL)

    Base.metadata.create_all(bind=engine)
    logger.info("建表完成，共 %d 张表", len(Base.metadata.tables))

    with SessionLocal() as db:
        added = seed_categories(db)
        db.commit()
        total = db.scalar(select(func.count()).select_from(Category)) or 0

    if added:
        logger.info("新增分类 %d 个，当前共 %d 个", added, total)
    else:
        logger.info("分类已是最新，无需新增（共 %d 个）", total)


if __name__ == "__main__":
    init_db()
