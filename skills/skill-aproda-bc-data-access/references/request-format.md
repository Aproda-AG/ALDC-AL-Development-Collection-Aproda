# Request format — Aproda BC Data Access API

API page `aproda/bcDataAccess/v1.0`, entity set `dataRequests`. The library (`Invoke-BcDataQuery`) builds the HTTP body;
you only pass the **request JSON**.

## HTTP (for reference)

```
POST https://api.businesscentral.dynamics.com/v2.0/<tenant>/<environment>/api/aproda/bcDataAccess/v1.0/companies(<companyId>)/dataRequests
{ "id": "<new GUID>", "request": "<request JSON as a string>" }
→ 201 { "id": "…", "result": "<result JSON as a string>" }
```

The `id` is **mandatory**: without a field bound to the record, Business Central does not run the page's insert
trigger and answers `201` with an empty `result` (E-012 F-19). The library always sends a new GUID.

## Request

```jsonc
{
  "tables": [
    {
      "table": "Payment Terms",                  // AL object name or number (e.g. 3, 2000000153)
      "fields": ["Code", "Due Date Calculation"], // REQUIRED, AL field names or numbers
      "filters": [ { "field": "Code", "filter": "1*" } ], // optional, BC filter syntax
      "top": 10                                  // optional, default and maximum 1000
    }
  ]
}
```

## Response (`result`)

```jsonc
[ { "tableNo": 3, "tableName": "Payment Terms", "records": [ { "Code": "…", "Due Date Calculation": "…" } ] } ]
```

In PowerShell `Invoke-BcDataQuery` returns this array already parsed — one object per requested table:

```powershell
$r = Invoke-BcDataQuery -Request $req
$r[0].tableName                # "Payment Terms"
@($r[0].records).Count         # number of rows of the first table — the rows are in .records (there is no .rows)
$r[0].records | Format-Table   # the rows
```

Only `-OutFile` returns a summary (`tableName`, `rows`, `file`) instead of the data.

| Field type | JSON value |
|---|---|
| Integer, BigInteger, Decimal | number |
| Boolean | `true` / `false` |
| Option / Enum | the value **name** |
| Code, Text | string |
| FlowField | calculated value of its type |
| Blob | Base64; larger than 64 KB → `null` plus `"<field>__truncated": true` |
| Media, MediaSet | the media id (GUID text) |
| Date, Time, DateTime, Guid, DateFormula, … | XML format (`Format(value, 0, 9)`) |

## Limits

- Read-only; runs with the signed-in user's permissions (`You do not have permission to read table …`).
- FlowFilter fields cannot be requested; obsolete-removed fields are not found.
- At most 1000 rows per table; no paging, sorting or aggregation (v1). Measured: ≈ 130 bytes per row for 5 fields;
  p95 410 ms per request.
- Several tables per request are fine; up to 5 parallel requests were measured without errors.

## Examples (shapes)

```json
{"tables":[{"table":"Payment Terms","fields":["Code","Due Date Calculation","Description"],"top":10}]}
{"tables":[{"table":"Customer","fields":["No.","<table-extension field>"],"top":5}]}
{"tables":[{"table":"G/L Account","filters":[{"field":"Account Type","filter":"Posting"}],"fields":["No.","Name","Balance"],"top":20}]}
{"tables":[{"table":2000000153,"fields":["Name","Publisher","Version Major","Version Minor","Published As"],"top":200}]}
{"tables":[{"table":17,"fields":["Entry No.","G/L Account No.","Posting Date","Amount","Document No."],"top":1000}]}
```
