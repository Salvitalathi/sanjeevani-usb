<#
    Sanjeevani PC Doctor - start it on any Windows PC with one line, without the USB:

        irm https://raw.githubusercontent.com/Salvitalathi/sanjeevani-usb/main/run.ps1 | iex

    (paste into PowerShell opened as Administrator). Like Chris Titus' WinUtil.
    It downloads the latest PC Doctor from GitHub (only the kit folder, about 2 MB) into
    %LOCALAPPDATA%\Sanjeevani-Web and starts it. Tools that are not on a USB are downloaded
    by PC Doctor's Tools guide from their official sites when needed.
    Nothing is installed; delete the Sanjeevani-Web folder to remove it.

    Note: this works only while the GitHub repository is public.
    Keep this file ASCII-only: "irm | iex" must not see a byte-order mark.
#>
& {
    $ErrorActionPreference = 'Stop'
    $repo   = 'Salvitalathi/sanjeevani-usb'
    $branch = 'main'
    $dest   = Join-Path $env:LOCALAPPDATA 'Sanjeevani-Web'
    $zip    = Join-Path $env:TEMP 'sanjeevani-web.zip'
    $tmp    = Join-Path $env:TEMP 'sanjeevani-web'

    Write-Host ''
    Write-Host '  Sanjeevani PC Doctor  -  by Mangesh Salvi' -ForegroundColor Cyan
    Write-Host '  PC Doctor download hot aahe / downloading ...' -ForegroundColor Gray

    if ($PSVersionTable.PSVersion.Major -lt 5) { Write-Host '  Windows PowerShell 5.1 or newer is needed.' -ForegroundColor Red; return }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    try {
        $url = "https://codeload.github.com/$repo/zip/refs/heads/$branch"
        $ProgressPreference = 'SilentlyContinue'      # the progress bar makes Invoke-WebRequest 10x slower on PS 5.1
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
        $kit = Join-Path $src.FullName 'kit'
        if (-not (Test-Path -LiteralPath (Join-Path $kit 'Sanjeevani\PCDoctor\PCDoctor.ps1'))) { throw 'PC Doctor was not found in the download.' }
        # keep the user's settings, reports and downloaded tools from an earlier run; replace only the program files
        $null = New-Item -ItemType Directory -Path $dest -Force
        $pd = Join-Path $dest 'kit\Sanjeevani\PCDoctor'
        foreach ($d in 'lib', 'data', 'assets', 'Rescue') { $p = Join-Path $pd $d; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force } }
        Copy-Item -Path $kit -Destination $dest -Recurse -Force
        Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Internet tapasa, kiwa Sanjeevani USB varun PC Doctor chalva.' -ForegroundColor Yellow
        return
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $doc = Join-Path $dest 'kit\Sanjeevani\PCDoctor\PCDoctor.ps1'
    Write-Host '  PC Doctor suru hot aahe / starting ...' -ForegroundColor Green
    # PC Doctor asks for administrator rights itself when it was not started as administrator
    Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$doc`"")
}
