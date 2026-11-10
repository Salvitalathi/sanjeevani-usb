#Requires -Version 5.1
<#
    Sanjeevani PC Doctor - finds and fixes Windows problems, speeds up old PCs,
    frees the C: drive and advises which OS / apps suit this hardware.
    Runs on Windows 10/11 (Windows PowerShell 5.1). Needs administrator rights.
    Languages: English / मराठी / हिन्दी (chosen in Setup, changeable in the title bar).

    -SelfTest          build the window in every language and exit (CI)
    -Screenshot <dir>  render every page with sample data to PNG files and exit (CI)
#>
param([switch]$NoElevate, [ValidateSet('', 'en', 'mr', 'hi')][string]$Lang = '', [string]$Screenshot, [switch]$SelfTest)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off
$Headless = [bool]($Screenshot -or $SelfTest)

# ---------------------------------------------------------------- elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate -and -not $Headless) {
    try {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
        if ($Lang) { $a += @('-Lang', $Lang) }
        Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $a
    } catch { }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$Here    = $PSScriptRoot
$UsbRoot = (Resolve-Path (Join-Path $Here '..\..')).Path
$DataDir = Join-Path $Here 'data'
$Assets  = Join-Path $Here 'assets'
$Modules = @('Common', 'Diagnostics', 'Repair', 'Speed', 'Storage', 'Advisor', 'Report', 'ToolGuide', 'Integrity', 'Registry', 'Ask', 'LocalAI', 'Troubleshoot') | ForEach-Object { Join-Path $Here "lib\$_.psm1" }

try {
    foreach ($m in $Modules) { Import-Module $m -Force -DisableNameChecking -ErrorAction Stop }
    $null = Initialize-PDContext -UsbRoot $UsbRoot
} catch {
    if ($Headless) { Write-Host "SELFTEST FAILED: $($_.Exception.Message)"; exit 1 }
    [System.Windows.MessageBox]::Show("PC Doctor could not start / सुरू होऊ शकला नाही:`n$($_.Exception.Message)", 'Sanjeevani PC Doctor', 'OK', 'Error') | Out-Null
    exit 1
}

$global:PDLogQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$global:PDState = [hashtable]::Synchronized(@{ Progress = -1; Status = ''; Cancel = $false })

# ---------------------------------------------------------------- language
# first start without a saved language: small picker (same as Setup)
function Select-PDLanguage {
    [xml]$x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sanjeevani PC Doctor" Width="540" SizeToContent="Height" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#0A101E" FontFamily="Segoe UI, Nirmala UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,0,10"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="#111A2E" BorderBrush="#1C2942" BorderThickness="1" CornerRadius="10" Padding="18,12"><ContentPresenter HorizontalAlignment="Left"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#2DD4BF"/><Setter TargetName="b" Property="Background" Value="#16223A"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <StackPanel Margin="30,26,30,22">
    <TextBlock Text="Sanjeevani PC Doctor" FontSize="24" FontWeight="SemiBold" Foreground="#F1F5F9"/>
    <TextBlock Text="Choose your language  ·  भाषा निवडा  ·  भाषा चुनें" FontSize="13" Foreground="#93A3B8" Margin="0,2,0,18"/>
    <Button Tag="en"><TextBlock Text="English" FontSize="18" FontWeight="SemiBold"/></Button>
    <Button Tag="mr"><TextBlock Text="मराठी" FontSize="18" FontWeight="SemiBold"/></Button>
    <Button Tag="hi"><TextBlock Text="हिन्दी" FontSize="18" FontWeight="SemiBold"/></Button>
  </StackPanel>
</Window>
'@
    try {
        $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
        $script:picked = ''
        $w.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] { param($s, $e) $script:picked = [string]$e.OriginalSource.Tag; if (-not $script:picked) { $script:picked = [string]$e.OriginalSource.TemplatedParent.Tag }; $w.Close() })
        [void]$w.ShowDialog()
    } catch { }
    if ($script:picked -in 'en', 'mr', 'hi') { return $script:picked }
    return 'en'
}
if (-not $Lang) { $Lang = [string]$global:PDCtx.Lang }
if ($Lang -notin 'en', 'mr', 'hi') {
    if ($Headless) { $Lang = 'en' } else { $Lang = Select-PDLanguage; [void](Set-PDLangSetting -UsbRoot $UsbRoot -Lang $Lang) }
}
$global:PDCtx.Lang = $Lang
$global:PDLang = $Lang

# ---------------------------------------------------------------- row types for WPF binding
class FindingRow { [string]$Title; [string]$Detail; [string]$Color; [string]$SevText; [string]$FixTag; [string]$FixVisible; [string]$FixText }
class CheckRow   { [bool]$Selected; [string]$Name; [string]$Sub; [string]$Badge; [string]$BadgeVisible; [int]$Index }
class InfoRow    { [string]$Title; [string]$Badge; [string]$Color; [string]$Detail; [string]$Tag; [string]$ButtonVisible; [string]$ButtonText }

# ---------------------------------------------------------------- UI text (English / मराठी / हिन्दी)
# Technical words that read better in English (Scan, Startup, Registry, Report ...) are kept in English on purpose.
$UiText = @{
    'brand'          = @('Sanjeevani', 'संजीवनी', 'संजीवनी')
    'tagline'        = @('PC Doctor', 'PC Doctor', 'PC Doctor')
    'splash.sub'     = @('Diagnose · Repair · Speed up', 'तपासणी · दुरुस्ती · वेग', 'जाँच · मरम्मत · स्पीड')
    'nav.ask'        = @('Assistant', 'Assistant', 'Assistant')
    'nav.dashboard'  = @('Health Check', 'PC तपासणी', 'PC जाँच')
    'nav.repair'     = @('Repair', 'दुरुस्ती', 'मरम्मत')
    'nav.speed'      = @('Speed Up', 'वेग वाढवा', 'स्पीड बढ़ाएँ')
    'nav.storage'    = @('Disk Space', 'C: drive जागा', 'C: drive जगह')
    'nav.advisor'    = @('OS & Apps Advice', 'OS व Apps सल्ला', 'OS और Apps सलाह')
    'nav.toolbox'    = @('Tools Guide', 'Tools मार्गदर्शक', 'Tools गाइड')
    'nav.report'     = @('Report', 'Report', 'Report')
    'nav.section1'   = @('DIAGNOSE & FIX', 'तपासणी व दुरुस्ती', 'जाँच और मरम्मत')
    'nav.section2'   = @('TOOLS', 'TOOLS', 'TOOLS')
    'ready'          = @('Ready', 'तयार', 'तैयार')
    'log.show'       = @('Activity log', 'Activity log', 'Activity log')
    'stop'           = @('Stop', 'थांबवा', 'रोकें')
    # dashboard
    'dash.title'     = @('PC Health Check', 'PC ची तपासणी', 'PC की जाँच')
    'dash.sub'       = @('Start a scan - nothing on the PC is changed.', 'Scan सुरू करा - PC मध्ये काहीही बदलत नाही.', 'Scan शुरू करें - PC में कुछ भी नहीं बदलता।')
    'dash.quick'     = @('Quick Scan', 'Quick Scan', 'Quick Scan')
    'dash.quick.tip' = @('About 2 minutes', 'सुमारे 2 मिनिटे', 'लगभग 2 मिनट')
    'dash.deep'      = @('Deep Scan', 'Deep Scan', 'Deep Scan')
    'dash.deep.tip'  = @('Also checks Windows system files - about 20 minutes', 'Windows system files पण तपासतो - सुमारे 20 मिनिटे', 'Windows system files भी जाँचता है - लगभग 20 मिनट')
    'dash.score'     = @('Health score', 'Health score', 'Health score')
    'dash.noscan'    = @('Not scanned yet', 'अजून scan झाला नाही', 'अभी scan नहीं हुआ')
    'dash.opt.title' = @('Make an old PC fast in one click', 'एका click मध्ये जुना PC वेगवान करा', 'एक click में पुराना PC तेज़ करें')
    'dash.opt.sub'   = @('Restore point → junk cleanup → unneeded startup apps off → lighter visual effects → right power plan → ads / tips off → bloatware removal → report. Every change can be undone.',
                         'Restore point → junk cleanup → अनावश्यक startup बंद → हलके visual effects → योग्य power plan → ads / tips बंद → bloatware काढणे → report. प्रत्येक बदल Undo करता येतो.',
                         'Restore point → junk cleanup → बेकार startup बंद → हल्के visual effects → सही power plan → ads / tips बंद → bloatware हटाना → report. हर बदलाव Undo हो सकता है।')
    'dash.opt.btn'   = @('One-Click Optimize', 'One-Click Optimize', 'One-Click Optimize')
    'dash.findings'  = @('Findings', 'सापडलेल्या समस्या', 'मिली हुई समस्याएँ')
    'dash.empty'     = @('Run a Quick Scan to see this PC''s problems here.', 'या PC च्या समस्या इथे पाहण्यासाठी Quick Scan करा.', 'इस PC की समस्याएँ यहाँ देखने के लिए Quick Scan करें।')
    # repair
    'rep.title'      = @('Windows Repair', 'Windows दुरुस्ती', 'Windows मरम्मत')
    'rep.sub'        = @('A System Restore point is created before every repair. Do not switch the PC off while a repair runs.', 'प्रत्येक दुरुस्तीआधी आपोआप System Restore point तयार होतो. Repair चालू असताना PC बंद करू नका.', 'हर मरम्मत से पहले अपने आप System Restore point बनता है। Repair के दौरान PC बंद न करें।')
    'reg.title'      = @('Registry check', 'Registry तपासणी', 'Registry जाँच')
    'reg.sub'        = @('Finds settings changed by viruses (Task Manager disabled, programs hijacked, Defender off ...) and broken entries. This is not a "registry cleaner" that deletes thousands of entries - that does not make a PC faster and can break it. Restore point + backup before every fix, can be undone.',
                         'Virus ने बदललेल्या settings (Task Manager बंद, programs उघडताना दुसरेच चालणे, Defender बंद...) आणि तुटलेल्या entries शोधतो. हजारो entries delete करणारा "registry cleaner" नाही - त्याने PC वेगवान होत नाही, उलट बिघडू शकतो. प्रत्येक दुरुस्तीआधी restore point + backup, Undo करता येते.',
                         'Virus द्वारा बदली गई settings (Task Manager बंद, programs खोलने पर कुछ और चलना, Defender बंद...) और टूटी entries ढूँढता है। यह हज़ारों entries delete करने वाला "registry cleaner" नहीं है - उससे PC तेज़ नहीं होता, उल्टा बिगड़ सकता है। हर मरम्मत से पहले restore point + backup, Undo हो सकता है।')
    'reg.scan'       = @('Check registry', 'Registry तपासा', 'Registry जाँचें')
    'reg.fix'        = @('Fix selected', 'निवडलेले दुरुस्त करा', 'चुने हुए ठीक करें')
    # speed
    'spd.title'      = @('Speed Up Windows', 'वेग वाढवा / Windows हलके करा', 'स्पीड बढ़ाएँ / Windows हल्का करें')
    'spd.sub'        = @('Scan first - the options suggested for this PC will then be ticked.', 'आधी Scan करा म्हणजे या PC साठी सुचवलेले पर्याय निवडलेले दिसतील.', 'पहले Scan करें - इस PC के लिए सुझाए गए विकल्प चुने हुए दिखेंगे।')
    'spd.undo'       = @('Undo all changes', 'सर्व बदल Undo करा', 'सभी बदलाव Undo करें')
    'spd.tweaks'     = @('Tweaks', 'Tweaks', 'Tweaks')
    't.cleanup'      = @('Clean junk files (temp, old updates, error reports)', 'Junk files साफ करा (temp, जुने updates, error reports)', 'Junk files साफ करें (temp, पुराने updates, error reports)')
    't.recycle'      = @('Empty the Recycle Bin', 'Recycle Bin रिकामा करा', 'Recycle Bin खाली करें')
    't.component'    = @('Deep clean of old updates (DISM, 10-20 min)', 'जुन्या updates ची deep cleanup (DISM, 10-20 मिनिटे)', 'पुराने updates की deep cleanup (DISM, 10-20 मिनट)')
    't.visual'       = @('Animations / transparency off (fonts stay smooth)', 'Animations / transparency बंद (fonts smooth राहतील)', 'Animations / transparency बंद (fonts smooth रहेंगे)')
    't.power'        = @('Right power plan (Desktop: High performance, Laptop: Balanced)', 'योग्य Power plan (Desktop: High performance, Laptop: Balanced)', 'सही Power plan (Desktop: High performance, Laptop: Balanced)')
    't.suggest'      = @('Windows tips, ads and auto-installed apps off', 'Windows tips, ads, auto-installed apps बंद', 'Windows tips, ads, auto-installed apps बंद')
    't.services'     = @('Reduce telemetry and unneeded services', 'Telemetry व अनावश्यक services कमी करा', 'Telemetry और बेकार services कम करें')
    't.pagefile'     = @('Turn the page file on if it is off', 'Page file बंद असेल तर चालू करा', 'Page file बंद हो तो चालू करें')
    't.background'   = @('Do not let Store apps run in the background', 'Store apps background मध्ये चालू देऊ नका', 'Store apps को background में चलने न दें')
    't.hiber'        = @('Hibernation off (frees space equal to the RAM on C:)', 'Hibernation बंद (C: वर RAM इतकी जागा मोकळी)', 'Hibernation बंद (C: पर RAM जितनी जगह खाली)')
    'spd.apply'      = @('Apply selected tweaks', 'निवडलेले tweaks लावा', 'चुने हुए tweaks लगाएँ')
    'spd.startup'    = @('Startup programs', 'Startup programs', 'Startup programs')
    'spd.startup.sub'= @('✔ = starts with Windows. Removing the ✔ turns it off (the program is not uninstalled).', '✔ = Windows सोबत सुरू होईल. काढलेला ✔ म्हणजे बंद (program uninstall होत नाही).', '✔ = Windows के साथ शुरू होगा। ✔ हटाने पर बंद (program uninstall नहीं होता)।')
    'spd.suggestsel' = @('Select suggested', 'सुचवलेले निवडा', 'सुझाए गए चुनें')
    'apply'          = @('Apply', 'लागू करा', 'लागू करें')
    'spd.bloat'      = @('Pre-installed bloatware', 'Pre-installed bloatware', 'Pre-installed bloatware')
    'spd.bloat.sub'  = @('Only apps from a safe list. They can be reinstalled from the Microsoft Store.', 'फक्त सुरक्षित यादीतील apps. हवे असल्यास Microsoft Store मधून परत install करता येतात.', 'सिर्फ़ सुरक्षित सूची के apps। चाहें तो Microsoft Store से फिर install कर सकते हैं।')
    'spd.bloat.btn'  = @('Remove selected apps', 'निवडलेले apps काढा', 'चुने हुए apps हटाएँ')
    # storage
    'sto.title'      = @('Is the C: drive full?', 'C: drive भरला आहे?', 'C: drive भर गया है?')
    'sto.sub'        = @('Move your files (Desktop, Documents, Downloads, Photos ...) to another drive. Windows and installed programs stay on C:.', 'तुमचे files (Desktop, Documents, Downloads, Photos...) दुसऱ्या drive वर हलवा. Windows आणि installed programs C: वरच राहतात.', 'अपनी files (Desktop, Documents, Downloads, Photos...) दूसरे drive पर ले जाएँ। Windows और installed programs C: पर ही रहते हैं।')
    'sto.analyze'    = @('Analyze C: drive', 'C: drive तपासा', 'C: drive जाँचें')
    'sto.warn'       = @('Back up important data (external disk / pendrive) before changing partitions or moving files. Keep the laptop on the charger.', 'Partition बदलण्याआधी आणि files हलवण्याआधी महत्त्वाच्या data चा backup (external disk / pendrive) घ्या. Laptop charging ला लावून ठेवा.', 'Partition बदलने और files ले जाने से पहले ज़रूरी data का backup (external disk / pendrive) लें। Laptop को charger पर रखें।')
    'sto.status'     = @('Status', 'स्थिती', 'स्थिति')
    'sto.press'      = @('Press "Analyze C: drive".', '"C: drive तपासा" दाबा.', '"C: drive जाँचें" दबाएँ।')
    'sto.where'      = @('1. Where should the files go?', '1. Files कुठे हलवायच्या?', '1. Files कहाँ ले जाएँ?')
    'sto.drive'      = @('Drive:', 'Drive:', 'Drive:')
    'sto.nodrive'    = @('No second drive? Shrink C: and create a new DATA drive (data stays safe; cleaning up first gives more space).', 'दुसरा drive नसेल तर: C: लहान करून नवीन DATA drive बनवा (data सुरक्षित राहतो, पण आधी cleanup केल्यास जास्त जागा मिळते).', 'दूसरा drive नहीं है? C: छोटा करके नया DATA drive बनाएँ (data सुरक्षित रहता है; पहले cleanup करने से ज़्यादा जगह मिलती है)।')
    'sto.size'       = @('New drive size (GB):', 'नवीन drive size (GB):', 'नए drive का size (GB):')
    'sto.newpart'    = @('Create DATA drive', 'नवीन DATA drive बनवा', 'नया DATA drive बनाएँ')
    'sto.what'       = @('2. What to move?', '2. काय हलवायचे?', '2. क्या ले जाना है?')
    'sto.what.sub'   = @('Copy first → verify every file → then remove from C:. Your own folders in C:\ keep working at the old path (junction).', 'आधी copy → प्रत्येक file तपासणी → मग C: वरून काढणे. C:\ मधले स्वतःचे folders हलवल्यावर जुना path पण चालतो (junction).', 'पहले copy → हर file की जाँच → फिर C: से हटाना। C:\ के अपने folders पुराने path पर भी चलते रहते हैं (junction)।')
    'sto.move'       = @('Move selected', 'निवडलेले हलवा', 'चुने हुए ले जाएँ')
    # advisor
    'adv.title'      = @('The right OS and apps for this PC', 'या PC साठी योग्य OS आणि apps', 'इस PC के लिए सही OS और apps')
    'adv.sub'        = @('Which OS suits the hardware, which apps to remove and their lighter alternatives.', 'Hardware नुसार कोणते OS योग्य, कोणते apps काढावेत आणि त्यांचे हलके पर्याय.', 'Hardware के अनुसार कौन सा OS सही है, कौन से apps हटाएँ और उनके हल्के विकल्प।')
    'adv.run'        = @('Get advice', 'सल्ला तयार करा', 'सलाह बनाएँ')
    'adv.win11'      = @('Windows 11 compatibility', 'Windows 11 योग्यता', 'Windows 11 योग्यता')
    'adv.os'         = @('Recommended OS', 'शिफारस केलेले OS', 'सुझाया गया OS')
    'adv.upgrade'    = @('Hardware upgrade', 'Hardware upgrade', 'Hardware upgrade')
    'adv.apps'       = @('Apps: remove / use a lighter alternative', 'Apps: काढा / हलका पर्याय वापरा', 'Apps: हटाएँ / हल्का विकल्प लें')
    # assistant
    'ask.title'      = @('Sanjeevani Assistant', 'Sanjeevani Assistant', 'Sanjeevani Assistant')
    'ask.sub'        = @('Describe the PC / laptop problem in English, Marathi or Hindi. The Assistant understands it, checks this PC and fixes it automatically.', 'PC / laptop ची समस्या मराठी, हिंदी किंवा English मध्ये लिहा. Assistant ती समजून घेईल, या PC वर तपासेल आणि आपोआप दुरुस्त करेल.', 'PC / laptop की समस्या हिंदी, मराठी या English में लिखें। Assistant उसे समझेगा, इस PC पर जाँचेगा और अपने आप ठीक करेगा।')
    'ask.mode.auto'  = @('Auto', 'Auto', 'Auto')
    'ask.mode.basic' = @('Basic', 'Basic', 'Basic')
    'ask.settings'   = @('AI settings', 'AI settings', 'AI settings')
    'ask.go'         = @('Fix it', 'दुरुस्त करा', 'ठीक करें')
    'ask.hint'       = @('e.g. "internet not working", "laptop gets very hot", "printer not printing"', 'उदा. "net chalat nahi", "laptop खूप गरम होतो", "printer print देत नाही"', 'उदा. "net nahi chal raha", "laptop बहुत गर्म होता है", "printer print नहीं कर रहा"')
    'ai.sub'         = @('Offline AI (Gemma, on the USB) works without internet. Online AI is optional and uses your own API key - Google Gemini keys are free. The AI only understands the problem; every check and repair is done by PC Doctor''s own tested actions.',
                         'Offline AI (Gemma, USB वर) internet शिवाय चालतो. Online AI optional आहे आणि तुमची स्वतःची API key वापरतो - Google Gemini ची key मोफत आहे. AI फक्त समस्या समजून घेतो; प्रत्येक तपासणी आणि दुरुस्ती PC Doctor च्या स्वतःच्या तपासलेल्या actions ने होते.',
                         'Offline AI (Gemma, USB पर) बिना internet के चलता है। Online AI optional है और आपकी अपनी API key इस्तेमाल करता है - Google Gemini की key मुफ़्त है। AI सिर्फ़ समस्या समझता है; हर जाँच और मरम्मत PC Doctor के अपने जाँचे हुए actions से होती है।')
    'ai.online'      = @('Online AI', 'Online AI', 'Online AI')
    'ai.key'         = @('API key', 'API key', 'API key')
    'ai.model'       = @('Model', 'Model', 'Model')
    'ai.model.tip'   = @('Leave empty - the newest model is picked automatically', 'रिकामे ठेवा - नवीन model आपोआप निवडले जाते', 'खाली छोड़ें - नया model अपने आप चुना जाता है')
    'ai.pcinfo'      = @('Send PC details to the online AI (model, Windows, RAM, disk type, scan findings - no names or files)', 'Online AI ला PC ची माहिती पाठवा (model, Windows, RAM, disk प्रकार, scan findings - नावे किंवा files नाहीत)', 'Online AI को PC की जानकारी भेजें (model, Windows, RAM, disk प्रकार, scan findings - नाम या files नहीं)')
    'ai.save'        = @('Save', 'Save करा', 'Save करें')
    'ai.getkey'      = @('Get a free Gemini key', 'मोफत Gemini key मिळवा', 'मुफ़्त Gemini key पाएँ')
    'ai.warn'        = @('The key is stored on this USB (Sanjeevani\ai.json) - do not hand the USB to others. On the free tier Google may use questions to improve its service: never type names, phone numbers or passwords.',
                         'Key या USB वर (Sanjeevani\ai.json) save होते - USB इतरांना देऊ नका. मोफत key वर Google प्रश्न त्यांची सेवा सुधारण्यासाठी वापरू शकते: नावे, फोन नंबर किंवा passwords कधीही लिहू नका.',
                         'Key इस USB पर (Sanjeevani\ai.json) save होती है - USB दूसरों को न दें। मुफ़्त key पर Google सवालों को अपनी सेवा सुधारने में इस्तेमाल कर सकता है: नाम, फ़ोन नंबर या passwords कभी न लिखें।')
    # toolbox
    'tg.title'       = @('Tools Guide', 'Tools मार्गदर्शक', 'Tools गाइड')
    'tg.sub'         = @('What each tool does, when to use it and how - in plain words. "Check automatically" runs the tool itself and explains the result.', 'प्रत्येक tool काय करतो, कधी वापरायचा आणि कसा - सोप्या भाषेत. "आपोआप तपासा" tool स्वतः चालवून निकाल समजावून सांगतो.', 'हर tool क्या करता है, कब और कैसे इस्तेमाल करें - आसान भाषा में। "अपने आप जाँचें" tool खुद चलाकर नतीजा समझाता है।')
    'tg.search'      = @('Search: disk, battery, virus, hot ...', 'शोधा: disk, battery, virus, गरम...', 'खोजें: disk, battery, virus, गर्म...')
    # report
    'rpt.title'      = @('Report', 'Report', 'Report')
    'rpt.sub'        = @('An HTML report for the customer / your records (can be printed or saved as PDF).', 'Customer ला देण्यासाठी / record साठी HTML report (print / PDF करता येतो).', 'Customer को देने / record के लिए HTML report (print / PDF हो सकता है)।')
    'rpt.make'       = @('Create and open report', 'Report तयार करा आणि उघडा', 'Report बनाएँ और खोलें')
    'rpt.folder'     = @('Open reports folder', 'Reports folder उघडा', 'Reports folder खोलें')
}
function S([string]$key) {
    $v = $UiText[$key]
    if (-not $v) { return $key }
    $i = @{ en = 0; mr = 1; hi = 2 }[$Lang]
    if ($v[$i]) { return $v[$i] }
    return $v[0]
}

