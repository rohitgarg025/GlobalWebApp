"""Project schedule: activities, FS links, calendar-day finish dates."""
from __future__ import annotations

import re
from collections import defaultdict, deque
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.db.models import PmActivity, PmActivityLink, PmCodeCounter, QsFloor
from app.services.project_service import get_project, require_active_project


def _d(value: date | str) -> date:
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value)[:10])


def _iso(d: date | None) -> str | None:
    return d.isoformat() if d else None


def _finish(start: date, duration_days: int) -> date:
    return start + timedelta(days=duration_days - 1)


ROW_TYPES = ("activity", "group")


def _activity_dict(
    a: PmActivity,
    predecessor_id: int | None,
    lag_days: int,
    floor_name: str | None = None,
) -> dict:
    return {
        "id": a.id,
        "project_id": a.project_id,
        "name": a.name,
        "code": a.code,
        "duration_days": a.duration_days,
        "start_date": _iso(a.start_date),
        "finish_date": _iso(a.finish_date),
        "start_mode": a.start_mode,
        "quantity": a.quantity,
        "unit": a.unit,
        "sort_order": a.sort_order,
        "predecessor_id": predecessor_id,
        "lag_days": lag_days,
        "created_by": a.created_by,
        "row_type": a.row_type or "activity",
        "parent_id": a.parent_id,
        "floor_id": a.floor_id,
        "floor_name": floor_name,
    }


def _floor_names(db: Session, project_id: int) -> dict[int, str]:
    return {f.id: f.name for f in db.query(QsFloor).filter_by(project_id=project_id).all()}


def _single_dict(db: Session, act: PmActivity) -> dict:
    link = _links_by_successor(db, act.project_id).get(act.id)
    floor = db.query(QsFloor).filter_by(id=act.floor_id).first() if act.floor_id else None
    return _activity_dict(
        act,
        link.predecessor_id if link else None,
        link.lag_days if link else 0,
        floor.name if floor else None,
    )


def _links_by_successor(db: Session, project_id: int) -> dict[int, PmActivityLink]:
    rows = db.query(PmActivityLink).filter_by(project_id=project_id).all()
    by_succ: dict[int, PmActivityLink] = {}
    for link in rows:
        by_succ[link.successor_id] = link
    return by_succ


def get_schedule(db: Session, project_id: int) -> dict:
    proj = get_project(db, project_id)
    activities = (
        db.query(PmActivity)
        .filter_by(project_id=project_id)
        .order_by(PmActivity.sort_order, PmActivity.id)
        .all()
    )
    links = _links_by_successor(db, project_id)
    floors = _floor_names(db, project_id)
    return {
        "project": {
            "id": proj.id,
            "name": proj.name,
            "code": proj.code,
            "status": proj.status,
        },
        "activities": [
            _activity_dict(
                a,
                links[a.id].predecessor_id if a.id in links else None,
                links[a.id].lag_days if a.id in links else 0,
                floors.get(a.floor_id) if a.floor_id else None,
            )
            for a in activities
        ],
    }


def _would_cycle(db: Session, project_id: int, successor_id: int, predecessor_id: int) -> bool:
    """True if predecessor is reachable from successor (would close a loop)."""
    if successor_id == predecessor_id:
        return True
    outgoing = defaultdict(list)
    for link in db.query(PmActivityLink).filter_by(project_id=project_id).all():
        outgoing[link.predecessor_id].append(link.successor_id)
    seen = set()
    stack = [successor_id]
    while stack:
        node = stack.pop()
        if node == predecessor_id:
            return True
        if node in seen:
            continue
        seen.add(node)
        stack.extend(outgoing.get(node, []))
    return False


