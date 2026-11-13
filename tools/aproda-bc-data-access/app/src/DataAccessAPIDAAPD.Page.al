namespace Aproda.BCDataAccess;

page 91050 "Data Access API DA APD"
{
    PageType = API;
    APIPublisher = 'aproda';
    APIGroup = 'bcDataAccess';
    APIVersion = 'v1.0';
    EntityName = 'dataRequest';
    EntitySetName = 'dataRequests';
    Caption = 'Data Request', Locked = true;
    SourceTable = "Data Request DA APD";
    SourceTableTemporary = true;
    DelayedInsert = true;
    ODataKeyFields = Id;
    InsertAllowed = true;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.Id)
                {
                    Editable = false;
                }
                field(request; RequestTxt) { }
                field(result; ResultTxt)
                {
                    Editable = false;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        ResultInStream: InStream;
    begin
        Rec.CalcFields(Result);
        Rec.Result.CreateInStream(ResultInStream, TextEncoding::UTF8);
        ResultInStream.Read(ResultTxt);
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        DataAccessMgt: Codeunit "Data Access Mgt DA APD";
        ResultOutStream: OutStream;
    begin
        // The API response is built from the record, so the result must live on Rec, not in a page variable.
        ResultTxt := DataAccessMgt.ProcessRequest(RequestTxt);
        if IsNullGuid(Rec.Id) then
            Rec.Id := CreateGuid();
        Rec.Result.CreateOutStream(ResultOutStream, TextEncoding::UTF8);
        ResultOutStream.WriteText(ResultTxt);
        Rec.Insert(false);
        exit(false);
    end;

    var
        RequestTxt: Text;
        ResultTxt: Text;
}
