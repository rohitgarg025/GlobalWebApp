from datetime import datetime, date

from sqlalchemy import (
    Column, Integer, String, Float, DateTime, Date, ForeignKey, Text,
    UniqueConstraint, Boolean,
)

from app.db.database import Base


class AuthRole(Base):
    """A role is a named set of accessible module ids (JSON-encoded list)."""
    __tablename__ = "auth_roles"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False, unique=True)
    modules = Column(Text, nullable=False, default="[]")  # JSON list[str]
    is_system = Column(Boolean, nullable=False, default=False)


class AuthUser(Base):
    __tablename__ = "auth_users"
    id = Column(Integer, primary_key=True)
    email = Column(String, nullable=False, unique=True)  # lowercase
    display_name = Column(String)
    picture_url = Column(String)
    role_id = Column(Integer, ForeignKey("auth_roles.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_login_at = Column(DateTime)


class Project(Base):
    """Company-wide project master. Created by admins only."""
    __tablename__ = "projects"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False, unique=True)
    code = Column(String)
    location = Column(String)
    client_name = Column(String)
    status = Column(String, nullable=False, default="active")  # active | archived
    created_at = Column(DateTime, default=datetime.utcnow)
    created_by = Column(String)


class QsActivity(Base):
    __tablename__ = "qs_activities"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False, unique=True)
    unit = Column(String, nullable=False)  # e.g. CUM, SQM, RMT, NOS


class QsFloor(Base):
    __tablename__ = "qs_floors"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
    name = Column(String, nullable=False)  # e.g. B2, B1, GF, FF, RF
    display_order = Column(Integer, nullable=False, default=0)
    __table_args__ = (UniqueConstraint("project_id", "name"),)


class QsBaseline(Base):
    """Locked GFC Drawing quantity per (project, activity, floor).
    Created on first submission; subsequent changes are logged."""
    __tablename__ = "qs_baselines"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
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
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
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


class PmActivity(Base):
    """A scheduled task on a project (not the QS quantity catalogue)."""
    __tablename__ = "pm_activities"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
    name = Column(String, nullable=False)
    code = Column(String, nullable=False)
    duration_days = Column(Integer, nullable=False)
    start_date = Column(Date, nullable=False)
    finish_date = Column(Date, nullable=False)
    start_mode = Column(String, nullable=False, default="manual")  # auto | manual
    row_type = Column(String, nullable=False, default="activity")  # activity | group
    parent_id = Column(Integer, ForeignKey("pm_activities.id"), nullable=True)  # owning group
    floor_id = Column(Integer, ForeignKey("qs_floors.id"), nullable=True)
    quantity = Column(Float)
    unit = Column(String)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    created_by = Column(String)
    __table_args__ = (UniqueConstraint("project_id", "code"),)


class PmActivityLink(Base):
    __tablename__ = "pm_activity_links"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
    predecessor_id = Column(Integer, ForeignKey("pm_activities.id"), nullable=False)
    successor_id = Column(Integer, ForeignKey("pm_activities.id"), nullable=False)
    link_type = Column(String, nullable=False, default="FS")
    lag_days = Column(Integer, nullable=False, default=0)
    __table_args__ = (UniqueConstraint("successor_id", "predecessor_id"),)


class PmHindrance(Base):
    __tablename__ = "pm_hindrances"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
    activity_id = Column(Integer, ForeignKey("pm_activities.id"), nullable=True)
    raised_on = Column(Date, nullable=False)
    type = Column(String, nullable=False)
    description = Column(Text, nullable=False)
    start_date = Column(Date)
    end_date = Column(Date)
    delay_days = Column(Integer)
    status = Column(String, nullable=False, default="open")  # open | closed
    remarks = Column(Text)
    raised_by = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
