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


class PmCodeCounter(Base):
    """Last COD number issued per (project, prefix) so codes are never reused."""
    __tablename__ = "pm_code_counters"
    project_id = Column(Integer, ForeignKey("projects.id"), primary_key=True)
    prefix = Column(String, primary_key=True)  # A = activity, G = group
    last_number = Column(Integer, nullable=False, default=0)


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


class TakeoffJob(Base):
    """A drawing uploaded for quantity takeoff, and the analysis of one floor."""
    __tablename__ = "takeoff_jobs"
    id = Column(Integer, primary_key=True)
    created_by = Column(String)
    filename = Column(String, nullable=False)
    # uploaded → converting → floors_ready → analysing → done | failed
    status = Column(String, nullable=False, default="uploaded")
    message = Column(Text)
    floors_json = Column(Text)        # [{layout, title}]
    floor_layout = Column(String)
    floor_title = Column(String)
    floor_height_m = Column(Float)
    default_slab_mm = Column(Integer)  # used only where the drawing gives no thickness
    members_json = Column(Text)       # measured + interpreted members
    ai_json = Column(Text)            # Claude's interpretation (notes, missing info)
    rows_json = Column(Text)          # {activity: [rows]} — edited measurement rows
    input_tokens = Column(Integer, default=0)
    output_tokens = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class BbsJob(Base):
    """A reinforcement drawing processed into a bar bending schedule + cutting plan."""
    __tablename__ = "bbs_jobs"
    id = Column(Integer, primary_key=True)
    created_by = Column(String)
    filename = Column(String, nullable=False)
    # uploaded → reading → needs_settings → computing → done | failed
    status = Column(String, nullable=False, default="uploaded")
    message = Column(Text)
    notes_json = Column(Text)       # what the drawing's general notes say
    strips_json = Column(Text)      # beam lines read from the drawing
    settings_json = Column(Text)    # confirmed lap / cover / stock / offcut settings
    lines_json = Column(Text)       # BBS lines (editable)
    issues_json = Column(Text)
    plan_json = Column(Text)        # cutting plan per dia
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)



class Drawing(Base):
    """A drawing sheet in a project's drawing register; its files live in DrawingRevision."""
    __tablename__ = "drawings"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
    number = Column(String, nullable=False)  # uppercase, unique per project
    title = Column(String, nullable=False)
    discipline = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    created_by = Column(String)
    __table_args__ = (UniqueConstraint("project_id", "number"),)


class DrawingRevision(Base):
    """One issued file of a drawing (R0, R1, …); the highest rev_no is current."""
    __tablename__ = "drawing_revisions"
    id = Column(Integer, primary_key=True)
    drawing_id = Column(Integer, ForeignKey("drawings.id"), nullable=False)
    rev_no = Column(Integer, nullable=False)
    filename = Column(String, nullable=False)
    fmt = Column(String, nullable=False)  # PDF | DWG
    size_bytes = Column(Integer, nullable=False, default=0)
    remarks = Column(Text)
    uploaded_by = Column(String)
    uploaded_at = Column(DateTime, default=datetime.utcnow)
    preview_status = Column(String, nullable=False, default="none")  # none | pending | ready | failed
    __table_args__ = (UniqueConstraint("drawing_id", "rev_no"),)
