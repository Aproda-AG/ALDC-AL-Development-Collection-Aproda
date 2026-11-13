namespace Aproda.BCDataAccess;

table 91050 "Data Request DA APD"
{
    Caption = 'Data Request', Locked = true;
    TableType = Temporary;
    DataClassification = SystemMetadata;
    Access = Internal;

    fields
    {
        field(1; Id; Guid)
        {
            Caption = 'Id', Locked = true;
        }
        field(2; Result; Blob)
        {
            Caption = 'Result', Locked = true;
        }
    }

    keys
    {
        key(PK; Id)
        {
            Clustered = true;
        }
    }
}