# ---------------------------------------------------------------- XAML  ({{key}} = UI text in the chosen language)
$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sanjeevani PC Doctor" Width="1240" Height="800" MinWidth="1000" MinHeight="640"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="CanResize" Background="#0A101E" Foreground="#E6EDF7"
        FontFamily="Segoe UI, Nirmala UI" FontSize="14" UseLayoutRounding="True">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="46" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <FontFamily x:Key="IconFont">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
    <SolidColorBrush x:Key="Card" Color="#111A2E"/>
    <SolidColorBrush x:Key="Line" Color="#1C2942"/>
    <SolidColorBrush x:Key="Muted" Color="#93A3B8"/>
    <SolidColorBrush x:Key="Accent" Color="#2DD4BF"/>
    <LinearGradientBrush x:Key="AccentGrad" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#14B8A6" Offset="0"/><GradientStop Color="#0D9488" Offset="1"/></LinearGradientBrush>
    <LinearGradientBrush x:Key="HeroGrad" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#10283A" Offset="0"/><GradientStop Color="#0F1B30" Offset="0.55"/><GradientStop Color="#111A2E" Offset="1"/></LinearGradientBrush>

    <!-- buttons: hover = light overlay fading in, press = slight shrink -->
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#E6EDF7"/>
      <Setter Property="Background" Value="#16223A"/>
      <Setter Property="BorderBrush" Value="#24324D"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid x:Name="root" RenderTransformOrigin="0.5,0.5">
              <Grid.RenderTransform><ScaleTransform/></Grid.RenderTransform>
              <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="9"/>
              <Border x:Name="hl" Background="#FFFFFF" CornerRadius="9" Opacity="0"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="hl" Storyboard.TargetProperty="Opacity" To="0.07" Duration="0:0:0.15"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="hl" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="root" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="0.97" Duration="0:0:0.08"/>
                  <DoubleAnimation Storyboard.TargetName="root" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="0.97" Duration="0:0:0.08"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="root" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.12"/>
                  <DoubleAnimation Storyboard.TargetName="root" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.12"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{StaticResource AccentGrad}"/>
      <Setter Property="BorderBrush" Value="#2DD4BF"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
    </Style>
    <Style x:Key="Nav" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#B4C2D6"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Margin" Value="12,1"/>
      <Setter Property="Padding" Value="14,10"/>
      <Setter Property="FontSize" Value="14.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="9"/>
              <Border x:Name="hl" Background="#FFFFFF" CornerRadius="9" Opacity="0"/>
              <Border Width="3" Height="18" HorizontalAlignment="Left" CornerRadius="2" Background="{TemplateBinding BorderBrush}"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="hl" Storyboard.TargetProperty="Opacity" To="0.05" Duration="0:0:0.15"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="hl" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="Width" Value="46"/><Setter Property="Height" Value="46"/>
      <Setter Property="Foreground" Value="#B4C2D6"/><Setter Property="FontFamily" Value="{StaticResource IconFont}"/><Setter Property="FontSize" Value="10"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#1C2942"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
              <MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="win:close"/></MultiTrigger.Conditions><Setter TargetName="b" Property="Background" Value="#C42B1C"/></MultiTrigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Seg" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Margin" Value="0"/><Setter Property="Padding" Value="12,5"/><Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Foreground" Value="#93A3B8"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
    </Style>

    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource IconFont}"/><Setter Property="FontSize" Value="16"/>
      <Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="0,0,12,0"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="FontSize" Value="26"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="#F1F5F9"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="17"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="#F1F5F9"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="Foreground" Value="#93A3B8"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="LineHeight" Value="21"/></Style>
    <Style x:Key="Label" TargetType="TextBlock"><Setter Property="Foreground" Value="#64748B"/><Setter Property="FontSize" Value="11"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background" Value="#111A2E"/><Setter Property="BorderBrush" Value="#1C2942"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="14"/><Setter Property="Padding" Value="20,18"/><Setter Property="Margin" Value="0,0,0,14"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#D5DEEA"/><Setter Property="Margin" Value="0,5"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="box" Width="18" Height="18" CornerRadius="5" BorderThickness="1.5" BorderBrush="#3B4B68" Background="#0D1526" VerticalAlignment="Top" Margin="0,1,10,0">
                <TextBlock x:Name="tick" Text="&#xE73E;" FontFamily="{StaticResource IconFont}" FontSize="11" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True"><Setter TargetName="box" Property="Background" Value="#0D9488"/><Setter TargetName="box" Property="BorderBrush" Value="#2DD4BF"/><Setter TargetName="tick" Property="Visibility" Value="Visible"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="#2DD4BF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0D1526"/><Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="BorderBrush" Value="#24324D"/>
      <Setter Property="CaretBrush" Value="#E6EDF7"/><Setter Property="Padding" Value="8,6"/><Setter Property="SelectionBrush" Value="#14B8A6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#2DD4BF"/></Trigger></ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="#0D1526"/><Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="BorderBrush" Value="#24324D"/><Setter Property="CaretBrush" Value="#E6EDF7"/><Setter Property="Padding" Value="8,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="PasswordBox">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#2DD4BF"/></Trigger></ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ComboToggle" TargetType="ToggleButton">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="b" Background="#0D1526" BorderBrush="#24324D" BorderThickness="1" CornerRadius="8">
              <TextBlock Text="&#xE70D;" FontFamily="{StaticResource IconFont}" FontSize="10" Foreground="#93A3B8" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"/>
            </Border>
            <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#2DD4BF"/></Trigger></ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="Height" Value="34"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Style="{StaticResource ComboToggle}" Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
              <ContentPresenter IsHitTestVisible="False" Margin="12,0,32,0" VerticalAlignment="Center" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                <Border Background="#111A2E" BorderBrush="#24324D" BorderThickness="1" CornerRadius="8" Margin="0,4,0,0" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="320">
                  <ScrollViewer><ItemsPresenter Margin="4"/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="Padding" Value="10,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="b" Property="Background" Value="#1C2942"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#134E4A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="{TemplateBinding Padding}" Margin="0,1"><ContentPresenter/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#16223A"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#13324A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#1C2942"/><Setter Property="Foreground" Value="#E6EDF7"/><Setter Property="BorderBrush" Value="#2E3F5E"/><Setter Property="Padding" Value="10,6"/>
    </Style>
    <!-- slim scroll bars -->
    <Style x:Key="ThumbStyle" TargetType="Thumb">
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Thumb"><Border x:Name="t" Background="#2A3A57" CornerRadius="4"/>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Background" Value="#3B4F73"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True"><Track.Thumb><Thumb Style="{StaticResource ThumbStyle}" Margin="1,2"/></Track.Thumb></Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="8"/><Setter Property="MinHeight" Value="8"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track" IsDirectionReversed="False"><Track.Thumb><Thumb Style="{StaticResource ThumbStyle}" Margin="2,1"/></Track.Thumb></Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid ClipToBounds="True">
              <Border x:Name="PART_Track" Background="#1C2942" CornerRadius="3"/>
              <Border x:Name="PART_Indicator" Background="{StaticResource AccentGrad}" CornerRadius="3" HorizontalAlignment="Left"/>
              <Border x:Name="glow" Width="90" CornerRadius="3" HorizontalAlignment="Left" Visibility="Collapsed">
                <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#002DD4BF" Offset="0"/><GradientStop Color="#FF2DD4BF" Offset="0.5"/><GradientStop Color="#002DD4BF" Offset="1"/></LinearGradientBrush></Border.Background>
                <Border.RenderTransform><TranslateTransform X="-90"/></Border.RenderTransform>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsIndeterminate" Value="True">
                <Setter TargetName="glow" Property="Visibility" Value="Visible"/>
                <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
                <Trigger.EnterActions><BeginStoryboard x:Name="indet"><Storyboard RepeatBehavior="Forever"><DoubleAnimation Storyboard.TargetName="glow" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" From="-90" To="300" Duration="0:0:1.3"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><StopStoryboard BeginStoryboardName="indet"/></Trigger.ExitActions>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <DataTemplate x:Key="FindingTpl">
      <Border Background="#111A2E" BorderBrush="#1C2942" BorderThickness="1" CornerRadius="12" Margin="0,0,0,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="4"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border Background="{Binding Color}" CornerRadius="12,0,0,12"/>
          <StackPanel Grid.Column="1" Margin="16,12">
            <StackPanel Orientation="Horizontal">
              <Border Background="{Binding Color}" CornerRadius="6" Padding="8,2" Margin="0,0,10,0" VerticalAlignment="Center"><TextBlock Text="{Binding SevText}" FontSize="11.5" Foreground="White" FontWeight="SemiBold"/></Border>
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="15" TextWrapping="Wrap" Foreground="#F1F5F9"/>
            </StackPanel>
            <TextBlock Text="{Binding Detail}" Foreground="#93A3B8" TextWrapping="Wrap" Margin="0,5,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Style="{StaticResource Primary}" Content="{Binding FixText}" Tag="{Binding FixTag}" Visibility="{Binding FixVisible}" Margin="0,0,16,0" VerticalAlignment="Center"/>
        </Grid>
      </Border>
    </DataTemplate>
    <DataTemplate x:Key="CheckTpl">
      <Border BorderBrush="#18233A" BorderThickness="0,0,0,1" Padding="4,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <CheckBox IsChecked="{Binding Selected, Mode=TwoWay}" VerticalAlignment="Center" Margin="0"/>
          <StackPanel Grid.Column="1">
            <TextBlock Text="{Binding Name}" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
            <TextBlock Text="{Binding Sub}" Foreground="#64748B" FontSize="12" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
          <Border Grid.Column="2" Background="#134E4A" CornerRadius="6" Padding="8,2" VerticalAlignment="Center" Visibility="{Binding BadgeVisible}">
            <TextBlock Text="{Binding Badge}" FontSize="11.5" Foreground="#5EEAD4"/>
          </Border>
        </Grid>
      </Border>
    </DataTemplate>
    <DataTemplate x:Key="InfoTpl">
      <Border Background="#111A2E" BorderBrush="#1C2942" BorderThickness="1" CornerRadius="12" Padding="16,12" Margin="0,0,0,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel>
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="15" Margin="0,0,10,0" Foreground="#F1F5F9"/>
              <Border Background="{Binding Color}" CornerRadius="6" Padding="8,2" VerticalAlignment="Center"><TextBlock Text="{Binding Badge}" FontSize="11.5" Foreground="White"/></Border>
            </StackPanel>
            <TextBlock Text="{Binding Detail}" Foreground="#93A3B8" TextWrapping="Wrap" Margin="0,5,0,0"/>
          </StackPanel>
          <Button Grid.Column="1" Style="{StaticResource Btn}" Content="{Binding ButtonText}" Tag="{Binding Tag}" Visibility="{Binding ButtonVisible}" VerticalAlignment="Center" Margin="10,0,0,0"/>
        </Grid>
      </Border>
    </DataTemplate>
  </Window.Resources>

  <Border Name="RootBorder" Background="#0A101E" BorderBrush="#1C2942" BorderThickness="1">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="252"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

    <!-- sidebar -->
    <Border>
      <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#0C1528" Offset="0"/><GradientStop Color="#080D1A" Offset="1"/></LinearGradientBrush></Border.Background>
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="22,22,10,26">
          <Viewbox Width="40" Height="43" Margin="0,0,12,0">
            <Canvas Width="120" Height="128">
              <Path Data="M60,0 L116,20 L110,84 L60,128 L10,84 L4,20 Z"><Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#5EEAD4" Offset="0"/><GradientStop Color="#0D9488" Offset="1"/></LinearGradientBrush></Path.Fill></Path>
              <Polyline Name="NavPulse" Points="18,62 42,62 52,38 66,88 78,52 86,62 104,62" Stroke="#0B1220" StrokeThickness="10" StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
            </Canvas>
          </Viewbox>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="{{brand}}" FontSize="22" FontWeight="Bold" Foreground="#F1F5F9"/>
            <TextBlock Text="PC DOCTOR" FontSize="10.5" FontWeight="SemiBold" Foreground="#2DD4BF" Margin="1,0,0,0"/>
          </StackPanel>
        </StackPanel>
        <Border DockPanel.Dock="Bottom" Margin="16,8,16,16" Padding="14,12" CornerRadius="12" Background="#0E1729" BorderBrush="#18233A" BorderThickness="1">
          <StackPanel>
            <StackPanel Orientation="Horizontal">
              <TextBlock Name="LockIcon" Style="{StaticResource Icon}" Text="&#xE72E;" FontSize="13" Foreground="#2DD4BF" Margin="0,0,8,0"/>
              <TextBlock Name="LockText" FontSize="12" Foreground="#B4C2D6" TextWrapping="Wrap"/>
            </StackPanel>
            <TextBlock Name="AdminText" Margin="0,6,0,0" FontSize="11" Foreground="#64748B" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <StackPanel Name="NavPanel">
          <TextBlock Style="{StaticResource Label}" Text="{{nav.section1}}" Margin="26,0,0,6"/>
          <Button Style="{StaticResource Nav}" Tag="nav:ask"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE8BD;"/><TextBlock Text="{{nav.ask}}"/></StackPanel></Button>
          <Button Style="{StaticResource Nav}" Tag="nav:dashboard"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE9D9;"/><TextBlock Text="{{nav.dashboard}}"/></StackPanel></Button>
          <Button Style="{StaticResource Nav}" Tag="nav:repair"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE90F;"/><TextBlock Text="{{nav.repair}}"/></StackPanel></Button>
          <Button Style="{StaticResource Nav}" Tag="nav:speed"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE945;"/><TextBlock Text="{{nav.speed}}"/></StackPanel></Button>
          <Button Style="{StaticResource Nav}" Tag="nav:storage"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xEDA2;"/><TextBlock Text="{{nav.storage}}"/></StackPanel></Button>
          <TextBlock Style="{StaticResource Label}" Text="{{nav.section2}}" Margin="26,16,0,6"/>
          <Button Style="{StaticResource Nav}" Tag="nav:advisor"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE82F;"/><TextBlock Text="{{nav.advisor}}"/></StackPanel></Button>
          <Button Style="{StaticResource Nav}" Tag="nav:toolbox"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xEC7A;"/><TextBlock Text="{{nav.toolbox}}"/></StackPanel></Button>
          <Button Style="{StaticResource Nav}" Tag="nav:report"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE8A5;"/><TextBlock Text="{{nav.report}}"/></StackPanel></Button>
        </StackPanel>
      </DockPanel>
    </Border>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="46"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

      <!-- title bar (drag area) -->
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Border CornerRadius="9" Background="#0E1729" BorderBrush="#1C2942" BorderThickness="1" VerticalAlignment="Center" Margin="0,0,10,0" Padding="2">
            <StackPanel Orientation="Horizontal" Name="LangPanel">
              <TextBlock Style="{StaticResource Icon}" Text="&#xE774;" FontSize="12" Foreground="#64748B" Margin="8,0,4,0"/>
              <Button Style="{StaticResource Seg}" Tag="lang:en" Content="English"/>
              <Button Style="{StaticResource Seg}" Tag="lang:mr" Content="मराठी"/>
              <Button Style="{StaticResource Seg}" Tag="lang:hi" Content="हिन्दी"/>
            </StackPanel>
          </Border>
          <Button Style="{StaticResource WinBtn}" Tag="win:min" Content="&#xE921;"/>
          <Button Style="{StaticResource WinBtn}" Tag="win:max" Name="MaxBtn" Content="&#xE922;"/>
          <Button Style="{StaticResource WinBtn}" Tag="win:close" Content="&#xE8BB;"/>
        </StackPanel>
        <TextBlock Name="CrumbText" Margin="30,0,0,0" VerticalAlignment="Center" FontSize="12" Foreground="#64748B"/>
      </DockPanel>

      <!-- pages -->
      <Grid Grid.Row="1" Margin="30,4,30,10">

        <!-- DASHBOARD -->
        <ScrollViewer Name="Page_dashboard" VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <Border CornerRadius="16" Padding="24,22" Margin="0,0,0,14" Background="{StaticResource HeroGrad}" BorderBrush="#1C3550" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <Grid Width="128" Height="128" Margin="0,0,26,0">
                  <Ellipse Stroke="#1C2942" StrokeThickness="11"/>
                  <Ellipse Name="ScoreArc" StrokeThickness="11" Stroke="#2DD4BF" StrokeDashArray="0 100" StrokeDashCap="Round" RenderTransformOrigin="0.5,0.5">
                    <Ellipse.RenderTransform><RotateTransform Angle="-90"/></Ellipse.RenderTransform>
                  </Ellipse>
                  <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock Name="ScoreText" Text="--" FontSize="38" FontWeight="Bold" HorizontalAlignment="Center" Foreground="#F1F5F9"/>
                    <TextBlock Text="/ 100" FontSize="11" Foreground="#64748B" HorizontalAlignment="Center" Margin="0,-4,0,0"/>
                  </StackPanel>
                </Grid>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <TextBlock Style="{StaticResource Label}" Text="{{dash.score}}"/>
                  <TextBlock Style="{StaticResource H1}" Text="{{dash.title}}"/>
                  <TextBlock Style="{StaticResource Sub}" Name="ModelText" Text="{{dash.sub}}"/>
                </StackPanel>
                <StackPanel Grid.Column="2" VerticalAlignment="Center">
                  <Button Style="{StaticResource Primary}" Tag="scan:quick" Margin="0,0,0,8" Padding="20,10" ToolTip="{{dash.quick.tip}}"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE721;" FontSize="14" Margin="0,0,8,0"/><TextBlock Text="{{dash.quick}}"/></StackPanel></Button>
                  <Button Style="{StaticResource Btn}" Tag="scan:deep" Margin="0" Padding="20,10" ToolTip="{{dash.deep.tip}}"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE9D9;" FontSize="14" Margin="0,0,8,0"/><TextBlock Text="{{dash.deep}}"/></StackPanel></Button>
                </StackPanel>
              </Grid>
            </Border>

            <UniformGrid Columns="4" Margin="0,0,0,14">
              <Border Style="{StaticResource CardBorder}" Margin="0,0,12,0" Padding="16,14"><DockPanel><TextBlock DockPanel.Dock="Left" Style="{StaticResource Icon}" Text="&#xE950;" FontSize="20" Foreground="#60A5FA" VerticalAlignment="Top" Margin="0,2,12,0"/><StackPanel><TextBlock Style="{StaticResource Label}" Text="CPU"/><TextBlock Name="CpuText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel></DockPanel></Border>
              <Border Style="{StaticResource CardBorder}" Margin="0,0,12,0" Padding="16,14"><DockPanel><TextBlock DockPanel.Dock="Left" Style="{StaticResource Icon}" Text="&#xE7B8;" FontSize="20" Foreground="#A78BFA" VerticalAlignment="Top" Margin="0,2,12,0"/><StackPanel><TextBlock Style="{StaticResource Label}" Text="RAM"/><TextBlock Name="RamText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel></DockPanel></Border>
              <Border Style="{StaticResource CardBorder}" Margin="0,0,12,0" Padding="16,14"><DockPanel><TextBlock DockPanel.Dock="Left" Style="{StaticResource Icon}" Text="&#xEDA2;" FontSize="20" Foreground="#FBBF24" VerticalAlignment="Top" Margin="0,2,12,0"/><StackPanel><TextBlock Style="{StaticResource Label}" Text="DISK"/><TextBlock Name="DiskText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel></DockPanel></Border>
              <Border Style="{StaticResource CardBorder}" Margin="0" Padding="16,14"><DockPanel><TextBlock DockPanel.Dock="Left" Style="{StaticResource Icon}" Text="&#xE7F4;" FontSize="20" Foreground="#2DD4BF" VerticalAlignment="Top" Margin="0,2,12,0"/><StackPanel><TextBlock Style="{StaticResource Label}" Text="WINDOWS"/><TextBlock Name="OsText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel></DockPanel></Border>
            </UniformGrid>

            <Border Name="ScoreWhyCard" Style="{StaticResource CardBorder}" Visibility="Collapsed"><StackPanel Name="ScoreWhy"/></Border>
            <Border Name="OptCard" Style="{StaticResource CardBorder}" BorderBrush="#14B8A6" Visibility="Collapsed"><StackPanel Name="OptPanel"/></Border>

            <Border Style="{StaticResource CardBorder}" BorderBrush="#155E59">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#0E2A2C" Offset="0"/><GradientStop Color="#111A2E" Offset="1"/></LinearGradientBrush></Border.Background>
              <DockPanel>
                <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="optimize" VerticalAlignment="Center" FontSize="15" Padding="20,11" Margin="16,0,0,0"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE945;" FontSize="15" Margin="0,0,8,0"/><TextBlock Text="{{dash.opt.btn}}"/></StackPanel></Button>
                <StackPanel>
                  <TextBlock Style="{StaticResource H2}" Text="{{dash.opt.title}}"/>
                  <TextBlock Style="{StaticResource Sub}" Text="{{dash.opt.sub}}"/>
                </StackPanel>
              </DockPanel>
            </Border>

            <TextBlock Style="{StaticResource H2}" Text="{{dash.findings}}" Margin="2,10,0,10"/>
            <ItemsControl Name="FindingsList" ItemTemplate="{StaticResource FindingTpl}"/>
            <Border Name="FindingsEmpty" Style="{StaticResource CardBorder}" Padding="20,26">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE9D9;" FontSize="30" Foreground="#2A3A57" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                <TextBlock Style="{StaticResource Sub}" Text="{{dash.empty}}" TextAlignment="Center"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- REPAIR -->
        <ScrollViewer Name="Page_repair" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="{{rep.title}}"/>
            <TextBlock Style="{StaticResource Sub}" Text="{{rep.sub}}" Margin="0,0,0,16"/>
            <WrapPanel Name="RepairCards"/>
            <Border Style="{StaticResource CardBorder}" Margin="0,4,12,12">
              <StackPanel>
                <DockPanel>
                  <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top" Margin="12,0,0,0">
                    <Button Style="{StaticResource Btn}" Tag="reg:scan" Content="{{reg.scan}}"/>
                    <Button Style="{StaticResource Primary}" Tag="reg:fix" Content="{{reg.fix}}" Margin="0"/>
                  </StackPanel>
                  <StackPanel>
                    <TextBlock Style="{StaticResource H2}" Text="{{reg.title}}"/>
                    <TextBlock Style="{StaticResource Sub}" Text="{{reg.sub}}"/>
                  </StackPanel>
                </DockPanel>
                <TextBlock Name="RegInfo" Style="{StaticResource Sub}" Margin="0,10,0,4"/>
                <ItemsControl Name="RegList" ItemTemplate="{StaticResource CheckTpl}"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- SPEED -->
        <ScrollViewer Name="Page_speed" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <DockPanel Margin="0,0,0,16">
              <Button DockPanel.Dock="Right" Style="{StaticResource Btn}" Tag="speed:undo" VerticalAlignment="Center" Margin="0"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE7A7;" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="{{spd.undo}}"/></StackPanel></Button>
              <StackPanel>
                <TextBlock Style="{StaticResource H1}" Text="{{spd.title}}"/>
                <TextBlock Style="{StaticResource Sub}" Text="{{spd.sub}}"/>
              </StackPanel>
            </DockPanel>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="{{spd.tweaks}}"/>
                <UniformGrid Columns="2">
                  <CheckBox Name="T_cleanup" IsChecked="True" Content="{{t.cleanup}}"/>
                  <CheckBox Name="T_recycle" Content="{{t.recycle}}"/>
                  <CheckBox Name="T_component" Content="{{t.component}}"/>
                  <CheckBox Name="T_visual" IsChecked="True" Content="{{t.visual}}"/>
                  <CheckBox Name="T_power" IsChecked="True" Content="{{t.power}}"/>
                  <CheckBox Name="T_suggest" IsChecked="True" Content="{{t.suggest}}"/>
                  <CheckBox Name="T_services" IsChecked="True" Content="{{t.services}}"/>
                  <CheckBox Name="T_pagefile" IsChecked="True" Content="{{t.pagefile}}"/>
                  <CheckBox Name="T_background" Content="{{t.background}}"/>
                  <CheckBox Name="T_hiber" Content="{{t.hiber}}"/>
                </UniformGrid>
                <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                  <Button Style="{StaticResource Primary}" Tag="speed:tweaks" Content="{{spd.apply}}"/>
                </StackPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <DockPanel>
                  <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
                    <Button Style="{StaticResource Btn}" Tag="speed:suggest-startup" Content="{{spd.suggestsel}}"/>
                    <Button Style="{StaticResource Primary}" Tag="speed:startup" Content="{{apply}}" Margin="0"/>
                  </StackPanel>
                  <StackPanel>
                    <TextBlock Style="{StaticResource H2}" Text="{{spd.startup}}"/>
                    <TextBlock Style="{StaticResource Sub}" Text="{{spd.startup.sub}}"/>
                  </StackPanel>
                </DockPanel>
                <ItemsControl Name="StartupList" ItemTemplate="{StaticResource CheckTpl}" Margin="0,10,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <DockPanel>
                  <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="speed:bloat" Content="{{spd.bloat.btn}}" VerticalAlignment="Top" Margin="0"/>
                  <StackPanel>
                    <TextBlock Style="{StaticResource H2}" Text="{{spd.bloat}}"/>
                    <TextBlock Style="{StaticResource Sub}" Text="{{spd.bloat.sub}}"/>
                  </StackPanel>
                </DockPanel>
                <ItemsControl Name="BloatList" ItemTemplate="{StaticResource CheckTpl}" Margin="0,10,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- STORAGE -->
        <ScrollViewer Name="Page_storage" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <DockPanel Margin="0,0,0,16">
              <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="storage:analyze" VerticalAlignment="Center" Margin="0"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xEDA2;" FontSize="14" Margin="0,0,8,0"/><TextBlock Text="{{sto.analyze}}"/></StackPanel></Button>
              <StackPanel>
                <TextBlock Style="{StaticResource H1}" Text="{{sto.title}}"/>
                <TextBlock Style="{StaticResource Sub}" Text="{{sto.sub}}"/>
              </StackPanel>
            </DockPanel>
            <Border Style="{StaticResource CardBorder}" Background="#231A0E" BorderBrush="#5C3B10" Padding="16,12">
              <DockPanel><TextBlock DockPanel.Dock="Left" Style="{StaticResource Icon}" Text="&#xE7BA;" Foreground="#FBBF24" VerticalAlignment="Top" Margin="0,2,12,0"/><TextBlock TextWrapping="Wrap" Foreground="#FCD34D" Text="{{sto.warn}}"/></DockPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="{{sto.status}}"/>
                <TextBlock Name="StorageSummary" Style="{StaticResource Sub}" Text="{{sto.press}}"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="{{sto.where}}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,10">
                  <TextBlock Text="{{sto.drive}}" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="#B4C2D6"/>
                  <ComboBox Name="TargetCombo" Width="380"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Sub}" Text="{{sto.nodrive}}"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <TextBlock Text="{{sto.size}}" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="#B4C2D6"/>
                  <TextBox Name="NewPartSize" Width="90" Text="50" VerticalContentAlignment="Center"/>
                  <Button Style="{StaticResource Btn}" Tag="storage:newpart" Content="{{sto.newpart}}" Margin="10,0,0,0"/>
                  <TextBlock Name="ShrinkInfo" Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="10,0,0,0"/>
                </StackPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <DockPanel>
                  <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="storage:move" Content="{{sto.move}}" VerticalAlignment="Top" Margin="0"/>
                  <StackPanel>
                    <TextBlock Style="{StaticResource H2}" Text="{{sto.what}}"/>
                    <TextBlock Style="{StaticResource Sub}" Text="{{sto.what.sub}}"/>
                  </StackPanel>
                </DockPanel>
                <ItemsControl Name="FolderList" ItemTemplate="{StaticResource CheckTpl}" Margin="0,10,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- ADVISOR -->
        <ScrollViewer Name="Page_advisor" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <DockPanel Margin="0,0,0,16">
              <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="advisor:run" VerticalAlignment="Center" Margin="0"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE82F;" FontSize="14" Margin="0,0,8,0"/><TextBlock Text="{{adv.run}}"/></StackPanel></Button>
              <StackPanel>
                <TextBlock Style="{StaticResource H1}" Text="{{adv.title}}"/>
                <TextBlock Style="{StaticResource Sub}" Text="{{adv.sub}}"/>
              </StackPanel>
            </DockPanel>
            <TextBlock Style="{StaticResource H2}" Text="{{adv.win11}}"/>
            <ItemsControl Name="Win11List" ItemTemplate="{StaticResource InfoTpl}"/>
            <TextBlock Style="{StaticResource H2}" Text="{{adv.os}}" Margin="0,12,0,6"/>
            <ItemsControl Name="OsList" ItemTemplate="{StaticResource InfoTpl}"/>
            <TextBlock Style="{StaticResource H2}" Text="{{adv.upgrade}}" Margin="0,12,0,6"/>
            <ItemsControl Name="UpgradeList" ItemTemplate="{StaticResource InfoTpl}"/>
            <TextBlock Style="{StaticResource H2}" Text="{{adv.apps}}" Margin="0,12,0,6"/>
            <ItemsControl Name="AppList" ItemTemplate="{StaticResource InfoTpl}"/>
          </StackPanel>
        </ScrollViewer>

        <!-- ASSISTANT -->
        <Grid Name="Page_ask" Visibility="Collapsed">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
              <Border CornerRadius="9" Background="#0E1729" BorderBrush="#1C2942" BorderThickness="1" Padding="2" Margin="0,0,8,0" VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal" Name="AiModePanel">
                  <Button Style="{StaticResource Seg}" Tag="aimode:auto" Content="{{ask.mode.auto}}"/>
                  <Button Style="{StaticResource Seg}" Tag="aimode:online" Content="Online AI"/>
                  <Button Style="{StaticResource Seg}" Tag="aimode:offline" Content="Offline AI"/>
                  <Button Style="{StaticResource Seg}" Tag="aimode:basic" Content="{{ask.mode.basic}}"/>
                </StackPanel>
              </Border>
              <Button Style="{StaticResource Btn}" Tag="ask:settings" Margin="0" VerticalAlignment="Center"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE713;" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="{{ask.settings}}"/></StackPanel></Button>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="{{ask.title}}"/>
              <TextBlock Name="AskSub" Style="{StaticResource Sub}" Text="{{ask.sub}}" Margin="0,0,20,0"/>
              <TextBlock Name="AiStatus" FontSize="11.5" Foreground="#64748B" Margin="0,6,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </DockPanel>
          <ScrollViewer Name="ChatScroll" Grid.Row="1" Margin="0,14,0,12" VerticalScrollBarVisibility="Auto">
            <StackPanel>
              <Border Name="AiSettings" Style="{StaticResource CardBorder}" Visibility="Collapsed" Margin="0,0,0,10">
                <StackPanel>
                  <TextBlock Style="{StaticResource H2}" Text="{{ask.settings}}"/>
                  <TextBlock Style="{StaticResource Sub}" Text="{{ai.sub}}"/>
                  <DockPanel Margin="0,12,0,0">
                    <TextBlock Text="{{ai.online}}" Width="110" Foreground="#B4C2D6" VerticalAlignment="Center"/>
                    <ComboBox Name="AiProvider" Width="360" HorizontalAlignment="Left">
                      <ComboBoxItem Content="Google Gemini (free key - Google AI Studio)" Tag="gemini" IsSelected="True"/>
                      <ComboBoxItem Content="Anthropic Claude (paid API key)" Tag="anthropic"/>
                    </ComboBox>
                  </DockPanel>
                  <DockPanel Margin="0,8,0,0">
                    <TextBlock Text="{{ai.key}}" Width="110" Foreground="#B4C2D6" VerticalAlignment="Center"/>
                    <PasswordBox Name="AiKey" Width="360" HorizontalAlignment="Left"/>
                  </DockPanel>
                  <DockPanel Margin="0,8,0,0">
                    <TextBlock Text="{{ai.model}}" Width="110" Foreground="#B4C2D6" VerticalAlignment="Center"/>
                    <TextBox Name="AiModel" Width="360" HorizontalAlignment="Left" ToolTip="{{ai.model.tip}}"/>
                  </DockPanel>
                  <CheckBox Name="AiPcInfo" Margin="0,12,0,0" IsChecked="True" Content="{{ai.pcinfo}}"/>
                  <WrapPanel Margin="0,12,0,0">
                    <Button Style="{StaticResource Primary}" Tag="ask:save" Content="{{ai.save}}"/>
                    <Button Style="{StaticResource Btn}" Tag="ask:getkey" Content="{{ai.getkey}}"/>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Sub}" Foreground="#FBBF24" Margin="0,10,0,0" Text="{{ai.warn}}"/>
                </StackPanel>
              </Border>
              <StackPanel Name="ChatPanel"/>
            </StackPanel>
          </ScrollViewer>
          <Border Grid.Row="2" Background="#0E1729" BorderBrush="#24324D" BorderThickness="1" CornerRadius="14" Padding="6">
            <DockPanel>
              <Button Name="AskGoBtn" DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="ask:go" Margin="6,0,0,0" Padding="22,10"><StackPanel Orientation="Horizontal"><TextBlock Text="{{ask.go}}"/><TextBlock Style="{StaticResource Icon}" Text="&#xE724;" FontSize="13" Margin="10,0,0,0"/></StackPanel></Button>
              <Grid>
                <TextBlock Name="AskHint" Text="{{ask.hint}}" Foreground="#4B5B76" FontSize="14.5" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
                <TextBox Name="AskBox" BorderThickness="0" Background="Transparent" FontSize="15" Padding="4,8" TextWrapping="Wrap" VerticalContentAlignment="Center"/>
              </Grid>
            </DockPanel>
          </Border>
        </Grid>

        <!-- TOOLS GUIDE -->
        <Grid Name="Page_toolbox" Visibility="Collapsed">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel>
            <TextBlock Name="TgTitle" Style="{StaticResource H1}" Text="{{tg.title}}"/>
            <TextBlock Name="TgSub" Style="{StaticResource Sub}" Text="{{tg.sub}}"/>
          </StackPanel>
          <Grid Grid.Row="1" Margin="0,14,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="330"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Background="#0E1729" BorderBrush="#1C2942" BorderThickness="1" CornerRadius="14" Padding="8">
              <DockPanel>
                <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
                  <TextBox Name="TgSearch" Padding="30,7,8,7"/>
                  <TextBlock Style="{StaticResource Icon}" Text="&#xE721;" FontSize="12" Foreground="#64748B" Margin="11,0,0,0" HorizontalAlignment="Left" IsHitTestVisible="False"/>
                </Grid>
                <ListBox Name="TgList" Background="Transparent" BorderThickness="0" Foreground="#E6EDF7" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
              </DockPanel>
            </Border>
            <ScrollViewer Grid.Column="1" Margin="18,0,0,0" VerticalScrollBarVisibility="Auto">
              <StackPanel Name="TgDetail"/>
            </ScrollViewer>
          </Grid>
        </Grid>

        <!-- REPORT -->
        <ScrollViewer Name="Page_report" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="{{rpt.title}}"/>
            <TextBlock Style="{StaticResource Sub}" Text="{{rpt.sub}}" Margin="0,0,0,16"/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Button Style="{StaticResource Primary}" Tag="report:make"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE8A5;" FontSize="14" Margin="0,0,8,0"/><TextBlock Text="{{rpt.make}}"/></StackPanel></Button>
                  <Button Style="{StaticResource Btn}" Tag="open:reports"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE838;" FontSize="14" Margin="0,0,8,0"/><TextBlock Text="{{rpt.folder}}"/></StackPanel></Button>
                </StackPanel>
                <TextBlock Name="ReportInfo" Style="{StaticResource Sub}" Margin="0,14,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </Grid>

      <!-- status bar + log -->
      <Border Grid.Row="2" Background="#0C1424" BorderBrush="#18233A" BorderThickness="0,1,0,0">
        <DockPanel Margin="30,9,24,9">
          <DockPanel DockPanel.Dock="Top">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button Name="StopBtn" Style="{StaticResource Btn}" Tag="job:stop" Padding="10,3" Margin="0,0,12,0" Visibility="Collapsed"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE71A;" FontSize="11" Margin="0,0,6,0"/><TextBlock Text="{{stop}}" FontSize="12.5"/></StackPanel></Button>
              <ProgressBar Name="Progress" Width="240" Height="6" Minimum="0" Maximum="100" VerticalAlignment="Center" Margin="0,0,14,0"/>
              <Button Style="{StaticResource Ghost}" Tag="log:toggle" Padding="10,3" Margin="0"><StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource Icon}" Text="&#xE9F9;" FontSize="12" Margin="0,0,6,0" Foreground="#93A3B8"/><TextBlock Text="{{log.show}}" FontSize="12.5" Foreground="#93A3B8"/></StackPanel></Button>
            </StackPanel>
            <Grid Name="Spinner" Width="16" Height="16" Margin="0,0,10,0" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
              <Grid.RenderTransform><RotateTransform/></Grid.RenderTransform>
              <Ellipse Stroke="#1C2942" StrokeThickness="2.5"/>
              <Path Data="M8,1.25 A6.75,6.75 0 0 1 14.75,8" Stroke="#2DD4BF" StrokeThickness="2.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
            </Grid>
            <TextBlock Name="StatusText" Text="{{ready}}" Foreground="#93A3B8" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
          <TextBox Name="LogBox" Height="130" Margin="0,8,0,0" IsReadOnly="True" Background="#080D1A" Foreground="#A7F3D0" BorderBrush="#18233A" Visibility="Collapsed"
                   FontFamily="Consolas, Nirmala UI" FontSize="12" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
        </DockPanel>
      </Border>
    </Grid>

    <!-- splash: shield grows in, the heartbeat line draws itself, a ring pulses out, then everything fades -->
    <Grid Name="Splash" Grid.ColumnSpan="2" Background="#0A101E">
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
        <Grid Width="220" Height="200">
          <Ellipse Name="SplashRing" Width="150" Height="150" Stroke="#2DD4BF" StrokeThickness="2" Opacity="0" RenderTransformOrigin="0.5,0.5">
            <Ellipse.RenderTransform><ScaleTransform/></Ellipse.RenderTransform>
          </Ellipse>
          <Viewbox Name="SplashLogo" Width="112" Height="120" RenderTransformOrigin="0.5,0.5" Opacity="0">
            <Viewbox.RenderTransform><ScaleTransform ScaleX="0.6" ScaleY="0.6"/></Viewbox.RenderTransform>
            <Canvas Width="120" Height="128">
              <Path Data="M60,0 L116,20 L110,84 L60,128 L10,84 L4,20 Z"><Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#5EEAD4" Offset="0"/><GradientStop Color="#0D9488" Offset="1"/></LinearGradientBrush></Path.Fill></Path>
              <Polyline Name="SplashPulse" Points="18,62 42,62 52,38 66,88 78,52 86,62 104,62" Stroke="#0B1220" StrokeThickness="9" StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeDashArray="20 20" StrokeDashOffset="20"/>
            </Canvas>
          </Viewbox>
        </Grid>
        <StackPanel Name="SplashText" Opacity="0" RenderTransformOrigin="0.5,0.5">
          <StackPanel.RenderTransform><TranslateTransform Y="14"/></StackPanel.RenderTransform>
          <TextBlock Text="{{brand}}" FontSize="40" FontWeight="Bold" Foreground="#F1F5F9" HorizontalAlignment="Center"/>
          <TextBlock Text="P C   D O C T O R" FontSize="13" FontWeight="SemiBold" Foreground="#2DD4BF" HorizontalAlignment="Center" Margin="0,2,0,14"/>
          <TextBlock Text="{{splash.sub}}" FontSize="13" Foreground="#64748B" HorizontalAlignment="Center"/>
        </StackPanel>
      </StackPanel>
    </Grid>
  </Grid>
  </Border>