def _recalculate(db: Session, project_id: int) -> None:
    activities = {
        a.id: a
        for a in db.query(PmActivity).filter_by(project_id=project_id).all()
    }
    if not activities:
        return
    links = db.query(PmActivityLink).filter_by(project_id=project_id).all()
    preds: dict[int, list[PmActivityLink]] = defaultdict(list)
    succ_count: dict[int, int] = {aid: 0 for aid in activities}
    for link in links:
        if link.successor_id not in activities or link.predecessor_id not in activities:
            continue
        preds[link.successor_id].append(link)
        succ_count[link.successor_id] = succ_count.get(link.successor_id, 0) + 1
        succ_count.setdefault(link.predecessor_id, 0)

    incoming = {aid: 0 for aid in activities}
    outgoing = defaultdict(list)
    for link in links:
        if link.successor_id not in activities or link.predecessor_id not in activities:
            continue
        incoming[link.successor_id] += 1
        outgoing[link.predecessor_id].append(link.successor_id)

    queue = deque([aid for aid, n in incoming.items() if n == 0])
    order: list[int] = []
    while queue:
        aid = queue.popleft()
        order.append(aid)
        for nxt in outgoing[aid]:
            incoming[nxt] -= 1
            if incoming[nxt] == 0:
                queue.append(nxt)
    if len(order) != len(activities):
        raise HTTPException(400, "Circular dependency in schedule")

    for aid in order:
        act = activities[aid]
        act.finish_date = _finish(act.start_date, act.duration_days)
        if act.start_mode != "auto":
            continue
        starts: list[date] = []
        for link in preds.get(aid, []):
            pred = activities[link.predecessor_id]
            pred.finish_date = _finish(pred.start_date, pred.duration_days)
            starts.append(pred.finish_date + timedelta(days=1 + (link.lag_days or 0)))
        if starts:
            act.start_date = max(starts)
            act.finish_date = _finish(act.start_date, act.duration_days)

    _roll_up_groups(activities)


def _depth(activities: dict[int, PmActivity], aid: int) -> int:
    depth = 0
    node = activities[aid]
    while node.parent_id and node.parent_id in activities and depth < len(activities):
        depth += 1
        node = activities[node.parent_id]
    return depth


def _roll_up_groups(activities: dict[int, PmActivity]) -> None:
    """Group start/finish span their children, like MS Project summary tasks."""
    children: dict[int, list[PmActivity]] = defaultdict(list)
    for a in activities.values():
        if a.parent_id in activities:
            children[a.parent_id].append(a)
    groups = [a for a in activities.values() if a.row_type == "group"]
    # Deepest first so nested groups are settled before their parents.
    groups.sort(key=lambda g: _depth(activities, g.id), reverse=True)
    dated: set[int] = set()  # groups that contain at least one activity
    for g in groups:
        # Empty sub-groups only hold placeholder dates; don't let them stretch the parent.
        kids = [
            k for k in children.get(g.id, [])
            if k.row_type != "group" or k.id in dated
        ]
        if not kids:
            continue
        dated.add(g.id)
        g.start_date = min(k.start_date for k in kids)
        g.finish_date = max(k.finish_date for k in kids)
        g.duration_days = (g.finish_date - g.start_date).days + 1


def _validate_complete(
    row_type: str,
    name: str,
    duration_days: int | None,
    start_date,
    floor_id: int | None,
    predecessor_id: int | None,
) -> None:
    errors = []
    if row_type not in ROW_TYPES:
        errors.append("Type must be activity or group")
    if not (name or "").strip():
        errors.append("Name is required")
    if row_type == "activity":
        if duration_days is None or duration_days < 1:
            errors.append("Days must be an integer of at least 1")
        if start_date is None:
            errors.append("Start date is required")
        if floor_id is None:
            errors.append("Floor is required")
    elif predecessor_id:
        errors.append("A group cannot have a predecessor")
    if errors:
        raise HTTPException(status_code=422, detail={"errors": errors})


def _validate_floor(db: Session, project_id: int, floor_id: int) -> None:
    if not db.query(QsFloor).filter_by(id=floor_id, project_id=project_id).first():
        raise HTTPException(400, "Floor not found on this project")


def _validate_parent(db: Session, project_id: int, act_id: int | None, parent_id: int) -> None:
    parent = db.query(PmActivity).filter_by(id=parent_id, project_id=project_id).first()
    if not parent:
        raise HTTPException(400, "Parent group not found on this project")
    if parent.row_type != "group":
        raise HTTPException(400, "Rows can only be placed inside a group")
    # Walk up from the new parent: hitting act_id means we'd nest a group inside itself.
    node, seen = parent, set()
    while node is not None and node.id not in seen:
        if node.id == act_id:
            raise HTTPException(400, "A group cannot be placed inside itself")
        seen.add(node.id)
        node = (
            db.query(PmActivity).filter_by(id=node.parent_id).first()
            if node.parent_id else None
        )


