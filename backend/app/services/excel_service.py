import os
import uuid
import asyncio
import shutil
import time
from pathlib import Path
from typing import List
from io import BytesIO

import pandas as pd

from processing.main import excel_transform

# Maps API report_type_id → processing constant string
REPORT_TYPE_MAP = {
    "labour_report": "Labour Report",
    "material_report": "Material Reconciliation Report",
    "activity_costing_report": "Activity Wise Costing Report",
    "all_reports": "All of the above",
    "multiple_cost_reports": "Multiple Projects - Cost Reports",
    "theoretical_consumption_report": "Theoretical Consumption Report",
}

JOB_TTL_SECONDS = 3600  # 1 hour

TEMP_BASE = Path(__file__).parent.parent.parent / "temp"

# In-memory job registry: {job_id: {"files": {file_id: path}, "created_at": timestamp}}
_job_registry: dict[str, dict] = {}


def _evict_expired_jobs() -> None:
    now = time.time()
    expired = [jid for jid, meta in _job_registry.items() if now - meta["created_at"] > JOB_TTL_SECONDS]
    for jid in expired:
        job_output_dir = TEMP_BASE / "outputs" / jid
        if job_output_dir.exists():
            shutil.rmtree(job_output_dir, ignore_errors=True)
        del _job_registry[jid]


def get_report_label(filename: str) -> str:
    name = Path(filename).stem.lower()
    if "labour" in name:
        return "Labour Costing Report"
    if "material" in name:
        return "Material Reconciliation Report"
    if "activity" in name:
        return "Activity Wise Costing Report"
    if "theoretical" in name:
        return "Theoretical Consumption Report"
    return "Report"


async def generate_report(
    report_type_id: str,
    file_bytes_list: List[tuple[str, bytes]],
) -> tuple[str, list[dict]]:
    """
    Accepts list of (original_filename, bytes) tuples.
    Returns (job_id, list of output file info dicts).
    """
    transform_option = REPORT_TYPE_MAP.get(report_type_id)
    if not transform_option:
        raise ValueError(f"Unknown report type: {report_type_id}")

    job_id = str(uuid.uuid4())
    job_output_dir = TEMP_BASE / "outputs" / job_id
    job_output_dir.mkdir(parents=True, exist_ok=True)

    # Run the CPU-bound Excel processing in a thread pool
    output_paths = await asyncio.to_thread(
        _run_transform, file_bytes_list, transform_option, str(job_output_dir)
    )

    _evict_expired_jobs()

    file_registry: dict[str, str] = {}
    output_file_infos = []

    for path in output_paths:
        file_id = str(uuid.uuid4())
        file_registry[file_id] = path
        size = os.path.getsize(path)
        filename = os.path.basename(path)
        output_file_infos.append({
            "file_id": file_id,
            "filename": filename,
            "download_url": f"/api/reports/download/{file_id}",
            "size_bytes": size,
            "report_label": get_report_label(filename),
        })

    _job_registry[job_id] = {"files": file_registry, "created_at": time.time()}
    return job_id, output_file_infos


def _run_transform(
    file_bytes_list: List[tuple[str, bytes]],
    transform_option: str,
    output_dir: str,
) -> List[str]:
    """Synchronous: reads bytes → DataFrames, runs excel_transform, returns output paths."""
    df_list = []
    for filename, content in file_bytes_list:
        buf = BytesIO(content)
        df = pd.read_excel(buf, skiprows=1)
        df_list.append(df)

    return excel_transform(df_list, transform_option, output_dir)


def get_file_path(file_id: str) -> str | None:
    """Look up an output file path by file_id across all jobs."""
    for meta in _job_registry.values():
        if file_id in meta["files"]:
            path = meta["files"][file_id]
            return path if os.path.exists(path) else None
    return None


def cleanup_job(job_id: str) -> bool:
    if job_id not in _job_registry:
        return False
    job_output_dir = TEMP_BASE / "outputs" / job_id
    if job_output_dir.exists():
        shutil.rmtree(job_output_dir, ignore_errors=True)
    del _job_registry[job_id]
    return True
