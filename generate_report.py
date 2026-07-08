#!/usr/bin/env python3
"""Generate a PDF project status report styled like LaTeX."""

from fpdf import FPDF

class Report(FPDF):
    def header(self):
        self.set_font("Times", "B", 18)
        self.cell(0, 12, "Project Status Report -- DSLS App", new_x="LMARGIN", new_y="NEXT", align="C")
        self.set_font("Times", "I", 12)
        self.cell(0, 8, "June 2026", new_x="LMARGIN", new_y="NEXT", align="C")
        self.ln(6)

    def footer(self):
        self.set_y(-15)
        self.set_font("Times", "I", 10)
        self.cell(0, 10, f"Page {self.page_no()}", align="C")

pdf = Report(orientation="P", unit="mm", format="A4")
pdf.set_auto_page_break(auto=True, margin=20)
pdf.add_page()

pdf.set_font("Times", "", 12)

# Salutation
pdf.ln(4)
pdf.cell(0, 7, "Dear Aunt Pauline,", new_x="LMARGIN", new_y="NEXT")
pdf.ln(3)

# Thank-you paragraph
body1 = (
    "I hope this message finds you well. I am writing to express my sincere "
    "gratitude for your generous contribution of UGX 200,000 toward the "
    "development of the DSLS App project. Your support has made a real difference."
)
pdf.multi_cell(0, 6, body1)
pdf.ln(4)

# Progress section
pdf.set_font("Times", "B", 12)
pdf.cell(0, 7, "Project Progress", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Times", "", 12)
pdf.ln(1)

body2 = (
    "The DSLS App is a software platform currently in active development. "
    "Even with modest investment, the project has achieved meaningful progress "
    "and continues to show promising results. We have successfully set up the "
    "core architecture and are now refining key features. Development is still "
    "ongoing as we work toward a stable and complete release."
)
pdf.multi_cell(0, 6, body2)
pdf.ln(4)

# Accountability section
pdf.set_font("Times", "B", 12)
pdf.cell(0, 7, "Accountability", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Times", "", 12)
pdf.ln(1)
pdf.cell(0, 6, "Below is a summary of how your contribution has been utilised:", new_x="LMARGIN", new_y="NEXT")
pdf.ln(3)

# Table
col_w = 120
col2_w = 50
pdf.set_font("Times", "B", 11)
pdf.cell(col_w, 7, "Item", border="B")
pdf.cell(col2_w, 7, "Amount (UGX)", border="B", new_x="LMARGIN", new_y="NEXT")

pdf.set_font("Times", "", 11)
items = [
    ("Internet data bundles (research, hosting, API)", "80,000"),
    ("AI and API service subscriptions", "55,000"),
    ("Transport for team meetings and collaboration", "40,000"),
    ("Printing and photocopying project documents", "25,000"),
]

for desc, amt in items:
    pdf.cell(col_w, 7, desc)
    pdf.cell(col2_w, 7, amt, new_x="LMARGIN", new_y="NEXT")

pdf.set_font("Times", "B", 11)
pdf.cell(col_w, 7, "Total", border="T")
pdf.cell(col2_w, 7, "200,000", border="T", new_x="LMARGIN", new_y="NEXT")

pdf.ln(8)

# Closing
pdf.set_font("Times", "", 12)
body3 = (
    "Thank you once again for your kindness and belief in this project. "
    "I will continue to keep you updated on our progress."
)
pdf.multi_cell(0, 6, body3)
pdf.ln(6)

pdf.cell(0, 7, "With gratitude,", new_x="LMARGIN", new_y="NEXT")
pdf.ln(2)
pdf.set_font("Times", "B", 12)
pdf.cell(0, 7, "Okello David", new_x="LMARGIN", new_y="NEXT")

pdf.output("report.pdf")
print("PDF generated: report.pdf")