</Window>
'@
# fill in the UI text (XML-escaped) and load
$xamlText = [regex]::Replace($xamlText, '\{\{([a-zA-Z0-9.]+)\}\}', { param($m) [Security.SecurityElement]::Escape((S $m.Groups[1].Value)) })
[xml]$xaml = $xamlText
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@Name]')) { $ui[$n.Name] = $win.FindName($n.Name) }
try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri (Join-Path $Assets 'sanjeevani.ico'))) } catch { }

$script:Scan = $null
$script:Storage = $null
$script:OSAdvice = $null
$script:Actions = New-Object System.Collections.ArrayList
$script:Job = $null
$script:Pages = 'ask', 'dashboard', 'repair', 'speed', 'storage', 'advisor', 'toolbox', 'report'
$script:Page = ''
$AppTitle = L 'Sanjeevani PC Doctor' 'संजीवनी PC Doctor' 'संजीवनी PC Doctor'

function Brush([string]$hex) { return (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }

# ---------------------------------------------------------------- animation helpers
function New-Ease([string]$kind = 'out') {
    $e = New-Object Windows.Media.Animation.CubicEase
    $e.EasingMode = if ($kind -eq 'inout') { 'EaseInOut' } elseif ($kind -eq 'in') { 'EaseIn' } else { 'EaseOut' }
    return $e
}
function New-Anim([double]$From, [double]$To, [int]$Ms, [int]$Delay = 0, $Ease = (New-Ease)) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    if (-not [double]::IsNaN($From)) { $a.From = $From }
    $a.To = $To; $a.Duration = [Windows.Duration]([TimeSpan]::FromMilliseconds($Ms)); $a.BeginTime = [TimeSpan]::FromMilliseconds($Delay)
    if ($Ease) { $a.EasingFunction = $Ease }
    return $a
}
# fade + slide an element in (pages, chat bubbles, result cards)
function Show-Entrance($el, [double]$dy = 12, [int]$ms = 280, [int]$delay = 0) {
    if (-not $el) { return }
    if ($script:NoAnim) { $el.Opacity = 1; return }
    $t = New-Object Windows.Media.TranslateTransform 0, $dy
    $el.RenderTransform = $t
    $el.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 0 1 $ms $delay))
    $t.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (New-Anim $dy 0 ($ms + 60) $delay))
}

# ---------------------------------------------------------------- dialogs (themed, in the chosen language)
function Show-PDDialog {
    param([string]$Text, [string]$Title = $AppTitle, [ValidateSet('info', 'warn', 'error', 'question', 'ok')][string]$Kind = 'info', [object[]]$Buttons)
    if (-not $Buttons) { $Buttons = @(, @('ok', 'OK', $true)) }
    if ($Headless -and -not $script:ShotDialog) { return [string]$Buttons[0][0] }
    $icon = @{ info = @('&#xE946;', '#60A5FA'); warn = @('&#xE7BA;', '#FBBF24'); error = @('&#xE783;', '#F87171'); question = @('&#xE9CE;', '#2DD4BF'); ok = @('&#xE73E;', '#22C55E') }[$Kind]
    [xml]$dx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" SizeToContent="Height" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True"
        Background="Transparent" FontFamily="Segoe UI, Nirmala UI" FontSize="14" ShowInTaskbar="False">
  <Border Background="#111A2E" BorderBrush="#24324D" BorderThickness="1" CornerRadius="14" Margin="14">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.55" Color="#000000"/></Border.Effect>
    <StackPanel Margin="24,20,24,18">
      <DockPanel Margin="0,0,0,12">
        <TextBlock DockPanel.Dock="Left" Text="$($icon[0])" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="20" Foreground="$($icon[1])" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <TextBlock Name="DTitle" FontSize="16" FontWeight="SemiBold" Foreground="#F1F5F9" VerticalAlignment="Center" TextWrapping="Wrap"/>
      </DockPanel>
      <ScrollViewer MaxHeight="440" VerticalScrollBarVisibility="Auto">
        <TextBlock Name="DText" Foreground="#C9D4E3" TextWrapping="Wrap" LineHeight="21"/>
      </ScrollViewer>
      <WrapPanel Name="DButtons" HorizontalAlignment="Right" Margin="0,18,0,0"/>
    </StackPanel>
  </Border>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dx))
    $d.FindName('DTitle').Text = $Title
    $d.FindName('DText').Text = $Text
    try { if ($win.IsVisible) { $d.Owner = $win } } catch { }
    $script:DlgResult = $null
    $bp = $d.FindName('DButtons')
    foreach ($b in $Buttons) {
        $btn = New-Object Windows.Controls.Button
        $btn.Content = $b[1]; $btn.Tag = [string]$b[0]; $btn.MinWidth = 96; $btn.Margin = '8,0,0,0'
        $btn.Style = $win.FindResource($(if ($b.Count -gt 2 -and $b[2]) { 'Primary' } else { 'Btn' }))
        $btn.Add_Click({ param($s, $e) $script:DlgResult = [string]$s.Tag; [Windows.Window]::GetWindow($s).Close() })
        [void]$bp.Children.Add($btn)
    }
    $d.Add_MouseLeftButtonDown({ param($s, $e) try { $s.DragMove() } catch { } })
    $d.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $s.Close() } })
    $d.Add_Loaded({ param($s, $e) Show-Entrance $s.Content 10 220 })
    if ($Headless) {      # CI screenshot of a dialog
        $d.ShowActivated = $false; $d.Show(); Wait-UI 300; Save-Visual $d.Content $script:ShotDialog; $d.Close(); $script:ShotDialog = $null
        return [string]$Buttons[0][0]
    }
    [void]$d.ShowDialog()
    return $script:DlgResult
}
function Ask([string]$text, [string]$title = $AppTitle) {
    return ((Show-PDDialog -Text $text -Title $title -Kind 'question' -Buttons @(@('yes', (L 'Yes' 'हो' 'हाँ'), $true), @('no', (L 'No' 'नाही' 'नहीं')))) -eq 'yes')
}
function Say([string]$text, [string]$icon = 'Information') {
    $k = switch ($icon) { 'Warning' { 'warn' } 'Error' { 'error' } 'OK' { 'ok' } default { 'info' } }
    [void](Show-PDDialog -Text $text -Kind $k)
}

# ---------------------------------------------------------------- background jobs
function Start-PDJob {
    param([string]$Title, [scriptblock]$Work, [hashtable]$Params = @{}, [scriptblock]$OnDone)
    if ($script:Job) { Say (L 'Another task is already running. Let it finish.' 'एक काम आधीच चालू आहे. ते पूर्ण होऊ द्या.' 'एक काम पहले से चल रहा है। उसे पूरा होने दें।') 'Warning'; return }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('PDLogQueue', $global:PDLogQueue)
    $rs.SessionStateProxy.SetVariable('PDState', $global:PDState)
    $rs.SessionStateProxy.SetVariable('PDCtx', $global:PDCtx)
    $rs.SessionStateProxy.SetVariable('PDLang', $Lang)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $wrapper = {
        param($Mods, $WorkText, $P)
        $ErrorActionPreference = 'Continue'
        foreach ($m in $Mods) { Import-Module $m -Force -DisableNameChecking }
        $sb = [scriptblock]::Create($WorkText)
        try { & $sb $P }
        catch { Write-PDLog ((L 'Error: ' 'त्रुटी: ' 'त्रुटि: ') + $_.Exception.Message) 'ERR'; [pscustomobject]@{ Error = $_.Exception.Message } }
    }
    [void]$ps.AddScript($wrapper.ToString()).AddArgument($Modules).AddArgument($Work.ToString()).AddArgument($Params)
    $global:PDState.Progress = -1
    $global:PDState.Cancel = $false
    $ui.StatusText.Text = $Title + ' ...'
    $ui.LogBox.AppendText(("`r`n===== {0} =====`r`n" -f $Title))
    Set-Busy $true
    $script:Job = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $OnDone; Title = $Title }
}

function Complete-PDJob {
    $j = $script:Job
    $result = $null
    try {
        $out = $j.PS.EndInvoke($j.Handle)
        if ($out -and $out.Count -gt 0) { $result = $out[$out.Count - 1] }
        foreach ($e in $j.PS.Streams.Error) { $global:PDLogQueue.Enqueue('[ERR] ' + $e.ToString()) }
    } catch { $global:PDLogQueue.Enqueue('[ERR] ' + $_.Exception.Message) }
    $j.PS.Dispose(); $j.RS.Close(); $j.RS.Dispose()
    $script:Job = $null
    $ui.StopBtn.Visibility = 'Collapsed'
    Set-Busy $false
    Flush-Log
    $ui.StatusText.Text = $j.Title + ' - ' + (L 'done' 'पूर्ण' 'पूरा')
    if ($result -and $result.PSObject.Properties['Error'] -and $result.Error) {
        Say ((L "The task did not finish:`n" "काम पूर्ण झाले नाही:`n" "काम पूरा नहीं हुआ:`n") + $result.Error) 'Warning'
        return
    }
    if ($j.OnDone) { try { & $j.OnDone $result } catch { Say ((L 'Error while showing the result: ' 'Result दाखवताना त्रुटी: ' 'Result दिखाते समय त्रुटि: ') + $_.Exception.Message) 'Warning' } }
}

function Flush-Log {
    $line = $null
    $sb = New-Object System.Text.StringBuilder
    while ($global:PDLogQueue.TryDequeue([ref]$line)) { [void]$sb.AppendLine($line) }
    if ($sb.Length -gt 0) {
        $ui.LogBox.AppendText($sb.ToString())
        if ($ui.LogBox.Text.Length -gt 200000) { $ui.LogBox.Text = $ui.LogBox.Text.Substring($ui.LogBox.Text.Length - 150000) }
        $ui.LogBox.ScrollToEnd()
    }
}

$script:SpinAnim = $null
function Set-Busy([bool]$busy) {
    foreach ($p in $script:Pages) {
        $page = $ui["Page_$p"]
        if ($page) { $page.IsEnabled = -not $busy }
    }
    $rot = $ui.Spinner.RenderTransform
    if ($busy) {
        $ui.Spinner.Visibility = 'Visible'
        $a = New-Anim 0 360 900 0 $null; $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $a)
    } else {
        $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
        $ui.Spinner.Visibility = 'Collapsed'
        $ui.Progress.IsIndeterminate = $false; $ui.Progress.Value = 0
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    Flush-Log
    if ($script:Job) {
        $p = [int]$global:PDState.Progress
        if ($p -ge 0) { $ui.Progress.IsIndeterminate = $false; $ui.Progress.Value = $p; if ($global:PDState.Status) { $ui.StatusText.Text = "$($script:Job.Title) - $($global:PDState.Status) ($p%)" } }
        else { $ui.Progress.IsIndeterminate = $true }
        if ($script:Job.Handle.IsCompleted) { Complete-PDJob }
    }
})

# ---------------------------------------------------------------- navigation
$NavNames = @{ ask = 'nav.ask'; dashboard = 'nav.dashboard'; repair = 'nav.repair'; speed = 'nav.speed'; storage = 'nav.storage'; advisor = 'nav.advisor'; toolbox = 'nav.toolbox'; report = 'nav.report' }
function Show-Page([string]$name) {
    foreach ($p in $script:Pages) { $ui["Page_$p"].Visibility = if ($p -eq $name) { 'Visible' } else { 'Collapsed' } }
    foreach ($b in $ui.NavPanel.Children) {
        if (-not ($b -is [Windows.Controls.Button])) { continue }
        $sel = ($b.Tag -eq "nav:$name")
        $b.Background = if ($sel) { Brush '#13233F' } else { [Windows.Media.Brushes]::Transparent }
        $b.BorderBrush = if ($sel) { Brush '#2DD4BF' } else { [Windows.Media.Brushes]::Transparent }
        $b.Foreground = if ($sel) { Brush '#FFFFFF' } else { Brush '#B4C2D6' }
    }
    $ui.CrumbText.Text = "$(S 'brand') PC Doctor  ›  $(S $NavNames[$name])"
    if ($script:Page -ne $name) { Show-Entrance $ui["Page_$name"] 14 300 }
    $script:Page = $name
    if ($name -eq 'toolbox') { Build-Toolbox }
    if ($name -eq 'ask') { Show-AskWelcome; $ui.AskBox.Focus() | Out-Null }
}

function Set-LangButtons {
    foreach ($b in $ui.LangPanel.Children) {
        if (-not ($b -is [Windows.Controls.Button])) { continue }
        $on = ($b.Tag -eq "lang:$Lang")
        $b.Background = if ($on) { Brush '#134E4A' } else { [Windows.Media.Brushes]::Transparent }
        $b.Foreground = if ($on) { Brush '#FFFFFF' } else { Brush '#93A3B8' }
    }
}
function Switch-Language([string]$to) {
    if ($to -eq $Lang) { return }
    $names = Get-PDLangNames
    $msg = @{ en = "Switch PC Doctor to English? It will reopen."; mr = "PC Doctor मराठीत करायचा? तो पुन्हा उघडेल."; hi = "PC Doctor हिन्दी में करें? यह फिर से खुलेगा।" }[$to]
    if ($script:Job) { Say (L 'Wait until the running task finishes.' 'चालू काम संपेपर्यंत थांबा.' 'चल रहा काम पूरा होने तक रुकें।') 'Warning'; return }
    if (-not (Ask $msg $names[$to])) { return }
    [void](Set-PDLangSetting -UsbRoot $UsbRoot -Lang $to)
    try { Stop-PDLocalAI } catch { }
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"", '-NoElevate', '-Lang', $to)
    $script:Relaunch = $true
    $win.Close()
}

# ---------------------------------------------------------------- small UI builders
function New-Tb([string]$text, [double]$size = 14, [string]$color = '#E6EDF7', [string]$weight = 'Normal', [string]$margin = '0,0,0,4') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = $size; $t.Foreground = Brush $color; $t.FontWeight = $weight; $t.TextWrapping = 'Wrap'; $t.Margin = $margin
    return $t
}
function New-Badge([string]$text, [string]$color) {
    $b = New-Object Windows.Controls.Border; $b.Background = Brush $color; $b.CornerRadius = 6; $b.Padding = '9,2'; $b.Margin = '0,0,6,0'
    $b.Child = (New-Tb $text 11.5 '#FFFFFF' 'SemiBold' '0'); return $b
}
function New-Icon([string]$glyph, [double]$size = 16, [string]$color = '#93A3B8') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $glyph; $t.FontFamily = $win.FindResource('IconFont'); $t.FontSize = $size; $t.Foreground = Brush $color; $t.VerticalAlignment = 'Center'
    return $t
}
function New-Button([string]$text, [string]$tag, [bool]$primary = $false) {
    $b = New-Object Windows.Controls.Button; $b.Content = $text; $b.Tag = $tag; $b.Margin = '0,0,8,8'
    $b.Style = $win.FindResource($(if ($primary) { 'Primary' } else { 'Btn' })); return $b
}

