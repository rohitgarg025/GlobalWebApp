import os
import uuid
import asyncio
import shutil
import tempfile
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
}

# In-memory job registry: {job_id: {file_id: absolute_path}}
_job_registry: dict[str, dict[str, str]] = {}

TEMP_BASE = Path(__file__).parent.parent.parent / "temp"


def get_report_label(filename: str) -> str:
    name = Path(filename).stem.lower()
    if "labour" in name:
        return "Labour Costing Report"
    if "material" in name:
        return "Material Reconciliation Report"
    if "activity" in name:
        return "Activity Wise Costing Report"
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

    _job_registry[job_id] = file_registry
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
    for job_files in _job_registry.values():
        if file_id in job_files:
            path = job_files[file_id]
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
