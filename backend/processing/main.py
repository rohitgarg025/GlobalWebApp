import pandas as pd
import os
import time
from datetime import datetime

from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

START_ROW = 3

LABOUR_REPORT_TITLE = "Labour Costing Report"
LABOUR_SUMMARY_TITLE = 'Labour Costing Summary'

# Report type constants
LABOUR_REPORT = "Labour Report"
MATERIAL_REPORT = "Material Reconciliation Report"
ACTIVITY_COSTING_REPORT = "Activity Wise Costing Report"
ALL_REPORTS = "All of the above"
MULTIPLE_COST_REPORTS = "Multiple Projects - Cost Reports"
MONTHWISE_SITEWISE_LABOUR_QTY_REPORT = "Monthwise Sitewise Labour Quantity Report"
THEORETICAL_CONSUMPTION_REPORT = "Theoretical Consumption Report"
FUND_REPORT = "Fund Report"

def format_excel_with_headers(writer, sheet_name, df, report_title, project_name=None):
    workbook = writer.book
    worksheet = writer.sheets[sheet_name]

    worksheet['A1'] = f'Report Type : {report_title}'
    worksheet['A1'].font = Font(name='Arial', size=14, bold=True)
    worksheet['A1'].alignment = Alignment(horizontal='left')

    if project_name:
        worksheet['A2'] = f'Project Name : {project_name}'
        worksheet['A2'].font = Font(name='Arial', size=11, bold=True)
        worksheet['A2'].alignment = Alignment(horizontal='left')

    row_offset = 3 if project_name else 2
    worksheet[f'A{row_offset}'] = f'Generated on: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}'
    worksheet[f'A{row_offset}'].font = Font(name='Arial', size=9, italic=True)

    header_row = row_offset + 1
    header_fill = PatternFill(start_color='0066CC', end_color='0066CC', fill_type='solid')
    header_font = Font(name='Arial', size=10, bold=True, color='FFFFFF')
    header_alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)

    for col in range(1, len(df.columns) + 1):
        cell = worksheet.cell(row=header_row, column=col)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = header_alignment


def get_output_excel(project_name, base_filename, file_extension, output_dir=""):
    project_name = project_name.lower().replace(' ', '_') if project_name else 'project'
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    new_filename = f"{project_name}_{base_filename}_{timestamp}{file_extension}"
    if output_dir:
        return os.path.join(output_dir, new_filename)
    return new_filename


def is_wbs_contain_string(df, str):
    return df['Parent WBS Name'].str.contains(str, case=False, na=False)


def get_labour_amt_summary_list(df, amt_type):
    flag_general_site_work = is_wbs_contain_string(df, "general site work")
    flag_site_expenses = is_wbs_contain_string(df, "site expenses") | is_wbs_contain_string(df, "site administrative expenses")
    flag_hire_rent = is_wbs_contain_string(df, "hire & rent")
    flag_site_infra_work = is_wbs_contain_string(df, "site infra work")

    general_site_work = float(df.loc[flag_general_site_work, amt_type].sum() or 0)
    site_expenses = float(df.loc[flag_site_expenses, amt_type].sum() or 0)
    hire_rent = float(df.loc[flag_hire_rent, amt_type].sum() or 0)
    site_infra_work = float(df.loc[flag_site_infra_work, amt_type].sum() or 0)

    overhead_total = site_expenses + hire_rent
    productive_total = float(df[amt_type].sum()) - (general_site_work + overhead_total + site_infra_work)

    return [productive_total, site_infra_work, general_site_work, hire_rent, site_expenses]


def get_consolidated_report(df_list):
    file1 = df_list[0].copy()
    file2 = df_list[1].copy()
    file3 = pd.DataFrame()
    if len(df_list) > 2:
        file3 = df_list[2].copy()

    file1['Key'] = file1['Activity Name'].astype(str).str.strip() + "   " + file1['Item Desc'].astype(str).str.strip()
    file2['Key'] = file2['Activity Name'].astype(str).str.strip() + "   " + file2['Resource Name'].astype(str).str.strip()

    file1 = file1.merge(file2[['Key', 'Resource Type']], on='Key', how='left')
    return [file1, file2, file3]


def clean_df(df):
    try:
        df = df.rename(columns={
            "3Est Qty": "Est Qty",
            "3Theoritical Qty": "Theoritical Qty",
            "3Actual Qty": "Actual Qty",
            "3Difference Qty": "Difference Qty",
        })
        return df
    except Exception as e:
        print(f"Invalid columns: {e}")
        return None


