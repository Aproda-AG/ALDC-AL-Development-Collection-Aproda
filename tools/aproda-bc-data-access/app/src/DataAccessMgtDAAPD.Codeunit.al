namespace Aproda.BCDataAccess;

using System.Reflection;
using System.Text;
using System.Utilities;

codeunit 91050 "Data Access Mgt DA APD"
{
    Access = Internal;

    var
        MaxRowsPerTable: Integer;
        MaxBlobLength: Integer;
        ResultText: Text;
        TableNos: Text;
        TotalRows: Integer;
        InvalidRequestErr: Label 'The request is not valid JSON or has no "tables" array.', Locked = true;
        TableNotFoundErr: Label 'Table %1 was not found.', Comment = '%1 = table name or number', Locked = true;
        NoReadPermissionErr: Label 'You do not have permission to read table %1.', Comment = '%1 = table name', Locked = true;
        FieldsRequiredErr: Label 'The "fields" array is required for table %1.', Comment = '%1 = table name', Locked = true;
        FieldNotFoundErr: Label 'Field %1 was not found in table %2.', Comment = '%1 = field name or number, %2 = table name', Locked = true;
        FlowFilterFieldErr: Label 'Field %1 in table %2 is a FlowFilter and cannot be returned.', Comment = '%1 = field name, %2 = table name', Locked = true;
        InvalidFilterErr: Label 'Each filter needs a "field" and a "filter" value (table %1).', Comment = '%1 = table name', Locked = true;
        RequestDeniedTelemetryMsg: Label 'Data Access API request denied or failed.', Locked = true;
        RequestServedTelemetryMsg: Label 'Data Access API request served.', Locked = true;

    procedure ProcessRequest(Request: Text): Text
    var
        ErrorText: Text;
    begin
        Clear(ResultText);
        Clear(TableNos);
        Clear(TotalRows);
        if not TryProcessRequest(Request) then begin
            ErrorText := GetLastErrorText();
            LogRequestDenied(ErrorText);
            Error(ErrorText);
        end;
        LogRequestServed(TableNos, TotalRows);
        exit(ResultText);
    end;

    [TryFunction]
    local procedure TryProcessRequest(Request: Text)
    var
        RequestObject: JsonObject;
        TablesToken: JsonToken;
        TableToken: JsonToken;
        Result: JsonArray;
    begin
        MaxRowsPerTable := 1000;
        MaxBlobLength := 65536;
        if not RequestObject.ReadFrom(Request) then
            Error(InvalidRequestErr);
        if not RequestObject.Get('tables', TablesToken) then
            Error(InvalidRequestErr);
        if not TablesToken.IsArray() then
            Error(InvalidRequestErr);

        foreach TableToken in TablesToken.AsArray() do
            Result.Add(ReadTable(TableToken.AsObject()));

        Result.WriteTo(ResultText);
    end;

    local procedure ReadTable(TableRequest: JsonObject): JsonObject
    var
        RecRef: RecordRef;
        Token: JsonToken;
        FieldNos: List of [Integer];
        FieldNo: Integer;
        Records: JsonArray;
        TableResult: JsonObject;
        TableNo: Integer;
        Top: Integer;
        RowCount: Integer;
    begin
        if not TableRequest.Get('table', Token) then
            Error(TableNotFoundErr, '');
        TableNo := ResolveTableNo(Token);

        RecRef.Open(TableNo);
        if not RecRef.ReadPermission() then
            Error(NoReadPermissionErr, RecRef.Name());

        ResolveFieldNos(TableRequest, RecRef, FieldNos);
        ApplyFilters(TableRequest, RecRef);
        foreach FieldNo in FieldNos do
            if RecRef.Field(FieldNo).Class() = FieldClass::Normal then
                RecRef.AddLoadFields(FieldNo);

        Top := MaxRowsPerTable;
        if TableRequest.Get('top', Token) then
            if Token.AsValue().AsInteger() > 0 then
                if Token.AsValue().AsInteger() < MaxRowsPerTable then
                    Top := Token.AsValue().AsInteger();

        if RecRef.FindSet() then
            repeat
                Records.Add(RecordToJson(RecRef, FieldNos));
                RowCount += 1;
            until (RecRef.Next() = 0) or (RowCount >= Top);

        TableResult.Add('tableNo', TableNo);
        TableResult.Add('tableName', RecRef.Name());
        TableResult.Add('records', Records);
        RecRef.Close();

        if TableNos <> '' then
            TableNos += ',';
        TableNos += Format(TableNo);
        TotalRows += RowCount;
        exit(TableResult);
    end;

    local procedure ResolveTableNo(TableToken: JsonToken): Integer
    var
        AllObjWithCaption: Record AllObjWithCaption;
        TableName: Text;
        TableNo: Integer;
    begin
        if IsJsonString(TableToken) then begin
            TableName := TableToken.AsValue().AsText();
            AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Table);
            AllObjWithCaption.SetRange("Object Name", CopyStr(TableName, 1, MaxStrLen(AllObjWithCaption."Object Name")));
            if not AllObjWithCaption.FindFirst() then
                Error(TableNotFoundErr, TableName);
            exit(AllObjWithCaption."Object ID");
        end;

        TableNo := TableToken.AsValue().AsInteger();
        if not AllObjWithCaption.Get(AllObjWithCaption."Object Type"::Table, TableNo) then
            Error(TableNotFoundErr, TableNo);
        exit(TableNo);
    end;

    local procedure ResolveFieldNos(TableRequest: JsonObject; RecRef: RecordRef; var FieldNos: List of [Integer])
    var
        FieldsToken: JsonToken;
        FieldToken: JsonToken;
        FieldNo: Integer;
    begin
        if not TableRequest.Get('fields', FieldsToken) then
            Error(FieldsRequiredErr, RecRef.Name());
        if not FieldsToken.IsArray() then
            Error(FieldsRequiredErr, RecRef.Name());
        if FieldsToken.AsArray().Count() = 0 then
            Error(FieldsRequiredErr, RecRef.Name());

        foreach FieldToken in FieldsToken.AsArray() do begin
            FieldNo := ResolveFieldNo(FieldToken, RecRef);
            if RecRef.Field(FieldNo).Class() = FieldClass::FlowFilter then
                Error(FlowFilterFieldErr, RecRef.Field(FieldNo).Name(), RecRef.Name());
            FieldNos.Add(FieldNo);
        end;
    end;

    local procedure ResolveFieldNo(FieldToken: JsonToken; RecRef: RecordRef): Integer
    var
        "Field": Record "Field";
        FieldName: Text;
        FieldNo: Integer;
    begin
        if IsJsonString(FieldToken) then begin
            FieldName := FieldToken.AsValue().AsText();
            Field.SetRange(TableNo, RecRef.Number());
            Field.SetRange(FieldName, CopyStr(FieldName, 1, MaxStrLen(Field.FieldName)));
            Field.SetFilter(ObsoleteState, '<>%1', Field.ObsoleteState::Removed);
            if not Field.FindFirst() then
                Error(FieldNotFoundErr, FieldName, RecRef.Name());
            exit(Field."No.");
        end;

        FieldNo := FieldToken.AsValue().AsInteger();
        if not RecRef.FieldExist(FieldNo) then
            Error(FieldNotFoundErr, FieldNo, RecRef.Name());
        exit(FieldNo);
    end;

    local procedure ApplyFilters(TableRequest: JsonObject; var RecRef: RecordRef)
    var
        FiltersToken: JsonToken;
        FilterToken: JsonToken;
        FieldToken: JsonToken;
        ValueToken: JsonToken;
        FilterObject: JsonObject;
    begin
        if not TableRequest.Get('filters', FiltersToken) then
            exit;
        if not FiltersToken.IsArray() then
            Error(InvalidFilterErr, RecRef.Name());

        foreach FilterToken in FiltersToken.AsArray() do begin
            FilterObject := FilterToken.AsObject();
            if not (FilterObject.Get('field', FieldToken) and FilterObject.Get('filter', ValueToken)) then
                Error(InvalidFilterErr, RecRef.Name());
            RecRef.Field(ResolveFieldNo(FieldToken, RecRef)).SetFilter(ValueToken.AsValue().AsText());
        end;
    end;

    local procedure RecordToJson(RecRef: RecordRef; FieldNos: List of [Integer]): JsonObject
    var
        TempBlob: Codeunit "Temp Blob";
        FldRef: FieldRef;
        RecordObject: JsonObject;
        FieldNo: Integer;
        Truncated: Boolean;
    begin
        foreach FieldNo in FieldNos do begin
            FldRef := RecRef.Field(FieldNo);
            if FldRef.Class() = FieldClass::FlowField then
                FldRef.CalcField();
            if FldRef.Type() = FieldType::Blob then begin
                FldRef.CalcField();
                TempBlob.FromFieldRef(FldRef);
                Truncated := TempBlob.Length() > MaxBlobLength;
                if Truncated then begin
                    RecordObject.Add(FldRef.Name(), BlobToJson(TempBlob, Truncated));
                    RecordObject.Add(FldRef.Name() + '__truncated', true);
                end else
                    RecordObject.Add(FldRef.Name(), BlobToJson(TempBlob, Truncated));
            end else
                RecordObject.Add(FldRef.Name(), FieldValueToJson(FldRef));
        end;
        exit(RecordObject);
    end;

    local procedure BlobToJson(var TempBlob: Codeunit "Temp Blob"; Truncated: Boolean): JsonValue
    var
        Base64Convert: Codeunit "Base64 Convert";
        JValue: JsonValue;
        BlobInStream: InStream;
    begin
        if Truncated or not TempBlob.HasValue() then
            JValue.SetValueToNull()
        else begin
            TempBlob.CreateInStream(BlobInStream);
            JValue.SetValue(Base64Convert.ToBase64(BlobInStream));
        end;
        exit(JValue);
    end;

    local procedure FieldValueToJson(FldRef: FieldRef): JsonValue
    var
        JValue: JsonValue;
        IntValue: Integer;
        BigIntValue: BigInteger;
        DecimalValue: Decimal;
        BoolValue: Boolean;
    begin
        case FldRef.Type() of
            FieldType::Integer:
                begin
                    IntValue := FldRef.Value();
                    JValue.SetValue(IntValue);
                end;
            FieldType::BigInteger:
                begin
                    BigIntValue := FldRef.Value();
                    JValue.SetValue(BigIntValue);
                end;
            FieldType::Decimal:
                begin
                    DecimalValue := FldRef.Value();
                    JValue.SetValue(DecimalValue);
                end;
            FieldType::Boolean:
                begin
                    BoolValue := FldRef.Value();
                    JValue.SetValue(BoolValue);
                end;
            FieldType::Option:
                begin
                    IntValue := FldRef.Value();
                    JValue.SetValue(FldRef.GetEnumValueNameFromOrdinalValue(IntValue));
                end;
            FieldType::Code, FieldType::Text:
                JValue.SetValue(Format(FldRef.Value()));
            FieldType::Media, FieldType::MediaSet:
                JValue.SetValue(Format(FldRef.Value()));
            else
                JValue.SetValue(Format(FldRef.Value(), 0, 9));
        end;
        exit(JValue);
    end;

    local procedure IsJsonString(Token: JsonToken): Boolean
    var
        RawValue: Text;
    begin
        if not Token.IsValue() then
            exit(false);
        Token.WriteTo(RawValue);
        exit(RawValue.StartsWith('"'));
    end;

    local procedure LogRequestDenied(ErrorText: Text)
    var
        CustomDimensions: Dictionary of [Text, Text];
    begin
        CustomDimensions.Add('Reason', CopyStr(ErrorText, 1, 250));
        Session.LogMessage('DAAPD0001', RequestDeniedTelemetryMsg, Verbosity::Warning, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    local procedure LogRequestServed(ServedTableNos: Text; ServedRows: Integer)
    var
        CustomDimensions: Dictionary of [Text, Text];
    begin
        CustomDimensions.Add('TableNos', ServedTableNos);
        CustomDimensions.Add('TotalRows', Format(ServedRows));
        Session.LogMessage('DAAPD0002', RequestServedTelemetryMsg, Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;
}
