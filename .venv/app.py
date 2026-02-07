# gui_app.py

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import os
from main import excel_transform  # ✅ Import your Excel logic
import pandas as pd
import platform
import subprocess

# CONSTANTS
LABOUR_REPORT = "Labour Report"
MATERIAL_REPORT = "Material Reconciliation Report"
ACTIVITY_COSTING_REPORT = "Activity Wise Costing Report"
ALL_REPORTS = "All of the above"
SELECT_REPORT_TYPE_TEXT = "-- Select Report Type --"
INPUT_REQ_DIR = {
SELECT_REPORT_TYPE_TEXT : "",
LABOUR_REPORT: "Select Excel Files in the following order:\n (1) Resource Reconciliation\n (2) Resource Requirement\n",
MATERIAL_REPORT: "Select Excel Files in the following order:\n (1) Resource Reconciliation\n (2) Resource Requirement\n (3) Stock Report",
ACTIVITY_COSTING_REPORT: "Select Excel Files in the following order:\n (1) Resource Reconciliation\n (2) Resource Requirement\n (3) Stock Report",
ALL_REPORTS: "Select Excel Files in the following order:\n (1) Resource Reconciliation\n (2) Resource Requirement\n (3) Stock Report"
}


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Excel Report Transformer")
        self.geometry("600x400")

        self.report_type = tk.StringVar()
        self.selected_files = []
        self.output_files = []

        container = tk.Frame(self)
        container.pack(fill="both", expand=True)

        self.frames = {}
        for F in (ReportTypePage, FileSelectPage, OutputPage):
            frame = F(container, self)
            self.frames[F] = frame
            frame.grid(row=0, column=0, sticky="nsew")

        self.show_frame(ReportTypePage)

    def show_frame(self, page):
        frame = self.frames[page]
        frame.tkraise()


class ReportTypePage(tk.Frame):
    def __init__(self, parent, controller):
        super().__init__(parent)
        self.controller = controller

        tk.Label(self, text="Step 1: Select Report Type", font=("Arial", 14, "bold")).pack(pady=20)

        ttk.Label(self, text="Choose report type to generate:").pack(pady=5)
        combo = ttk.Combobox(self, textvariable=controller.report_type, state="readonly")
        combo['values'] = ["-- Select Report Type --",LABOUR_REPORT, MATERIAL_REPORT,ACTIVITY_COSTING_REPORT,ALL_REPORTS]
        combo.current(0)
        combo.pack(pady=5)

        ttk.Button(self, text="Next ➜", command=self.next_page).pack(pady=20)

    def next_page(self):
        if self.controller.report_type.get() == "-- Select Report Type --":
            messagebox.showwarning("Warning", "Please select a report type.")
            return
        self.controller.show_frame(FileSelectPage)


class FileSelectPage(tk.Frame):
    def __init__(self, parent, controller):
        super().__init__(parent)
        self.controller = controller

        tk.Label(self, text="Step 2: Select Required Input Files", font=("Arial", 14, "bold")).pack(pady=20)

        self.info_label = tk.Label(self, text=INPUT_REQ_DIR[self.controller.report_type.get()], justify="left")
        self.info_label.pack(pady=10)

        ttk.Button(self, text="Browse Files", command=self.select_files).pack(pady=10)

        self.file_labels = []
        for i in range(3):
                f_label = tk.Label(self, text=f"File {i + 1}: Not Selected", anchor="w")
                f_label.pack(fill="x", padx=40, pady=3)
                self.file_labels.append(f_label)


        ttk.Button(self, text="Next ➜", command=self.next_page).pack(pady=10)

    def tkraise(self, *args, **kwargs):
        """Update instructions each time this page appears."""
        super().tkraise(*args, **kwargs)
        report_type = self.controller.report_type.get()
        instruction = INPUT_REQ_DIR.get(report_type, "")
        self.info_label.config(text=instruction)


    def select_files(self):
        files = filedialog.askopenfilenames(title="Select Excel Files", filetypes=[("Excel files", "*.xlsx *.xls")])
        # if len(files) != 3:
        #     messagebox.showerror("Error", "Please select exactly 3 files in the correct order.")
        #     return
        self.controller.selected_files = files
        for i, path in enumerate(files):
            name = os.path.basename(path)
            if i < len(files):
                self.file_labels[i].config(text=f"File {i + 1}: {name}")

    def next_page(self):
        if not self.controller.selected_files:
            messagebox.showerror("Error", "Please select files first.")
            return

        try:
            df_list = [pd.read_excel(f, skiprows=1) for f in self.controller.selected_files]
            self.controller.output_files = excel_transform(df_list, self.controller.report_type.get())
        except Exception as e:
            messagebox.showerror("Error", f"Transformation failed:\n{e}")
            return

        self.controller.show_frame(OutputPage)


class OutputPage(tk.Frame):
    def __init__(self, parent, controller):
        super().__init__(parent)
        self.controller = controller
        tk.Label(self, text="Step 3: Output Files Generated", font=("Arial", 14, "bold")).pack(pady=20)

        tk.Label(self, text=f'The following files were generated in current working directory : \n', font=("Arial", 12, "bold")).pack(pady=20)

        # output_text = "\n".join(self.controller.output_files)
        # tk.Label(self, text=output_text, font=("Arial", 14, "bold")).pack(pady=20)
        self.output_label = tk.Label(self, text=INPUT_REQ_DIR[self.controller.report_type.get()], justify="left")
        self.output_label.pack(pady=10)

        ttk.Button(self, text="Open Folder", command=self.open_folder).pack(pady=5)
        ttk.Button(self, text="Finish", command=self.quit).pack(pady=5)

    def tkraise(self, *args, **kwargs):
        super().tkraise(*args, **kwargs)
        # self.result_box.delete("1.0", tk.END)

        if not self.controller.output_files:
            self.output_label.config(text="No output files were generated.\n")
        else:
            # Join all file paths into one string with newlines
            output_text = "".join(self.controller.output_files)
            # self.result_box.insert(tk.END, output_text)
            self.output_label.config(text=output_text)

    def open_folder(self):
        if self.controller.output_files:
            folder = os.path.dirname(self.controller.output_files[0])

            try:
                if platform.system() == "Windows":
                    os.startfile(folder)
                elif platform.system() == "Darwin":  # macOS
                    subprocess.Popen(["open", folder])
                else:  # Linux
                    subprocess.Popen(["xdg-open", folder])
            except Exception as e:
                messagebox.showerror("Error", f"Could not open folder:\n{e}")


if __name__ == "__main__":
    app = App()
    app.mainloop()