def get_merged_df_with_stock_report(pivot, df_stock_report, stock_cols):
    pivot = pivot.merge(df_stock_report[['Item Desc'] + stock_cols], on='Item Desc', how='left')
    return pivot


def get_labour_sheet(df_list, output_dir=""):
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = df[df['Resource Type'].str.lower() == 'service']
    df = clean_df(df)

    df = df.sort_values(by='Parent WBS Name')

    estimated_amt_labour_summary_list = get_labour_amt_summary_list(df, "Est Amt")
    theoritical_amt_labour_summary_list = get_labour_amt_summary_list(df, "Theoritical Amt")
    actual_amt_labour_summary_list = get_labour_amt_summary_list(df, "Actual Amt")

    summary = pd.DataFrame({
        'Labour Costing Summary': [
            'Productive Labour',
            'Site Infra Work',
            'General Site Work',
            'Hire & Rent',
            'Site Admin Expenses'
        ],
        'Estimated Amount': estimated_amt_labour_summary_list,
        'Theoritical Amount': theoritical_amt_labour_summary_list,
        'Actual Amount': actual_amt_labour_summary_list
    })

    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None
    columns_to_delete = ["Sr", "Activity Code", "Project Name", "Sub Project", "Activity Unit", "3Total Qty", "Key", "Resource Type"]
    df = df.drop(columns=[c for c in columns_to_delete if c in df.columns])

    df = df.rename(columns={
        'Theoritical Qty': 'DPR Work Qty',
        'Actual Qty': 'SRN Billed Qty',
        'Theoritical Amt': 'Theoritical Work Amt',
        'Actual Amt': 'SRN Amt'
    })

    df["Act Rate"] = (df["SRN Amt"] / df["SRN Billed Qty"]).where(df["SRN Billed Qty"] != 0, 0)
    df["Balance Work Amt [Est - Th]"] = df["Est Amt"] - df["Theoritical Work Amt"]
    df["Percentage Work Completed [DPR/Est]*100"] = ((df["DPR Work Qty"] / df["Est Qty"]).where(df["Est Qty"] != 0, 0)) * 100
    df["Work Amt"] = df["DPR Work Qty"] * df["Act Rate"]

    output_path_file = get_output_excel(project_name, "Labour_Report", ".xlsx", output_dir)
    with pd.ExcelWriter(output_path_file, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Detailed Data', startrow=START_ROW)
        summary.to_excel(writer, index=False, sheet_name='Summary', startrow=START_ROW)
        format_excel_with_headers(writer, 'Detailed Data', df, LABOUR_REPORT_TITLE, project_name)
        format_excel_with_headers(writer, 'Summary', summary, LABOUR_SUMMARY_TITLE, project_name)

    print(f"Labour report generated: {output_path_file}")
    return output_path_file


def get_material_sheet(df_list, output_dir=""):
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = df[df['Resource Type'].str.lower() == 'material']
    df = clean_df(df)
    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None

    numeric_cols = ["Est Qty", "Est Rate", "Est Amt", "Theoritical Qty", "Actual Qty", "Theoritical Amt", "Actual Amt"]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    pivot = pd.pivot_table(
        df,
        index=["Item Group", "Item Desc", "Resource Unit"],
        values={"Est Qty": "sum", "Est Rate": "mean", "Est Amt": "sum",
                "Theoritical Qty": "sum", "Theoritical Amt": "sum",
                "Actual Qty": "sum", "Actual Amt": "sum"},
        aggfunc={"Est Qty": "sum", "Est Rate": "mean", "Est Amt": "sum",
                 "Theoritical Qty": "sum", "Theoritical Amt": "sum",
                 "Actual Qty": "sum", "Actual Amt": "sum"},
        fill_value=0,
        margins=True,
        margins_name="Total"
    ).reset_index()

    pivot["Wastage"] = pivot["Actual Qty"] - pivot["Theoritical Qty"]
    pivot["Wastage %"] = ((pivot["Wastage"] / pivot["Theoritical Qty"]) * 100).where(pivot["Theoritical Qty"] != 0, 0)
    pivot["Actual Rate"] = (pivot["Actual Amt"] / pivot["Actual Qty"]).where(pivot["Actual Qty"] != 0, 0)

    desired_columns_order = [
        "Item Group", "Item Desc", "Resource Unit",
        "Est Qty", "Est Rate", "Est Amt",
        "Theoritical Qty", "Theoritical Amt",
        "Actual Qty", "Actual Rate", "Actual Amt",
        "Wastage", "Wastage %"
    ]

    stock_cols = []
    if len(file_list) > 2 and not file_list[2].empty:
        df_stock_report = file_list[2].copy()
        stock_cols = ['Stock Received Qty (B)', 'Project Transfer Qty (E)', 'Stock Issue Qty (D)', 'Closing Stock Qty (CG)']
        pivot = get_merged_df_with_stock_report(pivot.copy(), df_stock_report, stock_cols)
        for col in stock_cols:
            pivot[col] = pd.to_numeric(pivot[col], errors='coerce').fillna(0)
        desired_columns_order.extend(stock_cols)

    pivot = pivot.reindex(columns=desired_columns_order)

    for col in ["Est Qty", "Est Rate", "Est Amt", "Theoritical Qty", "Theoritical Amt",
                "Actual Qty", "Actual Rate", "Actual Amt"]:
        pivot[col] = pivot[col].round(2)

    if stock_cols:
        for col in stock_cols:
            pivot[col] = pivot[col].round(2)
        pivot["Actual - Tag Issue Qty Difference"] = pivot["Stock Issue Qty (D)"] - pivot["Actual Qty"]

    pivot = pivot.sort_values(by=["Item Group", "Item Desc"])

    output_path = get_output_excel(project_name, "Material_Reconciliation_Report", ".xlsx", output_dir)
    pivot.to_excel(output_path, index=False)
    print(f"Material Reconciliation Report generated: {output_path}")
    return output_path


def get_activity_costing_report(df_list, output_dir=""):
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = clean_df(df)
    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None

    numeric_cols = ["Est Amt", "Theoritical Amt", "Actual Amt"]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    pivot = pd.pivot_table(
        df,
        index=["Parent WBS Name", "Activity Name", "Activity Unit"],
        columns=["Resource Type"],
        values=numeric_cols,
        aggfunc=sum,
        fill_value=0,
        margins=True,
        margins_name="Total"
    )

    new_columns = [f"{level1.upper()} - {level2.upper()}" for level1, level2 in pivot.columns]
    pivot.columns = new_columns

    key_cols = ["Parent WBS Name", "Activity Name", "Activity Unit"]
    pivot = pivot.reset_index()

    amount_order = ["Est Amt", "Theoritical Amt", "Actual Amt"]
    resource_order = ["MATERIAL", "SERVICE", "TOTAL"]

    desired_data_cols = []
    for amount in amount_order:
        for resource in resource_order:
            col_name = f"{amount.upper()} - {resource.upper()}"
            if col_name in pivot.columns:
                desired_data_cols.append(col_name)

    final_col_order = key_cols + desired_data_cols
    pivot = pivot.reindex(columns=final_col_order)

    numeric_cols_to_round = [col for col in pivot.columns if col not in key_cols]
    for col in numeric_cols_to_round:
        pivot[col] = pd.to_numeric(pivot[col], errors='coerce').fillna(0)
        pivot[col] = pivot[col].round(2)

    output_path = get_output_excel(project_name, "Activity_Costing_Report", ".xlsx", output_dir)
    pivot.to_excel(output_path, index=False)
    print(f"Activity Costing Report generated: {output_path}")
    return output_path


def get_all_reports_single_project(df_list, output_dir=""):
    ls = get_labour_sheet(df_list.copy(), output_dir)
    ms = get_material_sheet(df_list.copy(), output_dir)
    acs = get_activity_costing_report(df_list.copy(), output_dir)
    return [ls, ms, acs]


def get_multi_project_list(df_list):
    return [df_list[i:i + 3] for i in range(0, len(df_list), 3)]


def excel_transform(df_list, transform_option, output_dir=""):
    """
    Main dispatcher. Returns a list of output file paths.
    """
    if transform_option == LABOUR_REPORT:
        return [get_labour_sheet(df_list, output_dir)]
    elif transform_option == MATERIAL_REPORT:
        return [get_material_sheet(df_list, output_dir)]
    elif transform_option == ACTIVITY_COSTING_REPORT:
        return [get_activity_costing_report(df_list, output_dir)]
    elif transform_option == ALL_REPORTS:
        return get_all_reports_single_project(df_list, output_dir)
    elif transform_option == THEORETICAL_CONSUMPTION_REPORT:
        return [theoretical_consumption_sheet(df_list, output_dir)]
    elif transform_option == MULTIPLE_COST_REPORTS:
        multi_project_sheet_list = get_multi_project_list(df_list)
        all_outputs = []
        for project_files in multi_project_sheet_list:
            all_outputs.extend(get_all_reports_single_project(project_files, output_dir))
            time.sleep(1)
        return all_outputs
    else:
        raise ValueError(f"Invalid transform option: {transform_option}")


def theoretical_consumption_sheet(df_list, output_dir=""):
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = df[df['Resource Type'].str.lower() == 'material']
    df = clean_df(df)
    # Some ERP exports prefix the activity total with "3" like the other qty columns
    df = df.rename(columns={"3Total Qty": "Total Qty"})
    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None

    numeric_cols = ["Total Qty", "Est Qty", "Theoritical Qty"]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Resource Coefficient = material qty estimated per unit of activity
    df["Resource Coefficient"] = (df["Est Qty"] / df["Total Qty"]).where(df["Total Qty"] != 0, 0)

    desired_columns_order = [
        "Activity Name", "Activity Unit", "Total Qty",
        "Item Group", "Item Desc", "Resource Coefficient",
        "Resource Unit", "Est Qty", "Theoritical Qty",
    ]
    df = df.reindex(columns=desired_columns_order)

    df = df.sort_values(by=["Activity Name", "Item Group"]).reset_index(drop=True)

    for col in ["Total Qty", "Est Qty", "Theoritical Qty"]:
        df[col] = df[col].round(2)
    df["Resource Coefficient"] = df["Resource Coefficient"].round(6)

    sheet_name = 'Theoretical Consumption'
    output_path_file = get_output_excel(project_name, "Theoretical_Consumption_Report", ".xlsx", output_dir)

    with pd.ExcelWriter(output_path_file, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name=sheet_name, startrow=START_ROW)
        format_excel_with_headers(writer, sheet_name, df, THEORETICAL_CONSUMPTION_REPORT, project_name)

        worksheet = writer.sheets[sheet_name]

        # Detail data occupies rows first_data_row .. last_data_row (1-indexed);
        # to_excel(startrow=START_ROW) puts the header on excel row START_ROW+1.
        first_data_row = START_ROW + 2
        last_data_row = first_data_row + len(df) - 1
        item_desc_col = get_column_letter(df.columns.get_loc("Item Desc") + 1)
        th_qty_col = get_column_letter(df.columns.get_loc("Theoritical Qty") + 1)
        criteria_range = f"${item_desc_col}${first_data_row}:${item_desc_col}${last_data_row}"
        sum_range = f"${th_qty_col}${first_data_row}:${th_qty_col}${last_data_row}"

        # ── Material-wise summary (two blank rows below the detail table) ──────
        summary_start = last_data_row + 3

        title_cell = worksheet.cell(row=summary_start, column=1)
        title_cell.value = 'Material Wise Theoretical Consumption Summary'
        title_cell.font = Font(name='Arial', size=12, bold=True)

        header_row = summary_start + 1
        summary_headers = ['Item Desc', 'Resource Unit', 'Total Theoritical Qty']
        header_fill = PatternFill(start_color='0066CC', end_color='0066CC', fill_type='solid')
        header_font = Font(name='Arial', size=10, bold=True, color='FFFFFF')
        header_alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
        for col_idx, header in enumerate(summary_headers, start=1):
            cell = worksheet.cell(row=header_row, column=col_idx)
            cell.value = header
            cell.fill = header_fill
            cell.font = header_font
            cell.alignment = header_alignment

        # One summary row per material with a live =SUMIF formula; the criteria
        # references the Item Desc cell of the summary row itself, so clicking
        # the total in Excel highlights the detail ranges it draws from.
        write_row = header_row + 1
        for item_desc, group in df.groupby("Item Desc", sort=True):
            worksheet.cell(row=write_row, column=1).value = item_desc
            worksheet.cell(row=write_row, column=2).value = group["Resource Unit"].iloc[0]
            worksheet.cell(row=write_row, column=3).value = (
                f"=SUMIF({criteria_range},A{write_row},{sum_range})"
            )
            write_row += 1

    print(f"Theoretical Consumption Report generated: {output_path_file}")
    return output_path_file