CODE_PREFIX = {"activity": "A", "group": "G"}


def _next_code(db: Session, project_id: int, row_type: str) -> str:
    """Next system COD for the project: A001, A002… / G001… Never reused.

    The counter starts from the highest existing code with that prefix, so
    projects with older hand-typed codes continue without collisions."""
    prefix = CODE_PREFIX[row_type]
    counter = db.query(PmCodeCounter).filter_by(project_id=project_id, prefix=prefix).first()
    if counter is None:
        highest = 0
        pattern = re.compile(rf"^{prefix}(\d+)$")
        for (code,) in db.query(PmActivity.code).filter_by(project_id=project_id):
            m = pattern.match(code or "")
            if m:
                highest = max(highest, int(m.group(1)))
        counter = PmCodeCounter(project_id=project_id, prefix=prefix, last_number=highest)
        db.add(counter)
    taken = {c for (c,) in db.query(PmActivity.code).filter_by(project_id=project_id)}
    n = counter.last_number
    while True:
        n += 1
        code = f"{prefix}{n:03d}"
        if code not in taken:  # skip any legacy hand-typed code that matches
            break
    counter.last_number = n
    return code


def _next_sort_order(db: Session, project_id: int) -> int:
    last = (
        db.query(PmActivity)
        .filter_by(project_id=project_id)
        .order_by(PmActivity.sort_order.desc())
        .first()
    )
    return (last.sort_order + 1) if last else 0


def create_activity(
    db: Session,
    project_id: int,
    name: str,
    duration_days: int | None,
    start_date: date | str | None,
    predecessor_id: int | None,
    lag_days: int,
    quantity: float | None,
    unit: str | None,
    created_by: str | None,
    row_type: str = "activity",
    parent_id: int | None = None,
    floor_id: int | None = None,
) -> dict:
    require_active_project(db, project_id)
    name = (name or "").strip()
    _validate_complete(row_type, name, duration_days, start_date, floor_id, predecessor_id)
    if parent_id:
        _validate_parent(db, project_id, None, parent_id)
    is_group = row_type == "group"
    if floor_id and not is_group:
        _validate_floor(db, project_id, floor_id)

    # Groups get placeholder dates until children roll up into them.
    start = _d(start_date) if start_date else date.today()
    if is_group:
        duration_days = 1
        quantity = unit = floor_id = None
    start_mode = "auto" if predecessor_id else "manual"
    act = PmActivity(
        project_id=project_id,
        name=name,
        code=_next_code(db, project_id, row_type),
        duration_days=duration_days,
        start_date=start,
        finish_date=_finish(start, duration_days),
        start_mode=start_mode,
        quantity=quantity,
        unit=(unit or "").strip() or None,
        sort_order=_next_sort_order(db, project_id),
        created_by=created_by,
        row_type=row_type,
        parent_id=parent_id,
        floor_id=floor_id,
    )
    db.add(act)
    db.flush()
    if predecessor_id:
        _set_predecessor(db, project_id, act.id, predecessor_id, lag_days)
    _recalculate(db, project_id)
    db.commit()
    db.refresh(act)
    return _single_dict(db, act)


def _set_predecessor(
    db: Session,
    project_id: int,
    successor_id: int,
    predecessor_id: int | None,
    lag_days: int,
) -> None:
    db.query(PmActivityLink).filter_by(successor_id=successor_id).delete()
    if not predecessor_id:
        return
    pred = db.query(PmActivity).filter_by(id=predecessor_id, project_id=project_id).first()
    if not pred:
        raise HTTPException(400, "Predecessor activity not found on this project")
    if _would_cycle(db, project_id, successor_id, predecessor_id):
        raise HTTPException(400, "That dependency would create a cycle")
    db.add(PmActivityLink(
        project_id=project_id,
        predecessor_id=predecessor_id,
        successor_id=successor_id,
        link_type="FS",
        lag_days=lag_days or 0,
    ))
    db.flush()  # session has autoflush off; _recalculate must see this link


