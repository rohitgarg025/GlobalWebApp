import pandas as pd
import sys
import os
from datetime import datetime
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import pandas as pd
import time

from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
START_ROW = 3
SKIP_ROWS_IF_PIVOT_REPORT = 1
SKIP_ROWS_IF_CUSTOM_REPORT = 5
LABOUR_REPORT_TITLE = "Labour Costing Report"
LABOUR_SUMMARY_TITLE = 'Labour Costing Summary'

def format_excel_with_headers(writer, sheet_name, df, report_title, project_name=None):
    """
    Format Excel sheet with headers and styling
    """
    workbook = writer.book
    worksheet = writer.sheets[sheet_name]

    # Add Report Title (Row 1)
    worksheet['A1'] = f'Report Type : {report_title}'
    worksheet['A1'].font = Font(name='Arial', size=14, bold=True)
    # worksheet['A1'].fill = PatternFill(start_color='0066CC', end_color='0066CC', fill_type='solid')
    worksheet['A1'].alignment = Alignment(horizontal='left')
    # worksheet.merge_cells(f'A1:{get_column_letter(len(df.columns))}1')

    # Add Project Name (Row 2) if provided
    if project_name:
        worksheet['A2'] = f'Project Name : {project_name}'
        worksheet['A2'].font = Font(name='Arial', size=11, bold=True)
        worksheet['A2'].alignment = Alignment(horizontal='left')

    # Add Generation Date (Row 3)
    row_offset = 3 if project_name else 2
    worksheet[f'A{row_offset}'] = f'Generated on: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}'
    worksheet[f'A{row_offset}'].font = Font(name='Arial', size=9, italic=True)

    # Format column headers
    header_row = row_offset+1  # Leave one blank row
    header_fill = PatternFill(start_color='0066CC', end_color='0066CC', fill_type='solid')
    header_font = Font(name='Arial', size=10, bold=True, color='FFFFFF')
    header_alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)

    for col in range(1, len(df.columns) + 1):
        cell = worksheet.cell(row=header_row, column=col)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = header_alignment

# CONSTANTS
LABOUR_REPORT = "Labour Report"
MATERIAL_REPORT = "Material Reconciliation Report"
ACTIVITY_COSTING_REPORT = "Activity Wise Costing Report"
ALL_REPORTS = "All of the above"
MULTIPLE_COST_REPORTS = "Multiple Projects - Cost Reports"
MONTHWISE_SITEWISE_LABOUR_QTY_REPORT = "Monthwise Sitewise Labour Quantity Report"

def get_output_excel(project_name, base_filename, file_extension):
    '''
    :param project_name: 'project name extracted from erp report'
    :param base_filename: 'output report_name'
    :param file_extension: '.excel'
    :return:
    '''
    # Get the current datetime object
    project_name = project_name.lower().replace(' ', '_')
    now = datetime.now()

    # Format the datetime object into a string timestamp
    # Example format: YYYYMMDD_HHMMSS
    timestamp = now.strftime('%Y%m%d_%H%M%S')

    # Construct the new filename with the timestamp
    new_filename = f"{project_name}_{base_filename}_{timestamp}{file_extension}"

    return f"{new_filename}"

    # Example of creating a file with this name (optional)
    # with open(new_filename, 'w') as f:
    #     f.write("This is a test file with a timestamp in its name.")
    # print(f"File '{new_filename}' created.")

def is_wbs_contain_string(df,str):
    return df['Parent WBS Name'].str.contains(str, case=False, na=False)

def get_labour_amt_summary_list(df, amt_type):
    flag_general_site_work = is_wbs_contain_string(df,"general site work")
    flag_site_expenses = is_wbs_contain_string(df,"site expenses") | is_wbs_contain_string(df,"site administrative expenses")
    flag_hire_rent = is_wbs_contain_string(df,"hire & rent")
    flag_site_infra_work = is_wbs_contain_string(df,"site infra work")

    general_site_work = float(df.loc[flag_general_site_work,amt_type].sum() or 0)
    site_expenses = float(df.loc[flag_site_expenses,amt_type].sum() or 0)
    hire_rent = float(df.loc[flag_hire_rent,amt_type].sum() or 0)
    site_infra_work = float(df.loc[flag_site_infra_work,amt_type].sum() or 0)

    overhead_total = site_expenses + hire_rent
    productive_total = float(df[amt_type].sum()) - (general_site_work + overhead_total+site_infra_work)

    return [productive_total, site_infra_work, general_site_work, hire_rent, site_expenses]


