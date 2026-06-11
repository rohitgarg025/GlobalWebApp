from datetime import datetime

from sqlalchemy import (
    Column, Integer, String, Float, DateTime, ForeignKey, Text, UniqueConstraint,
)

from app.db.database import Base


class QsProject(Base):
    __tablename__ = "qs_projects"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class QsActivity(Base):
    __tablename__ = "qs_activities"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False, unique=True)
    unit = Column(String, nullable=False)  # e.g. CUM, SQM, RMT, NOS


class QsFloor(Base):
    __tablename__ = "qs_floors"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("qs_projects.id"), nullable=False)
    name = Column(String, nullable=False)  # e.g. B2, B1, GF, FF, RF
    display_order = Column(Integer, nullable=False, default=0)
    __table_args__ = (UniqueConstraint("project_id", "name"),)


class QsBaseline(Base):
    """Locked GFC Drawing quantity per (project, activity, floor).
    Created on first submission; subsequent changes are logged."""
    __tablename__ = "qs_baselines"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("qs_projects.id"), nullable=False)
    activity_id = Column(Integer, ForeignKey("qs_activities.id"), nullable=False)
    floor_id = Column(Integer, ForeignKey("qs_floors.id"), nullable=False)
    total_estimated_qty = Column(Float, nullable=False)
    locked_by = Column(String)
    locked_at = Column(DateTime, default=datetime.utcnow)
    __table_args__ = (UniqueConstraint("project_id", "activity_id", "floor_id"),)


class QsMonthlyEntry(Base):
    """Monthly progress data per (project, activity, floor, month)."""
    __tablename__ = "qs_monthly_entries"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("qs_projects.id"), nullable=False)
    activity_id = Column(Integer, ForeignKey("qs_activities.id"), nullable=False)
    floor_id = Column(Integer, ForeignKey("qs_floors.id"), nullable=False)
    month = Column(String, nullable=False)  # YYYY-MM
    estimate_actual_qty_till_date = Column(Float, nullable=False)
    actual_qty = Column(Float, nullable=False)
    justification = Column(Text)
    submitted_by = Column(String)
    submitted_at = Column(DateTime, default=datetime.utcnow)
    __table_args__ = (UniqueConstraint("project_id", "activity_id", "floor_id", "month"),)


class QsBaselineChangeLog(Base):
    """Audit trail when total_estimated_qty is changed after locking."""
    __tablename__ = "qs_baseline_changes"
    id = Column(Integer, primary_key=True)
    baseline_id = Column(Integer, ForeignKey("qs_baselines.id"), nullable=False)
    old_value = Column(Float, nullable=False)
    new_value = Column(Float, nullable=False)
    reason = Column(Text, nullable=False)
    changed_by = Column(String)
    changed_at = Column(DateTime, default=datetime.utcnow)
