namespace Aproda.BCDataAccess;

permissionset 91050 "DA APD Exec"
{
    Assignable = true;
    Caption = 'Data Access Exec', Locked = true;

    Permissions =
        page "Data Access API DA APD" = X,
        codeunit "Data Access Mgt DA APD" = X;
}
