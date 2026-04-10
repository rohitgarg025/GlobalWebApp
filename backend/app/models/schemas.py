from pydantic import BaseModel
from typing import List, Optional


class ReportTypeInfo(BaseModel):
    id: str
    display_name: str
    description: str
    required_files_count: int  # -1 means variable (multiple of 3)
    input_file_labels: List[str]
    supports_multiple_projects: bool = False
    files_per_project: Optional[int] = None


class ReportTypesResponse(BaseModel):
    report_types: List[ReportTypeInfo]


class OutputFile(BaseModel):
    file_id: str
    filename: str
    download_url: str
    size_bytes: int
    report_label: str


class GenerateReportResponse(BaseModel):
    job_id: str
    status: str
    output_files: List[OutputFile]


class HealthResponse(BaseModel):
    status: str
    version: str
