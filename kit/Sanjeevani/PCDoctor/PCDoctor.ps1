#Requires -Version 5.1
<#
    Sanjeevani PC Doctor - finds and fixes Windows problems, speeds up old PCs,
    frees the C: drive and advises which OS / apps suit this hardware.
    Runs on Windows 10/11 (Windows PowerShell 5.1). Needs administrator rights.
#>
param([switch]$NoElevate)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# ---------------------------------------------------------------- elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    try {
        Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
    } catch { }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$Here    = $PSScriptRoot
$UsbRoot = (Resolve-Path (Join-Path $Here '..\..')).Path
$DataDir = Join-Path $Here 'data'
$Modules = @('Common', 'Diagnostics', 'Repair', 'Speed', 'Storage', 'Advisor', 'Report') | ForEach-Object { Join-Path $Here "lib\$_.psm1" }

try {
    foreach ($m in $Modules) { Import-Module $m -Force -DisableNameChecking -ErrorAction Stop }
    $null = Initialize-PDContext -UsbRoot $UsbRoot
} catch {
    [System.Windows.MessageBox]::Show("PC Doctor सुरू होऊ शकला नाही:`n$($_.Exception.Message)", 'Sanjeevani PC Doctor', 'OK', 'Error') | Out-Null
    exit 1
}

$global:PDLogQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$global:PDState = [hashtable]::Synchronized(@{ Progress = -1; Status = '' })

# ---------------------------------------------------------------- row types for WPF binding
class FindingRow { [string]$Title; [string]$Detail; [string]$Color; [string]$SevText; [string]$FixTag; [string]$FixVisible; [string]$FixText }
class CheckRow   { [bool]$Selected; [string]$Name; [string]$Sub; [string]$Badge; [string]$BadgeVisible; [int]$Index }
class InfoRow    { [string]$Title; [string]$Badge; [string]$Color; [string]$Detail; [string]$Tag; [string]$ButtonVisible; [string]$ButtonText }