def get_consolidated_report(df_list):
    '''
        :param df_list:A
        :return:
        '''
    file1 = df_list[0].copy()
    file2 = df_list[1].copy()
    file3 = pd.DataFrame()
    if len(df_list) > 2:
        file3 = df_list[2].copy()

    # --- Step 3: Create a derived key column in both files ---
    # Example: Combine 'Resource Code' and 'Resource Name' (adjust as per your column names)
    file1['Key'] = file1['Activity Name'].astype(str).str.strip() + "   " + file1['Item Desc'].astype(str).str.strip()
    file2['Key'] = file2['Activity Name'].astype(str).str.strip() + "   " + file2['Resource Name'].astype(
        str).str.strip()

    print("Performing VLOOKUP (merge)...")
    file1 = file1.merge(file2[['Key', 'Resource Type']], on='Key', how='left')
    return [file1,file2,file3]

def clean_df(df):
    # Step 7: Rename metric columns
    try:
        df = df.rename(columns={
            "3Est Qty": "Est Qty",
            "3Theoritical Qty": "Theoritical Qty",
            "3Actual Qty": "Actual Qty",
            "3Difference Qty": "Difference Qty",
        })
        return df
    except:
        print("Invalid columns or data in uploaded excel files!\n")

def get_merged_df_with_stock_report(pivot, df_stock_report,stock_cols):
    '''
    :param pivot: pd.DataFrame
    :param df_stock_report: pd.DataFrame
    :return: pd.DataFrame
    '''

    print("Performing VLOOKUP (merge) of resource report with stock report...")
    pivot = pivot.merge(df_stock_report[['Item Desc'] + stock_cols ], on='Item Desc', how='left')
    return pivot

def get_monthwise_labour_sheet(df_list):
    file1 = df_list[0].copy()



