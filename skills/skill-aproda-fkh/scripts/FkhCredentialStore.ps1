<#
.SYNOPSIS
  Fkh credential store — DPAPI-protected (current user + machine only) cache for the
  UserPassword credentials used against an Fkh (AKS) BC container's web client.
  IMMUTABLE TEMPLATE. Loaded content-safe (SRP-exempt) by consumers; never edit per project.
.NOTES
  Owned by skill-aproda-fkh (D-26: Fkh owns transport/auth mechanics). Consumed by
  skill-aproda-deploy-run-verify's engine and may be reused by any ad-hoc Fkh script instead
  of hardcoding credentials.
  Store: %LOCALAPPDATA%\AprodaFkh\credentials\<sanitized-key>.cred.xml (one file per Fkh
  container hostname — different containers, same or different passwords, no collisions).
#>

function Get-FkhCredentialStoreDir {
    $dir = Join-Path $env:LOCALAPPDATA 'AprodaFkh\credentials'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function ConvertTo-FkhCredentialStoreFileName {
    param([Parameter(Mandatory)][string]$Key)
    $invalid = [regex]::Escape([string]([IO.Path]::GetInvalidFileNameChars() -join ''))
    ([regex]::Replace($Key, "[$invalid]", '_')) + '.cred.xml'
}

function Get-FkhStoredCredential {
    # Returns a PSCredential, or $null if none is stored or it can't be decrypted here
    # (e.g. copied to a different user/machine — DPAPI ties it to where it was saved).
    param([Parameter(Mandatory)][string]$Key)
    $path = Join-Path (Get-FkhCredentialStoreDir) (ConvertTo-FkhCredentialStoreFileName -Key $Key)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Import-Clixml -LiteralPath $path }
    catch {
        Write-Warning "Stored Fkh credential for '$Key' could not be read ($($_.Exception.Message)) — ignoring."
        $null
    }
}

function Save-FkhCredential {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential)
    $path = Join-Path (Get-FkhCredentialStoreDir) (ConvertTo-FkhCredentialStoreFileName -Key $Key)
    $Credential | Export-Clixml -LiteralPath $path -Force
}

function Remove-FkhStoredCredential {
    param([Parameter(Mandatory)][string]$Key)
    $path = Join-Path (Get-FkhCredentialStoreDir) (ConvertTo-FkhCredentialStoreFileName -Key $Key)
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