# ---------------------------------------------------------------- dashboard rendering
$SevColor = @{ Critical = '#E11D48'; Warning = '#D97706'; Info = '#2563EB'; OK = '#16A34A' }
$SevText = @{ Critical = (L 'Critical' 'गंभीर' 'गंभीर'); Warning = (L 'Attention' 'लक्ष द्या' 'ध्यान दें'); Info = (L 'Info' 'माहिती' 'जानकारी'); OK = 'OK' }
$FixText = @{
    registry = (L 'Repair registry' 'Registry दुरुस्ती' 'Registry मरम्मत'); storage = (L 'Free up space' 'जागा मोकळी करा' 'जगह खाली करें'); cleanup = (L 'Clean up' 'साफ करा' 'साफ़ करें')
    startup = (L 'Review startup' 'Startup पहा' 'Startup देखें'); power = (L 'Change' 'बदला' 'बदलें'); visual = (L 'Make lighter' 'हलके करा' 'हल्का करें'); debloat = (L 'Remove' 'काढा' 'हटाएँ')
    advisor = (L 'See advice' 'सल्ला पहा' 'सलाह देखें'); 'repair-os' = (L 'Repair' 'दुरुस्त करा' 'ठीक करें'); chkdsk = (L 'Check disk' 'Disk तपासा' 'Disk जाँचें'); wureset = (L 'Repair' 'दुरुस्त करा' 'ठीक करें')
    defender = (L 'Turn on' 'चालू करा' 'चालू करें'); drivers = 'Drivers'; bsod = (L 'Find the cause' 'कारण शोधा' 'कारण खोजें'); backup = (L 'Backup tools' 'Backup tools' 'Backup tools')
}
$KindInfo = [ordered]@{
    auto    = @([char]0xE945, (L 'One-Click Optimize fixes these automatically' 'One-Click Optimize आपोआप दुरुस्त करेल' 'One-Click Optimize इन्हें अपने आप ठीक करेगा'), '#2DD4BF')
    button  = @([char]0xE90F, (L 'Fix with the button next to the finding' 'समस्येसमोरच्या button ने दुरुस्त करा' 'समस्या के सामने वाले button से ठीक करें'), '#60A5FA')
    restart = @([char]0xE72C, (L 'Restart the PC' 'PC restart करा' 'PC restart करें'), '#A78BFA')
    you     = @([char]0xE77B, (L 'For you to do' 'तुम्ही करायचे' 'आपको करना है'), '#FBBF24')
    hw      = @([char]0xE950, (L 'Needs a hardware / Windows upgrade (software cannot fix this)' 'Hardware / Windows upgrade लागेल (software ने सुटणार नाही)' 'Hardware / Windows upgrade चाहिए (software से हल नहीं होगा)'), '#F87171')
}
function Show-ScoreWhy($s) {
    $p = $ui.ScoreWhy; $p.Children.Clear()
    $fs = @($s.Findings | Where-Object { $_.Points -gt 0 })
    if (-not $fs.Count) { $ui.ScoreWhyCard.Visibility = 'Collapsed'; return }
    $ui.ScoreWhyCard.Visibility = 'Visible'
    [void]$p.Children.Add((New-Tb ((L 'Score {0}/100 - why points were lost and how to reach 100' 'Score {0}/100 - गुण का कमी झाले आणि 100 साठी काय करायचे' 'Score {0}/100 - अंक क्यों कटे और 100 कैसे पाएँ') -f $s.Score) 17 '#F1F5F9' 'SemiBold' '0,0,0,8'))
    foreach ($k in $KindInfo.Keys) {
        $g = @($fs | Where-Object { $_.Kind -eq $k })
        if (-not $g.Count) { continue }
        $pts = ($g | Measure-Object Points -Sum).Sum
        $ki = $KindInfo[$k]
        $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,3'
        $ic = New-Icon ([string]$ki[0]) 14 $ki[2]; $ic.Margin = '0,0,10,0'; [void]$row.Children.Add($ic)
        [void]$row.Children.Add((New-Tb ("{0}  (+{1})" -f $ki[1], $pts) 14 $ki[2] 'SemiBold' '0'))
        [void]$p.Children.Add($row)
        foreach ($x in $g) {
            $how = switch ($k) {
                'auto'    { L 'press "One-Click Optimize" above' 'वरचे "One-Click Optimize" दाबा' 'ऊपर "One-Click Optimize" दबाएँ' }
                'button'  { '"' + $(if ($FixText[$x.FixId]) { $FixText[$x.FixId] } else { L 'Fix' 'उपाय' 'उपाय' }) + '"' }
                'restart' { 'Start → Power → Restart' }
                default   { $x.Detail }
            }
            [void]$p.Children.Add((New-Tb ("−{0}   {1}  →  {2}" -f $x.Points, $x.Title, $how) 13 '#C9D4E3' 'Normal' '24,0,0,3'))
        }
    }
    $reach = if ($s.Reachable) { $s.Reachable } else { $s.Score }
    $end = if ($reach -ge 100) { L 'After all of this the score will be 100. Then run Quick Scan again.' 'हे सगळे केल्यावर score 100 होईल. नंतर पुन्हा Quick Scan करा.' 'यह सब करने के बाद score 100 होगा। फिर से Quick Scan करें।' }
           else { (L 'Software can bring the score up to about {0}. The remaining points need a hardware / Windows upgrade - without it the PC still works, with those limits.' 'Software ने जास्तीत जास्त सुमारे {0} पर्यंत score जातो. उरलेले गुण hardware / Windows upgrade नेच मिळतात - ते न केल्यास PC चालेल, फक्त त्या मर्यादा राहतील.' 'Software से score लगभग {0} तक जाता है। बाकी अंक hardware / Windows upgrade से ही मिलते हैं - उसके बिना भी PC चलेगा, बस ये सीमाएँ रहेंगी।') -f $reach }
    [void]$p.Children.Add((New-Tb $end 13 '#93A3B8' 'Normal' '0,10,0,0'))
}

function Show-OptimizeResult($r) {
    $p = $ui.OptPanel; $p.Children.Clear(); $ui.OptCard.Visibility = 'Visible'
    [void]$p.Children.Add((New-Tb ("One-Click Optimize · {0:dd-MM-yyyy HH:mm}" -f (Get-Date)) 17 '#5EEAD4' 'SemiBold' '0,0,0,6'))
    $col = if ($r.Scan.Score -gt $r.Before) { '#22C55E' } else { '#E6EDF7' }
    [void]$p.Children.Add((New-Tb ("Health score: {0}  →  {1}" -f $r.Before, $r.Scan.Score) 15 $col 'SemiBold' '0,0,0,8'))
    if ($r.Junk) {
        $j = $r.Junk
        $found = ($j.Items | Measure-Object Found -Sum).Sum
        [void]$p.Children.Add((New-Tb ((L 'Junk files: {0} found, {1} freed (C: now has {2} free)' 'Junk files: {0} सापडले, {1} जागा मोकळी झाली (आता C: वर {2} मोकळे)' 'Junk files: {0} मिले, {1} जगह खाली हुई (अब C: पर {2} खाली)') -f (Format-PDSize $found), (Format-PDSize $j.Freed), (Format-PDSize $j.FreeAfter)) 14 '#E6EDF7' 'SemiBold' '0,0,0,6'))
        $g = New-Object Windows.Controls.Grid; $g.Margin = '16,0,0,8'
        foreach ($w in '*', '110', '110') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $row = 0
        $addRow = { param($a, $b, $c, $color, $weight)
            $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = 'Auto'; [void]$g.RowDefinitions.Add($rd)
            $k = 0
            foreach ($t in $a, $b, $c) { $tb = New-Tb $t 13 $color $weight '0,2,8,2'; [Windows.Controls.Grid]::SetRow($tb, $row); [Windows.Controls.Grid]::SetColumn($tb, $k); if ($k) { $tb.TextAlignment = 'Right' }; [void]$g.Children.Add($tb); $k++ }
            Set-Variable -Name row -Value ($row + 1) -Scope 1
        }
        & $addRow (L 'Type' 'प्रकार' 'प्रकार') (L 'Found' 'सापडले' 'मिले') (L 'Cleaned' 'साफ झाले' 'साफ़ हुए') '#64748B' 'SemiBold'
        foreach ($i in ($j.Items | Sort-Object Freed -Descending)) { & $addRow (Get-PDJunkName $i) (Format-PDSize $i.Found) (Format-PDSize $i.Freed) '#C9D4E3' 'Normal' }
        [void]$p.Children.Add($g)
        $left = @($j.Items | Where-Object { $_.Left -ge 50MB })
        if ($left.Count) { [void]$p.Children.Add((New-Tb (L 'Some files were in use and stayed (e.g. while a browser is open). Close browsers / programs and optimize again to clean them too.' 'काही files वापरात होत्या म्हणून राहिल्या (उदा. browser उघडा असल्यास). Browser / programs बंद करून पुन्हा Optimize केल्यास त्या पण साफ होतील.' 'कुछ files इस्तेमाल में थीं इसलिए रह गईं (जैसे browser खुला हो)। Browser / programs बंद करके फिर Optimize करें तो वे भी साफ़ होंगी।') 12 '#93A3B8' 'Normal' '16,0,0,6')) }
        if ($j.RecycleBinBytes -ge 100MB) { [void]$p.Children.Add((New-Tb ((L 'The Recycle Bin holds {0} - it may contain your files, so it was not emptied automatically. Empty it from the "Speed Up" page if you do not need them.' 'Recycle Bin मध्ये {0} आहेत - तुमच्या files असू शकतात म्हणून आपोआप रिकामा केला नाही. नको असल्यास "वेग वाढवा" page वरून रिकामा करा.' 'Recycle Bin में {0} हैं - आपकी files हो सकती हैं, इसलिए अपने आप खाली नहीं किया। ज़रूरत न हो तो "स्पीड बढ़ाएँ" page से खाली करें।') -f (Format-PDSize $j.RecycleBinBytes)) 12 '#FBBF24' 'Normal' '16,0,0,6')) }
    }
    [void]$p.Children.Add((New-Tb (L 'What was done:' 'काय केले:' 'क्या किया:') 14 '#E6EDF7' 'SemiBold' '0,6,0,2'))
    foreach ($a in ($r.Actions | Where-Object { $_ -notmatch '^\s+•' })) { [void]$p.Children.Add((New-Tb ('   ' + $a) 13 '#C9D4E3' 'Normal' '0,0,0,1')) }
    [void]$p.Children.Add((New-Tb (L 'Every change can be undone with "Speed Up → Undo all changes". Restart the PC for the full effect.' 'सगळे बदल "वेग वाढवा → सर्व बदल Undo करा" ने परत करता येतात. पूर्ण फरकासाठी PC restart करा.' 'सभी बदलाव "स्पीड बढ़ाएँ → सभी बदलाव Undo करें" से वापस हो सकते हैं। पूरे असर के लिए PC restart करें।') 12 '#93A3B8' 'Normal' '0,6,0,0'))
    Show-Entrance $ui.OptCard 10 300
}

# animated score: the ring fills and the number counts up
$RingLen = [math]::PI * (128 - 11) / 11
function Set-ScoreRing([int]$score) {
    $col = if ($score -ge 80) { '#22C55E' } elseif ($score -ge 55) { '#F59E0B' } else { '#F43F5E' }
    $ui.ScoreArc.Stroke = Brush $col
    $dash = New-Object Windows.Media.DoubleCollection; $dash.Add($RingLen); $dash.Add(200)
    $ui.ScoreArc.StrokeDashArray = $dash
    if ($script:NoAnim) { $ui.ScoreArc.StrokeDashOffset = $RingLen * (1 - $score / 100.0); $ui.ScoreText.Text = [string]$score; return }
    $ui.ScoreArc.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, (New-Anim $RingLen ($RingLen * (1 - $score / 100.0)) 1100 0 (New-Ease 'inout')))
    $script:CountTo = $score; $script:CountStart = [DateTime]::Now
    if (-not $script:CountTimer) {
        $script:CountTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:CountTimer.Interval = [TimeSpan]::FromMilliseconds(30)
        $script:CountTimer.Add_Tick({
            $t = [math]::Min(1.0, ([DateTime]::Now - $script:CountStart).TotalMilliseconds / 1100.0)
            $e = 1 - [math]::Pow(1 - $t, 3)
            $ui.ScoreText.Text = [string][int]([math]::Round($script:CountTo * $e))
            if ($t -ge 1) { $script:CountTimer.Stop() }
        })
    }
    $script:CountTimer.Start()
}

function Show-Scan($s) {
    $script:Scan = $s
    $i = $s.Info
    Set-ScoreRing ([int]$s.Score)
    $ui.CpuText.Text = "$($i.CPU)`n$($i.CPUCores) cores · load $($s.Load.CPUPct)%"
    $ui.RamText.Text = "$($i.RAMGB) GB $($i.RAMType)`n$(L 'in use' 'वापर' 'उपयोग') $($s.Load.RAMPct)%"
    $sd = @($i.Disks | Where-Object { $_.IsSystem })[0]
    $ui.DiskText.Text = "$(if ($sd) { $sd.MediaType } else { '?' }) · $($i.SysFreeGB) GB free`n($($i.SysFreePct)% of $($i.SysSizeGB) GB)"
    $ui.OsText.Text = "$($i.OSCaption -replace 'Microsoft ', '')`n$($i.DisplayVer) build $($i.OSBuild)"
    $mdl = if ($i.Model -like "$($i.Manufacturer)*") { $i.Model } else { "$($i.Manufacturer) $($i.Model)" }
    $ui.ModelText.Text = "$mdl · $($i.ComputerName) · scan: $(Get-Date $s.Time -Format 'HH:mm')"
    $rows = foreach ($f in $s.Findings) {
        $r = [FindingRow]::new()
        $r.Title = $f.Title; $r.Detail = $f.Detail; $r.Color = $SevColor[$f.Severity]; $r.SevText = $SevText[$f.Severity] + $(if ($f.Points -gt 0) { "  −$($f.Points)" } else { '' })
        if ($f.FixId) { $r.FixTag = "fix:$($f.FixId)"; $r.FixVisible = 'Visible'; $r.FixText = $(if ($FixText[$f.FixId]) { $FixText[$f.FixId] } else { L 'Fix' 'उपाय' 'उपाय' }) }
        else { $r.FixVisible = 'Collapsed' }
        $r
    }
    $ui.FindingsList.ItemsSource = @($rows)
    $ui.FindingsEmpty.Visibility = 'Collapsed'
    Show-Entrance $ui.FindingsList 16 380 150
    Show-ScoreWhy $s
    Show-SpeedLists
    if ($s.PSObject.Properties['Registry']) { Show-RegIssues @($s.Registry) }
}

function Show-SpeedLists {
    if (-not $script:Scan) { return }
    $safe = @(Get-PDSafeStartupToDisable -Items $script:Scan.Startup -DataDir $DataDir -RamGB $script:Scan.Info.RAMGB)
    $k = 0
    $rows = foreach ($it in $script:Scan.Startup) {
        $r = [CheckRow]::new(); $r.Index = $k; $k++
        $r.Selected = [bool]$it.Enabled; $r.Name = $it.Name; $r.Sub = "$($it.Location) · $($it.Command)"
        $isSafe = [bool]($safe | Where-Object { $_.Name -eq $it.Name -and $_.Location -eq $it.Location })
        $r.Badge = L 'suggested: turn off' 'बंद करणे सुचवले' 'बंद करना सुझाया'; $r.BadgeVisible = if ($isSafe) { 'Visible' } else { 'Collapsed' }
        $r
    }
    $ui.StartupList.ItemsSource = @($rows)
    $k = 0
    $brows = foreach ($b in $script:Scan.Bloat) {
        $r = [CheckRow]::new(); $r.Index = $k; $k++
        $r.Selected = [bool]$b.Default; $r.Name = $b.Label; $r.Sub = $b.Name; $r.BadgeVisible = 'Collapsed'
        $r
    }
    $ui.BloatList.ItemsSource = @($brows)
    $sd = @($script:Scan.Info.Disks | Where-Object { $_.IsSystem })[0]
    $low = ($script:Scan.Info.RAMGB -lt 7.5 -or ($sd -and $sd.MediaType -eq 'HDD'))
    $ui.T_visual.IsChecked = $low -or (-not $script:Scan.Info.HasDedicatedGPU)
    $ui.T_background.IsChecked = ($script:Scan.Info.RAMGB -le 4)
}

function Show-Storage($a) {
    $script:Storage = $a
    $used = $a.SizeBytes - $a.FreeBytes
    $userTotal = ($a.UserFolders | Where-Object { $_.OnSystem -and -not $_.OneDrive } | Measure-Object SizeBytes -Sum).Sum
    $ui.StorageSummary.Text = ((L "{0}: {2} used of {1}, {3} free.`nYour files (can be moved): {4} · Hibernation file: {5} · Page file: {6}`nDisk style: {7} · Unallocated: {8} · Safe shrink of C:: {9}" "{0}: {1} पैकी {2} वापरले, {3} मोकळे.`nतुमचे files (हलवता येतील): {4} · Hibernation file: {5} · Page file: {6}`nDisk style: {7} · Unallocated: {8} · C: मधून सुरक्षित shrink: {9}" "{0}: {1} में से {2} इस्तेमाल, {3} खाली।`nआपकी files (ले जा सकते हैं): {4} · Hibernation file: {5} · Page file: {6}`nDisk style: {7} · Unallocated: {8} · C: से सुरक्षित shrink: {9}") -f
        $a.Drive, (Format-PDSize $a.SizeBytes), (Format-PDSize $used), (Format-PDSize $a.FreeBytes), (Format-PDSize $userTotal),
        (Format-PDSize $a.HiberfilBytes), (Format-PDSize $a.PagefileBytes), $a.DiskStyle, (Format-PDSize $a.UnallocatedBytes), (Format-PDSize $a.ShrinkableBytes))
    $ui.ShrinkInfo.Text = (L '(at most ~{0:N0} GB)' '(जास्तीत जास्त ~{0:N0} GB)' '(ज़्यादा से ज़्यादा ~{0:N0} GB)') -f ([math]::Floor(([math]::Max([double]$a.UnallocatedBytes, [double]$a.ShrinkableBytes)) / 1GB))
    $ui.TargetCombo.Items.Clear()
    foreach ($t in $a.Targets) { [void]$ui.TargetCombo.Items.Add(("{0}:  {1}  -  {2} {3}" -f $t.Letter, $t.Label, (Format-PDSize $t.FreeBytes), (L 'free' 'मोकळे' 'खाली'))) }
    if ($ui.TargetCombo.Items.Count -gt 0) { $ui.TargetCombo.SelectedIndex = 0 }
    else { [void]$ui.TargetCombo.Items.Add((L 'No second drive - create a new DATA drive below' 'दुसरा drive नाही - खाली नवीन DATA drive बनवा' 'दूसरा drive नहीं - नीचे नया DATA drive बनाएँ')); $ui.TargetCombo.SelectedIndex = 0 }
    $k = 0
    $rows = @()
    foreach ($f in @($a.UserFolders) + @($a.RootFolders)) {
        $r = [CheckRow]::new(); $r.Index = $k; $k++
        $r.Name = "$($f.Label)  -  $(Format-PDSize $f.SizeBytes)"
        $r.Sub = $f.Path
        if (-not $f.OnSystem) { $r.Badge = L 'already on another drive' 'आधीच दुसऱ्या drive वर' 'पहले से दूसरे drive पर'; $r.BadgeVisible = 'Visible'; $r.Selected = $false }
        elseif ($f.OneDrive) { $r.Badge = 'OneDrive'; $r.BadgeVisible = 'Visible'; $r.Selected = $false }
        else { $r.BadgeVisible = 'Collapsed'; $r.Selected = ($f.SizeBytes -gt 200MB) }
        $rows += $r
    }
    $ui.FolderList.ItemsSource = $rows
}

function Show-Advice($adv) {
    $script:OSAdvice = $adv
    $ui.Win11List.ItemsSource = @(foreach ($c in $adv.Win11.Checks) {
        $r = [InfoRow]::new(); $r.Title = $c.Name; $r.Detail = $c.Detail; $r.ButtonVisible = 'Collapsed'
        if ($c.Pass -eq $true) { $r.Badge = 'OK'; $r.Color = '#16A34A' } elseif ($c.Pass -eq $false) { $r.Badge = L 'No' 'नाही' 'नहीं'; $r.Color = '#E11D48' } else { $r.Badge = '?'; $r.Color = '#D97706' }
        $r })
    $fitColor = @{ best = '#16A34A'; great = '#16A34A'; ok = '#2563EB'; temp = '#D97706'; check = '#D97706'; no = '#E11D48' }
    $ui.OsList.ItemsSource = @(foreach ($o in $adv.Recommendations) {
        $r = [InfoRow]::new(); $r.Title = $o.Title; $r.Badge = $o.Fit; $r.Detail = $o.Why; $r.ButtonVisible = 'Collapsed'
        $r.Color = if ($o.FitId -and $fitColor[$o.FitId]) { $fitColor[$o.FitId] } else { '#2563EB' }
        $r })
    $ui.UpgradeList.ItemsSource = @(foreach ($u in $adv.Upgrades) { $r = [InfoRow]::new(); $r.Title = 'Upgrade'; $r.Badge = L 'Advice' 'सल्ला' 'सलाह'; $r.Color = '#0F766E'; $r.Detail = $u; $r.ButtonVisible = 'Collapsed'; $r })
    $kindName = @{ pup = (L 'Unwanted' 'नको असलेले' 'अनचाहा'); outdated = (L 'Outdated' 'जुने' 'पुराना'); replace = (L 'Replace' 'बदला' 'बदलें'); av = 'Antivirus'; heavy = (L 'Heavy' 'भारी' 'भारी') }
    $kindColor = @{ pup = '#E11D48'; outdated = '#D97706'; replace = '#2563EB'; av = '#D97706'; heavy = '#7C3AED' }
    $k = 0
    $rows = foreach ($a in $script:Scan.AppAdvice) {
        $r = [InfoRow]::new(); $r.Title = $a.App; $r.Badge = $kindName[$a.Kind]; $r.Color = $kindColor[$a.Kind]
        $r.Detail = "$($a.Reason)`n$(L 'Alternatives' 'पर्याय' 'विकल्प'): $($a.Alternatives)"
        if ($a.Uninstall -and $a.Action -ne 'keep-if-needed') { $r.Tag = "uninst:$k"; $r.ButtonText = 'Uninstall'; $r.ButtonVisible = 'Visible' }
        elseif ($a.Uninstall) { $r.Tag = "uninst:$k"; $r.ButtonText = L 'Uninstall if not needed' 'गरज नसल्यास Uninstall' 'ज़रूरत न हो तो Uninstall'; $r.ButtonVisible = 'Visible' }
        else { $r.ButtonVisible = 'Collapsed' }
        $k++
        $r
    }
    if (-not $rows) { $r = [InfoRow]::new(); $r.Title = L 'Nothing to remove' 'काही काढण्यासारखे सापडले नाही' 'हटाने लायक कुछ नहीं मिला'; $r.Badge = 'OK'; $r.Color = '#16A34A'; $r.ButtonVisible = 'Collapsed'; $rows = @($r) }
    $ui.AppList.ItemsSource = @($rows)
}

# ---------------------------------------------------------------- repair cards
function New-ActionCard([string]$glyph, [string]$title, [string]$desc, [string]$btn, [string]$tag) {
    $b = New-Object Windows.Controls.Border
    $b.Style = $win.FindResource('CardBorder'); $b.Width = 440; $b.Margin = '0,0,14,14'
    $dp = New-Object Windows.Controls.DockPanel
    $icb = New-Object Windows.Controls.Border; $icb.Width = 42; $icb.Height = 42; $icb.CornerRadius = 11; $icb.Background = Brush '#13324A'; $icb.VerticalAlignment = 'Top'; $icb.Margin = '0,0,14,0'
    $ic = New-Icon $glyph 18 '#2DD4BF'; $ic.HorizontalAlignment = 'Center'; $icb.Child = $ic
    [Windows.Controls.DockPanel]::SetDock($icb, 'Left'); [void]$dp.Children.Add($icb)
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $title; $t.Style = $win.FindResource('H2')
    $d = New-Object Windows.Controls.TextBlock; $d.Text = $desc; $d.Style = $win.FindResource('Sub'); $d.Margin = '0,0,0,12'; $d.MinHeight = 42
    $x = New-Button $btn $tag $true; $x.HorizontalAlignment = 'Left'; $x.Margin = '0'
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($d); [void]$sp.Children.Add($x)
    [void]$dp.Children.Add($sp)
    $b.Child = $dp
    $b.Add_MouseEnter({ param($s, $e) $s.BorderBrush = Brush '#2DD4BF' })
    $b.Add_MouseLeave({ param($s, $e) $s.BorderBrush = Brush '#1C2942' })
    return $b
}

