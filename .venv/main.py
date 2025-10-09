import pandas as pd
import sys
import os
from datetime import datetime

def get_output_excel(base_filename, file_extension):
    '''
    :param base_filename: 'output report_name'
    :param file_extension: '.excel'
    :return:
    '''
    # Get the current datetime object
    now = datetime.now()

    # Format the datetime object into a string timestamp
    # Example format: YYYYMMDD_HHMMSS
    timestamp = now.strftime('%Y%m%d_%H%M%S')

    # Construct the new filename with the timestamp
    new_filename = f"{base_filename}_{timestamp}{file_extension}"

    return f"Generated filename: {new_filename}"

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

    output_path_file = get_output_excel("labour_sheet",".xlsx")

    # Step 6: Remove unnecessary columns from dataframe
    columns_to_delete = ["Sr","Activity Code", "Project Name","Sub Project","Activity Unit", "3Total Qty","Key","Resource Type"]
    df = df.drop(columns=columns_to_delete)

    # Step 8 : Add Actual Rate Column
    df["Act Rate"] = (df["Actual Amt"] / df["Actual Qty"]).where(df["Actual Qty"] != 0, 0)
    df["Balance Work Qty [Est - Th]"] = df["Est Amt"] - df["Theoritical Amt"]

    # Step 6: Write output to Excel
    with pd.ExcelWriter(output_path_file, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Detailed Data')
        summary.to_excel(writer, index=False, sheet_name='Summary')

    print(f"✅ Labour report generated at {output_path_file}")

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
    df["Actual Rate"] = (df["Actual Amt"] / df["Actual Qty"]).where(df["Actual Qty"] != 0, 0)

    # Step2: Perform Pivot Table Operation
    # Ensure numeric conversions
    numeric_cols = ["Est Qty", "Est Rate", "Est Amt","Theoritical Qty","Actual Qty","Theoritical Amt","Actual Amt","Actual Rate"]
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
            "Actual Rate": "mean",
            "Actual Amt": "sum",

        },
        aggfunc={
            "Est Qty": "sum",
            "Est Rate": "mean",
            "Est Amt": "sum",
            "Theoritical Qty": "sum",
            "Theoritical Amt": "sum",
            "Actual Qty": "sum",
            "Actual Rate": "mean",
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
        stock_cols = ['Stock Received Qty (B)', 'Project Transfer Qty (E)', 'Stock Issue Qty (D)', 'Closing Stock Qty (CG)']
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

    # Export to Excel
    output_path = get_output_excel("Material Reconciliation",".xlsx")
    pivot.to_excel(output_path, index=False)
    print(f"✅ Material Reconciliation Report generated: {output_path}")

    return pivot

def get_activity_costing_report(df_list):
    '''
    :param df_list: pd.DataFrame
    :return:
    '''

    # Step 1 : Prepare consolidated dataframe
    file_list = get_consolidated_report(df_list)
    df = file_list[0].copy()
    df = clean_df(df)

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

    output_path = get_output_excel("Activity Costing Report",".xlsx")
    pivot.to_excel(output_path, index=False)
    print(f"✅ Activity Costing Report generated: {output_path}")

    return pivot

def excel_transform(df_list,transform_option):
    '''
    :param df_list:
    :param transform_option:
    :return:
    '''

    if transform_option == "labour_sheet":
        return get_labour_sheet(df_list.copy())
    elif transform_option == "material_sheet":
        return get_material_sheet(df_list.copy())
    elif transform_option == "activity_costing_report":
        return get_activity_costing_report(df_list.copy())
    elif transform_option == "all":
        ls = get_labour_sheet(df_list.copy())
        ms = get_material_sheet(df_list.copy())
        acs = get_activity_costing_report(df_list.copy())
        return 0;
    else:
        raise Exception("Invalid transform option!")
        return 0

def get_df_from_files(files):
    '''
    :param files:
    :return:
    '''
    pass

if __name__ == '__main__':
    num_files = int(input("Enter the number of files:"))
    print(f"You entered: {num_files}")

    file_list = []
    for i in range(0,num_files):
        file_list.append(input(f'Enter file {i+1} : '))
    # --- Step 2: Read both Excel files ---

    print("Reading Excel files...")
    try:
        df_list = [pd.read_excel(x,skiprows=1) for x in file_list]
    except:
        print("Files are invalid or not convertible to data frames. \n")

    transform_option = input("Enter report type:\n")
    print(f"You entered: {transform_option}")

    excel_transform(df_list,transform_option)

    '''
    1. Consider that the two files are located in same folder as the python script. 
    2. 1st Argument is excel file 1
    3. 2nd Argument is excel file 2
    4. We create a new column based on two columns in excel file 1
    5. We create same column in based on same two columns in excel file 2
    6. We do vlookup in excel to get an existing column "Resource Type" from excel_file_2 into excel_file_1.
    7. Now use transformed excel_file_1 to generate two reports.
    8. First report is generated by applying filter in Resource Type column of this transformed excel file 1
    9. Second report is generated by doing pivot, grouping and summmaring data.
    '''