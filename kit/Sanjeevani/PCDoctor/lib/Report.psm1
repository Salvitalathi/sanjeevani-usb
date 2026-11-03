# Sanjeevani PC Doctor - HTML report
Set-StrictMode -Off

function ConvertTo-PDHtml { param([string]$s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }

function New-PDReport {
    param([Parameter(Mandatory)]$Scan, $OSAdvice, [string[]]$Actions = @())
    $i = $Scan.Info
    $e = { param($x) ConvertTo-PDHtml $x }
    $sevColor = @{ Critical = '#e11d48'; Warning = '#d97706'; Info = '#2563eb'; OK = '#16a34a' }
    $sevMr = @{ Critical = 'गंभीर'; Warning = 'लक्ष द्या'; Info = 'माहिती'; OK = 'ठीक' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!DOCTYPE html><html lang="mr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PC Report - $(& $e $i.ComputerName)</title>
<style>
body{font-family:'Nirmala UI','Segoe UI',sans-serif;background:#f1f5f9;color:#0f172a;margin:0;padding:24px}
.wrap{max-width:980px;margin:auto}
h1{margin:0 0 4px;font-size:26px} h2{font-size:18px;margin:28px 0 10px;border-bottom:2px solid #2dd4bf;padding-bottom:6px}
.muted{color:#64748b;font-size:13px}
.card{background:#fff;border-radius:12px;padding:16px 18px;box-shadow:0 1px 3px rgba(0,0,0,.08);margin-bottom:12px}
.score{font-size:44px;font-weight:700}
table{width:100%;border-collapse:collapse;font-size:14px} td,th{padding:7px 8px;border-bottom:1px solid #e2e8f0;text-align:left;vertical-align:top}
th{background:#f8fafc;font-weight:600}
.sev{display:inline-block;color:#fff;border-radius:6px;padding:2px 8px;font-size:12px;font-weight:600}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px} @media(max-width:700px){.grid{grid-template-columns:1fr}}
@media print{body{background:#fff}.card{box-shadow:none;border:1px solid #ddd}}
</style></head><body><div class="wrap">
<div class="card"><h1>संजीवनी PC Doctor - तपासणी अहवाल</h1>
<div class="muted">$(& $e $i.ComputerName) · $(& $e $(if ($i.Model -like "$($i.Manufacturer)*") { $i.Model } else { "$($i.Manufacturer) $($i.Model)" })) · $(Get-Date $Scan.Time -Format 'dd-MM-yyyy HH:mm')</div>
<div style="margin-top:10px"><span class="score" style="color:$(if ($Scan.Score -ge 80) { '#16a34a' } elseif ($Scan.Score -ge 55) { '#d97706' } else { '#e11d48' })">$($Scan.Score)</span><span class="muted"> / 100 health score</span></div></div>
<h2>System</h2><div class="card"><table>
<tr><th>OS</th><td>$(& $e $i.OSCaption) $(& $e $i.DisplayVer) (build $($i.OSBuild))</td></tr>
<tr><th>CPU</th><td>$(& $e $i.CPU) - $($i.CPUCores) cores / $($i.CPUThreads) threads</td></tr>
<tr><th>RAM</th><td>$($i.RAMGB) GB $($i.RAMType) $(if ($i.RAMSpeed) { "$($i.RAMSpeed) MHz" }) · slots $($i.RAMSlotsUsed)/$($i.RAMSlotsTotal)</td></tr>
<tr><th>GPU</th><td>$(& $e $i.GPU)</td></tr>
<tr><th>$($i.SystemDrive) drive</th><td>$($i.SysFreeGB) GB free of $($i.SysSizeGB) GB ($($i.SysFreePct)%)</td></tr>
<tr><th>Firmware</th><td>$($i.Firmware) · Secure Boot: $($i.SecureBoot) · TPM: $(if ($i.TPM.Present) { $i.TPM.Version } else { 'नाही' })</td></tr>
<tr><th>Load</th><td>CPU $($Scan.Load.CPUPct)% · RAM $($Scan.Load.RAMPct)% · Disk $($Scan.Load.DiskPct)%</td></tr>
</table></div>
<h2>Disks</h2><div class="card"><table><tr><th>Model</th><th>Type</th><th>Size</th><th>Health</th><th>Temp</th><th>Wear</th></tr>
"@)
    foreach ($d in $i.Disks) {
        [void]$sb.Append("<tr><td>$(& $e $d.Model)$(if ($d.IsSystem) { ' <b>(Windows)</b>' })</td><td>$($d.MediaType) / $($d.BusType)</td><td>$($d.SizeGB) GB</td><td>$(& $e $d.Health)</td><td>$(if ($d.TempC) { "$($d.TempC)°C" })</td><td>$(if ($null -ne $d.WearPct) { "$($d.WearPct)%" })</td></tr>")
    }
    [void]$sb.Append('</table></div><h2>समस्या आणि सल्ला</h2><div class="card"><table>')
    foreach ($f in $Scan.Findings) {
        [void]$sb.Append("<tr><td style='width:90px'><span class='sev' style='background:$($sevColor[$f.Severity])'>$($sevMr[$f.Severity])</span></td><td><b>$(& $e $f.Title)</b><br><span class='muted'>$(& $e $f.Detail)</span></td></tr>")
    }
    [void]$sb.Append('</table></div>')
    if ($OSAdvice) {
        [void]$sb.Append('<h2>या PC साठी योग्य OS</h2><div class="card"><table><tr><th>OS</th><th>योग्यता</th><th>का?</th></tr>')
        foreach ($r in $OSAdvice.Recommendations) { [void]$sb.Append("<tr><td><b>$(& $e $r.Title)</b></td><td>$(& $e $r.Fit)</td><td>$(& $e $r.Why)</td></tr>") }
        [void]$sb.Append('</table>')
        if ($OSAdvice.Upgrades.Count) { [void]$sb.Append('<p><b>Hardware upgrade सल्ला:</b></p><ul>'); foreach ($u in $OSAdvice.Upgrades) { [void]$sb.Append("<li>$(& $e $u)</li>") }; [void]$sb.Append('</ul>') }
        [void]$sb.Append('</div>')
    }
    if ($Scan.AppAdvice.Count) {
        [void]$sb.Append('<h2>Apps: काढा / बदला</h2><div class="card"><table><tr><th>App</th><th>का?</th><th>हलका पर्याय</th></tr>')
        foreach ($a in $Scan.AppAdvice) { [void]$sb.Append("<tr><td>$(& $e $a.App)</td><td>$(& $e $a.Reason)</td><td>$(& $e $a.Alternatives)</td></tr>") }
        [void]$sb.Append('</table></div>')
    }
    if ($Actions.Count) {
        [void]$sb.Append('<h2>केलेली कामे</h2><div class="card"><ul>')
        foreach ($a in $Actions) { [void]$sb.Append("<li>$(& $e $a)</li>") }
        [void]$sb.Append('</ul></div>')
    }
    [void]$sb.Append("<p class='muted'>Sanjeevani Rescue USB · PC Doctor. Undo माहिती: $(& $e $global:PDCtx.UndoFile)</p></div></body></html>")
    $file = Join-Path $global:PDCtx.ReportDir ("Report-{0:yyyyMMdd-HHmm}.html" -f (Get-Date))
    [IO.File]::WriteAllText($file, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    Write-PDLog "Report तयार: $file" 'OK'
    return $file
}

Export-ModuleMember -Function *