$repairCards = @(
    @([char]0xE90F, (L 'Repair Windows system files' 'Windows system files दुरुस्ती' 'Windows system files मरम्मत'), (L 'DISM (from Windows Update / the Windows ISO on the USB) + SFC. Replaces damaged system files. 15-40 minutes.' 'DISM (Windows Update / USB वरील Windows ISO वरून) + SFC. खराब system files बदलतो. 15-40 मिनिटे.' 'DISM (Windows Update / USB पर Windows ISO से) + SFC. खराब system files बदलता है। 15-40 मिनट।'), (L 'Repair' 'दुरुस्त करा' 'ठीक करें'), 'repair:os'),
    @([char]0xEDA2, (L 'Check disk for errors' 'Disk errors तपासा' 'Disk errors जाँचें'), (L 'Finds file-system errors. If there are any, they are repaired at the next restart.' 'File-system errors शोधतो. Errors असल्यास पुढच्या restart ला दुरुस्ती होते.' 'File-system errors ढूँढता है। Errors हों तो अगले restart पर मरम्मत होती है।'), (L 'Check disk' 'Disk तपासा' 'Disk जाँचें'), 'repair:chkdsk'),
    @([char]0xE895, (L 'Repair Windows Update' 'Windows Update दुरुस्ती' 'Windows Update मरम्मत'), (L 'Resets the update components when updates are stuck or show errors.' 'Update अडकले / error येत असल्यास update components reset करतो.' 'Update अटके हों / error आए तो update components reset करता है।'), 'Reset', 'repair:wu'),
    @([char]0xE701, (L 'Internet / network reset' 'Internet / Network reset' 'Internet / Network reset'), (L 'Internet not working, DNS errors, "No internet" - winsock / IP reset.' 'Internet चालत नाही, DNS error, "No internet" - winsock/IP reset.' 'Internet नहीं चल रहा, DNS error, "No internet" - winsock/IP reset.'), 'Reset', 'repair:net'),
    @([char]0xEA18, (L 'Turn on antivirus + quick scan' 'Antivirus चालू करा + quick scan' 'Antivirus चालू करें + quick scan'), (L 'Microsoft Defender on, definitions updated and a quick scan.' 'Microsoft Defender चालू, definitions update आणि quick scan.' 'Microsoft Defender चालू, definitions update और quick scan.'), (L 'Turn on' 'चालू करा' 'चालू करें'), 'repair:defender'),
    @([char]0xE772, (L 'Check / update drivers' 'Drivers तपासा / update' 'Drivers जाँचें / update'), (L 'Shows missing, faulty or old drivers and the safe order to fix them. Installs nothing by itself.' 'कोणते drivers नाहीत, खराब किंवा जुने आहेत ते तपासते आणि सुरक्षित क्रमाने उपाय सुचवते. स्वतःहून काहीही install करत नाही.' 'कौन से drivers नहीं हैं, खराब या पुराने हैं यह जाँचता है और सुरक्षित क्रम में उपाय बताता है। खुद कुछ install नहीं करता।'), (L 'Check' 'तपासा' 'जाँचें'), 'repair:drivers'),
    @([char]0xE8F1, (L 'Back up drivers' 'Drivers backup' 'Drivers backup'), (L 'Save all of this PC''s drivers (Wi-Fi, LAN, audio, display ...) to the USB. Always do this before reinstalling Windows.' 'या PC चे सगळे drivers (WiFi, LAN, audio, display...) pendrive वर save करा. Windows reinstall करण्याआधी नक्की करा.' 'इस PC के सारे drivers (WiFi, LAN, audio, display...) pendrive पर save करें। Windows reinstall से पहले ज़रूर करें।'), (L 'Back up' 'Backup घ्या' 'Backup लें'), 'repair:drvbackup'),
    @([char]0xE777, (L 'Restore drivers' 'Drivers restore' 'Drivers restore'), (L 'After reinstalling Windows, install the backed-up drivers again in one click.' 'Windows reinstall नंतर backup केलेले drivers एका click मध्ये परत install करा.' 'Windows reinstall के बाद backup किए drivers एक click में फिर install करें।'), 'Restore', 'repair:drvrestore'),
    @([char]0xE72E, (L 'Pendrive virus check' 'Pendrive virus तपासणी' 'Pendrive virus जाँच'), (L 'Compares every program on this Sanjeevani USB with Setup''s record (SHA-256). Finds changed / new suspicious files, autorun.inf and shortcut viruses and quarantines them.' 'या Sanjeevani pendrive वरचे सगळे programs Setup च्या नोंदीशी (SHA-256) जुळवतो. बदललेले / नवीन संशयास्पद files, autorun.inf, shortcut virus शोधून quarantine करतो.' 'इस Sanjeevani pendrive के सारे programs को Setup के record (SHA-256) से मिलाता है। बदली / नई संदिग्ध files, autorun.inf, shortcut virus ढूँढकर quarantine करता है।'), (L 'Check' 'तपासा' 'जाँचें'), 'repair:usbcheck'),
    @([char]0xE81C, (L 'Create a restore point now' 'Restore point आत्ता बनवा' 'Restore point अभी बनाएँ'), (L 'For safety before a big change.' 'मोठा बदल करण्याआधी सुरक्षिततेसाठी.' 'बड़े बदलाव से पहले सुरक्षा के लिए।'), (L 'Create' 'बनवा' 'बनाएँ'), 'repair:restorepoint'),
    @([char]0xE7BA, (L 'Windows does not start?' 'Windows सुरूच होत नाही?' 'Windows शुरू ही नहीं होता?'), (L 'Boot from the USB → "Hiren''s BootCD PE" → run PCDoctor-Rescue.cmd from the USB (offline SFC / DISM, boot repair, stuck updates, data rescue).' 'USB वरून boot करा → "Hiren''s BootCD PE" → USB वरील PCDoctor-Rescue.cmd चालवा (offline SFC/DISM, boot repair, अडकलेले updates, data वाचवणे).' 'USB से boot करें → "Hiren''s BootCD PE" → USB पर PCDoctor-Rescue.cmd चलाएँ (offline SFC/DISM, boot repair, अटके updates, data बचाना)।'), (L 'How' 'कसे' 'कैसे'), 'repair:offline-info')
)
foreach ($c in $repairCards) { [void]$ui.RepairCards.Children.Add((New-ActionCard ([string]$c[0]) $c[1] $c[2] $c[3] $c[4])) }

# ---------------------------------------------------------------- Tools guide
$script:Tg = $null            # guide + catalog, loaded once
$script:TgSel = $null
$script:TgResults = @{}
$TgText = @{
    what = (L 'What it does' 'काय करतो' 'क्या करता है'); when = (L 'When to use it' 'कधी वापरायचा' 'कब इस्तेमाल करें'); how = (L 'How to use it' 'कसा वापरायचा' 'कैसे इस्तेमाल करें')
    good = (L 'How to read the result' 'निकाल कसा वाचायचा' 'नतीजा कैसे पढ़ें'); warn = (L 'Warnings' 'इशारे' 'चेतावनी')
    auto = (L 'Check automatically' 'आपोआप तपासा' 'अपने आप जाँचें'); open = (L 'Open (use it yourself)' 'उघडा (स्वतः वापरा)' 'खोलें (खुद इस्तेमाल करें)'); install = 'Install'
    pd = (L 'Open in PC Doctor' 'PC Doctor मध्ये पहा' 'PC Doctor में देखें'); web = (L 'Open download page' 'Download page उघडा' 'Download page खोलें'); file = (L 'Open report' 'Report उघडा' 'Report खोलें')
    safe = (L 'Safe' 'सुरक्षित' 'सुरक्षित'); caution = (L 'Use with care' 'काळजीपूर्वक' 'सावधानी से'); danger = (L 'Dangerous' 'धोकादायक' 'खतरनाक')
    onusb = (L 'On the USB' 'Pendrive वर आहे' 'Pendrive पर है'); notusb = (L 'Not on the USB' 'Pendrive वर नाही' 'Pendrive पर नहीं'); boot = (L 'Boot from the USB' 'Pendrive वरून boot करून' 'Pendrive से boot करके')
    builtin = (L 'Built into Windows' 'Windows मध्येच आहे' 'Windows में ही है'); autoyes = (L 'Automatic check' 'आपोआप तपासणी' 'अपने आप जाँच'); pick = (L '← Pick a tool on the left.' '← डावीकडून tool निवडा.' '← बाईं ओर से tool चुनें।')
    confirm = (L 'Keep in mind when using this tool:' 'हा tool वापरताना लक्षात ठेवा:' 'इस tool का इस्तेमाल करते समय ध्यान रखें:'); go = (L 'Understood. Open it?' 'समजले. उघडायचे?' 'समझ गया। खोलें?')
    stress = (L 'The stress test runs for 10 minutes. The PC gets very hot and the fan loud; it stops by itself if the CPU passes 95°C. Plug in the laptop charger. Start?' 'Stress test 10 मिनिटे चालेल. PC खूप गरम होईल आणि fan जोरात फिरेल; CPU 95°C ओलांडल्यास test आपोआप थांबेल. Laptop ला charger लावा. सुरू करायचे?' 'Stress test 10 मिनट चलेगा। PC बहुत गर्म होगा और fan तेज़ चलेगा; CPU 95°C पार करे तो test अपने आप रुकेगा। Laptop का charger लगाएँ। शुरू करें?')
    optional = (L 'This is an optional tool - the USB works fine without it.' 'हा optional tool आहे - pendrive वर नसला तरी चालतो.' 'यह optional tool है - pendrive पर न हो तो भी चलता है।'); docs = (L 'Tests and information' 'Tests आणि माहिती' 'Tests और जानकारी')
    result = (L 'Result' 'निकाल' 'नतीजा'); extract = (L 'Extract' 'Extract करा' 'Extract करें')
    mytools = (L "My tools: copy your own apps into the USB's MyTools folder - they appear here." 'माझे tools: स्वतःचे apps pendrive च्या MyTools folder मध्ये copy करा - ते इथे दिसतील.' 'मेरे tools: अपने apps pendrive के MyTools folder में copy करें - वे यहाँ दिखेंगे।')
}
$RiskColor = @{ safe = '#16A34A'; caution = '#D97706'; danger = '#E11D48' }
$StatusColor = @{ ok = '#16A34A'; warn = '#D97706'; bad = '#E11D48'; info = '#2563EB' }
$LangSuffix = @{ en = 'En'; mr = 'Mr'; hi = 'Hi' }[$Lang]

function TgT($g) { foreach ($k in @($Lang, 'en', 'mr')) { if ($g.$k) { return $g.$k } }; return $null }   # guide text in the user's language
function Get-TgResText($res, [string]$what) {
    $v = $res.($what + $LangSuffix)
    if (-not $v -or (($v -is [Collections.ICollection]) -and -not $v.Count)) { $v = $res.($what + 'En') }
    return $v
}