# ---------------------------------------------------------------- XAML
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="संजीवनी PC Doctor" Width="1200" Height="780" MinWidth="980" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#0B1220" Foreground="#E2E8F0"
        FontFamily="Nirmala UI, Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Card" Color="#121C30"/>
    <SolidColorBrush x:Key="Line" Color="#22304D"/>
    <SolidColorBrush x:Key="Muted" Color="#94A3B8"/>
    <SolidColorBrush x:Key="Accent" Color="#2DD4BF"/>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#E2E8F0"/>
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="BorderBrush" Value="#334155"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#2DD4BF"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#0F766E"/>
      <Setter Property="BorderBrush" Value="#14B8A6"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Nav" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Margin" Value="10,2"/>
      <Setter Property="Padding" Value="14,10"/>
      <Setter Property="FontSize" Value="15"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E2E8F0"/>
      <Setter Property="Margin" Value="0,4"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background" Value="#121C30"/>
      <Setter Property="BorderBrush" Value="#22304D"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="16"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="FontSize" Value="24"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="17"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="Foreground" Value="#94A3B8"/><Setter Property="TextWrapping" Value="Wrap"/></Style>

    <DataTemplate x:Key="FindingTpl">
      <Border Background="#121C30" BorderBrush="#22304D" BorderThickness="1" CornerRadius="10" Margin="0,0,0,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="6"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border Background="{Binding Color}" CornerRadius="10,0,0,10"/>
          <StackPanel Grid.Column="1" Margin="14,10">
            <StackPanel Orientation="Horizontal">
              <Border Background="{Binding Color}" CornerRadius="5" Padding="7,1" Margin="0,0,8,0"><TextBlock Text="{Binding SevText}" FontSize="12" Foreground="White" FontWeight="SemiBold"/></Border>
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="15" TextWrapping="Wrap"/>
            </StackPanel>
            <TextBlock Text="{Binding Detail}" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Style="{StaticResource Primary}" Content="{Binding FixText}" Tag="{Binding FixTag}" Visibility="{Binding FixVisible}" Margin="0,0,14,0" VerticalAlignment="Center"/>
        </Grid>
      </Border>
    </DataTemplate>

    <DataTemplate x:Key="CheckTpl">
      <Border BorderBrush="#1E293B" BorderThickness="0,0,0,1" Padding="4,6">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <CheckBox IsChecked="{Binding Selected, Mode=TwoWay}" VerticalAlignment="Center" Margin="0,0,10,0"/>
          <StackPanel Grid.Column="1">
            <TextBlock Text="{Binding Name}" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
            <TextBlock Text="{Binding Sub}" Foreground="#64748B" FontSize="12" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
          <Border Grid.Column="2" Background="#134E4A" CornerRadius="5" Padding="7,1" VerticalAlignment="Center" Visibility="{Binding BadgeVisible}">
            <TextBlock Text="{Binding Badge}" FontSize="12" Foreground="#5EEAD4"/>
          </Border>
        </Grid>
      </Border>
    </DataTemplate>

    <DataTemplate x:Key="InfoTpl">
      <Border Background="#121C30" BorderBrush="#22304D" BorderThickness="1" CornerRadius="10" Padding="14,10" Margin="0,0,0,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel>
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="15" Margin="0,0,10,0"/>
              <Border Background="{Binding Color}" CornerRadius="5" Padding="7,1"><TextBlock Text="{Binding Badge}" FontSize="12" Foreground="White"/></Border>
            </StackPanel>
            <TextBlock Text="{Binding Detail}" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
          <Button Grid.Column="1" Style="{StaticResource Btn}" Content="{Binding ButtonText}" Tag="{Binding Tag}" Visibility="{Binding ButtonVisible}" VerticalAlignment="Center" Margin="10,0,0,0"/>
        </Grid>
      </Border>
    </DataTemplate>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

    <!-- sidebar -->
    <Border Grid.RowSpan="2" Background="#070C18" BorderBrush="#1E293B" BorderThickness="0,0,1,0">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="22,24,10,22">
          <TextBlock Text="संजीवनी" FontSize="30" FontWeight="Bold" Foreground="#2DD4BF"/>
          <TextBlock Text="PC Doctor" FontSize="15" Foreground="#94A3B8"/>
        </StackPanel>
        <TextBlock DockPanel.Dock="Bottom" Name="AdminText" Margin="22,10,10,18" FontSize="12" Foreground="#64748B" TextWrapping="Wrap"/>
        <StackPanel Name="NavPanel">
          <Button Style="{StaticResource Nav}" Tag="nav:dashboard" Content="🩺  तपासणी (Scan)"/>
          <Button Style="{StaticResource Nav}" Tag="nav:repair"    Content="🔧  दुरुस्ती (Repair)"/>
          <Button Style="{StaticResource Nav}" Tag="nav:speed"     Content="⚡  वेग वाढवा (Speed)"/>
          <Button Style="{StaticResource Nav}" Tag="nav:storage"   Content="💾  C: drive जागा"/>
          <Button Style="{StaticResource Nav}" Tag="nav:advisor"   Content="💡  OS / Apps सल्ला"/>
          <Button Style="{StaticResource Nav}" Tag="nav:toolbox"   Content="🧰  Toolbox"/>
          <Button Style="{StaticResource Nav}" Tag="nav:report"    Content="📄  Report"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- pages -->
    <Grid Grid.Column="1" Margin="26,22,26,8">

      <!-- DASHBOARD -->
      <ScrollViewer Name="Page_dashboard" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <DockPanel Margin="0,0,0,14">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
              <Button Style="{StaticResource Primary}" Tag="scan:quick" Content="Quick Scan (2 मिनिटे)"/>
              <Button Style="{StaticResource Btn}" Tag="scan:deep" Content="Deep Scan (+ system files, 20 मिनिटे)"/>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="PC ची तपासणी"/>
              <TextBlock Style="{StaticResource Sub}" Name="ModelText" Text="Scan सुरू करा - PC मध्ये काहीही बदलत नाही."/>
            </StackPanel>
          </DockPanel>

          <UniformGrid Columns="5" Margin="0,0,0,12">
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0"><StackPanel><TextBlock Style="{StaticResource Sub}" Text="Health score"/><TextBlock Name="ScoreText" Text="--" FontSize="34" FontWeight="Bold"/></StackPanel></Border>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0"><StackPanel><TextBlock Style="{StaticResource Sub}" Text="CPU"/><TextBlock Name="CpuText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold"/></StackPanel></Border>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0"><StackPanel><TextBlock Style="{StaticResource Sub}" Text="RAM"/><TextBlock Name="RamText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold"/></StackPanel></Border>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0"><StackPanel><TextBlock Style="{StaticResource Sub}" Text="Windows disk"/><TextBlock Name="DiskText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold"/></StackPanel></Border>
            <Border Style="{StaticResource CardBorder}" Margin="0"><StackPanel><TextBlock Style="{StaticResource Sub}" Text="OS"/><TextBlock Name="OsText" Text="--" TextWrapping="Wrap" FontWeight="SemiBold"/></StackPanel></Border>
          </UniformGrid>

          <Border Style="{StaticResource CardBorder}" Background="#0F2A2A" BorderBrush="#115E59">
            <DockPanel>
              <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="optimize" Content="⚡ One-Click Optimize" VerticalAlignment="Center" FontSize="15" Padding="18,10"/>
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="एका click मध्ये जुना PC वेगवान करा"/>
                <TextBlock Style="{StaticResource Sub}" Text="Restore point → junk cleanup → अनावश्यक startup बंद → हलके visual effects → योग्य power plan → ads/tips बंद → bloatware काढणे → report. प्रत्येक बदल Undo करता येतो."/>
              </StackPanel>
            </DockPanel>
          </Border>

          <TextBlock Style="{StaticResource H2}" Text="सापडलेल्या समस्या" Margin="0,8,0,8"/>
          <ItemsControl Name="FindingsList" ItemTemplate="{StaticResource FindingTpl}"/>
          <TextBlock Name="FindingsEmpty" Style="{StaticResource Sub}" Text="अजून scan झाला नाही."/>
        </StackPanel>
      </ScrollViewer>

      <!-- REPAIR -->
      <ScrollViewer Name="Page_repair" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Windows दुरुस्ती"/>
          <TextBlock Style="{StaticResource Sub}" Text="प्रत्येक दुरुस्तीआधी आपोआप System Restore point तयार होतो. Repair चालू असताना PC बंद करू नका." Margin="0,0,0,14"/>
          <WrapPanel Name="RepairCards"/>
        </StackPanel>
      </ScrollViewer>

      <!-- SPEED -->
      <ScrollViewer Name="Page_speed" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
        <StackPanel>
          <DockPanel>
            <Button DockPanel.Dock="Right" Style="{StaticResource Btn}" Tag="speed:undo" Content="↩ सर्व बदल Undo करा" VerticalAlignment="Center"/>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="वेग वाढवा / Windows हलके करा"/>
              <TextBlock Style="{StaticResource Sub}" Text="आधी Scan करा म्हणजे या PC साठी सुचवलेले पर्याय निवडलेले दिसतील." Margin="0,0,0,14"/>
            </StackPanel>
          </DockPanel>

          <Border Style="{StaticResource CardBorder}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Tweaks"/>
              <UniformGrid Columns="2">
                <CheckBox Name="T_cleanup" IsChecked="True" Content="Junk files साफ करा (temp, जुने updates, error reports)"/>
                <CheckBox Name="T_recycle" Content="Recycle Bin रिकामा करा"/>
                <CheckBox Name="T_component" Content="जुन्या updates ची deep cleanup (DISM, 10-20 मिनिटे)"/>
                <CheckBox Name="T_visual" IsChecked="True" Content="Animations / transparency बंद (fonts smooth राहतील)"/>
                <CheckBox Name="T_power" IsChecked="True" Content="योग्य Power plan (Desktop: High perf, Laptop: Balanced)"/>
                <CheckBox Name="T_suggest" IsChecked="True" Content="Windows tips, ads, auto-installed apps बंद"/>
                <CheckBox Name="T_services" IsChecked="True" Content="Telemetry व अनावश्यक services कमी करा"/>
                <CheckBox Name="T_pagefile" IsChecked="True" Content="Page file बंद असेल तर चालू करा"/>
                <CheckBox Name="T_background" Content="Store apps background मध्ये चालू देऊ नका"/>
                <CheckBox Name="T_hiber" Content="Hibernation बंद (C: वर RAM इतकी जागा मोकळी)"/>
              </UniformGrid>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <Button Style="{StaticResource Primary}" Tag="speed:tweaks" Content="निवडलेले tweaks लावा"/>
              </StackPanel>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource CardBorder}">
            <StackPanel>
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                  <Button Style="{StaticResource Btn}" Tag="speed:suggest-startup" Content="सुचवलेले निवडा"/>
                  <Button Style="{StaticResource Primary}" Tag="speed:startup" Content="Apply"/>
                </StackPanel>
                <StackPanel>
                  <TextBlock Style="{StaticResource H2}" Text="Startup programs"/>
                  <TextBlock Style="{StaticResource Sub}" Text="✔ = Windows सोबत सुरू होईल. काढलेला ✔ म्हणजे बंद (program uninstall होत नाही)."/>
                </StackPanel>
              </DockPanel>
              <ItemsControl Name="StartupList" ItemTemplate="{StaticResource CheckTpl}" Margin="0,10,0,0"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource CardBorder}">
            <StackPanel>
              <DockPanel>
                <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="speed:bloat" Content="निवडलेले apps काढा"/>
                <StackPanel>
                  <TextBlock Style="{StaticResource H2}" Text="Pre-installed bloatware"/>
                  <TextBlock Style="{StaticResource Sub}" Text="फक्त सुरक्षित यादीतील apps. हवे असल्यास Microsoft Store मधून परत install करता येतात."/>
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
          <DockPanel>
            <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="storage:analyze" Content="C: drive तपासा" VerticalAlignment="Center"/>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="C: drive भरला आहे?"/>
              <TextBlock Style="{StaticResource Sub}" Text="तुमचे files (Desktop, Documents, Downloads, Photos...) दुसऱ्या drive वर हलवा. Windows आणि installed programs C: वरच राहतात." Margin="0,0,0,14"/>
            </StackPanel>
          </DockPanel>
          <Border Style="{StaticResource CardBorder}" Background="#2A1A0B" BorderBrush="#92400E">
            <TextBlock TextWrapping="Wrap" Foreground="#FCD34D" Text="⚠ Partition बदलण्याआधी आणि files हलवण्याआधी महत्त्वाच्या data चा backup (external disk / pendrive) घ्या. Laptop charging ला लावून ठेवा."/>
          </Border>
          <Border Style="{StaticResource CardBorder}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="स्थिती"/>
              <TextBlock Name="StorageSummary" Style="{StaticResource Sub}" Text="'C: drive तपासा' दाबा."/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource CardBorder}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="1. Files कुठे हलवायच्या?"/>
              <StackPanel Orientation="Horizontal" Margin="0,4,0,8">
                <TextBlock Text="Drive:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <ComboBox Name="TargetCombo" Width="360" Height="32" VerticalContentAlignment="Center"/>
              </StackPanel>
              <TextBlock Style="{StaticResource Sub}" Text="दुसरा drive नसेल तर: C: लहान करून नवीन DATA drive बनवा (data सुरक्षित राहतो, पण आधी cleanup केल्यास जास्त जागा मिळते)."/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <TextBlock Text="नवीन drive size (GB):" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <TextBox Name="NewPartSize" Width="90" Height="30" VerticalContentAlignment="Center" Text="50" Background="#0B1220" Foreground="#E2E8F0" BorderBrush="#334155"/>
                <Button Style="{StaticResource Btn}" Tag="storage:newpart" Content="नवीन DATA drive बनवा" Margin="10,0,0,0"/>
                <TextBlock Name="ShrinkInfo" Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="10,0,0,0"/>
              </StackPanel>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource CardBorder}">
            <StackPanel>
              <DockPanel>
                <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="storage:move" Content="निवडलेले हलवा"/>
                <StackPanel>
                  <TextBlock Style="{StaticResource H2}" Text="2. काय हलवायचे?"/>
                  <TextBlock Style="{StaticResource Sub}" Text="आधी copy → प्रत्येक file तपासणी → मग C: वरून काढणे. C:\ मधले स्वतःचे folders हलवल्यावर जुना path पण चालतो (junction)."/>
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
          <DockPanel>
            <Button DockPanel.Dock="Right" Style="{StaticResource Primary}" Tag="advisor:run" Content="सल्ला तयार करा" VerticalAlignment="Center"/>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="या PC साठी योग्य OS आणि apps"/>
              <TextBlock Style="{StaticResource Sub}" Text="Hardware नुसार कोणते OS योग्य, कोणते apps काढावेत आणि त्यांचे हलके पर्याय." Margin="0,0,0,14"/>
            </StackPanel>
          </DockPanel>
          <TextBlock Style="{StaticResource H2}" Text="Windows 11 योग्यता"/>
          <ItemsControl Name="Win11List" ItemTemplate="{StaticResource InfoTpl}"/>
          <TextBlock Style="{StaticResource H2}" Text="शिफारस केलेले OS" Margin="0,10,0,6"/>
          <ItemsControl Name="OsList" ItemTemplate="{StaticResource InfoTpl}"/>
          <TextBlock Style="{StaticResource H2}" Text="Hardware upgrade" Margin="0,10,0,6"/>
          <ItemsControl Name="UpgradeList" ItemTemplate="{StaticResource InfoTpl}"/>
          <TextBlock Style="{StaticResource H2}" Text="Apps: काढा / हलका पर्याय वापरा" Margin="0,10,0,6"/>
          <ItemsControl Name="AppList" ItemTemplate="{StaticResource InfoTpl}"/>
        </StackPanel>
      </ScrollViewer>

      <!-- TOOLBOX -->
      <ScrollViewer Name="Page_toolbox" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Toolbox"/>
          <TextBlock Style="{StaticResource Sub}" Text="USB वरील portable tools - install न करता चालतात." Margin="0,0,0,14"/>
          <StackPanel Name="ToolPanel"/>
        </StackPanel>
      </ScrollViewer>

      <!-- REPORT -->
      <ScrollViewer Name="Page_report" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Report"/>
          <TextBlock Style="{StaticResource Sub}" Text="Customer ला देण्यासाठी / record साठी HTML report (print / PDF करता येतो)." Margin="0,0,0,14"/>
          <StackPanel Orientation="Horizontal">
            <Button Style="{StaticResource Primary}" Tag="report:make" Content="Report तयार करा आणि उघडा"/>
            <Button Style="{StaticResource Btn}" Tag="open:reports" Content="Reports folder उघडा"/>
          </StackPanel>
          <TextBlock Name="ReportInfo" Style="{StaticResource Sub}" Margin="0,14,0,0"/>
        </StackPanel>
      </ScrollViewer>
    </Grid>

    <!-- log + status -->
    <Border Grid.Row="1" Grid.Column="1" Background="#070C18" BorderBrush="#1E293B" BorderThickness="0,1,0,0">
      <DockPanel Margin="26,8,26,10">
        <DockPanel DockPanel.Dock="Top" Margin="0,0,0,6">
          <ProgressBar Name="Progress" DockPanel.Dock="Right" Width="260" Height="8" Background="#1E293B" Foreground="#2DD4BF" BorderThickness="0" Minimum="0" Maximum="100"/>
          <TextBlock Name="StatusText" Text="तयार" Foreground="#94A3B8"/>
        </DockPanel>
        <TextBox Name="LogBox" Height="120" IsReadOnly="True" Background="#0B1220" Foreground="#A7F3D0" BorderBrush="#1E293B"
                 FontFamily="Consolas, Nirmala UI" FontSize="12" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)
$ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@Name]')) { $ui[$n.Name] = $win.FindName($n.Name) }

$script:Scan = $null
$script:Storage = $null
$script:OSAdvice = $null
$script:Actions = New-Object System.Collections.ArrayList
$script:Job = $null
$script:Pages = 'dashboard', 'repair', 'speed', 'storage', 'advisor', 'toolbox', 'report'

function Brush([string]$hex) { return (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }
function Ask([string]$text, [string]$title = 'संजीवनी PC Doctor') {
    return ([System.Windows.MessageBox]::Show($win, $text, $title, 'YesNo', 'Question') -eq 'Yes')
}
function Say([string]$text, [string]$icon = 'Information') { [void][System.Windows.MessageBox]::Show($win, $text, 'संजीवनी PC Doctor', 'OK', $icon) }

# ---------------------------------------------------------------- background jobs
function Start-PDJob {
    param([string]$Title, [scriptblock]$Work, [hashtable]$Params = @{}, [scriptblock]$OnDone)
    if ($script:Job) { Say 'एक काम आधीच चालू आहे. ते पूर्ण होऊ द्या.' 'Warning'; return }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('PDLogQueue', $global:PDLogQueue)
    $rs.SessionStateProxy.SetVariable('PDState', $global:PDState)
    $rs.SessionStateProxy.SetVariable('PDCtx', $global:PDCtx)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $wrapper = {
        param($Mods, $WorkText, $P)
        $ErrorActionPreference = 'Continue'
        foreach ($m in $Mods) { Import-Module $m -Force -DisableNameChecking }
        $sb = [scriptblock]::Create($WorkText)
        try { & $sb $P }
        catch { Write-PDLog ('त्रुटी: ' + $_.Exception.Message) 'ERR'; [pscustomobject]@{ Error = $_.Exception.Message } }
    }
    [void]$ps.AddScript($wrapper.ToString()).AddArgument($Modules).AddArgument($Work.ToString()).AddArgument($Params)
    $global:PDState.Progress = -1
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
    Set-Busy $false
    Flush-Log
    $ui.StatusText.Text = $j.Title + ' - पूर्ण'
    if ($result -and $result.PSObject.Properties['Error'] -and $result.Error) {
        Say ("काम पूर्ण झाले नाही:`n" + $result.Error) 'Warning'
        return
    }
    if ($j.OnDone) { try { & $j.OnDone $result } catch { Say ("Result दाखवताना त्रुटी: " + $_.Exception.Message) 'Warning' } }
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

function Set-Busy([bool]$busy) {
    foreach ($p in $script:Pages) {
        $page = $ui["Page_$p"]
        if ($page) { $page.IsEnabled = -not $busy }
    }
    if (-not $busy) { $ui.Progress.IsIndeterminate = $false; $ui.Progress.Value = 0 }
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
function Show-Page([string]$name) {
    foreach ($p in $script:Pages) { $ui["Page_$p"].Visibility = if ($p -eq $name) { 'Visible' } else { 'Collapsed' } }
    foreach ($b in $ui.NavPanel.Children) { $b.Background = if ($b.Tag -eq "nav:$name") { Brush '#13233F' } else { [Windows.Media.Brushes]::Transparent } }
    if ($name -eq 'toolbox') { Build-Toolbox }
}

# ---------------------------------------------------------------- rendering
$SevColor = @{ Critical = '#E11D48'; Warning = '#D97706'; Info = '#2563EB'; OK = '#16A34A' }
$SevMr = @{ Critical = 'गंभीर'; Warning = 'लक्ष द्या'; Info = 'माहिती'; OK = 'ठीक' }
$FixText = @{ storage = 'जागा मोकळी करा'; cleanup = 'साफ करा'; startup = 'Startup पहा'; power = 'बदला'; visual = 'हलके करा'; debloat = 'काढा';
    advisor = 'सल्ला पहा'; 'repair-os' = 'दुरुस्त करा'; chkdsk = 'Disk तपासा'; wureset = 'दुरुस्त करा'; defender = 'चालू करा'; drivers = 'Drivers'; bsod = 'कारण शोधा'; backup = 'Backup tools' }

function Show-Scan($s) {
    $script:Scan = $s
    $i = $s.Info
    $ui.ScoreText.Text = [string]$s.Score
    $ui.ScoreText.Foreground = Brush $(if ($s.Score -ge 80) { '#22C55E' } elseif ($s.Score -ge 55) { '#F59E0B' } else { '#F43F5E' })
    $ui.CpuText.Text = "$($i.CPU)`n$($i.CPUCores) cores · load $($s.Load.CPUPct)%"
    $ui.RamText.Text = "$($i.RAMGB) GB $($i.RAMType)`nवापर $($s.Load.RAMPct)%"
    $sd = @($i.Disks | Where-Object { $_.IsSystem })[0]
    $ui.DiskText.Text = "$(if ($sd) { $sd.MediaType } else { '?' }) · $($i.SysFreeGB) GB free`n($($i.SysFreePct)% of $($i.SysSizeGB) GB)"
    $ui.OsText.Text = "$($i.OSCaption -replace 'Microsoft ', '')`n$($i.DisplayVer) build $($i.OSBuild)"
    $ui.ModelText.Text = "$($i.Manufacturer) $($i.Model) · $($i.ComputerName) · scan: $(Get-Date $s.Time -Format 'HH:mm')"
    $rows = foreach ($f in $s.Findings) {
        $r = [FindingRow]::new()
        $r.Title = $f.Title; $r.Detail = $f.Detail; $r.Color = $SevColor[$f.Severity]; $r.SevText = $SevMr[$f.Severity]
        if ($f.FixId) { $r.FixTag = "fix:$($f.FixId)"; $r.FixVisible = 'Visible'; $r.FixText = $(if ($FixText[$f.FixId]) { $FixText[$f.FixId] } else { 'उपाय' }) }
        else { $r.FixVisible = 'Collapsed' }
        $r
    }
    $ui.FindingsList.ItemsSource = @($rows)
    $ui.FindingsEmpty.Visibility = 'Collapsed'
    Show-SpeedLists
}

function Show-SpeedLists {
    if (-not $script:Scan) { return }
    $safe = @(Get-PDSafeStartupToDisable -Items $script:Scan.Startup -DataDir $DataDir -RamGB $script:Scan.Info.RAMGB)
    $k = 0
    $rows = foreach ($it in $script:Scan.Startup) {
        $r = [CheckRow]::new(); $r.Index = $k; $k++
        $r.Selected = [bool]$it.Enabled; $r.Name = $it.Name; $r.Sub = "$($it.Location) · $($it.Command)"
        $isSafe = [bool]($safe | Where-Object { $_.Name -eq $it.Name -and $_.Location -eq $it.Location })
        $r.Badge = 'बंद करणे सुचवले'; $r.BadgeVisible = if ($isSafe) { 'Visible' } else { 'Collapsed' }
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
    $ui.StorageSummary.Text = ("{0}: {1} पैकी {2} वापरले, {3} मोकळे.`nतुमचे files (हलवता येतील): {4} · Hibernation file: {5} · Page file: {6}`nDisk style: {7} · Unallocated: {8} · C: मधून सुरक्षित shrink: {9}" -f
        $a.Drive, (Format-PDSize $a.SizeBytes), (Format-PDSize $used), (Format-PDSize $a.FreeBytes), (Format-PDSize $userTotal),
        (Format-PDSize $a.HiberfilBytes), (Format-PDSize $a.PagefileBytes), $a.DiskStyle, (Format-PDSize $a.UnallocatedBytes), (Format-PDSize $a.ShrinkableBytes))
    $ui.ShrinkInfo.Text = "(जास्तीत जास्त ~{0:N0} GB)" -f ([math]::Floor(([math]::Max($a.UnallocatedBytes, $a.ShrinkableBytes)) / 1GB))
    $ui.TargetCombo.Items.Clear()
    foreach ($t in $a.Targets) { [void]$ui.TargetCombo.Items.Add(("{0}:  {1}  - {2} मोकळे" -f $t.Letter, $t.Label, (Format-PDSize $t.FreeBytes))) }
    if ($ui.TargetCombo.Items.Count -gt 0) { $ui.TargetCombo.SelectedIndex = 0 }
    else { [void]$ui.TargetCombo.Items.Add('दुसरा drive नाही - खाली नवीन DATA drive बनवा'); $ui.TargetCombo.SelectedIndex = 0 }
    $k = 0
    $rows = @()
    foreach ($f in @($a.UserFolders) + @($a.RootFolders)) {
        $r = [CheckRow]::new(); $r.Index = $k; $k++
        $r.Name = "$($f.Label)  -  $(Format-PDSize $f.SizeBytes)"
        $r.Sub = $f.Path
        if (-not $f.OnSystem) { $r.Badge = 'आधीच दुसऱ्या drive वर'; $r.BadgeVisible = 'Visible'; $r.Selected = $false }
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
        if ($c.Pass -eq $true) { $r.Badge = 'OK'; $r.Color = '#16A34A' } elseif ($c.Pass -eq $false) { $r.Badge = 'नाही'; $r.Color = '#E11D48' } else { $r.Badge = '?'; $r.Color = '#D97706' }
        $r })
    $fitColor = @{ 'सर्वोत्तम' = '#16A34A'; 'खूप चांगला' = '#16A34A'; 'चालेल' = '#2563EB'; 'तात्पुरता' = '#D97706'; 'तपासा' = '#D97706' }
    $ui.OsList.ItemsSource = @(foreach ($o in $adv.Recommendations) {
        $r = [InfoRow]::new(); $r.Title = $o.Title; $r.Badge = $o.Fit; $r.Detail = $o.Why; $r.ButtonVisible = 'Collapsed'
        $r.Color = if ($fitColor[$o.Fit]) { $fitColor[$o.Fit] } elseif ($o.Fit -match 'नाही') { '#E11D48' } else { '#2563EB' }
        $r })
    $ui.UpgradeList.ItemsSource = @(foreach ($u in $adv.Upgrades) { $r = [InfoRow]::new(); $r.Title = 'Upgrade'; $r.Badge = 'सल्ला'; $r.Color = '#0F766E'; $r.Detail = $u; $r.ButtonVisible = 'Collapsed'; $r })
    $kindMr = @{ pup = 'नको असलेले'; outdated = 'जुने'; replace = 'बदला'; av = 'Antivirus'; heavy = 'भारी' }
    $kindColor = @{ pup = '#E11D48'; outdated = '#D97706'; replace = '#2563EB'; av = '#D97706'; heavy = '#7C3AED' }
    $k = 0
    $rows = foreach ($a in $script:Scan.AppAdvice) {
        $r = [InfoRow]::new(); $r.Title = $a.App; $r.Badge = $kindMr[$a.Kind]; $r.Color = $kindColor[$a.Kind]
        $r.Detail = "$($a.Reason)`nपर्याय: $($a.Alternatives)"
        if ($a.Uninstall -and $a.Action -ne 'keep-if-needed') { $r.Tag = "uninst:$k"; $r.ButtonText = 'Uninstall'; $r.ButtonVisible = 'Visible' }
        elseif ($a.Uninstall) { $r.Tag = "uninst:$k"; $r.ButtonText = 'गरज नसल्यास Uninstall'; $r.ButtonVisible = 'Visible' }
        else { $r.ButtonVisible = 'Collapsed' }
        $k++
        $r
    }
    if (-not $rows) { $r = [InfoRow]::new(); $r.Title = 'काही काढण्यासारखे सापडले नाही'; $r.Badge = 'OK'; $r.Color = '#16A34A'; $r.ButtonVisible = 'Collapsed'; $rows = @($r) }
    $ui.AppList.ItemsSource = @($rows)
}

# ---------------------------------------------------------------- repair cards / toolbox
function New-ActionCard([string]$title, [string]$desc, [string]$btn, [string]$tag) {
    $b = New-Object Windows.Controls.Border
    $b.Style = $win.FindResource('CardBorder'); $b.Width = 430; $b.Margin = '0,0,12,12'
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $title; $t.Style = $win.FindResource('H2')
    $d = New-Object Windows.Controls.TextBlock; $d.Text = $desc; $d.Style = $win.FindResource('Sub'); $d.Margin = '0,0,0,10'; $d.MinHeight = 40
    $x = New-Object Windows.Controls.Button; $x.Content = $btn; $x.Tag = $tag; $x.Style = $win.FindResource('Primary'); $x.HorizontalAlignment = 'Left'
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($d); [void]$sp.Children.Add($x)
    $b.Child = $sp
    return $b
}

$repairCards = @(
    @('Windows system files दुरुस्ती', 'DISM (Windows Update / USB वरील Windows ISO वरून) + SFC. खराब system files बदलतो. 15-40 मिनिटे.', 'दुरुस्त करा', 'repair:os'),
    @('Disk errors तपासा', 'File-system errors शोधतो. Errors असल्यास पुढच्या restart ला दुरुस्ती होते.', 'Disk तपासा', 'repair:chkdsk'),
    @('Windows Update दुरुस्ती', 'Update अडकले / error येत असल्यास update components reset करतो.', 'Reset करा', 'repair:wu'),
    @('Internet / Network reset', 'Internet चालत नाही, DNS error, "No internet" - winsock/IP reset.', 'Reset करा', 'repair:net'),
    @('Antivirus चालू करा + quick scan', 'Microsoft Defender चालू, definitions update आणि quick scan.', 'चालू करा', 'repair:defender'),
    @('Drivers install / update', 'Snappy Driver Installer Origin (USB वरून) उघडतो. Internet शिवाय पण चालतो.', 'उघडा', 'repair:drivers'),
    @('Drivers backup', 'या PC चे सगळे drivers (WiFi, LAN, audio, display...) pendrive वर save करा. Windows reinstall करण्याआधी नक्की करा.', 'Backup घ्या', 'repair:drvbackup'),
    @('Drivers restore', 'Windows reinstall नंतर backup केलेले drivers एका click मध्ये परत install करा.', 'Restore करा', 'repair:drvrestore'),
    @('Restore point आत्ता बनवा', 'मोठा बदल करण्याआधी सुरक्षिततेसाठी.', 'बनवा', 'repair:restorepoint'),
    @('Windows सुरूच होत नाही?', 'USB वरून boot करा → "Hiren''s BootCD PE" → USB वरील Sanjeevani\PCDoctor\Offline-Repair.cmd चालवा (offline SFC/DISM, boot repair, अडकलेले updates).', 'माहिती', 'repair:offline-info')
)
foreach ($c in $repairCards) { [void]$ui.RepairCards.Children.Add((New-ActionCard $c[0] $c[1] $c[2] $c[3])) }

$script:ToolboxBuilt = $false
function Build-Toolbox {
    if ($script:ToolboxBuilt) { return }
    $script:ToolboxBuilt = $true
    $catFile = Join-Path $UsbRoot 'Sanjeevani\tools.json'
    $instFile = Join-Path $UsbRoot 'Sanjeevani\installed.json'
    if (-not (Test-Path $catFile)) { return }
    $cat = Get-Content $catFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $inst = @{}
    if (Test-Path $instFile) { (Get-Content $instFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $inst[$_.Name] = $_.Value } }
    $groups = $cat.tools | Group-Object category
    foreach ($g in $groups) {
        $h = New-Object Windows.Controls.TextBlock; $h.Text = $g.Name; $h.Style = $win.FindResource('H2'); $h.Margin = '0,10,0,8'
        [void]$ui.ToolPanel.Children.Add($h)
        $wp = New-Object Windows.Controls.WrapPanel
        foreach ($t in $g.Group) {
            $rel = $null
            if ($inst[$t.id] -and $inst[$t.id].path) { $rel = $inst[$t.id].path }
            $btn = New-Object Windows.Controls.Button
            $btn.Style = $win.FindResource('Btn'); $btn.Margin = '0,0,10,10'; $btn.Width = 250; $btn.HorizontalContentAlignment = 'Left'
            $sp = New-Object Windows.Controls.StackPanel
            $n = New-Object Windows.Controls.TextBlock; $n.Text = $t.name; $n.FontWeight = 'SemiBold'
            $d = New-Object Windows.Controls.TextBlock; $d.Text = $t.desc; $d.Foreground = Brush '#94A3B8'; $d.FontSize = 12; $d.TextWrapping = 'Wrap'
            [void]$sp.Children.Add($n); [void]$sp.Children.Add($d)
            $btn.Content = $sp
            if ($rel) { $btn.Tag = "tool:$rel" } else { $btn.Tag = "web:$($t.page)"; $btn.Opacity = 0.6; $btn.ToolTip = 'USB वर नाही - download page उघडेल' }
            [void]$wp.Children.Add($btn)
        }
        [void]$ui.ToolPanel.Children.Add($wp)
    }
    $h = New-Object Windows.Controls.TextBlock; $h.Text = 'Tests आणि माहिती'; $h.Style = $win.FindResource('H2'); $h.Margin = '0,10,0,8'
    [void]$ui.ToolPanel.Children.Add($h)
    $wp = New-Object Windows.Controls.WrapPanel
    foreach ($d in $cat.docs) {
        $btn = New-Object Windows.Controls.Button; $btn.Style = $win.FindResource('Btn'); $btn.Margin = '0,0,10,10'; $btn.Content = $d.name; $btn.Tag = "tool:$($d.file)"
        [void]$wp.Children.Add($btn)
    }
    [void]$ui.ToolPanel.Children.Add($wp)
}

function Open-UsbTool([string]$rel, [string]$toolId) {
    if (-not $rel -and $toolId) {
        $instFile = Join-Path $UsbRoot 'Sanjeevani\installed.json'
        if (Test-Path $instFile) { $i = Get-Content $instFile -Raw -Encoding UTF8 | ConvertFrom-Json; if ($i.$toolId) { $rel = $i.$toolId.path } }
    }
    if (-not $rel) { Say 'हा tool USB वर नाही. Setup script पुन्हा चालवा किंवा Toolbox मधून download page उघडा.' 'Warning'; Show-Page 'toolbox'; return }
    $full = Join-Path $UsbRoot $rel
    if (-not (Test-Path -LiteralPath $full)) { Say "File सापडली नाही:`n$full" 'Warning'; return }
    try { Start-Process -FilePath $full -WorkingDirectory (Split-Path $full) } catch { Say $_.Exception.Message 'Warning' }
}

# ---------------------------------------------------------------- actions
$ScanWork = { param($P) Invoke-PDScan -Deep:$P.Deep -DataDir $P.DataDir }

function Invoke-Scan([bool]$deep) {
    Start-PDJob -Title $(if ($deep) { 'Deep scan' } else { 'Quick scan' }) -Work $ScanWork -Params @{ Deep = $deep; DataDir = $DataDir } -OnDone { param($r) if ($r) { Show-Scan $r; Show-Page 'dashboard' } }
}

function Need-Scan {
    if ($script:Scan) { return $true }
    Say 'आधी Scan करा. (Quick Scan सुरू करत आहे...)'
    Invoke-Scan $false
    return $false
}

function Invoke-Optimize {
    $msg = @"
One-Click Optimize खालील गोष्टी करेल:

• System Restore point
• Junk files cleanup (temp, जुने updates, error reports)
• अनावश्यक startup programs बंद (सुरक्षित यादीनुसार)
• हलके visual effects (कमकुवत PC वर)
• योग्य power plan
• Windows tips / ads बंद, telemetry कमी
• Pre-installed bloatware काढणे (सुरक्षित यादी)
• पुन्हा scan आणि report

सगळे बदल 'Speed' tab मधील Undo ने परत करता येतात. सुरू करायचे?
"@
    if (-not (Ask $msg)) { return }
    $repair = $false
    if ($script:Scan -and $script:Scan.ImageHealth -in 'Repairable', 'NonRepairable') { $repair = Ask 'Windows system files खराब आहेत. सोबत दुरुस्ती (DISM + SFC, 20-40 मिनिटे) पण करायची?' }
    $work = {
        param($P)
        $acts = @()
        $s = Invoke-PDScan -DataDir $P.DataDir
        [void](New-PDRestorePoint 'Sanjeevani: One-click optimize')
        $freed = Clear-PDJunk
        $acts += ('Junk cleanup: ' + (Format-PDSize $freed) + ' मोकळे')
        $safe = @(Get-PDSafeStartupToDisable -Items $s.Startup -DataDir $P.DataDir -RamGB $s.Info.RAMGB)
        foreach ($it in $safe) { Set-PDStartupState -Item $it -Enabled $false }
        if ($safe.Count) { $acts += ('Startup बंद: ' + (($safe | ForEach-Object { $_.Name }) -join ', ')) }
        $sd = @($s.Info.Disks | Where-Object { $_.IsSystem })[0]
        $hdd = [bool]($sd -and $sd.MediaType -eq 'HDD')
        if ($s.Info.RAMGB -lt 7.5 -or $hdd -or -not $s.Info.HasDedicatedGPU) { Set-PDVisualPerformance; $acts += 'Visual effects हलके केले' }
        Set-PDPowerPlan -IsLaptop $s.Info.IsLaptop; $acts += 'Power plan तपासला'
        Disable-PDSuggestions; $acts += 'Tips/ads बंद'
        Optimize-PDServices -DataDir $P.DataDir -SystemOnHdd $hdd -RamGB $s.Info.RAMGB; $acts += 'Telemetry / अनावश्यक services कमी'
        Set-PDPagefileAuto
        $bl = @($s.Bloat | Where-Object { $_.Default } | ForEach-Object { $_.Name })
        if ($bl.Count) { Remove-PDBloat -Packages $bl; $acts += ('Bloatware काढले: ' + $bl.Count) }
        if ($P.Repair) { $r = Invoke-PDRepairOS -SkipRestorePoint; $acts += ("System repair - DISM: {0}, SFC: {1}" -f $r.Dism, $r.Sfc) }
        Write-PDLog 'पुन्हा scan करत आहे...' 'STEP'
        $s2 = Invoke-PDScan -DataDir $P.DataDir
        $adv = Get-PDOSAdvice -Info $s2.Info -DataDir $P.DataDir
        $rep = New-PDReport -Scan $s2 -OSAdvice $adv -Actions $acts
        [pscustomobject]@{ Scan = $s2; Advice = $adv; Report = $rep; Actions = $acts; Before = $s.Score }
    }
    Start-PDJob -Title 'One-Click Optimize' -Work $work -Params @{ DataDir = $DataDir; Repair = $repair } -OnDone {
        param($r)
        if (-not $r -or -not $r.Scan) { return }
        foreach ($a in $r.Actions) { [void]$script:Actions.Add($a) }
        Show-Scan $r.Scan; Show-Advice $r.Advice
        $ui.ReportInfo.Text = "शेवटचा report: $($r.Report)"
        Say ("Optimize पूर्ण!`n`nHealth score: {0} → {1}`n`n{2}`n`nसगळे बदल लागू होण्यासाठी PC restart करा." -f $r.Before, $r.Scan.Score, ($r.Actions -join "`n"))
        try { Start-Process $r.Report } catch { }
    }
}

function Invoke-Repair([string]$what) {
    switch ($what) {
        'os' {
            if (-not (Ask "Windows system files दुरुस्ती सुरू करायची? (15-40 मिनिटे, Internet असल्यास चांगले)")) { return }
            Start-PDJob -Title 'System repair' -Work { param($P) Invoke-PDRepairOS } -OnDone { param($r) if ($r) { [void]$script:Actions.Add("System repair - DISM: $($r.Dism); SFC: $($r.Sfc)"); Say ("DISM: {0}`nSFC: {1}`n`n{2}" -f $r.Dism, $r.Sfc, ($r.Notes -join "`n")) } }
        }
        'chkdsk' { Start-PDJob -Title 'Disk check' -Work { param($P) Invoke-PDDiskCheck } -OnDone { param($r) [void]$script:Actions.Add("Disk check: $r"); Say ([string]$r) } }
        'wu' { if (Ask 'Windows Update components reset करायचे?') { Start-PDJob -Title 'Windows Update reset' -Work { param($P) Reset-PDWindowsUpdate; 'ok' } -OnDone { param($r) [void]$script:Actions.Add('Windows Update reset'); Say 'Windows Update reset पूर्ण. आता Settings > Windows Update मध्ये Check for updates करा.' } } }
        'net' { if (Ask 'Network reset केल्यावर PC restart करावा लागेल. सुरू करायचे?') { Start-PDJob -Title 'Network reset' -Work { param($P) Reset-PDNetwork; 'ok' } -OnDone { param($r) [void]$script:Actions.Add('Network reset'); Say 'Network reset पूर्ण. PC restart करा.' } } }
        'defender' { Start-PDJob -Title 'Defender' -Work { param($P) Repair-PDDefender; Start-PDQuickVirusScan; 'ok' } -OnDone { param($r) [void]$script:Actions.Add('Defender चालू + quick scan'); Say 'Defender तपासणी पूर्ण. Threats असतील तर Windows Security मध्ये दिसतील.' } }
        'drivers' { Open-UsbTool $null 'sdio' }
        'drvbackup' {
            Start-PDJob -Title 'Drivers backup' -Work { param($P) Backup-PDDrivers } -OnDone { param($r) [void]$script:Actions.Add("Drivers backup: $($r.Count) drivers"); Say ("{0} drivers backup झाले:`n{1}`n`nWindows reinstall नंतर 'Drivers restore' मधून हाच folder निवडा." -f $r.Count, $r.Path) }
        }
        'drvrestore' {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Drivers backup चा folder निवडा (Reports\<PC नाव>\Drivers-...)'
            $dlg.SelectedPath = Join-Path $UsbRoot 'Reports'
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $path = $dlg.SelectedPath
            if (-not (Ask "या folder मधील drivers install करायचे?`n$path")) { return }
            Start-PDJob -Title 'Drivers restore' -Work { param($P) Restore-PDDrivers -Path $P.Path } -Params @{ Path = $path } -OnDone { param($r) [void]$script:Actions.Add("Drivers restore: $($r.Count)"); Say ("{0} drivers तपासले/install केले. PC restart करा." -f $r.Count) }
        }
        'restorepoint' { Start-PDJob -Title 'Restore point' -Work { param($P) New-PDRestorePoint 'Sanjeevani: manual' } -OnDone { param($r) if ($r) { Say 'Restore point तयार झाला.' } else { Say 'Restore point बनला नाही (log पहा). System Protection बंद असू शकते.' 'Warning' } } }
        'offline-info' { Say "Windows boot होत नसेल तर:`n`n1. PC बंद करा, USB लावा, Boot Menu key दाबा (Toolbox > Boot keys).`n2. 'Hiren's BootCD PE' निवडा.`n3. Desktop आल्यावर USB drive उघडा → Sanjeevani\PCDoctor\Offline-Repair.cmd वर right-click → Run as administrator.`n4. Menu मधून Offline SFC / DISM / Boot repair / अडकलेले updates revert निवडा." }
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
    if ($o.Recycle -and -not (Ask 'Recycle Bin मधील files कायमच्या delete होतील. चालेल?')) { return }
    if ($o.Hiber -and $o.IsLaptop -and -not (Ask 'Laptop वर hibernation बंद केल्यास battery संपल्यावर काम save होणार नाही. तरी बंद करायचे?')) { $o.Hiber = $false }
    $work = {
        param($P)
        $acts = @()
        [void](New-PDRestorePoint 'Sanjeevani: speed tweaks')
        if ($P.Cleanup -or $P.Recycle -or $P.Component) { $f = Clear-PDJunk -RecycleBin:$P.Recycle -ComponentStore:$P.Component; $acts += ('Cleanup: ' + (Format-PDSize $f)) }
        if ($P.Visual) { Set-PDVisualPerformance; $acts += 'Visual effects हलके' }
        if ($P.Power) { Set-PDPowerPlan -IsLaptop $P.IsLaptop; $acts += 'Power plan' }
        if ($P.Suggest) { Disable-PDSuggestions; $acts += 'Tips/ads बंद' }
        if ($P.Services) { Optimize-PDServices -DataDir $P.DataDir -SystemOnHdd $P.Hdd -RamGB $P.RamGB; $acts += 'Services कमी' }
        if ($P.Pagefile) { Set-PDPagefileAuto }
        if ($P.Background) { Disable-PDBackgroundApps; $acts += 'Background apps बंद' }
        if ($P.Hiber) { Disable-PDHibernation; $acts += 'Hibernation बंद' }
        [pscustomobject]@{ Actions = $acts }
    }
    Start-PDJob -Title 'Speed tweaks' -Work $work -Params $o -OnDone { param($r) foreach ($a in $r.Actions) { [void]$script:Actions.Add($a) }; Say ("पूर्ण:`n" + ($r.Actions -join "`n") + "`n`nPC restart केल्यावर पूर्ण फरक दिसेल.") }
}

function Invoke-StartupApply {
    if (-not (Need-Scan)) { return }
    $changes = @()
    foreach ($row in $ui.StartupList.ItemsSource) {
        $it = $script:Scan.Startup[$row.Index]
        if ([bool]$row.Selected -ne [bool]$it.Enabled) { $changes += [pscustomobject]@{ Item = $it; Enabled = [bool]$row.Selected } }
    }
    if (-not $changes.Count) { Say 'काहीही बदल केलेला नाही.'; return }
    if (-not (Ask ("{0} startup बदल लागू करायचे?" -f $changes.Count))) { return }
    foreach ($c in $changes) { Set-PDStartupState -Item $c.Item -Enabled $c.Enabled; $c.Item.Enabled = $c.Enabled }
    Flush-Log
    [void]$script:Actions.Add("Startup बदल: $($changes.Count)")
    Say 'Startup बदल लागू झाले. पुढच्या restart पासून लागू.'
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
    if (-not $names.Count) { Say 'काहीही निवडलेले नाही.'; return }
    if (-not (Ask ("{0} apps काढायचे?`n{1}" -f $names.Count, ($names -join ', ')))) { return }
    Start-PDJob -Title 'Bloatware removal' -Work { param($P) Remove-PDBloat -Packages $P.Names; [pscustomobject]@{ N = $P.Names.Count } } -Params @{ Names = $names } -OnDone { param($r) [void]$script:Actions.Add("Bloatware काढले: $($r.N)"); Say 'पूर्ण.' }
}

function Invoke-Undo {
    if (-not (Ask 'PC Doctor ने केलेले startup, services, visual effects, power plan, registry बदल परत करायचे? (काढलेले apps Store मधून परत install करावे लागतील)')) { return }
    Start-PDJob -Title 'Undo' -Work { param($P) Undo-PDChanges; 'ok' } -OnDone { param($r) Say 'Undo पूर्ण. PC restart करा.' }
}

function Get-SelectedTarget {
    if (-not $script:Storage -or $script:Storage.Targets.Count -eq 0) { return $null }
    $i = $ui.TargetCombo.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:Storage.Targets.Count) { return $null }
    return $script:Storage.Targets[$i]
}

function Invoke-StorageAnalyze {
    Start-PDJob -Title 'C: drive विश्लेषण' -Work { param($P) Get-PDStorageAnalysis } -OnDone { param($r) if ($r) { Show-Storage $r } }
}

function Invoke-NewPartition {
    if (-not $script:Storage) { Say 'आधी "C: drive तपासा" दाबा.'; return }
    $gb = 0
    if (-not [double]::TryParse($ui.NewPartSize.Text, [ref]$gb) -or $gb -lt 10) { Say 'Size (GB) मध्ये 10 किंवा जास्त आकडा टाका.' 'Warning'; return }
    $msg = "C: drive मधून $gb GB काढून नवीन 'DATA' drive बनवायचा?`n`n• Data delete होत नाही.`n• तरीही power जाणे / disk खराब असणे धोक्याचे - आधी backup घ्या.`n• Laptop charging ला लावा."
    if (-not (Ask $msg 'Partition - लक्ष द्या')) { return }
    Start-PDJob -Title 'नवीन DATA drive' -Work { param($P) $l = New-PDDataPartition -SizeGB $P.GB; [pscustomobject]@{ Letter = $l; A = (Get-PDStorageAnalysis) } } -Params @{ GB = $gb } -OnDone {
        param($r)
        if ($r.Letter) { [void]$script:Actions.Add("नवीन DATA drive $($r.Letter): बनवला"); Show-Storage $r.A; Say "नवीन drive $($r.Letter): तयार. आता files हलवता येतील." }
    }
}

function Invoke-MoveFolders {
    if (-not $script:Storage) { Say 'आधी "C: drive तपासा" दाबा.'; return }
    $t = Get-SelectedTarget
    if (-not $t) { Say 'Files हलवण्यासाठी दुसरा drive नाही. आधी "नवीन DATA drive बनवा".' 'Warning'; return }
    $all = @($script:Storage.UserFolders) + @($script:Storage.RootFolders)
    $sel = @(foreach ($r in $ui.FolderList.ItemsSource) { if ($r.Selected) { $all[$r.Index] } })
    $sel = @($sel | Where-Object { $_.OnSystem -and -not $_.OneDrive })
    if (-not $sel.Count) { Say 'काहीही निवडलेले नाही.'; return }
    $need = ($sel | Measure-Object SizeBytes -Sum).Sum
    if ($need -gt ($t.FreeBytes - 2GB)) { Say ("{0}: वर पुरेशी जागा नाही. लागेल {1}, आहे {2}." -f $t.Letter, (Format-PDSize $need), (Format-PDSize $t.FreeBytes)) 'Warning'; return }
    $msg = "{0} ({1}) {2}: drive वर हलवायचे?`n`n{3}`n`nहलवताना उघडे programs (Word, browser downloads) बंद करा." -f $sel.Count, (Format-PDSize $need), $t.Letter, (($sel | ForEach-Object { '• ' + $_.Path }) -join "`n")
    if (-not (Ask $msg)) { return }
    $known = @($sel | Where-Object { $_.Kind -eq 'Known' } | ForEach-Object { $_.Name })
    $roots = @($sel | Where-Object { $_.Kind -eq 'Root' } | ForEach-Object { $_.Path })
    Start-PDJob -Title 'Files हलवणे' -Work {
        param($P)
        $rep = @()
        if ($P.Known.Count) { $rep += Move-PDUserFolders -Names $P.Known -TargetDrive $P.Drive }
        if ($P.Roots.Count) { $rep += Move-PDRootFolders -Paths $P.Roots -TargetDrive $P.Drive }
        [pscustomobject]@{ Report = $rep; A = (Get-PDStorageAnalysis) }
    } -Params @{ Known = $known; Roots = $roots; Drive = $t.Letter } -OnDone {
        param($r)
        foreach ($x in $r.Report) { [void]$script:Actions.Add($x) }
        Show-Storage $r.A
        Say ("पूर्ण:`n`n" + ($r.Report -join "`n"))
    }
}

function Invoke-Advisor {
    if (-not $script:Scan) {
        Start-PDJob -Title 'Scan + सल्ला' -Work { param($P) $s = Invoke-PDScan -DataDir $P.DataDir; [pscustomobject]@{ Scan = $s; Adv = (Get-PDOSAdvice -Info $s.Info -DataDir $P.DataDir) } } -Params @{ DataDir = $DataDir } -OnDone { param($r) Show-Scan $r.Scan; Show-Advice $r.Adv; Show-Page 'advisor' }
    } else {
        Show-Advice (Get-PDOSAdvice -Info $script:Scan.Info -DataDir $DataDir)
    }
}

function Invoke-AppUninstall([int]$k) {
    $a = $script:Scan.AppAdvice[$k]
    if (-not $a) { return }
    if (-not (Ask "'$($a.App)' uninstall करायचे? त्याचा uninstaller उघडेल.")) { return }
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
        'bsod'      { Open-UsbTool $null 'bluescreenview' }
        'backup'    { Say "Disk खराब होत आहे. लगेच:`n1. महत्त्वाचे files external disk / pendrive वर copy करा.`n2. पूर्ण disk साठी USB वरून boot करून Rescuezilla / Clonezilla वापरा.`n3. Toolbox > CrystalDiskInfo ने health पहा." 'Warning' }
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
            'web'     { if ($arg) { Start-Process $arg } }
            'report'  { Invoke-Report }
            'open'    { Start-Process explorer.exe $global:PDCtx.ReportDir }
        }
    } catch { Say ("त्रुटी: " + $_.Exception.Message) 'Warning' }
})

$win.Add_Closing({
    param($s, $e)
    if ($script:Job) {
        if (-not (Ask 'एक काम अजून चालू आहे. मध्येच बंद केल्यास अपूर्ण राहील. तरी बंद करायचे?')) { $e.Cancel = $true; return }
        try { $script:Job.PS.Stop() } catch { }
    }
    $timer.Stop()
})

$ui.AdminText.Text = "Administrator ✓`nReports: $($global:PDCtx.ReportDir)"
if (-not (Test-PDSameUserAsDesktop)) {
    $win.Add_ContentRendered({ Say "लक्ष द्या: PC Doctor दुसऱ्या (admin) account ने चालू आहे. Startup, visual effects आणि folders चे बदल त्या admin account ला लागतील, या user ला नाही.`n`nयोग्य मार्ग: ज्या user चा PC आहे त्यालाच admin बनवून / त्याच्या login मधून चालवा." 'Warning' })
}
Show-Page 'dashboard'
$timer.Start()
Write-PDLog "PC Doctor सुरू - USB: $UsbRoot" 'INFO'
[void]$win.ShowDialog()