def get_labour_sheet(df_list):
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = df[df['Resource Type'].str.lower() == 'service']
    df = clean_df(df)

    # Step 3: Sort by Parent WBS
    df = df.sort_values(by='Parent WBS Name')

    # Step 4: Compute summary
    estimated_amt_labour_summary_list = get_labour_amt_summary_list(df,"Est Amt")
    theoritical_amt_labour_summary_list = get_labour_amt_summary_list(df,"Theoritical Amt")
    actual_amt_labour_summary_list = get_labour_amt_summary_list(df,"Actual Amt")

    print("Step 4: Compute summary")

    # Step 5: Prepare summary dataframe
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

    print("Step 5: Prepare summary dataframe")

    # Step 6: Remove unnecessary columns from dataframe
    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None
    columns_to_delete = ["Sr","Activity Code", "Project Name","Sub Project","Activity Unit", "3Total Qty","Key","Resource Type"]
    df = df.drop(columns=columns_to_delete)

    #Step 9 : Rename cells as per business requirements
    df = df.rename(columns={
        'Theoritical Qty': 'DPR Work Qty',
        'Actual Qty': 'SRN Billed Qty',
        'Theoritical Amt': 'Theoritical Work Amt',
        'Actual Amt' : 'SRN Amt'
    })

    # Step 10 : Add Actual Rate Column
    df["Act Rate"] = (df["SRN Amt"] / df["SRN Billed Qty"]).where(df["SRN Billed Qty"] != 0, 0)
    df["Balance Work Amt [Est - Th]"] = df["Est Amt"] - df["Theoritical Work Amt"]
    df["Percentage Work Completed [DPR/Est]*100"] = ((df["DPR Work Qty"] / df["Est Qty"]).where(df["Est Qty"] != 0,0))*100
    df["Work Amt"] = df["DPR Work Qty"]*df["Act Rate"]

    # Step 11: Write output to Excel with formatting
    output_path_file = get_output_excel(project_name,"Labour_Report", ".xlsx")
    start_row = START_ROW
    with pd.ExcelWriter(output_path_file, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Detailed Data',startrow=start_row)
        summary.to_excel(writer, index=False, sheet_name='Summary',startrow=start_row)

        # Extract project name from first row if available
        # project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None

        # Format both sheets
        format_excel_with_headers(writer, 'Detailed Data', df, LABOUR_REPORT_TITLE, project_name)
        format_excel_with_headers(writer, 'Summary', summary, LABOUR_SUMMARY_TITLE, project_name)
    print(f"✅ Labour report generated at {output_path_file}")
    return output_path_file

def get_material_sheet(df_list):
    '''
    :param df_list:
    :return:
    '''

    # Step1: Fetch material entries from Resource Reconciliation Report
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = df[df['Resource Type'].str.lower() == 'material']
    df = clean_df(df)
    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None
    # df["Actual Rate"] = (df["Actual Amt"] / df["Actual Qty"]).where(df["Actual Qty"] != 0, 0)

    # Step2: Perform Pivot Table Operation
    # Ensure numeric conversions
    numeric_cols = ["Est Qty", "Est Rate", "Est Amt","Theoritical Qty","Actual Qty","Theoritical Amt","Actual Amt"]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Create Pivot Table
    pivot = pd.pivot_table(
        df,
        index=["Item Group", "Item Desc", "Resource Unit"],
        values={
            "Est Qty": "sum",
            "Est Rate": "mean",
            "Est Amt": "sum",
            "Theoritical Qty": "sum",
            "Theoritical Amt": "sum",
            "Actual Qty": "sum",
            "Actual Amt": "sum",

        },
        aggfunc={
            "Est Qty": "sum",
            "Est Rate": "mean",
            "Est Amt": "sum",
            "Theoritical Qty": "sum",
            "Theoritical Amt": "sum",
            "Actual Qty": "sum",
            "Actual Amt": "sum"
        },
        fill_value=0,
        margins=True,
        margins_name="Total"
    ).reset_index()

    #Step: Add Derived Columns(New Step)
    pivot["Wastage"] = pivot["Actual Qty"] - pivot["Theoritical Qty"]
    pivot["Wastage %"] = (
            (pivot["Wastage"] / pivot["Theoritical Qty"]) * 100
    ).where(pivot["Theoritical Qty"] != 0, 0)  # Sets to 0 if Est Qty is 0

    pivot["Actual Rate"] = (pivot["Actual Amt"] / pivot["Actual Qty"]).where(pivot["Actual Qty"]!=0,0)

    desired_columns_order = [
        "Item Group",
        "Item Desc",
        "Resource Unit",
        "Est Qty",
        "Est Rate",
        "Est Amt",
        "Theoritical Qty",
        "Theoritical Amt",
        "Actual Qty",
        "Actual Rate",
        "Actual Amt",
        "Wastage",
        "Wastage %"
    ]

    stock_cols = []
    if len(file_list) > 2:
        df_stock_report = file_list[2].copy()
        stock_cols = ['Stock Received Qty (B)', 'Project Transfer Qty (E)', 'Stock Issue Qty (D)','Closing Stock Qty (CG)']
        pivot = get_merged_df_with_stock_report(pivot.copy(), df_stock_report,stock_cols)
        for col in stock_cols:
            pivot[col] = pd.to_numeric(pivot[col], errors='coerce').fillna(0)  # Convert to numeric, replace NaNs with 0

        desired_columns_order.extend(stock_cols)

    # The 'Total' row adds the 'Total' value in the index columns, but since
    # reset_index() is used, the 'Total' row is just another data row.
    # We ensure all columns are present before reindexing.

    # Reindex the DataFrame to set the column order
    # Use .reindex(columns=...) to apply the order
    pivot = pivot.reindex(columns=desired_columns_order)

    # Round values for clean report
    pivot["Est Qty"] = pivot["Est Qty"].round(2)
    pivot["Est Rate"] = pivot["Est Rate"].round(2)
    pivot["Est Amt"] = pivot["Est Amt"].round(2)
    pivot["Theoritical Qty"] = pivot["Theoritical Qty"].round(2)
    pivot["Theoritical Amt"] = pivot["Theoritical Amt"].round(2)
    pivot["Actual Qty"] = pivot["Actual Qty"].round(2)
    pivot["Actual Rate"] = pivot["Actual Rate"].round(2)
    pivot["Actual Amt"] = pivot["Actual Amt"].round(2)

    if len(file_list) > 2:
        # Check if column exists before trying to round it (safety check)
        for col in stock_cols:
            pivot[col] = pivot[col].round(2)

    # Sort alphabetically for neatness
    pivot = pivot.sort_values(by=["Item Group", "Item Desc"])

    pivot["Actual - Tag Issue Qty Difference"] = pivot["Stock Issue Qty (D)"] - pivot["Actual Qty"]
    # Export to Excel
    output_path = get_output_excel(project_name,"Material_Reconciliation_Report",".xlsx")
    pivot.to_excel(output_path, index=False)
    print(f"✅ Material Reconciliation Report generated: {output_path}")

    return output_path

def get_activity_costing_report(df_list):
    '''
    :param df_list: pd.DataFrame
    :return:
    '''

    # Step 1 : Prepare consolidated dataframe
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = clean_df(df)
    project_name = df['Project Name'].iloc[0] if 'Project Name' in df.columns else None

    # Step2: Apply Pivot to get activity wise costing
    # Ensure numeric conversions
    numeric_cols = ["Est Amt", "Theoritical Amt", "Actual Amt"]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Create Pivot Table
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

    # Flatten by joining the level names
    # Example: ('Actual Amt', 'material') -> 'Actual Amt - Material'
    new_columns = [
        f"{level1.upper()} - {level2.upper()}"
        for level1, level2 in pivot.columns
    ]
    pivot.columns = new_columns

    # 4. Final Cleanup: Convert 'Activity Name' from index back to a regular column
    key_cols = ["Parent WBS Name", "Activity Name", "Activity Unit"]
    pivot = pivot.reset_index()

    # --- NEW STEP: Define and Apply Desired Column Order ---

    # Define the desired order for the two levels of the hierarchy
    amount_order = ["Est Amt", "Theoritical Amt", "Actual Amt"]
    resource_order = ["MATERIAL", "SERVICE", "Total"]  # 'Total' must match margins_name capitalization

    # Build the list of desired column names (excluding the key columns)
    desired_data_cols = []
    for amount in amount_order:
        for resource in resource_order:
            # Recreate the exact format used when flattening (e.g., 'EST AMT - MATERIAL')
            col_name = f"{amount.upper()} - {resource.upper()}"

            # Check if the column exists (useful if some combinations are missing)
            if col_name in pivot.columns:
                desired_data_cols.append(col_name)

    # Combine the key columns and the desired data columns for the final order
    final_col_order = key_cols + desired_data_cols

    # Reindex the DataFrame to apply the custom column order
    pivot = pivot.reindex(columns=final_col_order)

    # 5. FIX THE TYPE ERROR: Use .to_numeric to ONLY process numeric columns

    # Filter for columns that are not key columns
    numeric_cols_to_round = [col for col in pivot.columns if col not in key_cols]

    for col in numeric_cols_to_round:
        # 5a: Convert column to numeric, forcing any non-numeric values to 0.
        pivot[col] = pd.to_numeric(pivot[col], errors='coerce').fillna(0)

        # 5b: Apply rounding.
        pivot[col] = pivot[col].round(2)

    # 5. Round the results
    # All columns except the first one ('Activity Name') are numeric amounts
    # for col in pivot.columns[1:]:
    #     pivot[col] = pd.to_numeric(pivot[col], errors='coerce').fillna(0)
    #     pivot[col] = pivot[col].round(2)

    output_path = get_output_excel(project_name,"Activity_Costing_Report",".xlsx")
    pivot.to_excel(output_path, index=False)
    print(f"✅ Activity Costing Report generated: {output_path}")

    return output_path

def get_fund_report(df_list):
    pass
def excel_transform(df_list,transform_option):
    '''
    :param df_list:
    :param transform_option:
    :return:
    '''

    if transform_option == LABOUR_REPORT:
        return get_labour_sheet(df_list.copy())
    elif transform_option == MATERIAL_REPORT:
        return get_material_sheet(df_list.copy())
    elif transform_option == ACTIVITY_COSTING_REPORT:
        return get_activity_costing_report(df_list.copy())
    elif transform_option == ALL_REPORTS:
        return get_all_reports_single_project(df_list)
    elif transform_option == MULTIPLE_COST_REPORTS:
        multi_project_sheet_list = get_multi_project_list(df_list.copy())
        output_files_string = ''
        for i in multi_project_sheet_list:
            output_files_string = output_files_string +  get_all_reports_single_project(i.copy())
            time.sleep(1)
        return output_files_string + '\n'

    else:
        raise Exception("Invalid transform option!")
        return 0


def get_all_reports_single_project(df_list):
    ls = get_labour_sheet(df_list.copy())
    ms = get_material_sheet(df_list.copy())
    acs = get_activity_costing_report(df_list.copy())
    return f'{ls},\n{ms},\n{acs}';

def get_multi_project_list(df_list):
    '''
    :param df_list:
    :return: list of triads {resource_reconciliation_i, resource_requirement_i, stock_report_i}
    '''
    return [df_list[i:i + 3] for i in range(0, len(df_list), 3)]


# def get_df_from_files(files):
#     '''
#     :param files:
#     :return:
#     '''
#     pass

# if __name__ == '__main__':
#     num_files = int(input("Enter the number of files:"))
#     print(f"You entered: {num_files}")
#
#     file_list = []
#     for i in range(0,num_files):
#         file_list.append(input(f'Enter file {i+1} : '))
#     # --- Step 2: Read both Excel files ---
#
#     print("Reading Excel files...")
#     try:
#         df_list = [pd.read_excel(x,skiprows=1) for x in file_list]
#     except:
#         print("Files are invalid or not convertible to data frames. \n")
#
#     transform_option = input("Enter report type:\n")
#     print(f"You entered: {transform_option}")
#
#     excel_transform(df_list,transform_option)
#
#     '''
#     1. Consider that the two files are located in same folder as the python script.
#     2. 1st Argument is excel file 1
#     3. 2nd Argument is excel file 2
#     4. We create a new column based on two columns in excel file 1
#     5. We create same column in based on same two columns in excel file 2
#     6. We do vlookup in excel to get an existing column "Resource Type" from excel_file_2 into excel_file_1.
#     7. Now use transformed excel_file_1 to generate two reports.
#     8. First report is generated by applying filter in Resource Type column of this transformed excel file 1
#     9. Second report is generated by doing pivot, grouping and summmaring data.
#     '''

# def browse_files():
#     filenames = filedialog.askopenfilenames(
#         title="Select Excel Files",
#         filetypes=[("Excel files", "*.xlsx *.xls")]
#     )
#     file_list_box.delete(0, tk.END)
#     for f in filenames:
#         file_list_box.insert(tk.END, f)

def open_output_folder(folder_path):
    """Opens the folder where reports are saved."""
    try:
        if platform.system() == "Windows":
            os.startfile(folder_path)
        elif platform.system() == "Darwin":  # macOS
            subprocess.Popen(["open", folder_path])
        else:  # Linux
            subprocess.Popen(["xdg-open", folder_path])
    except Exception as e:
        messagebox.showerror("Error", f"Could not open folder:\n{e}")


def browse_files():
    filenames = filedialog.askopenfilenames(
        title="Select Excel Files in the following order: \n (1) Resource Reconciliation \n (2) Resource Requirement \n (3) Stock Report \n",
        filetypes=[("Excel files", "*.xlsx *.xls")]
    )
    for f in filenames:
        if f not in file_list_box.get(0, tk.END):  # avoid duplicates
            file_list_box.insert(tk.END, f)

def run_transformation():
    try:
        files = file_list_box.get(0, tk.END)
        if not files:
            messagebox.showerror("Error", "Please select at least one file.")
            return

        transform_option = report_type_var.get()
        print(transform_option)
        if not transform_option:
            messagebox.showerror("Error", "Please select a report type.")
            return

        skrows = SKIP_ROWS_IF_PIVOT_REPORT # TODO: I will get back to this
        df_list = [pd.read_excel(x, skiprows=skrows) for x in files]
        excel_transform(df_list, transform_option)
        messagebox.showinfo("Success", f"Reports generated successfully with transformation option : '{transform_option}'")

        # Automatically open the output folder
        open_output_folder(os.getcwd())

    except Exception as e:
        print(e)
        messagebox.showerror("Error", f"Something went wrong:\n{e}")

def open_folder_button_action():
    """Manual button to open output folder."""
    open_output_folder(os.getcwd())

# # --- GUI setup ---
# root = tk.Tk()
# root.title("Excel Report Transformer")
# root.geometry("500x400")
#
# # Title
# tk.Label(root, text="Excel Report Transformer", font=("Arial", 14, "bold")).pack(pady=10)
#
# # Dropdown for report type
# tk.Label(root, text="Select Report Type:").pack(pady=5)
# report_type_var = tk.StringVar()
# report_dropdown = ttk.Combobox(root, textvariable=report_type_var, values=[
#     MATERIAL_REPORT,
#     LABOUR_REPORT,
#     ACTIVITY_COSTING_REPORT,
#     ALL_REPORTS
# ])
# report_dropdown.current(0)  # Show default
# report_dropdown.pack(pady=5)
#
# #Description
# instruction_text = (
#     "Select Excel Files generated from ERP in the following order:\n"
#     "  (1) Resource Reconciliation\n"
#     "  (2) Resource Requirement\n"
#     "  (3) Stock Report"
# )
# tk.Label(
#     root,
#     text=instruction_text,
#     justify="left",
#     font=("Arial", 14, "bold")
# ).pack(pady=(5, 5))
#
# # File selection
# tk.Button(root, text="Browse Excel Files", command=browse_files).pack(pady=5)
# file_list_box = tk.Listbox(root, width=60, height=5)
# file_list_box.pack(pady=5)
#
# # Run button
# tk.Button(root, text="Generate Report", command=run_transformation, bg="#4CAF50", fg="black").pack(pady=20)
#
# # Open folder button
# tk.Button(root, text="Open Output Folder", command=open_folder_button_action, bg="#2196F3", fg="white").pack(pady=5)
#
# root.mainloop()