function Get-TgState {
    if ($script:Tg) { return $script:Tg }
    $guide = Get-TGGuide $DataDir
    $info = Get-TGCatalog $UsbRoot
    $entries = @{}
    foreach ($k in $info.Catalog.isos) { $entries[$k.id] = [pscustomobject]@{ Id = $k.id; Name = ($k.alias -replace '\s+-\s+.*$', ''); Cat = $k; Iso = $true } }
    foreach ($k in $info.Catalog.tools) { $entries[$k.id] = [pscustomobject]@{ Id = $k.id; Name = ($k.name -replace '\s*\((installer|portable|free, installer)\)', ''); Cat = $k; Iso = $false } }
    foreach ($p in $guide.tools.PSObject.Properties) {
        if (-not $entries[$p.Name]) { $entries[$p.Name] = [pscustomobject]@{ Id = $p.Name; Name = $p.Value.name; Cat = $null; Iso = $false } }
        $entries[$p.Name] | Add-Member -NotePropertyName G -NotePropertyValue $p.Value -Force
    }
    $paths = @{}
    foreach ($m in (Get-TGMyTools $UsbRoot)) {
        $how = @{ mr = $(if ($m.Archive) { 'Extract करा' } elseif ($m.Installer) { 'Install करा' } else { 'उघडा' }); en = $(if ($m.Archive) { 'Extract' } elseif ($m.Installer) { 'Install' } else { 'Open' }); hi = $(if ($m.Archive) { 'Extract करें' } elseif ($m.Installer) { 'Install करें' } else { 'खोलें' }) }
        $what = @{
            mr = $(if ($m.Archive) { 'Zip / 7z / rar file - आधी "Extract करा" दाबा, मग आतला program इथेच दिसेल.' } elseif ($m.Info) { $m.Info } else { 'तुम्ही MyTools मध्ये जोडलेला program.' })
            en = $(if ($m.Archive) { 'Zip / 7z / rar file - press "Extract" first, then the program inside appears here.' } elseif ($m.Info) { $m.Info } else { 'A program you added to MyTools.' })
            hi = $(if ($m.Archive) { 'Zip / 7z / rar file - पहले "Extract करें" दबाएँ, फिर अंदर का program यहीं दिखेगा।' } elseif ($m.Info) { $m.Info } else { 'आपके द्वारा MyTools में जोड़ा गया program.' })
        }
        $warn = @{ mr = 'हा program Sanjeevani ने तपासलेला नाही - फक्त official website वरून घेतलेला, virus scan केलेला program वापरा.'; en = 'Sanjeevani has not checked this program - use only programs from the official website, virus-scanned.'; hi = 'यह program Sanjeevani ने नहीं जाँचा है - सिर्फ़ official website से लिया, virus scan किया हुआ program इस्तेमाल करें।' }
        $g = [pscustomobject]@{ group = 'mytools'; risk = 'caution' }
        foreach ($l in 'mr', 'en', 'hi') {
            $g | Add-Member -NotePropertyName $l -NotePropertyValue ([pscustomobject]@{ what = $what[$l]; when = ''; steps = @("`"$($how[$l])`"") + @($m.Notes); good = ''; warn = @($warn[$l]) })
        }
        $entries[$m.Id] = [pscustomobject]@{ Id = $m.Id; Name = $(if ($m.Archive) { "$($m.Name) (zip)" } else { $m.Name }); Cat = [pscustomobject]@{ installer = $m.Installer; archive = $m.Archive }; Iso = $false; G = $g }
        $paths[$m.Id] = $m.Path
    }
    $script:Tg = [pscustomobject]@{ Guide = $guide; Info = $info; Entries = $entries; Paths = $paths }
    return $script:Tg
}

function Get-TgPath($e) {
    $st = Get-TgState
    if (-not $st.Paths.ContainsKey($e.Id)) {
        $p = $null
        if ($e.Iso) { $i = $st.Info.Installed[$e.Id]; if ($i -and $i.path -and (Test-Path -LiteralPath (Join-Path $UsbRoot $i.path))) { $p = Join-Path $UsbRoot $i.path } }
        elseif ($e.G.builtin) { $p = 'builtin' }
        else { $p = Find-TGTool -UsbRoot $UsbRoot -Id $e.Id -Info $st.Info }
        $st.Paths[$e.Id] = $p
    }
    return $st.Paths[$e.Id]
}

function New-TgHeader([string]$text) {
    $h = New-Object Windows.Controls.ListBoxItem; $h.IsEnabled = $false; $h.Margin = '0,10,0,2'; $h.Padding = '8,2'
    $h.Content = (New-Tb $text.ToUpper() 11 '#2DD4BF' 'SemiBold' '0'); return $h
}
function Build-TgList {
    $st = Get-TgState
    $q = $ui.TgSearch.Text.Trim().ToLower()
    $ui.TgList.Items.Clear()
    foreach ($g in $st.Guide.groups) {
        $items = @($st.Entries.Values | Where-Object { $_.G -and $_.G.group -eq $g.id } | Sort-Object Name)
        if ($q) { $items = @($items | Where-Object { ($_.Name + ' ' + $_.G.mr.what + ' ' + $_.G.en.what + ' ' + $_.G.hi.what + ' ' + $_.G.mr.when + ' ' + $_.G.en.when + ' ' + $_.G.hi.when).ToLower().Contains($q) }) }
        if (-not $items.Count) { continue }
        [void]$ui.TgList.Items.Add((New-TgHeader (TgT $g)))
        foreach ($e in $items) {
            $it = New-Object Windows.Controls.ListBoxItem; $it.Tag = $e.Id; $it.Padding = '10,7'
            $sp = New-Object Windows.Controls.StackPanel
            $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
            $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 8; $dot.Height = 8; $dot.Margin = '0,0,9,0'; $dot.Fill = Brush $RiskColor[$e.G.risk]
            [void]$row.Children.Add($dot)
            $nm = New-Tb $e.Name 14 '#E6EDF7' 'SemiBold' '0'
            $path = Get-TgPath $e
            if (-not $path -and -not $e.G.builtin) { $nm.Opacity = 0.5 }
            [void]$row.Children.Add($nm)
            if ($e.G.auto -and $e.G.auto -notlike 'pd:*') { $ai = New-Icon ([string][char]0xE768) 10 '#2DD4BF'; $ai.Margin = '8,0,0,0'; [void]$row.Children.Add($ai) }
            [void]$sp.Children.Add($row)
            $w = New-Tb (TgT $e.G).what 12 '#93A3B8' 'Normal' '17,2,0,0'; $w.TextTrimming = 'CharacterEllipsis'; $w.TextWrapping = 'NoWrap'
            [void]$sp.Children.Add($w)
            $it.Content = $sp
            [void]$ui.TgList.Items.Add($it)
            if ($script:TgSel -eq $e.Id) { $ui.TgList.SelectedItem = $it }
        }
    }
    if (-not $q -and -not @($st.Entries.Values | Where-Object { $_.G.group -eq 'mytools' }).Count) {
        $h = New-Object Windows.Controls.ListBoxItem; $h.IsEnabled = $false; $h.Margin = '0,10,0,2'; $h.Padding = '8,2'
        $h.Content = (New-Tb $TgText.mytools 12 '#93A3B8' 'Normal' '0'); [void]$ui.TgList.Items.Add($h)
    }
    # extra pages (screen test, keyboard test, BIOS keys, guide)
    if (-not $q -and $st.Info.Catalog.docs) {
        [void]$ui.TgList.Items.Add((New-TgHeader $TgText.docs))
        foreach ($d in $st.Info.Catalog.docs) {
            $file = $d.file -replace 'guide-mr\.html$', "guide-$Lang.html"
            $it = New-Object Windows.Controls.ListBoxItem; $it.Tag = "doc:$file"; $it.Padding = '10,7'
            $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
            $ic = New-Icon ([string][char]0xE8A5) 13 '#93A3B8'; $ic.Margin = '0,0,9,0'; [void]$row.Children.Add($ic)
            $nm = if ($d.file -match 'guide-mr\.html$') { L 'Complete guide' 'संपूर्ण मार्गदर्शक' 'पूरी गाइड' } else { $d.name }
            [void]$row.Children.Add((New-Tb $nm 14 '#E6EDF7' 'Normal' '0'))
            $it.Content = $row; [void]$ui.TgList.Items.Add($it)
        }
    }
}

function Add-TgSection($panel, [string]$title, $lines, [string]$color = '#E6EDF7') {
    $lines = @($lines | Where-Object { $_ })
    if (-not $lines.Count) { return }
    [void]$panel.Children.Add((New-Tb $title 15 '#2DD4BF' 'SemiBold' '0,14,0,5'))
    $n = 1
    foreach ($l in $lines) {
        $prefix = if ($lines.Count -gt 1) { "$n.  " } else { '' }
        [void]$panel.Children.Add((New-Tb ($prefix + $l) 14 $color 'Normal' '0,0,0,5')); $n++
    }
}

function Show-TgDetail([string]$id) {
    $ui.TgDetail.Children.Clear()
    $st = Get-TgState
    $e = $st.Entries[$id]
    if (-not $e -or -not $e.G) {
        $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '0,60,0,0'; $sp.HorizontalAlignment = 'Center'
        $ic = New-Icon ([string][char]0xEC7A) 36 '#2A3A57'; $ic.HorizontalAlignment = 'Center'; [void]$sp.Children.Add($ic)
        [void]$sp.Children.Add((New-Tb $TgText.pick 15 '#93A3B8' 'Normal' '0,10,0,0'))
        [void]$ui.TgDetail.Children.Add($sp); return
    }
    $script:TgSel = $id
    $t = TgT $e.G
    $path = Get-TgPath $e
    $card = New-Object Windows.Controls.Border; $card.Style = $win.FindResource('CardBorder')
    $cp = New-Object Windows.Controls.StackPanel; $card.Child = $cp
    [void]$cp.Children.Add((New-Tb $e.Name 24 '#F1F5F9' 'SemiBold' '0,0,0,8'))
    $badges = New-Object Windows.Controls.WrapPanel; $badges.Margin = '0,0,0,8'
    [void]$badges.Children.Add((New-Badge $TgText[$e.G.risk] $RiskColor[$e.G.risk]))
    if ($e.G.boot) { [void]$badges.Children.Add((New-Badge $TgText.boot '#475569')) }
    elseif ($e.G.builtin) { [void]$badges.Children.Add((New-Badge $TgText.builtin '#475569')) }
    elseif ($path) { [void]$badges.Children.Add((New-Badge $TgText.onusb '#0F766E')) }
    else { [void]$badges.Children.Add((New-Badge $TgText.notusb '#475569')) }
    if ($e.G.auto -and $e.G.auto -notlike 'pd:*') { [void]$badges.Children.Add((New-Badge $TgText.autoyes '#1D4ED8')) }
    [void]$cp.Children.Add($badges)
    [void]$cp.Children.Add((New-Tb $t.what 15 '#E6EDF7' 'Normal' '0,4,0,0'))
    if ($t.when) { Add-TgSection $cp $TgText.when @($t.when) '#C9D4E3' }

    $bp = New-Object Windows.Controls.WrapPanel; $bp.Margin = '0,16,0,0'
    $auto = [string]$e.G.auto
    if ($auto -like 'pd:*') { [void]$bp.Children.Add((New-Button $TgText.pd "tg:pd:$($auto.Substring(3))" $true)) }
    elseif ($auto) { [void]$bp.Children.Add((New-Button $TgText.auto "tg:auto:$id" $true)) }
    if (-not $e.G.boot) {
        if ($path) {
            if ($e.Cat -and $e.Cat.archive) { [void]$bp.Children.Add((New-Button $TgText.extract "tg:extract:$id" $true)) }
            else {
                $label = if ($e.Cat -and $e.Cat.installer) { $TgText.install } else { $TgText.open }
                [void]$bp.Children.Add((New-Button $label "tg:open:$id" (-not $auto)))
            }
        } elseif ($e.Cat -and $e.Cat.page) { [void]$bp.Children.Add((New-Button $TgText.web "tg:web:$id" $false)) }
    }
    if ($script:TgResults[$id] -and $script:TgResults[$id].File) { [void]$bp.Children.Add((New-Button $TgText.file "tg:file:$id" $false)) }
    [void]$cp.Children.Add($bp)
    if (-not $path -and -not $e.G.builtin -and -not $e.G.boot -and $e.Cat -and $e.Cat.optional) {
        $note = $TgText.optional; if ($e.Cat.alt) { $note += "`n" + $e.Cat.alt }
        [void]$cp.Children.Add((New-Tb $note 13 '#93A3B8' 'Normal' '0,4,0,0'))
    }
    [void]$ui.TgDetail.Children.Add($card)
    # last result
    $res = $script:TgResults[$id]
    if ($res) {
        $box = New-Object Windows.Controls.Border; $box.BorderBrush = Brush $StatusColor[$res.Status]; $box.BorderThickness = '1.5'; $box.CornerRadius = 14; $box.Padding = '18,14'; $box.Margin = '0,0,0,14'; $box.Background = Brush '#0E1729'
        $sp = New-Object Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-Tb $TgText.result.ToUpper() 11 '#64748B' 'SemiBold' '0,0,0,2'))
        [void]$sp.Children.Add((New-Tb (Get-TgResText $res 'Head') 17 $StatusColor[$res.Status] 'SemiBold' '0,0,0,8'))
        foreach ($l in (Get-TgResText $res 'Lines')) { $tb = New-Tb $l 13 '#E6EDF7' 'Normal' '0,0,0,3'; $tb.FontFamily = 'Consolas, Nirmala UI'; [void]$sp.Children.Add($tb) }
        $box.Child = $sp; [void]$ui.TgDetail.Children.Add($box)
        Show-Entrance $box 10 300
    }
    $more = New-Object Windows.Controls.StackPanel; $more.Margin = '4,0,0,0'
    Add-TgSection $more $TgText.how $t.steps
    if ($t.good) { Add-TgSection $more $TgText.good @($t.good) '#C9D4E3' }
    Add-TgSection $more ('⚠  ' + $TgText.warn) $t.warn '#FBBF24'
    [void]$ui.TgDetail.Children.Add($more)
    Show-Entrance $card 8 240
}

$script:ToolboxBuilt = $false
function Build-Toolbox {
    if ($script:ToolboxBuilt) { return }
    $script:ToolboxBuilt = $true
    try { [void](Get-TgState) } catch { [void]$ui.TgDetail.Children.Add((New-Tb ((L 'The tools guide could not load: ' 'Tools मार्गदर्शक उघडू शकला नाही: ' 'Tools गाइड नहीं खुल सकी: ') + $_.Exception.Message) 14 '#F43F5E')); return }
    $ui.TgList.Add_SelectionChanged({
        $it = $ui.TgList.SelectedItem
        if (-not $it -or -not $it.Tag) { return }
        $tag = [string]$it.Tag
        if ($tag -like 'doc:*') { Open-UsbTool $tag.Substring(4) $null; return }
        Show-TgDetail $tag
    })
    $ui.TgSearch.Add_TextChanged({ Build-TgList })
    $ui.TgSearch.ToolTip = S 'tg.search'
    Build-TgList
    if ($script:TgSel) { Show-TgDetail $script:TgSel } else { Show-TgDetail '' }
}

function Confirm-TgWarnings($e) {
    if ($e.G.risk -eq 'safe') { return $true }
    $w = @((TgT $e.G).warn | Where-Object { $_ })
    if (-not $w.Count) { return $true }
    $text = "$($TgText.confirm)`n`n" + (($w | ForEach-Object { "⚠  $_" }) -join "`n`n") + "`n`n$($TgText.go)"
    $kind = if ($e.G.risk -eq 'danger') { 'warn' } else { 'question' }
    return ((Show-PDDialog -Text $text -Title $e.Name -Kind $kind -Buttons @(@('yes', $TgText.open, $true), @('no', (L 'Cancel' 'रद्द करा' 'रद्द करें')))) -eq 'yes')
}

function Invoke-ToolGuide([string]$arg) {
    $act, $id = $arg.Split(':', 2)
    $st = Get-TgState
    $e = $st.Entries[$id]
    switch ($act) {
        'pd' {
            switch ($id) {
                'drivers' { Show-Page 'repair'; Invoke-Repair 'drivers' }
                'advisor' { Show-Page 'advisor'; Invoke-Advisor }
                default   { Show-Page $id }
            }
            return
        }
        'web'  { if ($e.Cat.page) { Start-Process $e.Cat.page } ; return }
        'extract' {
            $arc = Get-TgPath $e
            try {
                $dest = Expand-TGMyArchive -UsbRoot $UsbRoot -Archive $arc
                # the user unpacked it on purpose: record its programs so the USB check does not ask again
                $rel = @(Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(exe|dll|msi|bat|cmd|ps1|vbs|js|sys|ocx|cpl|scr|com)$' } | ForEach-Object { $_.FullName.Substring($UsbRoot.TrimEnd('\').Length + 1) })
                if ($rel.Count) { try { [void](Add-SJTrusted -Root $UsbRoot -Rel $rel) } catch { } }
                Write-PDLog "MyTools: $(Split-Path $arc -Leaf) → $dest" 'OK'
                $script:Tg = $null; $script:TgSel = 'my:' + [IO.Path]::GetFileNameWithoutExtension($arc)
                Build-TgList; Show-TgDetail $script:TgSel
            } catch {
                $why = if (-not (Test-TGDirWritable (Split-Path $arc))) { L 'The pendrive is locked - unlock it and try again.' 'Pendrive locked आहे - unlock करून पुन्हा प्रयत्न करा.' 'Pendrive locked है - unlock करके फिर कोशिश करें।' } else { $_.Exception.Message }
                Say ((L 'Could not extract: ' 'Extract होऊ शकले नाही: ' 'Extract नहीं हो सका: ') + $why) 'Warning'
            }
            return
        }
        'file' { $f = $script:TgResults[$id].File; if ($f -and (Test-Path -LiteralPath $f)) { Start-Process -FilePath $f } ; return }
        'open' {
            if (-not (Confirm-TgWarnings $e)) { return }
            if ($id -eq 'win-memdiag') { Start-Process -FilePath "$env:WINDIR\System32\mdsched.exe"; return }
            $path = Get-TgPath $e
            if (-not $path -or $path -eq 'builtin') { Say $TgText.notusb 'Warning'; return }
            if (-not ($e.Cat -and $e.Cat.installer)) { $path = Get-TGRunPath $path }   # locked USB: run from a temp copy
            Initialize-TGToolConfig $id $path
            try { Start-Process -FilePath $path -WorkingDirectory (Split-Path $path) } catch { Say $_.Exception.Message 'Warning' }
            return
        }
        'auto' {
            $h = [string]$e.G.auto
            if ($h -eq 'stress-cpu' -and -not (Ask $TgText.stress)) { return }
            $script:TgRunning = $id
            $ui.StopBtn.Visibility = 'Visible'
            Start-PDJob -Title ("{0} - {1}" -f $e.Name, $TgText.result) -Work { param($P) Invoke-TGAuto -Handler $P.Handler -UsbRoot $P.UsbRoot -P $P } `
                -Params @{ Handler = $h; UsbRoot = $UsbRoot; ReportDir = $global:PDCtx.ReportDir; Minutes = 10 } -OnDone {
                    param($r)
                    $ui.StopBtn.Visibility = 'Collapsed'
                    if ($r -and $r.PSObject.Properties['HeadEn']) {
                        $script:TgResults[$script:TgRunning] = $r
                        Write-PDLog ("{0}: {1}" -f $script:TgRunning, (Get-TgResText $r 'Head')) $(if ($r.Status -eq 'bad') { 'WARN' } else { 'OK' })
                    }
                    Show-Page 'toolbox'
                    Show-TgDetail $script:TgRunning
                }
            if (-not $script:Job) { $ui.StopBtn.Visibility = 'Collapsed' }
        }
    }
}

function Open-UsbTool([string]$rel, [string]$toolId) {
    if (-not $rel -and $toolId) {
        $instFile = Join-Path $UsbRoot 'Sanjeevani\installed.json'
        if (Test-Path $instFile) { $i = Get-Content $instFile -Raw -Encoding UTF8 | ConvertFrom-Json; if ($i.$toolId) { $rel = $i.$toolId.path } }
    }
    if (-not $rel) { Say (L 'This tool is not on the USB. Run Setup / UPDATE.cmd again, or open its download page from the Tools guide.' 'हा tool USB वर नाही. Setup / UPDATE.cmd पुन्हा चालवा किंवा Tools मार्गदर्शक मधून download page उघडा.' 'यह tool USB पर नहीं है। Setup / UPDATE.cmd फिर चलाएँ या Tools गाइड से download page खोलें।') 'Warning'; Show-Page 'toolbox'; return }
    $full = Join-Path $UsbRoot $rel
    if (-not (Test-Path -LiteralPath $full) -and $rel -match 'guide-(en|hi)\.html$') { $full = Join-Path $UsbRoot ($rel -replace 'guide-(en|hi)\.html$', 'guide-mr.html') }
    if (-not (Test-Path -LiteralPath $full)) { Say ((L "File not found:`n" "File सापडली नाही:`n" "File नहीं मिली:`n") + $full) 'Warning'; return }
    try { Start-Process -FilePath $full -WorkingDirectory (Split-Path $full) } catch { Say $_.Exception.Message 'Warning' }
}

# ---------------------------------------------------------------- actions
$ScanWork = { param($P) Invoke-PDScan -Deep:$P.Deep -DataDir $P.DataDir }

function Invoke-Scan([bool]$deep) {
    Start-PDJob -Title $(if ($deep) { 'Deep Scan' } else { 'Quick Scan' }) -Work $ScanWork -Params @{ Deep = $deep; DataDir = $DataDir } -OnDone { param($r) if ($r) { Show-Page 'dashboard'; Show-Scan $r } }
}

function Need-Scan {
    if ($script:Scan) { return $true }
    Say (L 'Scan first. (Starting a Quick Scan ...)' 'आधी Scan करा. (Quick Scan सुरू करत आहे...)' 'पहले Scan करें। (Quick Scan शुरू कर रहे हैं...)')
    Invoke-Scan $false
    return $false
}

function Invoke-Optimize {
    $msg = L @"
One-Click Optimize will:

•  create a System Restore point
•  clean junk files (temp, old updates, error reports)
•  turn off unneeded startup programs (safe list)
•  lighten visual effects (on weak PCs)
•  set the right power plan
•  turn off Windows tips / ads, reduce telemetry
•  remove pre-installed bloatware (safe list)
•  scan again and write a report

Everything can be undone from the Speed Up page. Start?
"@ @"
One-Click Optimize खालील गोष्टी करेल:

•  System Restore point
•  Junk files cleanup (temp, जुने updates, error reports)
•  अनावश्यक startup programs बंद (सुरक्षित यादीनुसार)
•  हलके visual effects (कमकुवत PC वर)
•  योग्य power plan
•  Windows tips / ads बंद, telemetry कमी
•  Pre-installed bloatware काढणे (सुरक्षित यादी)
•  पुन्हा scan आणि report

सगळे बदल "वेग वाढवा" page वरून Undo करता येतात. सुरू करायचे?
"@ @"
One-Click Optimize ये करेगा:

•  System Restore point
•  Junk files cleanup (temp, पुराने updates, error reports)
•  बेकार startup programs बंद (सुरक्षित सूची के अनुसार)
•  हल्के visual effects (कमज़ोर PC पर)
•  सही power plan
•  Windows tips / ads बंद, telemetry कम
•  Pre-installed bloatware हटाना (सुरक्षित सूची)
•  फिर से scan और report

सभी बदलाव "स्पीड बढ़ाएँ" page से Undo हो सकते हैं। शुरू करें?
"@
    if (-not (Ask $msg 'One-Click Optimize')) { return }
    $repair = $false
    if ($script:Scan -and $script:Scan.ImageHealth -in 'Repairable', 'NonRepairable') { $repair = Ask (L 'Windows system files are damaged. Repair them as well (DISM + SFC, 20-40 minutes)?' 'Windows system files खराब आहेत. सोबत दुरुस्ती (DISM + SFC, 20-40 मिनिटे) पण करायची?' 'Windows system files खराब हैं। साथ में मरम्मत (DISM + SFC, 20-40 मिनट) भी करें?') }
    $work = {
        param($P)
        $acts = @()
        $s = Invoke-PDScan -DataDir $P.DataDir
        [void](New-PDRestorePoint 'Sanjeevani: One-click optimize')
        $junk = Clear-PDJunk
        $acts += ('✔ ' + ((L 'Junk cleanup: {0} freed' 'Junk cleanup: {0} जागा मोकळी झाली' 'Junk cleanup: {0} जगह खाली हुई') -f (Format-PDSize $junk.Freed)))
        $safe = @(Get-PDSafeStartupToDisable -Items $s.Startup -DataDir $P.DataDir -RamGB $s.Info.RAMGB)
        foreach ($it in $safe) { Set-PDStartupState -Item $it -Enabled $false }
        if ($safe.Count) { $acts += ('✔ ' + (L 'Turned off at startup: ' 'Startup मधून बंद केले: ' 'Startup से बंद किए: ') + (($safe | ForEach-Object { $_.Name }) -join ', ')) }
        $sd = @($s.Info.Disks | Where-Object { $_.IsSystem })[0]
        $hdd = [bool]($sd -and $sd.MediaType -eq 'HDD')
        if ($s.Info.RAMGB -lt 7.5 -or $hdd -or -not $s.Info.HasDedicatedGPU) { Set-PDVisualPerformance; $acts += ('✔ ' + (L 'Lighter visual effects (weak PC)' 'Visual effects हलके केले (कमकुवत PC)' 'Visual effects हल्के किए (कमज़ोर PC)')) }
        Set-PDPowerPlan -IsLaptop $s.Info.IsLaptop; $acts += ('✔ ' + (L 'Right power plan set' 'योग्य power plan लावला' 'सही power plan लगाया'))
        Disable-PDSuggestions; $acts += ('✔ ' + (L 'Windows tips / ads turned off' 'Windows tips / ads बंद केले' 'Windows tips / ads बंद किए'))
        Optimize-PDServices -DataDir $P.DataDir -SystemOnHdd $hdd -RamGB $s.Info.RAMGB; $acts += ('✔ ' + (L 'Telemetry / unneeded services reduced' 'Telemetry / अनावश्यक services कमी केल्या' 'Telemetry / बेकार services कम कीं'))
        Set-PDPagefileAuto
        $bl = @($s.Bloat | Where-Object { $_.Default } | ForEach-Object { $_.Name })
        if ($bl.Count) { Remove-PDBloat -Packages $bl; $acts += ('✔ ' + (L 'Bloatware removed' 'Bloatware काढले' 'Bloatware हटाया') + ' (' + $bl.Count + '): ' + (($s.Bloat | Where-Object { $_.Default } | ForEach-Object { $_.Label }) -join ', ')) }
        if ($P.Repair) { $r = Invoke-PDRepairOS -SkipRestorePoint; $acts += ("System repair - DISM: {0}, SFC: {1}" -f $r.Dism, $r.Sfc) }
        foreach ($i in $junk.Items) { $acts += ("   • {0}: {1} → {2}" -f (Get-PDJunkName $i), (Format-PDSize $i.Found), (Format-PDSize $i.Freed)) }
        Write-PDLog (L 'Scanning again ...' 'पुन्हा scan करत आहे...' 'फिर से scan कर रहे हैं...') 'STEP'
        $s2 = Invoke-PDScan -DataDir $P.DataDir
        $adv = Get-PDOSAdvice -Info $s2.Info -DataDir $P.DataDir
        $rep = New-PDReport -Scan $s2 -OSAdvice $adv -Actions $acts
        [pscustomobject]@{ Scan = $s2; Advice = $adv; Report = $rep; Actions = $acts; Before = $s.Score; Junk = $junk; StartupOff = @($safe | ForEach-Object { $_.Name }) }
    }
    Start-PDJob -Title 'One-Click Optimize' -Work $work -Params @{ DataDir = $DataDir; Repair = $repair } -OnDone {
        param($r)
        if (-not $r -or -not $r.Scan) { return }
        foreach ($a in $r.Actions) { [void]$script:Actions.Add($a) }
        Show-Page 'dashboard'
        Show-Scan $r.Scan; Show-Advice $r.Advice
        $ui.ReportInfo.Text = (L 'Last report: ' 'शेवटचा report: ' 'आख़िरी report: ') + $r.Report
        Show-OptimizeResult $r
        $freedTxt = if ($r.Junk) { Format-PDSize $r.Junk.Freed } else { '?' }
        Say ((L "Optimize finished!`n`nHealth score: {0} → {1}`nSpace freed: {2}`n`nWhat was done, how much junk there was and why the score is not 100 - all on the Health Check page. The report opens too.`n`nRestart the PC so every change takes effect." "Optimize पूर्ण!`n`nHealth score: {0} → {1}`nमोकळी झालेली जागा: {2}`n`nकाय केले, कोणते junk किती होते आणि score 100 का नाही - सगळे तपासणी page वर दिसत आहे. Report पण उघडत आहे.`n`nसगळे बदल लागू होण्यासाठी PC restart करा." "Optimize पूरा!`n`nHealth score: {0} → {1}`nखाली हुई जगह: {2}`n`nक्या किया, कितना junk था और score 100 क्यों नहीं - सब जाँच page पर दिख रहा है। Report भी खुल रहा है।`n`nसभी बदलाव लागू होने के लिए PC restart करें।") -f $r.Before, $r.Scan.Score, $freedTxt) 'OK'
        try { Start-Process $r.Report } catch { }
    }
}

function Show-DriverAdvice($r) {
    $T = New-Object System.Collections.ArrayList
    $p = @($r.Problems); $age = @($r.Age); $wu = @($r.WU)
    if ($p.Count) { [void]$T.Add("⚠ " + (L 'Devices not working properly' 'नीट न चालणारे devices' 'ठीक से न चलने वाले devices') + " ($($p.Count)):"); foreach ($x in $p | Select-Object -First 8) { [void]$T.Add("   • $($x.Name) - $($x.Meaning)") } }
    else { [void]$T.Add('✔ ' + (L 'Every device has a driver and is working.' 'सगळ्या devices ना driver आहे आणि ते चालू आहेत.' 'सभी devices के driver हैं और वे चालू हैं।')) }
    $uns = @($age | Where-Object Unsigned)
    if ($uns.Count) { [void]$T.Add(''); [void]$T.Add("⚠ " + (L 'Unsigned drivers' 'Signature नसलेले drivers' 'बिना signature के drivers') + " ($($uns.Count)):"); foreach ($x in $uns | Select-Object -First 5) { [void]$T.Add("   • $($x.Name) ($($x.Provider))") } }
    $old = @($age | Where-Object Old)
    if ($old.Count) { [void]$T.Add(''); [void]$T.Add("ℹ " + (L 'Older than 3 years - do not change them if they work' '3 वर्षांपेक्षा जुने - चालत असतील तर बदलू नका' '3 साल से पुराने - चल रहे हों तो न बदलें') + " ($($old.Count)):"); foreach ($x in $old | Select-Object -First 6) { [void]$T.Add("   • $($x.Name) - $($x.Version) ($(if ($x.Date) { $x.Date.ToString('yyyy-MM') }))") } }
    if ($null -eq $r.WU) { [void]$T.Add(''); [void]$T.Add('ℹ ' + (L 'Windows Update could not be checked (internet?).' 'Windows Update तपासता आले नाही (internet?).' 'Windows Update जाँच नहीं हो सका (internet?)।')) }
    elseif ($wu.Count) { [void]$T.Add(''); [void]$T.Add('✔ ' + ((L 'Windows Update has {0} driver updates checked by Microsoft:' 'Windows Update मध्ये Microsoft ने तपासलेले {0} driver updates:' 'Windows Update में Microsoft द्वारा जाँचे {0} driver updates:') -f $wu.Count)); foreach ($x in $wu | Select-Object -First 6) { [void]$T.Add("   • $($x.Title)") } }
    else { [void]$T.Add(''); [void]$T.Add('✔ ' + (L 'No new driver updates in Windows Update.' 'Windows Update मध्ये नवीन driver updates नाहीत.' 'Windows Update में नए driver updates नहीं हैं।')) }
    [void]$T.Add('')
    [void]$T.Add((L 'Safe order: 1) Windows Update → Optional updates  2) the PC maker''s app / website  3) SDIO - only for devices without a driver.' 'सुरक्षित क्रम: 1) Windows Update → Optional updates  2) PC निर्मात्याचे app / website  3) SDIO - फक्त driver नसलेल्या devices साठी.' 'सुरक्षित क्रम: 1) Windows Update → Optional updates  2) PC निर्माता का app / website  3) SDIO - सिर्फ़ बिना driver वाले devices के लिए।'))
    $ans = Show-PDDialog -Text ($T -join "`n") -Title (L 'Driver check' 'Drivers तपासणी' 'Drivers जाँच') -Kind 'info' -Buttons @(
        @('wu', 'Windows Update', $true), @('sdio', (L 'Restore point + SDIO' 'Restore point + SDIO' 'Restore point + SDIO')), @('no', (L 'Close' 'बंद करा' 'बंद करें')))
    if ($ans -eq 'wu') { Start-Process 'ms-settings:windowsupdate-optionalupdates' }
    elseif ($ans -eq 'sdio') { Invoke-Repair 'sdio-safe' }
}

# ---------------------------------------------------------------- Assistant (understand -> check -> fix)
$script:Problems = $null
$script:AiMode = 'auto'
function Get-AskProblems { if (-not $script:Problems) { $script:Problems = Get-PDProblems $DataDir }; return $script:Problems }

function New-Bubble([bool]$mine) {
    $row = New-Object Windows.Controls.DockPanel; $row.Margin = $(if ($mine) { '140,6,0,6' } else { '0,6,140,6' }); $row.LastChildFill = $false
    if (-not $mine) {
        $av = New-Object Windows.Controls.Border; $av.Width = 34; $av.Height = 34; $av.CornerRadius = 17; $av.Background = $win.FindResource('AccentGrad'); $av.VerticalAlignment = 'Top'; $av.Margin = '0,2,10,0'
        $ic = New-Icon ([string][char]0xE95E) 15 '#FFFFFF'; $ic.HorizontalAlignment = 'Center'; $av.Child = $ic
        [Windows.Controls.DockPanel]::SetDock($av, 'Left'); [void]$row.Children.Add($av)
    }
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = $(if ($mine) { '16,16,4,16' } else { '4,16,16,16' }); $b.Padding = '16,12'
    $b.Background = Brush $(if ($mine) { '#1E4FD8' } else { '#111A2E' })
    if (-not $mine) { $b.BorderBrush = Brush '#1C3550'; $b.BorderThickness = '1' }
    [Windows.Controls.DockPanel]::SetDock($b, $(if ($mine) { 'Right' } else { 'Left' }))
    $sp = New-Object Windows.Controls.StackPanel; $b.Child = $sp
    [void]$row.Children.Add($b)
    [void]$ui.ChatPanel.Children.Add($row)
    Show-Entrance $row 14 280
    $ui.ChatScroll.ScrollToEnd()
    return $sp
}
function Add-BubbleText($sp, [string]$text, [double]$size = 14, [string]$color = '#E6EDF7', [string]$weight = 'Normal') { [void]$sp.Children.Add((New-Tb $text $size $color $weight '0,0,0,4')) }

# three bouncing dots while the Assistant works
function New-TypingDots {
    $wp = New-Object Windows.Controls.StackPanel; $wp.Orientation = 'Horizontal'; $wp.Margin = '0,4,0,2'
    for ($i = 0; $i -lt 3; $i++) {
        $d = New-Object Windows.Shapes.Ellipse; $d.Width = 8; $d.Height = 8; $d.Margin = '0,0,6,0'; $d.Fill = Brush '#2DD4BF'
        $t = New-Object Windows.Media.TranslateTransform; $d.RenderTransform = $t
        $a = New-Anim 0 -6 320 ($i * 140) (New-Ease 'inout'); $a.AutoReverse = $true; $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $t.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a)
        [void]$wp.Children.Add($d)
    }
    return $wp
}

function Show-AskWelcome {
    if ($ui.ChatPanel.Children.Count) { return }
    $sp = New-Bubble $false
    Add-BubbleText $sp (L 'Hello! Tell me what is wrong with the PC - I will understand it, check this PC and fix it.' 'नमस्कार! PC मध्ये काय समस्या आहे ते लिहा - मी ती समजून घेऊन या PC वर तपासतो आणि दुरुस्त करतो.' 'नमस्ते! PC में क्या समस्या है लिखें - मैं उसे समझकर इस PC पर जाँचूँगा और ठीक करूँगा।') 15 '#F1F5F9' 'SemiBold'
    Add-BubbleText $sp (L 'Try one of these:' 'उदाहरणे:' 'उदाहरण:') 12 '#93A3B8'
    $wp = New-Object Windows.Controls.WrapPanel
    $samples = @{
        en = @('Internet is not working', 'PC is very slow', 'Printer does not print', 'No sound', 'C drive full', 'Laptop gets very hot', 'WiFi not showing')
        mr = @('Internet चालत नाही', 'PC खूप हळू चालतो', 'Printer print देत नाही', 'आवाज येत नाही', 'C drive full', 'Laptop खूप गरम होतो', 'WiFi दिसत नाही')
        hi = @('Internet नहीं चल रहा', 'PC बहुत धीमा है', 'Printer print नहीं कर रहा', 'आवाज़ नहीं आ रही', 'C drive full', 'Laptop बहुत गर्म होता है', 'WiFi नहीं दिख रहा')
    }[$Lang]
    foreach ($t in $samples) { $btn = New-Button $t "ask:sample:$t"; $btn.Margin = '0,6,6,0'; $btn.Padding = '12,6'; $btn.FontSize = 13; [void]$wp.Children.Add($btn) }
    [void]$sp.Children.Add($wp)
    Update-AiStatus
    Set-AiModeButtons
}

function Set-AiModeButtons {
    foreach ($b in $ui.AiModePanel.Children) {
        $on = ($b.Tag -eq "aimode:$($script:AiMode)")
        $b.Background = if ($on) { Brush '#134E4A' } else { [Windows.Media.Brushes]::Transparent }
        $b.Foreground = if ($on) { Brush '#FFFFFF' } else { Brush '#93A3B8' }
    }
}

function Update-AiStatus {
    $cfg = Get-PDAiConfig $UsbRoot
    $ai = Find-PDLocalAI $UsbRoot
    $off = if ($ai) { $f = Test-PDLocalAIFit $ai; if ($f.Ok) { "Offline AI: " + (L 'ready' 'तयार' 'तैयार') + " ($([IO.Path]::GetFileNameWithoutExtension($ai.Model)))" } else { "Offline AI: " + (L 'cannot run on this PC' 'या PC वर चालू शकत नाही' 'इस PC पर नहीं चल सकता') + " - $($f.Why)" } } else { 'Offline AI: ' + (L 'not on the USB (UPDATE.cmd → Y for offline AI)' 'USB वर नाही (UPDATE.cmd → offline AI साठी Y)' 'USB पर नहीं (UPDATE.cmd → offline AI के लिए Y)') }
    $on = if ($cfg.key) { "Online AI: $($cfg.provider)" } else { 'Online AI: ' + (L 'no key' 'key नाही' 'key नहीं') }
    $ui.AiStatus.Text = "$off   ·   $on   ·   " + (L 'Basic matching: always on' 'Basic matching: नेहमी चालू' 'Basic matching: हमेशा चालू')
}

function Get-AskPcInfo {
    $s = $script:Scan
    if (-not $s) {
        try { $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
            return ("{0} {1}; {2} ({3}); RAM {4} GB" -f $cs.Manufacturer, $cs.Model, $os.Caption, $os.Version, [math]::Round($cs.TotalPhysicalMemory / 1GB)) } catch { return '' }
    }
    $i = $s.Info
    $disk = ($i.Disks | Where-Object { $_.IsSystem } | ForEach-Object { "$($_.MediaType) $([math]::Round($_.SizeGB)) GB" }) -join ', '
    $f = ($s.Findings | Where-Object { $_.Severity -ne 'OK' } | Select-Object -First 6 | ForEach-Object { $_.Title }) -join '; '
    return ("{0} {1}; {2} {3} (build {4}); CPU {5}; RAM {6} GB {7}; system disk {8}; laptop={9}; health score {10}; scan findings: {11}" -f $i.Manufacturer, $i.Model, $i.OSCaption, $i.DisplayVer, $i.OSBuild, $i.CPU, $i.RAMGB, $i.RAMType, $disk, $i.IsLaptop, $s.Score, $f)
}

function Invoke-AskGo([string]$text) {
    if (-not $text) { $text = $ui.AskBox.Text.Trim() }
    if ($text.Length -lt 2) { return }
    if ($script:Job) { Say (L 'Another task is running - let it finish.' 'एक काम आधीच चालू आहे - ते संपू द्या.' 'एक काम पहले से चल रहा है - उसे पूरा होने दें।'); return }
    $mode = $script:AiMode
    $cfg = Get-PDAiConfig $UsbRoot
    $online = ($mode -in 'auto', 'online') -and $cfg.key
    $send = if ($online) { if ($cfg.sendPcInfo) { L ' (the problem description and the PC''s hardware details go to the online AI - no names or files)' ' (online AI ला समस्येचे वर्णन आणि PC ची hardware माहिती पाठवली जाईल - नावे / files नाहीत)' ' (online AI को समस्या का विवरण और PC की hardware जानकारी जाएगी - नाम / files नहीं)' } else { L ' (the problem description goes to the online AI)' ' (online AI ला समस्येचे वर्णन पाठवले जाईल)' ' (online AI को समस्या का विवरण जाएगा)' } } else { L ' (without internet)' ' (internet शिवाय)' ' (बिना internet के)' }
    $msg = (L "The Assistant will now:`n`n1.  understand the problem{0}`n2.  check whether it really exists on this PC`n3.  if it does, fix it automatically - a restore point first; big repairs (e.g. system files) can take 15-40 minutes`n`nEvery change can be undone. Start?" "Assistant आता:`n`n1.  समस्या समजून घेईल{0}`n2.  ती समस्या या PC वर खरंच आहे का ते तपासेल`n3.  असल्यास आपोआप दुरुस्त करेल - आधी restore point; मोठ्या दुरुस्त्यांना (उदा. system files) 15-40 मिनिटे लागू शकतात`n`nसगळे बदल Undo करता येतात. सुरू करायचे?" "Assistant अब:`n`n1.  समस्या समझेगा{0}`n2.  जाँचेगा कि वह इस PC पर सच में है या नहीं`n3.  है तो अपने आप ठीक करेगा - पहले restore point; बड़ी मरम्मत (जैसे system files) में 15-40 मिनट लग सकते हैं`n`nसभी बदलाव Undo हो सकते हैं। शुरू करें?") -f $send
    if (-not (Ask $msg 'Sanjeevani Assistant')) { return }
    $ui.AskBox.Text = ''
    $me = New-Bubble $true; Add-BubbleText $me $text 15 '#FFFFFF'
    $script:AskWork = New-Bubble $false
    Add-BubbleText $script:AskWork (L 'Understanding the problem and checking this PC ...' 'समस्या समजून घेत आहे आणि या PC वर तपासत आहे...' 'समस्या समझ रहे हैं और इस PC पर जाँच रहे हैं...') 14 '#93A3B8'
    [void]$script:AskWork.Children.Add((New-TypingDots))
    $pc = if ($online -and $cfg.sendPcInfo) { Get-AskPcInfo } else { '' }
    Start-PDJob -Title 'Assistant' -Work {
        param($P)
        $probs = Get-PDProblems $P.DataDir
        $u = Resolve-PDProblemIds -Text $P.Text -Problems $probs -UsbRoot $P.UsbRoot -Mode $P.Mode -PcInfo $P.Pc
        $r = if ($u.Ids.Count) { Invoke-PDTroubleshoot -Ids $u.Ids -Problems $probs } else { $null }
        [pscustomobject]@{ U = $u; R = $r; mr = $(if ($r) { Format-PDTroubleshoot $r 'mr' }); en = $(if ($r) { Format-PDTroubleshoot $r 'en' }); hi = $(if ($r) { Format-PDTroubleshoot $r 'hi' }) }
    } -Params @{ Text = $text; Mode = $mode; Pc = $pc; DataDir = $DataDir; UsbRoot = $UsbRoot } -OnDone { param($o) Show-AskResult $o }
}

function Show-AskResult($o) {
    $sp = $script:AskWork; if (-not $sp) { $sp = New-Bubble $false }
    $sp.Children.Clear()
    if (-not $o -or -not $o.PSObject.Properties['U']) { Add-BubbleText $sp (L 'Sorry, something went wrong - see the activity log.' 'माफ करा, काहीतरी अडचण आली - Activity log पहा.' 'माफ़ करें, कुछ गड़बड़ हुई - Activity log देखें।') 14 '#FBBF24'; return }
    $src = switch ($o.U.Source) { 'online' { "Online AI · $($o.U.Model)" } 'offline' { "Offline AI · $($o.U.Model)" } default { 'Basic matching' } }
    $head = New-Object Windows.Controls.WrapPanel; $head.Margin = '0,0,0,8'
    [void]$head.Children.Add((New-Badge $src '#334155'))
    if ($o.R -and $o.R.Issue) {
        $ok = $o.R.Resolved
        [void]$head.Children.Add((New-Badge $(if ($ok -and -not $o.R.Restart) { '✔ ' + (L 'Solved' 'दुरुस्त झाले' 'ठीक हो गया') } elseif ($o.R.Restart) { '↻ ' + (L 'Restart needed' 'Restart लागेल' 'Restart चाहिए') } else { '⚠ ' + (L 'Needs you' 'तुमची मदत लागेल' 'आपकी मदद चाहिए') }) $(if ($ok) { '#16A34A' } else { '#D97706' })))
    }
    [void]$sp.Children.Add($head)
    if (-not $o.R) {
        Add-BubbleText $sp (L 'I could not understand this problem well. Describe it in other words (which part: internet, printer, sound, screen, battery ... and what happens), or run a Quick Scan for a full check.' 'ही समस्या मला नीट समजली नाही. थोडे वेगळ्या शब्दांत लिहा (कोणता भाग: internet, printer, आवाज, screen, battery... आणि काय होते), किंवा पूर्ण तपासणीसाठी Quick Scan करा.' 'यह समस्या मुझे ठीक से समझ नहीं आई। दूसरे शब्दों में लिखें (कौन सा हिस्सा: internet, printer, आवाज़, screen, battery... और क्या होता है), या पूरी जाँच के लिए Quick Scan करें।') 14
        $b = New-Button 'Quick Scan' 'scan:quick'; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,6,0,0'; [void]$sp.Children.Add($b)
    } else {
        $first = $true
        foreach ($l in $o.$Lang) { Add-BubbleText $sp $l $(if ($first) { 15 } else { 14 }) $(if ($first) { '#F1F5F9' } else { '#C9D4E3' }) $(if ($first) { 'SemiBold' } else { 'Normal' }); $first = $false }
        if ($o.R.Restart) {
            $b = New-Button (L 'Restart now' 'आत्ता Restart करा' 'अभी Restart करें') 'ask:restart' $true; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,8,0,0'; [void]$sp.Children.Add($b)
        }
        if ($o.R.Issue) { [void]$script:Actions.Add("Assistant: $((Get-PDText $o.R.Issue).title) - $(Get-PDText $o.R.Fix.Text)") }
    }
    foreach ($n in $o.U.Notes) { Add-BubbleText $sp ("ℹ " + $n) 11 '#64748B' }
    $ui.ChatScroll.ScrollToEnd()
    Update-AiStatus
}

function Show-AiSettings {
    $ui.AiSettings.Visibility = if ($ui.AiSettings.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
    if ($ui.AiSettings.Visibility -eq 'Visible') { Show-Entrance $ui.AiSettings 10 260 }
    $cfg = Get-PDAiConfig $UsbRoot
    foreach ($it in $ui.AiProvider.Items) { $it.IsSelected = ($it.Tag -eq $cfg.provider) }
    $ui.AiKey.Password = [string]$cfg.key; $ui.AiModel.Text = [string]$cfg.model; $ui.AiPcInfo.IsChecked = [bool]$cfg.sendPcInfo
}
function Save-AiSettings {
    $prov = [string]$ui.AiProvider.SelectedItem.Tag
    $cfg = [pscustomobject]@{ provider = $(if ($prov) { $prov } else { 'gemini' }); key = $ui.AiKey.Password.Trim(); model = $ui.AiModel.Text.Trim(); sendPcInfo = [bool]$ui.AiPcInfo.IsChecked }
    try { Save-PDAiConfig $UsbRoot $cfg; $ui.AiSettings.Visibility = 'Collapsed'; Update-AiStatus; Say (L 'AI settings saved.' 'AI settings save झाल्या.' 'AI settings save हो गईं।') 'OK' }
    catch { Say ((L 'Could not save (USB locked?): ' 'Save होऊ शकले नाही (USB locked?): ' 'Save नहीं हो सका (USB locked?): ') + $_.Exception.Message) 'Warning' }
}

# ---------------------------------------------------------------- registry check
$script:RegIssues = @()
$script:RegRows = @()
function Show-RegIssues($items) {
    $script:RegIssues = @($items)
    $k = 0
    $script:RegRows = @(foreach ($i in $script:RegIssues) {
            $r = [CheckRow]::new(); $r.Selected = [bool]$i.Selected; $r.Name = $i.Title; $r.Sub = $i.Detail; $r.Index = $k; $k++
            $r.Badge = if ($i.Kind -eq 'malware') { if ($i.Severity -eq 'Critical') { L 'possible virus' 'virus चा संशय' 'virus का शक' } else { L 'check' 'तपासा' 'जाँचें' } } else { L 'broken' 'तुटलेले' 'टूटा हुआ' }
            $r.BadgeVisible = 'Visible'; $r
        })
    $ui.RegList.ItemsSource = $script:RegRows
    $mal = @($script:RegIssues | Where-Object { $_.Kind -eq 'malware' }).Count
    $brk = @($script:RegIssues | Where-Object { $_.Kind -eq 'broken' }).Count
    $ui.RegInfo.Text = if (-not $script:RegIssues.Count) { '✔ ' + (L 'Nothing wrong found in the registry.' 'Registry मध्ये काही चुकीचे सापडले नाही.' 'Registry में कुछ गलत नहीं मिला।') }
                       else { (L 'Found: virus-like changes {0} · broken entries {1}. The safe ones are already selected; you decide on the rest (e.g. an office proxy).' 'सापडले: virus सारखे बदल {0} · तुटलेल्या entries {1}. सुरक्षित वाटणारे आधीच निवडले आहेत; बाकी (उदा. office proxy) तुम्ही ठरवा.' 'मिले: virus जैसे बदलाव {0} · टूटी entries {1}. सुरक्षित वाले पहले से चुने हैं; बाकी (जैसे office proxy) आप तय करें।') -f $mal, $brk }
}
function Invoke-RegScan {
    Start-PDJob -Title (S 'reg.title') -Work { param($P) [pscustomobject]@{ Items = @(Get-PDRegistryIssues) } } -OnDone { param($r) Show-RegIssues $r.Items; Show-Page 'repair' }
}
function Invoke-RegFix {
    $sel = @($script:RegRows | Where-Object { $_.Selected } | ForEach-Object { $script:RegIssues[$_.Index] })
    if (-not $sel.Count) { Say (L 'First press "Check registry" and select the entries to fix.' 'आधी "Registry तपासा" करा आणि दुरुस्त करायच्या entries निवडा.' 'पहले "Registry जाँचें" करें और ठीक करने वाली entries चुनें।'); return }
    if (-not (Ask ((L "Fix {0} registry entries?`n`nA restore point and a backup of every key are taken first. ""Speed Up → Undo all changes"" reverts it." "{0} registry entries दुरुस्त करायच्या?`n`nआधी restore point आणि प्रत्येक key चा backup घेतला जाईल. ""वेग वाढवा → सर्व बदल Undo करा"" ने परत करता येते." "{0} registry entries ठीक करें?`n`nपहले restore point और हर key का backup लिया जाएगा। ""स्पीड बढ़ाएँ → सभी बदलाव Undo करें"" से वापस हो सकता है।") -f $sel.Count))) { return }
    Start-PDJob -Title 'Registry' -Work { param($P) Repair-PDRegistryIssues -Issues $P.Issues } -Params @{ Issues = $sel } -OnDone {
        param($r)
        [void]$script:Actions.Add("Registry: $($r.Fixed) entries")
        Say ((L 'Registry: {0} fixed{1}. Some changes apply after a restart.' 'Registry: {0} दुरुस्त{1}. काही बदल restart नंतर लागू होतात.' 'Registry: {0} ठीक{1}. कुछ बदलाव restart के बाद लागू होते हैं।') -f $r.Fixed, $(if ($r.Failed) { ", $($r.Failed) " + (L 'failed (see the log)' 'होऊ शकले नाहीत (log पहा)' 'नहीं हो सके (log देखें)') } else { '' })) 'OK'
        Invoke-RegScan
    }
}

# ---------------------------------------------------------------- USB virus check
function Set-UsbLockText($locked) {
    $ui.LockIcon.Text = [string][char]$(if ($locked) { 0xE72E } else { 0xE785 })
    $ui.LockIcon.Foreground = Brush $(if ($locked) { '#2DD4BF' } else { '#FBBF24' })
    $ui.LockText.Text = if ($locked) { L 'Pendrive locked (safe)' 'Pendrive locked (सुरक्षित)' 'Pendrive locked (सुरक्षित)' } else { L 'Pendrive unlocked' 'Pendrive unlocked' 'Pendrive unlocked' }
}
function Show-UsbCheck($r, [bool]$quiet) {
    if (-not $r -or -not $r.PSObject.Properties['Root']) { return }
    Set-UsbLockText ([bool]$r.Locked)
    $lines = Format-SJResult $r $Lang
    $quarMy = $false
    $myNew = @($r.NewMyTools)
    $list = ($myNew | ForEach-Object { "•  $_" }) -join "`n"
    if ($myNew.Count) {
        if ($r.Locked) { Say ((L "MyTools has new programs:`n{0}`n`nIf you put them there, unlock the pendrive, open PC Doctor again and confirm them." "MyTools मध्ये नवीन programs आहेत:`n{0}`n`nतुम्ही टाकले असल्यास pendrive unlock करून PC Doctor पुन्हा उघडा आणि नोंदवा." "MyTools में नए programs हैं:`n{0}`n`nआपने रखे हों तो pendrive unlock करके PC Doctor फिर खोलें और दर्ज करें।") -f $list) }
        else {
            $a = Show-PDDialog -Kind 'question' -Title 'MyTools' -Text ((L "MyTools has these new programs:`n`n{0}`n`nDid you put them there yourself?" "MyTools मध्ये हे नवीन programs आहेत:`n`n{0}`n`nहे तुम्ही स्वतः टाकले आहेत का?" "MyTools में ये नए programs हैं:`n`n{0}`n`nक्या ये आपने खुद रखे हैं?") -f $list) -Buttons @(
                @('yes', (L 'Yes - trust them' 'हो - नोंदवा' 'हाँ - दर्ज करें'), $true), @('no', (L 'No - quarantine' 'नाही - quarantine करा' 'नहीं - quarantine करें')))
            if ($a -eq 'yes') {
                $n = Add-SJTrusted -Root $UsbRoot -Rel $myNew
                Write-PDLog "MyTools: $n trusted" 'OK'
                $script:Tg = $null; $script:ToolboxBuilt = $false
            } elseif ($a -eq 'no') { $quarMy = $true }
        }
    }
    if (-not (Get-SJIssueCount $r) -and -not $quarMy) { if (-not $quiet -and -not $myNew.Count) { Say ($lines -join "`n") 'OK' }; return }
    if ($quarMy -and -not (Get-SJIssueCount $r)) {
        $fix = Repair-SJIntegrity $r -IncludeMyTools
        Say "Quarantine: $(@($fix.Quarantined).Count) files (_to_delete\quarantine)"; return
    }
    if ($r.Locked) {
        Say ((L "Suspicious changes on this pendrive:`n`n{0}`n`nThe pendrive is locked, so it cannot be cleaned here. Unlock it on your own clean PC and run CLEAN.cmd / UPDATE.cmd.`nUntil then do not run the programs marked ✖." "या pendrive वर संशयास्पद बदल आहेत:`n`n{0}`n`nPendrive locked असल्यामुळे इथे साफ करता येत नाही. तुमच्या स्वच्छ PC वर unlock करून CLEAN.cmd / UPDATE.cmd चालवा.`nतोपर्यंत ✖ खूण असलेले programs चालवू नका." "इस pendrive पर संदिग्ध बदलाव हैं:`n`n{0}`n`nPendrive locked है इसलिए यहाँ साफ़ नहीं हो सकता। अपने साफ़ PC पर unlock करके CLEAN.cmd / UPDATE.cmd चलाएँ।`nतब तक ✖ वाले programs न चलाएँ।") -f ($lines -join "`n")) 'Warning'
        return
    }
    if (Ask ((L "A virus may have changed this pendrive:`n`n{0}`n`nQuarantine the suspicious files (_to_delete\quarantine) and show the hidden folders again?" "या pendrive वर virus ने बदल केल्याची शक्यता:`n`n{0}`n`nसंशयास्पद files quarantine (_to_delete\quarantine) करून लपवलेले folders परत दाखवायचे?" "इस pendrive पर virus द्वारा बदलाव की संभावना:`n`n{0}`n`nसंदिग्ध files quarantine (_to_delete\quarantine) करके छिपे folders फिर दिखाएँ?") -f ($lines -join "`n"))) {
        $fix = Repair-SJIntegrity $r -IncludeMyTools:$quarMy
        $msg = "Quarantine: $(@($fix.Quarantined).Count) files · " + (L 'folders shown again' 'परत दाखवलेले folders' 'फिर दिखाए folders') + ": $(@($fix.Unhidden).Count)"
        if (@($fix.Redownload).Count) { $msg += "`n`n" + (L 'Changed tools were quarantined. Run UPDATE.cmd on your own clean PC to download them again.' 'बदललेले tools quarantine केले. तुमच्या स्वच्छ PC वर UPDATE.cmd चालवा म्हणजे ते पुन्हा download होतील.' 'बदले हुए tools quarantine किए। अपने साफ़ PC पर UPDATE.cmd चलाएँ ताकि वे फिर download हों।') }
        Write-PDLog $msg 'OK'; Say $msg 'OK'
    }
}
function Invoke-UsbCheck([bool]$full, [bool]$quiet) {
    $script:UsbCheckQuiet = $quiet
    Start-PDJob -Title $(if ($full) { L 'Pendrive virus check (full)' 'Pendrive virus तपासणी (पूर्ण)' 'Pendrive virus जाँच (पूरी)' } else { L 'Pendrive check' 'Pendrive तपासणी' 'Pendrive जाँच' }) -Work { param($P) Test-SJIntegrity -Root $P.Root -Full:$P.Full } `
        -Params @{ Root = $UsbRoot; Full = $full } -OnDone { param($r) Show-UsbCheck $r $script:UsbCheckQuiet }
}

function Invoke-Repair([string]$what) {
    switch ($what) {
        'usbcheck' { Invoke-UsbCheck $true $false; return }
        'os' {
            if (-not (Ask (L 'Start repairing Windows system files? (15-40 minutes, better with internet)' 'Windows system files दुरुस्ती सुरू करायची? (15-40 मिनिटे, Internet असल्यास चांगले)' 'Windows system files की मरम्मत शुरू करें? (15-40 मिनट, internet हो तो बेहतर)'))) { return }
            Start-PDJob -Title 'System repair' -Work { param($P) Invoke-PDRepairOS } -OnDone { param($r) if ($r) { [void]$script:Actions.Add("System repair - DISM: $($r.Dism); SFC: $($r.Sfc)"); Say ("DISM: {0}`nSFC: {1}`n`n{2}" -f $r.Dism, $r.Sfc, ($r.Notes -join "`n")) } }
        }
        'chkdsk' { Start-PDJob -Title 'Disk check' -Work { param($P) Invoke-PDDiskCheck } -OnDone { param($r) [void]$script:Actions.Add("Disk check: $r"); Say ([string]$r) } }
        'wu' { if (Ask (L 'Reset the Windows Update components?' 'Windows Update components reset करायचे?' 'Windows Update components reset करें?')) { Start-PDJob -Title 'Windows Update reset' -Work { param($P) Reset-PDWindowsUpdate; 'ok' } -OnDone { param($r) [void]$script:Actions.Add('Windows Update reset'); Say (L 'Windows Update reset done. Now open Settings > Windows Update and press "Check for updates".' 'Windows Update reset पूर्ण. आता Settings > Windows Update मध्ये Check for updates करा.' 'Windows Update reset पूरा। अब Settings > Windows Update में Check for updates करें।') 'OK' } } }
        'net' { if (Ask (L 'After a network reset the PC must be restarted. Start?' 'Network reset केल्यावर PC restart करावा लागेल. सुरू करायचे?' 'Network reset के बाद PC restart करना होगा। शुरू करें?')) { Start-PDJob -Title 'Network reset' -Work { param($P) Reset-PDNetwork; 'ok' } -OnDone { param($r) [void]$script:Actions.Add('Network reset'); Say (L 'Network reset done. Restart the PC.' 'Network reset पूर्ण. PC restart करा.' 'Network reset पूरा। PC restart करें।') 'OK' } } }
        'defender' { Start-PDJob -Title 'Defender' -Work { param($P) Repair-PDDefender; Start-PDQuickVirusScan; 'ok' } -OnDone { param($r) [void]$script:Actions.Add('Defender on + quick scan'); Say (L 'Defender check finished. Any threats are shown in Windows Security.' 'Defender तपासणी पूर्ण. Threats असतील तर Windows Security मध्ये दिसतील.' 'Defender जाँच पूरी। Threats हों तो Windows Security में दिखेंगे।') 'OK' } }
        'drivers' {
            Start-PDJob -Title 'Drivers' -Work { param($P) [pscustomobject]@{ Problems = @(Get-PDDriverProblems); Age = @(Get-PDDriverAge); WU = (Get-PDWindowsUpdateDrivers) } } -OnDone { param($r) Show-DriverAdvice $r }
        }
        'sdio-safe' {
            Start-PDJob -Title 'Restore point + SDIO' -Work { param($P) New-PDRestorePoint 'Sanjeevani: before driver install' } -OnDone { param($r) Open-UsbTool $null 'sdio' }
        }
        'drvbackup' {
            Start-PDJob -Title 'Drivers backup' -Work { param($P) Backup-PDDrivers } -OnDone { param($r) [void]$script:Actions.Add("Drivers backup: $($r.Count) drivers"); Say ((L "{0} drivers backed up:`n{1}`n`nAfter reinstalling Windows choose this folder in ""Restore drivers""." "{0} drivers backup झाले:`n{1}`n`nWindows reinstall नंतर ""Drivers restore"" मधून हाच folder निवडा." "{0} drivers का backup हुआ:`n{1}`n`nWindows reinstall के बाद ""Drivers restore"" में यही folder चुनें।") -f $r.Count, $r.Path) 'OK' }
        }
        'drvrestore' {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = L 'Choose the drivers backup folder (Reports\<PC name>\Drivers-...)' 'Drivers backup चा folder निवडा (Reports\<PC नाव>\Drivers-...)' 'Drivers backup का folder चुनें (Reports\<PC नाम>\Drivers-...)'
            $dlg.SelectedPath = Join-Path $UsbRoot 'Reports'
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $path = $dlg.SelectedPath
            if (-not (Ask ((L "Install the drivers in this folder?`n{0}" "या folder मधील drivers install करायचे?`n{0}" "इस folder के drivers install करें?`n{0}") -f $path))) { return }
            Start-PDJob -Title 'Drivers restore' -Work { param($P) Restore-PDDrivers -Path $P.Path } -Params @{ Path = $path } -OnDone { param($r) [void]$script:Actions.Add("Drivers restore: $($r.Count)"); Say ((L '{0} drivers checked / installed. Restart the PC.' '{0} drivers तपासले/install केले. PC restart करा.' '{0} drivers जाँचे/install किए। PC restart करें।') -f $r.Count) 'OK' }
        }
        'restorepoint' { Start-PDJob -Title 'Restore point' -Work { param($P) New-PDRestorePoint 'Sanjeevani: manual' } -OnDone { param($r) if ($r) { Say (L 'Restore point created.' 'Restore point तयार झाला.' 'Restore point बन गया।') 'OK' } else { Say (L 'The restore point was not created (see the log). System Protection may be off.' 'Restore point बनला नाही (log पहा). System Protection बंद असू शकते.' 'Restore point नहीं बना (log देखें)। System Protection बंद हो सकता है।') 'Warning' } } }
        'offline-info' { Say (L "If Windows does not start or shows a blue screen:`n`n1.  Switch the PC off, plug in the USB and press the Boot Menu key (Tools guide > Boot Menu / BIOS keys).`n2.  Choose ""Hiren's BootCD PE"".`n3.  On its desktop open the USB drive → run PCDoctor-Rescue.cmd.`n4.  Menu: internet / missing drivers, blue-screen cause (driver), stuck updates, SFC, DISM from the ISO, chkdsk, boot repair, and saving personal files to the pendrive." "Windows सुरू होत नसेल / blue screen येत असेल तर:`n`n1.  PC बंद करा, USB लावा, Boot Menu key दाबा (Tools मार्गदर्शक > Boot Menu / BIOS keys).`n2.  ""Hiren's BootCD PE"" निवडा.`n3.  Desktop आल्यावर USB drive उघडा → PCDoctor-Rescue.cmd चालवा.`n4.  Menu: internet / missing drivers, blue screen चे कारण (driver), अडकलेले updates, SFC, ISO मधून DISM, chkdsk, boot repair, आणि personal files pendrive वर वाचवणे." "Windows शुरू न हो / blue screen आए तो:`n`n1.  PC बंद करें, USB लगाएँ, Boot Menu key दबाएँ (Tools गाइड > Boot Menu / BIOS keys)।`n2.  ""Hiren's BootCD PE"" चुनें।`n3.  Desktop आने पर USB drive खोलें → PCDoctor-Rescue.cmd चलाएँ।`n4.  Menu: internet / missing drivers, blue screen का कारण (driver), अटके updates, SFC, ISO से DISM, chkdsk, boot repair, और personal files pendrive पर बचाना।") }
    }
}

function Invoke-Tweaks {
    if (-not (Need-Scan)) { return }
    $o = @{
        DataDir = $DataDir; Cleanup = [bool]$ui.T_cleanup.IsChecked; Recycle = [bool]$ui.T_recycle.IsChecked; Component = [bool]$ui.T_component.IsChecked
        Visual = [bool]$ui.T_visual.IsChecked; Power = [bool]$ui.T_power.IsChecked; Suggest = [bool]$ui.T_suggest.IsChecked; Services = [bool]$ui.T_services.IsChecked
        Pagefile = [bool]$ui.T_pagefile.IsChecked; Background = [bool]$ui.T_background.IsChecked; Hiber = [bool]$ui.T_hiber.IsChecked
        IsLaptop = [bool]$script:Scan.Info.IsLaptop; RamGB = [double]$script:Scan.Info.RAMGB
        Hdd = [bool](@($script:Scan.Info.Disks | Where-Object { $_.IsSystem -and $_.MediaType -eq 'HDD' }).Count)
    }
    if ($o.Recycle -and -not (Ask (L 'Files in the Recycle Bin will be deleted permanently. OK?' 'Recycle Bin मधील files कायमच्या delete होतील. चालेल?' 'Recycle Bin की files हमेशा के लिए delete होंगी। ठीक है?'))) { return }
    if ($o.Hiber -and $o.IsLaptop -and -not (Ask (L 'With hibernation off on a laptop, work is not saved when the battery runs out. Turn it off anyway?' 'Laptop वर hibernation बंद केल्यास battery संपल्यावर काम save होणार नाही. तरी बंद करायचे?' 'Laptop पर hibernation बंद करने से battery खत्म होने पर काम save नहीं होगा। फिर भी बंद करें?'))) { $o.Hiber = $false }
    $work = {
        param($P)
        $acts = @()
        [void](New-PDRestorePoint 'Sanjeevani: speed tweaks')
        if ($P.Cleanup -or $P.Recycle -or $P.Component) {
            $f = Clear-PDJunk -RecycleBin:$P.Recycle -ComponentStore:$P.Component
            $acts += ('Cleanup: ' + (Format-PDSize $f.Freed) + ' ' + (L 'freed' 'मोकळे' 'खाली'))
            foreach ($i in $f.Items) { $acts += ("   • {0}: {1} → {2}" -f (Get-PDJunkName $i), (Format-PDSize $i.Found), (Format-PDSize $i.Freed)) }
        }
        if ($P.Visual) { Set-PDVisualPerformance; $acts += (L 'Lighter visual effects' 'Visual effects हलके' 'Visual effects हल्के') }
        if ($P.Power) { Set-PDPowerPlan -IsLaptop $P.IsLaptop; $acts += 'Power plan' }
        if ($P.Suggest) { Disable-PDSuggestions; $acts += (L 'Tips / ads off' 'Tips/ads बंद' 'Tips/ads बंद') }
        if ($P.Services) { Optimize-PDServices -DataDir $P.DataDir -SystemOnHdd $P.Hdd -RamGB $P.RamGB; $acts += (L 'Fewer services' 'Services कमी' 'Services कम') }
        if ($P.Pagefile) { Set-PDPagefileAuto }
        if ($P.Background) { Disable-PDBackgroundApps; $acts += (L 'Background apps off' 'Background apps बंद' 'Background apps बंद') }
        if ($P.Hiber) { Disable-PDHibernation; $acts += (L 'Hibernation off' 'Hibernation बंद' 'Hibernation बंद') }
        [pscustomobject]@{ Actions = $acts }
    }
    Start-PDJob -Title 'Speed tweaks' -Work $work -Params $o -OnDone { param($r) foreach ($a in $r.Actions) { [void]$script:Actions.Add($a) }; Say ((L "Done:`n" "पूर्ण:`n" "पूरा:`n") + ($r.Actions -join "`n") + "`n`n" + (L 'Restart the PC to see the full effect.' 'PC restart केल्यावर पूर्ण फरक दिसेल.' 'PC restart करने पर पूरा असर दिखेगा।')) 'OK' }
}

function Invoke-StartupApply {
    if (-not (Need-Scan)) { return }
    $changes = @()
    foreach ($row in $ui.StartupList.ItemsSource) {
        $it = $script:Scan.Startup[$row.Index]
        if ([bool]$row.Selected -ne [bool]$it.Enabled) { $changes += [pscustomobject]@{ Item = $it; Enabled = [bool]$row.Selected } }
    }
    if (-not $changes.Count) { Say (L 'Nothing was changed.' 'काहीही बदल केलेला नाही.' 'कुछ नहीं बदला गया।'); return }
    if (-not (Ask ((L 'Apply {0} startup changes?' '{0} startup बदल लागू करायचे?' '{0} startup बदलाव लागू करें?') -f $changes.Count))) { return }
    foreach ($c in $changes) { Set-PDStartupState -Item $c.Item -Enabled $c.Enabled; $c.Item.Enabled = $c.Enabled }
    Flush-Log
    [void]$script:Actions.Add("Startup: $($changes.Count)")
    Say (L 'Startup changes applied. They take effect from the next restart.' 'Startup बदल लागू झाले. पुढच्या restart पासून लागू.' 'Startup बदलाव लागू हुए। अगले restart से लागू।') 'OK'
}

function Invoke-SuggestStartup {
    if (-not (Need-Scan)) { return }
    $rows = @($ui.StartupList.ItemsSource)
    foreach ($r in $rows) { if ($r.BadgeVisible -eq 'Visible') { $r.Selected = $false } }
    $ui.StartupList.ItemsSource = $null; $ui.StartupList.ItemsSource = $rows
}

function Invoke-BloatRemove {
    if (-not (Need-Scan)) { return }
    $names = @(foreach ($r in $ui.BloatList.ItemsSource) { if ($r.Selected) { $script:Scan.Bloat[$r.Index].Name } })
    if (-not $names.Count) { Say (L 'Nothing selected.' 'काहीही निवडलेले नाही.' 'कुछ नहीं चुना।'); return }
    if (-not (Ask ((L "Remove {0} apps?`n{1}" "{0} apps काढायचे?`n{1}" "{0} apps हटाएँ?`n{1}") -f $names.Count, ($names -join ', ')))) { return }
    Start-PDJob -Title 'Bloatware' -Work { param($P) Remove-PDBloat -Packages $P.Names; [pscustomobject]@{ N = $P.Names.Count } } -Params @{ Names = $names } -OnDone { param($r) [void]$script:Actions.Add("Bloatware: $($r.N)"); Say (L 'Done.' 'पूर्ण.' 'पूरा।') 'OK' }
}

function Invoke-Undo {
    if (-not (Ask (L 'Revert the startup, services, visual effects, power plan and registry changes made by PC Doctor? (Removed apps must be reinstalled from the Store.)' 'PC Doctor ने केलेले startup, services, visual effects, power plan, registry बदल परत करायचे? (काढलेले apps Store मधून परत install करावे लागतील)' 'PC Doctor के किए startup, services, visual effects, power plan, registry बदलाव वापस करें? (हटाए गए apps Store से फिर install करने होंगे)'))) { return }
    Start-PDJob -Title 'Undo' -Work { param($P) Undo-PDChanges; 'ok' } -OnDone { param($r) Say (L 'Undo finished. Restart the PC.' 'Undo पूर्ण. PC restart करा.' 'Undo पूरा। PC restart करें।') 'OK' }
}

function Get-SelectedTarget {
    if (-not $script:Storage -or $script:Storage.Targets.Count -eq 0) { return $null }
    $i = $ui.TargetCombo.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:Storage.Targets.Count) { return $null }
    return $script:Storage.Targets[$i]
}

function Invoke-StorageAnalyze {
    Start-PDJob -Title (S 'sto.analyze') -Work { param($P) Get-PDStorageAnalysis } -OnDone { param($r) if ($r) { Show-Storage $r } }
}

function Invoke-NewPartition {
    if (-not $script:Storage) { Say (L 'First press "Analyze C: drive".' 'आधी "C: drive तपासा" दाबा.' 'पहले "C: drive जाँचें" दबाएँ।'); return }
    $gb = 0
    if (-not [double]::TryParse($ui.NewPartSize.Text, [ref]$gb) -or $gb -lt 10) { Say (L 'Enter a size of 10 GB or more.' 'Size (GB) मध्ये 10 किंवा जास्त आकडा टाका.' 'Size (GB) में 10 या ज़्यादा लिखें।') 'Warning'; return }
    $msg = (L "Take {0} GB from the C: drive and create a new 'DATA' drive?`n`n•  No data is deleted.`n•  A power cut or a failing disk is still risky - back up first.`n•  Keep the laptop on the charger." "C: drive मधून {0} GB काढून नवीन 'DATA' drive बनवायचा?`n`n•  Data delete होत नाही.`n•  तरीही power जाणे / disk खराब असणे धोक्याचे - आधी backup घ्या.`n•  Laptop charging ला लावा." "C: drive से {0} GB लेकर नया 'DATA' drive बनाएँ?`n`n•  Data delete नहीं होता।`n•  फिर भी बिजली जाना / disk खराब होना खतरनाक - पहले backup लें।`n•  Laptop को charger पर रखें।") -f $gb
    if (-not (Ask $msg 'Partition')) { return }
    Start-PDJob -Title 'DATA drive' -Work { param($P) $l = New-PDDataPartition -SizeGB $P.GB; [pscustomobject]@{ Letter = $l; A = (Get-PDStorageAnalysis) } } -Params @{ GB = $gb } -OnDone {
        param($r)
        if ($r.Letter) { [void]$script:Actions.Add("DATA drive $($r.Letter):"); Show-Storage $r.A; Say ((L 'New drive {0}: is ready. Files can be moved now.' 'नवीन drive {0}: तयार. आता files हलवता येतील.' 'नया drive {0}: तैयार। अब files ले जा सकते हैं।') -f $r.Letter) 'OK' }
    }
}

function Invoke-MoveFolders {
    if (-not $script:Storage) { Say (L 'First press "Analyze C: drive".' 'आधी "C: drive तपासा" दाबा.' 'पहले "C: drive जाँचें" दबाएँ।'); return }
    $t = Get-SelectedTarget
    if (-not $t) { Say (L 'There is no second drive to move files to. First "Create DATA drive".' 'Files हलवण्यासाठी दुसरा drive नाही. आधी "नवीन DATA drive बनवा".' 'Files ले जाने के लिए दूसरा drive नहीं है। पहले "नया DATA drive बनाएँ"।') 'Warning'; return }
    $all = @($script:Storage.UserFolders) + @($script:Storage.RootFolders)
    $sel = @(foreach ($r in $ui.FolderList.ItemsSource) { if ($r.Selected) { $all[$r.Index] } })
    $sel = @($sel | Where-Object { $_.OnSystem -and -not $_.OneDrive })
    if (-not $sel.Count) { Say (L 'Nothing selected.' 'काहीही निवडलेले नाही.' 'कुछ नहीं चुना।'); return }
    $need = ($sel | Measure-Object SizeBytes -Sum).Sum
    if ($need -gt ($t.FreeBytes - 2GB)) { Say ((L 'Not enough space on {0}:. Needed {1}, available {2}.' '{0}: वर पुरेशी जागा नाही. लागेल {1}, आहे {2}.' '{0}: पर पर्याप्त जगह नहीं। चाहिए {1}, है {2}।') -f $t.Letter, (Format-PDSize $need), (Format-PDSize $t.FreeBytes)) 'Warning'; return }
    $msg = (L "Move {0} ({1}) to the {2}: drive?`n`n{3}`n`nClose open programs (Word, browser downloads) while moving." "{0} ({1}) {2}: drive वर हलवायचे?`n`n{3}`n`nहलवताना उघडे programs (Word, browser downloads) बंद करा." "{0} ({1}) {2}: drive पर ले जाएँ?`n`n{3}`n`nले जाते समय खुले programs (Word, browser downloads) बंद करें।") -f $sel.Count, (Format-PDSize $need), $t.Letter, (($sel | ForEach-Object { '•  ' + $_.Path }) -join "`n")
    if (-not (Ask $msg)) { return }
    $known = @($sel | Where-Object { $_.Kind -eq 'Known' } | ForEach-Object { $_.Name })
    $roots = @($sel | Where-Object { $_.Kind -eq 'Root' } | ForEach-Object { $_.Path })
    Start-PDJob -Title (S 'sto.move') -Work {
        param($P)
        $rep = @()
        if ($P.Known.Count) { $rep += Move-PDUserFolders -Names $P.Known -TargetDrive $P.Drive }
        if ($P.Roots.Count) { $rep += Move-PDRootFolders -Paths $P.Roots -TargetDrive $P.Drive }
        [pscustomobject]@{ Report = $rep; A = (Get-PDStorageAnalysis) }
    } -Params @{ Known = $known; Roots = $roots; Drive = $t.Letter } -OnDone {
        param($r)
        foreach ($x in $r.Report) { [void]$script:Actions.Add($x) }
        Show-Storage $r.A
        Say ((L "Done:`n`n" "पूर्ण:`n`n" "पूरा:`n`n") + ($r.Report -join "`n")) 'OK'
    }
}

function Invoke-Advisor {
    if (-not $script:Scan) {
        Start-PDJob -Title (S 'nav.advisor') -Work { param($P) $s = Invoke-PDScan -DataDir $P.DataDir; [pscustomobject]@{ Scan = $s; Adv = (Get-PDOSAdvice -Info $s.Info -DataDir $P.DataDir) } } -Params @{ DataDir = $DataDir } -OnDone { param($r) Show-Scan $r.Scan; Show-Advice $r.Adv; Show-Page 'advisor' }
    } else {
        Show-Advice (Get-PDOSAdvice -Info $script:Scan.Info -DataDir $DataDir)
    }
}

function Invoke-AppUninstall([int]$k) {
    $a = $script:Scan.AppAdvice[$k]
    if (-not $a) { return }
    if (-not (Ask ((L 'Uninstall "{0}"? Its uninstaller will open.' '"{0}" uninstall करायचे? त्याचा uninstaller उघडेल.' '"{0}" uninstall करें? उसका uninstaller खुलेगा।') -f $a.App))) { return }
    Start-PDJob -Title "Uninstall $($a.App)" -Work { param($P) Invoke-PDUninstall -UninstallString $P.U -Name $P.N; [pscustomobject]@{ N = $P.N } } -Params @{ U = $a.Uninstall; N = $a.App } -OnDone { param($r) [void]$script:Actions.Add("Uninstall: $($r.N)") }
}

function Invoke-Report {
    if (-not $script:Scan) {
        Start-PDJob -Title 'Scan + Report' -Work { param($P) $s = Invoke-PDScan -DataDir $P.DataDir; $adv = Get-PDOSAdvice -Info $s.Info -DataDir $P.DataDir; [pscustomobject]@{ Scan = $s; Adv = $adv; File = (New-PDReport -Scan $s -OSAdvice $adv -Actions $P.Acts) } } -Params @{ DataDir = $DataDir; Acts = @($script:Actions) } -OnDone {
            param($r) Show-Scan $r.Scan; Show-Advice $r.Adv; $ui.ReportInfo.Text = "Report: $($r.File)"; try { Start-Process $r.File } catch { } }
        return
    }
    $adv = if ($script:OSAdvice) { $script:OSAdvice } else { Get-PDOSAdvice -Info $script:Scan.Info -DataDir $DataDir }
    $f = New-PDReport -Scan $script:Scan -OSAdvice $adv -Actions @($script:Actions)
    Flush-Log
    $ui.ReportInfo.Text = "Report: $f"
    try { Start-Process $f } catch { }
}

function Invoke-Fix([string]$id) {
    switch ($id) {
        'storage'   { Show-Page 'storage'; Invoke-StorageAnalyze }
        'cleanup'   { Show-Page 'speed' }
        'startup'   { Show-Page 'speed' }
        'power'     { Show-Page 'speed' }
        'visual'    { Show-Page 'speed' }
        'debloat'   { Show-Page 'speed' }
        'advisor'   { Show-Page 'advisor'; Invoke-Advisor }
        'repair-os' { Invoke-Repair 'os' }
        'chkdsk'    { Invoke-Repair 'chkdsk' }
        'wureset'   { Invoke-Repair 'wu' }
        'defender'  { Invoke-Repair 'defender' }
        'drivers'   { Invoke-Repair 'drivers' }
        'registry'  { Show-Page 'repair'; Invoke-RegScan }
        'bsod'      { Show-Page 'toolbox'; Show-TgDetail 'bluescreenview'; Invoke-ToolGuide 'auto:bluescreenview' }
        'backup'    { Say (L "The disk is failing. Right now:`n1.  Copy important files to an external disk / pendrive.`n2.  For the whole disk boot from the USB and use Rescuezilla / Clonezilla.`n3.  Tools guide > CrystalDiskInfo > ""Check automatically"" shows its health." "Disk खराब होत आहे. लगेच:`n1.  महत्त्वाचे files external disk / pendrive वर copy करा.`n2.  पूर्ण disk साठी USB वरून boot करून Rescuezilla / Clonezilla वापरा.`n3.  Tools मार्गदर्शक > CrystalDiskInfo > ""आपोआप तपासा"" ने health पहा." "Disk खराब हो रहा है। तुरंत:`n1.  ज़रूरी files external disk / pendrive पर copy करें।`n2.  पूरे disk के लिए USB से boot करके Rescuezilla / Clonezilla इस्तेमाल करें।`n3.  Tools गाइड > CrystalDiskInfo > ""अपने आप जाँचें"" से health देखें।") 'Warning' }
    }
}

# ---------------------------------------------------------------- click router
$win.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
    param($sender, $e)
    $b = $e.OriginalSource
    if (-not ($b -is [Windows.Controls.Button]) -or -not $b.Tag) { return }
    $tag = [string]$b.Tag
    $kind, $arg = $tag.Split(':', 2)
    try {
        switch ($kind) {
            'nav'     { Show-Page $arg }
            'scan'    { Invoke-Scan ($arg -eq 'deep') }
            'optimize'{ Invoke-Optimize }
            'fix'     { Invoke-Fix $arg }
            'repair'  { Invoke-Repair $arg }
            'speed'   { switch ($arg) { 'tweaks' { Invoke-Tweaks } 'startup' { Invoke-StartupApply } 'suggest-startup' { Invoke-SuggestStartup } 'bloat' { Invoke-BloatRemove } 'undo' { Invoke-Undo } } }
            'storage' { switch ($arg) { 'analyze' { Invoke-StorageAnalyze } 'newpart' { Invoke-NewPartition } 'move' { Invoke-MoveFolders } } }
            'advisor' { Invoke-Advisor }
            'uninst'  { Invoke-AppUninstall ([int]$arg) }
            'tool'    { Open-UsbTool $arg $null }
            'tg'      { Invoke-ToolGuide $arg }
            'reg'     { if ($arg -eq 'fix') { Invoke-RegFix } else { Invoke-RegScan } }
            'aimode'  { $script:AiMode = $arg; Set-AiModeButtons }
            'ask'     {
                switch -Regex ($arg) {
                    '^go$'      { Invoke-AskGo }
                    '^sample:'  { Invoke-AskGo $arg.Substring(7) }
                    '^restart$' { if (Ask (L 'Restart the PC now? Save open work first.' 'PC आत्ता restart करायचा? उघडी कामे save करा.' 'PC अभी restart करें? खुला काम पहले save करें।')) { Restart-Computer -Force } }
                    '^settings$'{ Show-AiSettings }
                    '^save$'    { Save-AiSettings }
                    '^getkey$'  { Say (L "Free Gemini API key:`n`n1.  Open aistudio.google.com/apikey (sign in with a Google account).`n2.  Press ""Create API key"".`n3.  Copy the key, paste it into API key here and press Save.`n`nNo card needed. Free limit: a few hundred questions a day." "मोफत Gemini API key:`n`n1.  aistudio.google.com/apikey उघडा (Google account ने login).`n2.  ""Create API key"" दाबा.`n3.  Key copy करून इथे API key मध्ये टाका आणि Save करा.`n`nCard लागत नाही. मोफत मर्यादा: दिवसाला काही शेकडो प्रश्न." "मुफ़्त Gemini API key:`n`n1.  aistudio.google.com/apikey खोलें (Google account से login)।`n2.  ""Create API key"" दबाएँ।`n3.  Key copy करके यहाँ API key में डालें और Save करें।`n`nCard नहीं चाहिए। मुफ़्त सीमा: रोज़ कुछ सौ सवाल।"); try { Start-Process 'https://aistudio.google.com/apikey' } catch { } }
                }
            }
            'job'     { $global:PDState.Cancel = $true; $ui.StatusText.Text = L 'Stopping ...' 'थांबवत आहे...' 'रोक रहे हैं...' }
            'web'     { if ($arg) { Start-Process $arg } }
            'report'  { Invoke-Report }
            'open'    { Start-Process explorer.exe $global:PDCtx.ReportDir }
            'log'     { $ui.LogBox.Visibility = if ($ui.LogBox.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }; $ui.LogBox.ScrollToEnd() }
            'lang'    { Switch-Language $arg }
            'win'     {
                switch ($arg) {
                    'min'   { $win.WindowState = 'Minimized' }
                    'max'   { $win.WindowState = if ($win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } }
                    'close' { $win.Close() }
                }
            }
        }
    } catch { Say ((L 'Error: ' 'त्रुटी: ' 'त्रुटि: ') + $_.Exception.Message) 'Warning' }
})

