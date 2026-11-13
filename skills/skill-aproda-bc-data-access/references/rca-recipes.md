# RCA recipes — BC Data Access

Request JSONs for frequent support questions. Pass them to `Invoke-BcDataQuery -Request '<json>'`.
Cite results in diagnoses by table, key and setup value — never personal data (SKILL.md §7).

## Find field names of a table

```json
{"tables":[{"table":2000000041,"filters":[{"field":"TableNo","filter":"77"}],"fields":["No.","FieldName","Class","Type"],"top":200}]}
```

`Class` shows `Normal` / `FlowField` / `FlowFilter`. Works for base, PTE and table-extension fields.

## Installed apps and versions

```json
{"tables":[{"table":2000000153,"fields":["Name","Publisher","Version Major","Version Minor","Version Build","Published As"],"top":500}]}
```

## Report selection for a document

Step 1 — which usages exist (enum **names**, not captions):

```json
{"tables":[{"table":"Report Selections","fields":["Usage","Sequence","Report ID","Report Caption"],"top":1000}]}
```

Step 2 — one usage, e.g. posted sales invoice:

```json
{"tables":[{"table":"Report Selections","filters":[{"field":"Usage","filter":"S.Invoice"}],"fields":["Sequence","Report ID","Report Caption","Report Layout Name","Use for Email Attachment","Use for Email Body"],"top":50}]}
```

## Number series near their end

```json
{"tables":[
  {"table":"Sales & Receivables Setup","fields":["Customer Nos.","Order Nos.","Invoice Nos.","Posted Invoice Nos."],"top":1},
  {"table":"No. Series Line","fields":["Series Code","Starting No.","Ending No.","Last No. Used","Open"],"top":1000}
]}
```

Compare `Last No. Used` with `Ending No.` for the series named in the setup.

## Posting setup for a combination

```json
{"tables":[{"table":"General Posting Setup","filters":[{"field":"Gen. Bus. Posting Group","filter":"<group>"}],"fields":["Gen. Bus. Posting Group","Gen. Prod. Posting Group","Sales Account","Purch. Account","COGS Account"],"top":100}]}
```

## Users and permission assignments (counts only)

```json
{"tables":[{"table":2000000120,"filters":[{"field":"State","filter":"Enabled"}],"fields":["User Security ID"],"top":1000}]}
{"tables":[{"table":2000000053,"filters":[{"field":"Role ID","filter":"<permission set>"}],"fields":["Role ID","Company Name"],"top":1000}]}
```

Report the **number** of rows, not user names.

## Recent changes to a setup table (change log)

```json
{"tables":[{"table":"Change Log Entry","filters":[{"field":"Table No.","filter":"311"}],"fields":["Date and Time","Table No.","Field No.","Type of Change","Old Value","New Value"],"top":200}]}
```

Only when the change log is active for that table; do not record `User ID` values.

## Ledger entries of one document

```json
{"tables":[{"table":17,"filters":[{"field":"Document No.","filter":"<document no.>"}],"fields":["Entry No.","Posting Date","G/L Account No.","Amount","Dimension Set ID"],"top":200}]}
```
