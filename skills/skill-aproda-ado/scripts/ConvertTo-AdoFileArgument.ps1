#Requires -Version 5.1
<#
.SYNOPSIS
    Writes a text value to a temp file and returns the `@<path>` argument form az CLI expects for it.
.DESCRIPTION
    az.cmd re-parses the command line through cmd.exe on Windows: embedded newlines truncate a value,
    shell metacharacters (< > & | ^) are misread as redirection/pipe operators, and a literal " breaks
    the argument boundary outright. az CLI's generic "@<file>" convention (documented for any string
    parameter, not just --description) reads the value straight from disk instead, so none of that ever
    touches the command line. Use this for any parameter carrying multiline or untrusted text --
    --description, --title, --discussion, etc.

    Returns an object with `Argument` (the "@<path>" string to pass to az) and `Path` (delete it after
    the az call, e.g. in a finally block).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Content
)

$path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "aproda-ado-$([guid]::NewGuid()).txt")
Set-Content -LiteralPath $path -Value $Content -NoNewline -Encoding utf8

[pscustomobject]@{
    Argument = "@$path"
    Path     = $path
}
