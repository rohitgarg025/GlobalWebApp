from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from typing import List

from app.models.schemas import (
    GenerateReportResponse,
    OutputFile,
    ReportTypesResponse,
    ReportTypeInfo,
)
from app.services import excel_service

router = APIRouter(prefix="/api", tags=["reports"])

REPORT_TYPES = [
    ReportTypeInfo(
        id="labour_report",
        display_name="Labour Report",
        description="Select files in order: (1) Resource Reconciliation  (2) Resource Requirement",
        required_files_count=2,
        input_file_labels=["Resource Reconciliation", "Resource Requirement"],
    ),
    ReportTypeInfo(
        id="material_report",
        display_name="Material Reconciliation Report",
        description="Select files in order: (1) Resource Reconciliation  (2) Resource Requirement  (3) Stock Report",
        required_files_count=3,
        input_file_labels=["Resource Reconciliation", "Resource Requirement", "Stock Report"],
    ),
    ReportTypeInfo(
        id="activity_costing_report",
        display_name="Activity Wise Costing Report",
        description="Select files in order: (1) Resource Reconciliation  (2) Resource Requirement  (3) Stock Report",
        required_files_count=3,
        input_file_labels=["Resource Reconciliation", "Resource Requirement", "Stock Report"],
    ),
    ReportTypeInfo(
        id="theoretical_consumption_report",
        display_name="Theoretical Consumption Report",
        description="Select files in order: (1) Resource Reconciliation  (2) Resource Requirement",
        required_files_count=2,
        input_file_labels=["Resource Reconciliation", "Resource Requirement"],
    ),
    ReportTypeInfo(
        id="fund_report",
        display_name="Fund Report",
        description="Select files in order: (1) Resource Reconciliation  (2) Resource Requirement",
        required_files_count=2,
        input_file_labels=["Resource Reconciliation", "Resource Requirement"],
    ),
    ReportTypeInfo(
        id="bill_master_report",
        display_name="Bill Master Report",
        description="Select file: (1) SRN Report",
        required_files_count=1,
        input_file_labels=["SRN Report"],
    ),
    ReportTypeInfo(
        id="monthly_projectwise_labour_report",
        display_name="Monthly Projectwise Labour Report",
        description="Select file: (1) SRN Report of all projects",
        required_files_count=1,
        input_file_labels=["SRN Report (All Projects)"],
    ),
    ReportTypeInfo(
        id="all_reports",
        display_name="All Reports (Labour + Material + Activity)",
        description="Generates all 3 reports. Select files in order: (1) Resource Reconciliation  (2) Resource Requirement  (3) Stock Report",
        required_files_count=3,
        input_file_labels=["Resource Reconciliation", "Resource Requirement", "Stock Report"],
    ),
    ReportTypeInfo(
        id="multiple_cost_reports",
        display_name="Multiple Projects – Cost Reports",
        description="Upload sets of 3 files per project (Reconciliation, Requirement, Stock). Total files must be a multiple of 3.",
        required_files_count=-1,
        input_file_labels=["Sets of: Resource Reconciliation, Resource Requirement, Stock Report"],
        supports_multiple_projects=True,
        files_per_project=3,
    ),
]


@router.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}


@router.get("/report-types", response_model=ReportTypesResponse)
async def get_report_types():
    return ReportTypesResponse(report_types=REPORT_TYPES)


@router.post("/reports/generate", response_model=GenerateReportResponse)
async def generate_report(
    report_type_id: str = Form(...),
    files: List[UploadFile] = File(...),
):
    # Validate report type
    report_type = next((r for r in REPORT_TYPES if r.id == report_type_id), None)
    if not report_type:
        raise HTTPException(status_code=422, detail=f"Unknown report type: '{report_type_id}'")

    # Validate file count
    if report_type.required_files_count != -1 and len(files) != report_type.required_files_count:
        raise HTTPException(
            status_code=422,
            detail=f"'{report_type.display_name}' requires exactly {report_type.required_files_count} file(s), but {len(files)} were uploaded."
        )
    if report_type.required_files_count == -1 and len(files) % 3 != 0:
        raise HTTPException(
            status_code=422,
            detail=f"Multiple Projects mode requires files in multiples of 3, but {len(files)} were uploaded."
        )

    # Read file bytes
    file_bytes_list = []
    for f in files:
        content = await f.read()
        file_bytes_list.append((f.filename, content))

    try:
        job_id, output_file_infos = await excel_service.generate_report(report_type_id, file_bytes_list)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Report generation failed: {str(e)}")

    return GenerateReportResponse(
        job_id=job_id,
        status="completed",
        output_files=[OutputFile(**info) for info in output_file_infos],
    )


@router.get("/reports/download/{file_id}")
async def download_report(file_id: str):
    path = excel_service.get_file_path(file_id)
    if not path:
        raise HTTPException(status_code=404, detail="File not found or already expired.")

    import os
    filename = os.path.basename(path)
    return FileResponse(
        path=path,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        filename=filename,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.delete("/reports/session/{job_id}")
async def cleanup_session(job_id: str):
    deleted = excel_service.cleanup_job(job_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Job not found.")
    return {"deleted": True}