$win.Add_StateChanged({
    $max = ($win.WindowState -eq 'Maximized')
    $ui.RootBorder.Margin = if ($max) { '7' } else { '0' }
    $ui.RootBorder.BorderThickness = if ($max) { '0' } else { '1' }
    $ui.MaxBtn.Content = [string][char]$(if ($max) { 0xE923 } else { 0xE922 })
})
$win.Add_Closing({
    param($s, $e)
    if ($script:Job -and -not $script:Relaunch -and -not $Headless) {
        if (-not (Ask (L 'A task is still running. Closing now leaves it unfinished. Close anyway?' 'एक काम अजून चालू आहे. मध्येच बंद केल्यास अपूर्ण राहील. तरी बंद करायचे?' 'एक काम अभी चल रहा है। बीच में बंद करने से अधूरा रहेगा। फिर भी बंद करें?'))) { $e.Cancel = $true; return }
    }
    if ($script:Job) { try { $script:Job.PS.Stop() } catch { } }
    $timer.Stop()
    try { Stop-PDLocalAI } catch { }      # the offline AI server must not keep running after PC Doctor closes
})
$ui.AskBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $e.Handled = $true; Invoke-AskGo } })
$ui.AskBox.Add_TextChanged({ $ui.AskHint.Visibility = if ($ui.AskBox.Text) { 'Collapsed' } else { 'Visible' } })

