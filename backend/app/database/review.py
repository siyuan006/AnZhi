"""知识内容审核命令。

这是「AI 生成初稿 → 人工审核 → 发布」流程的执行工具。
导入的初稿 `is_published` 一律为 False，只有通过本命令显式发布，
内容才会出现在 `GET /api/knowledge` 的返回里。

用法：
    cd backend

    # 1. 导入初稿（未发布状态）
    .venv\\Scripts\\python.exe -m app.database.review --import-drafts

    # 2. 查看待审核内容
    .venv\\Scripts\\python.exe -m app.database.review --list-pending

    # 3. 审核后发布（按 id）
    .venv\\Scripts\\python.exe -m app.database.review --publish 1,2,3

    # 4. 发现内容有问题时撤回
    .venv\\Scripts\\python.exe -m app.database.review --unpublish 2

发布前请逐条确认内容正确、且不含任何可能导致伤害的操作。

各函数都接收 Session 参数（而不是内部打开全局会话），
这样测试可以直接传临时库的会话进来。
"""

from __future__ import annotations

import argparse
import sys

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config.logging_config import setup_logging
from app.database.knowledge_drafts import DRAFT_KNOWLEDGE
from app.database.session import SessionLocal
from app.models import Category, Knowledge

logger = setup_logging()

RISK_MARK = {"low": "🟢", "medium": "🟡", "high": "🔴"}


def import_drafts(db: Session) -> int:
    """导入尚未存在的初稿，返回新增条数。

    以 `title` 判断是否已存在，因此可重复执行。
    **导入的条目一律为未发布状态。**
    """
    existing_titles = set(db.scalars(select(Knowledge.title)).all())

    added = 0
    for draft in DRAFT_KNOWLEDGE:
        if draft.title in existing_titles:
            continue
        db.add(
            Knowledge(
                title=draft.title,
                category_id=draft.category_id,
                summary=draft.summary,
                content=draft.content,
                risk_level=draft.risk_level,
                # 关键：导入时不发布
                is_published=False,
            )
        )
        added += 1

    db.commit()

    logger.info(
        "导入完成：新增 %d 条，跳过已存在 %d 条",
        added,
        len(DRAFT_KNOWLEDGE) - added,
    )
    if added:
        logger.info("这些内容当前**未发布**，审核后执行 --publish 才会对外可见")
    return added


def set_published(db: Session, ids: list[int], published: bool) -> int:
    """发布 / 撤回指定条目，返回实际改动的条数。"""
    targets = list(
        db.scalars(select(Knowledge).where(Knowledge.id.in_(ids)).order_by(Knowledge.id)).all()
    )

    missing = set(ids) - {item.id for item in targets}
    if missing:
        logger.warning("以下 id 不存在，已跳过：%s", sorted(missing))

    changed = 0
    for item in targets:
        if item.is_published != published:
            item.is_published = published
            changed += 1
    db.commit()

    action = "发布" if published else "撤回"
    logger.info("%s完成：%d 条", action, changed)

    # 发布时提示补来源：source 为空意味着无法追溯内容依据
    if published:
        without_source = [item.id for item in targets if not item.source]
        if without_source:
            logger.warning(
                "注意：id %s 的 source 字段为空，建议补充权威出处后再对外发布",
                without_source,
            )

    return changed


def list_items(db: Session, only_unpublished: bool = False) -> int:
    """列出知识条目及其发布状态，返回列出的条数。"""
    stmt = select(Knowledge).order_by(Knowledge.id)
    if only_unpublished:
        stmt = stmt.where(Knowledge.is_published.is_(False))

    items = list(db.scalars(stmt).all())
    categories = {c.id: c.name for c in db.scalars(select(Category)).all()}

    if not items:
        print("（没有符合条件的知识条目）")
        return 0

    print(f"{'ID':>4}  {'状态':<6} {'风险':<3} {'分类':<14} 标题")
    print("-" * 78)
    for item in items:
        state = "已发布" if item.is_published else "待审核"
        risk = RISK_MARK.get(item.risk_level, "??")
        category = categories.get(item.category_id, "未分类")
        print(f"{item.id:>4}  {state:<6} {risk:<3} {category:<14} {item.title}")

    unpublished = sum(1 for item in items if not item.is_published)
    print("-" * 78)
    print(f"共 {len(items)} 条，其中待审核 {unpublished} 条")
    return len(items)


def available_ids(db: Session) -> list[int]:
    return list(db.scalars(select(Knowledge.id).order_by(Knowledge.id)).all())


def parse_ids(raw: str, db: Session) -> list[int]:
    """解析 `--publish` 的参数，支持 `1,2,3` 与 `all`。"""
    if raw.strip().lower() == "all":
        return available_ids(db)

    ids: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        if not part.isdigit():
            raise ValueError(f"id 必须是整数，收到：{part!r}")
        ids.append(int(part))
    return ids


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.database.review",
        description="安知 —— 知识内容审核工具（AI 初稿 → 人工审核 → 发布）",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--import-drafts", action="store_true", help="导入初稿（未发布状态）"
    )
    group.add_argument("--list", action="store_true", help="列出全部知识条目")
    group.add_argument("--list-pending", action="store_true", help="只列出待审核条目")
    group.add_argument("--publish", metavar="IDS", help="发布指定 id，如 1,2,3 或 all")
    group.add_argument("--unpublish", metavar="IDS", help="撤回指定 id")

    args = parser.parse_args(argv)

    with SessionLocal() as db:
        if args.import_drafts:
            import_drafts(db)
        elif args.list:
            list_items(db)
        elif args.list_pending:
            list_items(db, only_unpublished=True)
        elif args.publish is not None:
            try:
                set_published(db, parse_ids(args.publish, db), published=True)
            except ValueError as exc:
                logger.error("%s", exc)
                return 2
        elif args.unpublish is not None:
            try:
                set_published(db, parse_ids(args.unpublish, db), published=False)
            except ValueError as exc:
                logger.error("%s", exc)
                return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