def update_activity(
    db: Session,
    activity_id: int,
    name: str | None = None,
    duration_days: int | None = None,
    start_date: date | str | None = None,
    start_mode: str | None = None,
    predecessor_id: int | None = None,
    lag_days: int | None = None,
    quantity: float | None = None,
    unit: str | None = None,
    clear_predecessor: bool = False,
    clear_quantity: bool = False,
    parent_id: int | None = None,
    clear_parent: bool = False,
    floor_id: int | None = None,
) -> dict:
    act = db.query(PmActivity).filter_by(id=activity_id).first()
    if not act:
        raise HTTPException(404, "Activity not found")
    require_active_project(db, act.project_id)
    is_group = act.row_type == "group"
    if clear_parent:
        act.parent_id = None
    elif parent_id is not None:
        _validate_parent(db, act.project_id, act.id, parent_id)
        act.parent_id = parent_id
    if floor_id is not None and not is_group:
        _validate_floor(db, act.project_id, floor_id)
        act.floor_id = floor_id
    if is_group and predecessor_id is not None:
        raise HTTPException(422, "A group cannot have a predecessor")
    if name is not None:
        if not name.strip():
            raise HTTPException(422, "Activity name is required")
        act.name = name.strip()
    if duration_days is not None:
        if duration_days < 1:
            raise HTTPException(422, "Days must be an integer of at least 1")
        act.duration_days = duration_days
    if start_date is not None:
        act.start_date = _d(start_date)
        act.start_mode = "manual"
    if start_mode is not None:
        if start_mode not in ("auto", "manual"):
            raise HTTPException(422, "start_mode must be auto or manual")
        act.start_mode = start_mode
    if quantity is not None:
        act.quantity = quantity
    elif clear_quantity:
        act.quantity = None
    if unit is not None:
        act.unit = unit.strip() or None
    if clear_predecessor:
        _set_predecessor(db, act.project_id, act.id, None, 0)
        act.start_mode = "manual"
    elif predecessor_id is not None:
        _set_predecessor(db, act.project_id, act.id, predecessor_id, lag_days or 0)
        act.start_mode = "auto"
    elif lag_days is not None:
        link = db.query(PmActivityLink).filter_by(successor_id=act.id).first()
        if link:
            link.lag_days = lag_days
    act.updated_at = datetime.utcnow()
    _recalculate(db, act.project_id)
    db.commit()
    db.refresh(act)
    return _single_dict(db, act)


def delete_activity(db: Session, activity_id: int) -> None:
    act = db.query(PmActivity).filter_by(id=activity_id).first()
    if not act:
        raise HTTPException(404, "Activity not found")
    if db.query(PmActivity).filter_by(parent_id=activity_id).first():
        raise HTTPException(409, "Move or delete the rows inside this group first.")
    if db.query(PmActivityLink).filter_by(predecessor_id=activity_id).first():
        raise HTTPException(409, "Other activities depend on this one. Remove those links first.")
    db.query(PmActivityLink).filter_by(successor_id=activity_id).delete()
    project_id = act.project_id
    db.delete(act)
    db.flush()
    _recalculate(db, project_id)
    db.commit()


def reorder_activities(db: Session, project_id: int, activity_ids: list[int]) -> dict:
    """Set the order of rows that share one parent (the tree orders siblings only)."""
    require_active_project(db, project_id)
    rows = (
        db.query(PmActivity)
        .filter(PmActivity.project_id == project_id, PmActivity.id.in_(activity_ids))
        .all()
    )
    if len({r.parent_id for r in rows}) > 1:
        raise HTTPException(400, "Rows can only be reordered within the same group")
    by_id = {r.id: r for r in rows}
    for order, aid in enumerate(activity_ids):
        if aid in by_id:
            by_id[aid].sort_order = order
    db.commit()
    return get_schedule(db, project_id)


def activity_options(db: Session, project_id: int) -> list[dict]:
    get_project(db, project_id)
    rows = (
        db.query(PmActivity)
        .filter_by(project_id=project_id)
        .order_by(PmActivity.sort_order, PmActivity.id)
        .all()
    )
    return [{"id": a.id, "name": a.name, "code": a.code} for a in rows]