$ui.AdminText.Text = (L 'Administrator' 'Administrator' 'Administrator') + " ✓`n" + (L 'Reports' 'Reports' 'Reports') + ": $($global:PDCtx.ReportDir)"
$ui.LockText.Text = L 'Checking the pendrive ...' 'Pendrive तपासत आहे...' 'Pendrive जाँच रहे हैं...'
Set-LangButtons

# ---------------------------------------------------------------- splash: logo grows in, the heartbeat line draws itself, a ring pulses out, then it fades away
function Start-Splash {
    $sc = $ui.SplashLogo.RenderTransform
    $back = New-Object Windows.Media.Animation.BackEase; $back.Amplitude = 0.45; $back.EasingMode = 'EaseOut'
    $ui.SplashLogo.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 0 1 350))
    $sc.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Anim 0.6 1 700 0 $back))
    $sc.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (New-Anim 0.6 1 700 0 $back))
    $ui.SplashPulse.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, (New-Anim 20 0 800 450 (New-Ease 'inout')))
    $rs = $ui.SplashRing.RenderTransform
    $ui.SplashRing.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 0.8 0 1000 1150))
    $rs.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Anim 0.75 1.7 1000 1150))
    $rs.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (New-Anim 0.75 1.7 1000 1150))
    $ui.SplashText.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 0 1 450 550))
    $ui.SplashText.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (New-Anim 14 0 500 550))
    $out = New-Anim 1 0 420 2150 (New-Ease 'in')
    $out.Add_Completed({
        $ui.Splash.Visibility = 'Collapsed'
        Show-Entrance $ui.Page_dashboard 14 320
        Invoke-UsbCheck $false $true      # quick check of the USB itself (lock switch, changes made by viruses)
        if (-not (Test-PDSameUserAsDesktop)) {
            Say (L "Note: PC Doctor is running under another (admin) account. Startup, visual-effect and folder changes will apply to that admin account, not to this user.`n`nBetter: make the PC's own user an admin and run it from that login." "लक्ष द्या: PC Doctor दुसऱ्या (admin) account ने चालू आहे. Startup, visual effects आणि folders चे बदल त्या admin account ला लागतील, या user ला नाही.`n`nयोग्य मार्ग: ज्या user चा PC आहे त्यालाच admin बनवून / त्याच्या login मधून चालवा." "ध्यान दें: PC Doctor दूसरे (admin) account से चल रहा है। Startup, visual effects और folders के बदलाव उस admin account पर लागू होंगे, इस user पर नहीं।`n`nसही तरीका: जिस user का PC है उसी को admin बनाकर / उसके login से चलाएँ।") 'Warning'
        }
    })
    $ui.Splash.BeginAnimation([Windows.UIElement]::OpacityProperty, $out)
}

# ---------------------------------------------------------------- CI: self test / screenshots
function Wait-UI([int]$ms) {
    $end = [DateTime]::Now.AddMilliseconds($ms)
    do {
        $f = New-Object Windows.Threading.DispatcherFrame
        [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action[object]] { param($fr) $fr.Continue = $false }, $f)
        [Windows.Threading.Dispatcher]::PushFrame($f)
        Start-Sleep -Milliseconds 15
    } while ([DateTime]::Now -lt $end)
}
function Save-Visual($el, [string]$name) {
    $el.UpdateLayout()
    $w = [int][math]::Ceiling($el.ActualWidth); $h = [int][math]::Ceiling($el.ActualHeight)
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($el)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $Screenshot "$Lang-$name.png")); $enc.Save($fs); $fs.Close()
}
if ($Headless) {
    $code = 0
    try {
        $script:NoAnim = $true
        foreach ($n in 'FindingsList', 'StartupList', 'BloatList', 'FolderList', 'LogBox', 'Progress', 'TargetCombo', 'Win11List', 'AppList', 'TgList', 'TgDetail', 'TgSearch', 'StopBtn', 'RegList', 'RegInfo', 'OptCard', 'OptPanel', 'AskBox', 'ChatPanel', 'ChatScroll', 'AskGoBtn', 'AiModePanel', 'AiStatus', 'AiSettings', 'AiKey', 'AiProvider', 'Splash', 'ScoreArc', 'LangPanel') {
            if (-not $ui[$n]) { throw "element $n missing" }
        }
        $win.Left = 20; $win.Top = 20; $win.ShowActivated = $false
        $win.Show(); Wait-UI 300
        if ($Screenshot) {
            New-Item -ItemType Directory -Path $Screenshot -Force | Out-Null
            # splash in its final pose
            $ui.SplashLogo.Opacity = 1; $ui.SplashLogo.RenderTransform.ScaleX = 1; $ui.SplashLogo.RenderTransform.ScaleY = 1
            $ui.SplashPulse.StrokeDashOffset = 0; $ui.SplashText.Opacity = 1; $ui.SplashText.RenderTransform.Y = 0
            $ui.SplashRing.Opacity = 0.35; $ui.SplashRing.RenderTransform.ScaleX = 1.3; $ui.SplashRing.RenderTransform.ScaleY = 1.3
            Wait-UI 200; Save-Visual $ui.RootBorder '00-splash'
        }
        $ui.Splash.Visibility = 'Collapsed'
        if ($Screenshot) {
            $s = Invoke-PDScan -DataDir $DataDir
            Show-Page 'dashboard'; Show-Scan $s; Wait-UI 500; Save-Visual $ui.RootBorder '01-dashboard'
            $ui.Page_dashboard.ScrollToVerticalOffset(520); Wait-UI 300; Save-Visual $ui.RootBorder '02-dashboard-findings'
            Show-Page 'ask'
            $me = New-Bubble $true; Add-BubbleText $me (@{ en = 'printer is not printing'; mr = 'printer print देत नाही'; hi = 'printer print नहीं कर रहा' }[$Lang]) 15 '#FFFFFF'
            $sp = New-Bubble $false
            $demo = [pscustomobject]@{ U = [pscustomobject]@{ Source = 'offline'; Model = 'gemma-4-E2B-it'; Notes = @(); Ids = @('printer') }
                R = [pscustomobject]@{ Issue = $null; Resolved = $true; Restart = $false }
                en = @('Issue: Printer not printing - the print service had stopped.', 'What was done: removed 2 stuck print jobs and restarted the print service.', 'Result: ✔ fixed - the print service is running and the queue is clear.')
                mr = @('समस्या: Printer print देत नाही - print service बंद होती.', 'काय केले: अडकलेले 2 print jobs काढले आणि print service पुन्हा सुरू केली.', 'निकाल: ✔ दुरुस्त - print service चालू आहे आणि queue रिकामी आहे.')
                hi = @('समस्या: Printer print नहीं कर रहा - print service बंद थी।', 'क्या किया: अटके 2 print jobs हटाए और print service फिर शुरू की।', 'नतीजा: ✔ ठीक - print service चल रही है और queue खाली है।') }
            $demo.R.Issue = [pscustomobject]@{ en = [pscustomobject]@{ title = 'Printer' }; mr = [pscustomobject]@{ title = 'Printer' }; hi = [pscustomobject]@{ title = 'Printer' } }
            $demo.R | Add-Member -NotePropertyName Fix -NotePropertyValue ([pscustomobject]@{ Text = [pscustomobject]@{ en = 'demo'; mr = 'demo'; hi = 'demo' } })
            $script:AskWork = $sp; Show-AskResult $demo
            $wk = New-Bubble $false; Add-BubbleText $wk (L 'Understanding the problem and checking this PC ...' 'समस्या समजून घेत आहे आणि या PC वर तपासत आहे...' 'समस्या समझ रहे हैं और इस PC पर जाँच रहे हैं...') 14 '#93A3B8'; [void]$wk.Children.Add((New-TypingDots))
            Wait-UI 500; Save-Visual $ui.RootBorder '03-assistant'
            Show-Page 'repair'; Wait-UI 300; Save-Visual $ui.RootBorder '04-repair'
            Show-Page 'speed'; Wait-UI 300; Save-Visual $ui.RootBorder '05-speed'
            Show-Storage (Get-PDStorageAnalysis); Show-Page 'storage'; Wait-UI 300; Save-Visual $ui.RootBorder '06-storage'
            Show-Advice (Get-PDOSAdvice -Info $s.Info -DataDir $DataDir); Show-Page 'advisor'; Wait-UI 300; Save-Visual $ui.RootBorder '07-advisor'
            Show-Page 'toolbox'; Show-TgDetail 'crystaldiskinfo'; Wait-UI 400; Save-Visual $ui.RootBorder '08-tools'
            Show-Page 'report'; Set-Busy $true; $ui.StatusText.Text = 'Quick Scan - 45%'; $ui.Progress.Value = 45; $ui.LogBox.Visibility = 'Visible'; Wait-UI 300; Save-Visual $ui.RootBorder '09-report-busy'; Set-Busy $false
            $script:ShotDialog = 'dialog'
            [void](Ask (L "The Assistant will now:`n`n1.  understand the problem`n2.  check whether it really exists on this PC`n3.  if it does, fix it automatically" "Assistant आता:`n`n1.  समस्या समजून घेईल`n2.  ती समस्या या PC वर खरंच आहे का ते तपासेल`n3.  असल्यास आपोआप दुरुस्त करेल" "Assistant अब:`n`n1.  समस्या समझेगा`n2.  जाँचेगा कि वह इस PC पर सच में है या नहीं`n3.  है तो अपने आप ठीक करेगा") 'Sanjeevani Assistant')
        } else {
            foreach ($p in $script:Pages) { Show-Page $p; Wait-UI 50 }
        }
        Write-Host "SELFTEST OK ($Lang)"
    } catch {
        Write-Host ("SELFTEST FAILED ($Lang): " + $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
        $code = 1
    }
    try { $win.Close() } catch { }
    exit $code
}

Show-Page 'dashboard'
$timer.Start()
$win.Add_ContentRendered({ Start-Splash })
Write-PDLog "PC Doctor - USB: $UsbRoot - language: $Lang" 'INFO'
[void]$win.ShowDialog()
