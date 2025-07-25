#Requires -RunAsAdministrator
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Stop'
$currentDrive = ($PWD.Path -split '\\')[0]
<#
.SYNOPSIS
A PowerShell script with a GUI to select and silently install applications from a predefined list. (Static Background Fix v5 - Remove Scroll Sleep - Maximized Start Fix - Prevent Restore Drag - Added Preset ComboBox)

.DESCRIPTION
Attempts to achieve a static form background with transparent scrolling panels on top.
Removed Start-Sleep from scroll event handlers to potentially improve scroll animation smoothness.
Modified to start maximized and prevent resizing or restoring via title bar drag.
Added a ComboBox for selecting predefined application sets (Browsers, Essentials).

.NOTES
Author: AI Assistant based on user request (Prevent Restore Drag + ComboBox)
Date:   2025-04-19
Requires: PowerShell 5.1+, .NET Framework, Administrator privileges, Application Icons at specified paths.
Limitations: See previous notes. Scrolling performance might still vary. Essential apps list is predefined.
#>

# Determine current drive (less reliable than $PSScriptRoot used later)
# $currentDrive = ($PWD.Path -split '\\')[0] # This line seems less relevant now as $scriptDrive is used later
# $env:Path += ";${currentDrive}\Programs Files\chocolatey\bin\Winget\AppInstaller_x64_stub" # Be cautious modifying system Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- دالة معالجة المعرف ---
function Get-ValidationCode {
    param (
        [string]$InputString
    )
    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return $null
    }
    try {
        $processor = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
        $processedBytes = $processor.ComputeHash($bytes)
        return [BitConverter]::ToString($processedBytes) -replace '-'
    } catch {
        return $null
    }
}

# --- START: تحديد حرف القرص بناءً على مسار العمل الحالي (PWD) ---
# !!! تحذير: هذه الطريقة تعتمد على أن السكربت يتم تشغيله من داخل مجلده !!!
# !!! قد لا تكون دقيقة إذا تم تشغيل السكربت من مسار مختلف !!!
try {
    # الحصول على مسار العمل الحالي وتقسيمه للحصول على حرف القرص
    $scriptDrive = ($PWD.Path -split '\\' | Select-Object -First 1)
} catch {
    # معالجة أي خطأ محتمل أثناء الحصول على المسار أو تقسيمه
     [System.Windows.Forms.MessageBox]::Show("لا يمكن تحديد مسار العمل الحالي.", "خطأ فادح", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
     exit
}

# التحقق إذا تم الحصول على حرف القرص بنجاح
if ([string]::IsNullOrWhiteSpace($scriptDrive)) {
    [System.Windows.Forms.MessageBox]::Show("فشل تحديد حرف القرص من مسار العمل الحالي.", "خطأ فادح", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# التأكد من وجود النقطتين ":" بعد حرف القرص
if ($scriptDrive -notlike "*:") { $scriptDrive += ":" }
# Write-Host "DEBUG: Determined Script Drive (from PWD): $scriptDrive" # Optional debug output
# --- END: تحديد حرف القرص بناءً على مسار العمل الحالي (PWD) ---


# --- تحقق من تنسيق حرف القرص ---
if ($scriptDrive -notmatch '^[A-Za-z]:$') {
    [System.Windows.Forms.MessageBox]::Show("لا يمكن تحديد قرص تشغيل صالح للسكربت ('$scriptDrive').", "خطأ فادح", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# --- البحث عن المعرف التسلسلي للقرص الحالي ---
$currentIdentifier = $null
$isTargetDrive = $false
try {
    $logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '$scriptDrive'" -ErrorAction Stop
    if ($null -eq $logicalDisk) { throw "لم يتم العثور على القرص المنطقي '$scriptDrive'."}

    $partition = Get-CimInstance -Query "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='$($logicalDisk.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" -ErrorAction Stop
    if ($null -eq $partition -or $partition.Count -eq 0) { throw "لم يتم العثور على أقسام للقرص المنطقي '$scriptDrive'."}

    # Using modern commands first
    $diskNumber = $null
    $targetDisk = $null
    try {
       $diskNumber = (Get-Partition -PartitionNumber $partition[0].Index -ErrorAction SilentlyContinue).DiskNumber
       if ($null -ne $diskNumber) {
           $targetDisk = Get-Disk -Number $diskNumber -ErrorAction SilentlyContinue | Where-Object {$_.Bustype -eq "USB"}
       }
    } catch {} # Ignore errors from modern commands

    # WMI Fallback
    if ($null -eq $targetDisk) {
        $diskDriveWmi = Get-CimInstance -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($partition[0].DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition" -ErrorAction SilentlyContinue
        if ($null -ne $diskDriveWmi) {
            $targetDisk = $diskDriveWmi | Where-Object { $_.InterfaceType -eq "USB" } | Select-Object -First 1
        }
    }

    # Get Serial number
    if ($null -ne $targetDisk) {
         if ($targetDisk.PSObject.TypeNames -contains 'Microsoft.Management.Infrastructure.CimInstance#ROOT/Microsoft/Windows/Storage/MSFT_Disk') {
             $currentIdentifier = $targetDisk.SerialNumber.Trim()
         } elseif ($targetDisk.PSObject.TypeNames -contains 'Microsoft.Management.Infrastructure.CimInstance#ROOT/cimv2/Win32_DiskDrive') {
             $currentIdentifier = $targetDisk.SerialNumber.Trim()
         }
         $isTargetDrive = $true
    } else {
        $isTargetDrive = $false
    }

} catch {
     $isTargetDrive = $false
     # Write-Warning "Error getting device info for '$scriptDrive': $($_.Exception.Message)"
}

# --- تحديد مسار ملف البيانات ---
$dataPath = Join-Path -Path $scriptDrive -ChildPath "indexes\pakage"
$dataFileName = "aGlkZGVuX2ZpbGUudHh0.bin"
$dataFilePath = Join-Path -Path $dataPath -ChildPath $dataFileName

# --- إجراء التحقق اللازم ---
$showErrorWindow = $true

if ($isTargetDrive -and (-not [string]::IsNullOrWhiteSpace($currentIdentifier)) -and (Test-Path $dataFilePath -PathType Leaf)) {
    try {
        $storedCode = (Get-Content $dataFilePath -TotalCount 1).Trim()
        $currentCode = Get-ValidationCode -InputString $currentIdentifier

        if ((-not [string]::IsNullOrWhiteSpace($storedCode)) -and ($null -ne $currentCode) -and ($storedCode -eq $currentCode)) {
            $showErrorWindow = $false
        }
    } catch {
        # Error during verification
    }
}

# --- إظهار نافذة الخطأ أو السماح للسكربت بالاستمرار ---
if ($showErrorWindow) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "خطأ في التشغيل"
    $form.Size = New-Object System.Drawing.Size(450, 250)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "لا يمكن تشغيل التطبيق من هذا الموقع أو الجهاز." + "`n" + "يرجى المحاولة من المصدر المعتمد."
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $label.AutoSize = $false
    $label.Size = New-Object System.Drawing.Size(410, 100)
    $label.Location = New-Object System.Drawing.Point(20, 30)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($label)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = "موافق"
    $button.Size = New-Object System.Drawing.Size(100, 35)
    $button.Location = New-Object System.Drawing.Point(175, 150)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,80,80)
    $button.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $button.Add_Click({ $form.Close() })
    $form.Controls.Add($button)

    $form.ShowDialog() | Out-Null
    exit
}


# الكود الرئيسي للسكربت يأتي هنا إذا نجح التحقق
# ...

# --- Load Required Assemblies FIRST ---
try {
    Write-Host "Attempting to load required .NET assemblies..."
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Add-Type -AssemblyName System.Design -ErrorAction Stop
    Write-Host "Successfully loaded System.Windows.Forms, System.Drawing, System.Design." -ForegroundColor Green
} catch {
    Write-Error "FATAL: Failed to load required .NET GUI assemblies. Cannot continue. Error: $($_.Exception.Message)"
    Read-Host "Press Enter to exit"; exit 1
}

if (-not ([System.Management.Automation.PSTypeName]'System.Drawing.Color').Type) {
    Write-Error "FATAL: The type [System.Drawing.Color] is still not available after Add-Type."
    Read-Host "Press Enter to exit"; exit 1
} else {
    Write-Host "Confirmed [System.Drawing.Color] type is available." -ForegroundColor Green
}

# --- Configuration ---
$installersBasePath = "${currentDrive}\Programs Files\APPS"
$iconsBasePath = "${currentDrive}\الأدوات\source\icons"
$backgroundImagePath = "${currentDrive}\الأدوات\source\Wallpaper.jpg"
Write-Host "DEBUG: iconsBasePath is set to '$iconsBasePath'" -ForegroundColor Yellow

# --- Define Colors ---
$bgColor = [System.Drawing.Color]::FromArgb(45, 45, 48) # Fallback Background ONLY
$fgColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$panelColor = [System.Drawing.Color]::FromArgb(60, 60, 63) # Bottom Panel
$textBoxBgColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$textBoxFgColor = $fgColor
$progressBgColor = $panelColor
$progressFgColor = [System.Drawing.Color]::FromArgb(0, 122, 204) # Checked Box Fill
$checkBoxUncheckedBackColor = [System.Drawing.Color]::FromArgb(50, 80, 80, 80) # Semi-transparent dark gray for unchecked box fill
$groupBoxTitleColor = [System.Drawing.Color]::White
$buttonFgColor = $fgColor
$buttonHoverBgOverlay = [System.Drawing.Color]::FromArgb(40, 200, 200, 200)
$buttonDownBgOverlay = [System.Drawing.Color]::FromArgb(70, 180, 180, 180)
$comboBoxBorderColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$textMargin = 3


# --- Define Applications and their Installers / Icons ---
# !! تأكد من أن مسارات IconPath هنا تطابق الملفات الموجودة فعلياً !!
$AppInstallers = @{
    # --- Left Column Categories ---
    "7-Zip (x64) - برنامج فك الضغط" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\7z2409-x64.exe"; IconPath = "$iconsBasePath\7zip.ico" }; # Archiving
    "WinRAR (x64) - برنامج فك الضغط" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\winrar-x64-711 (1).exe"; IconPath = "$iconsBasePath\winrar.ico" }; # Archiving
    "UltraISO - برنامج تعديل ملفات ISO" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\uiso9_pe.exe"; IconPath = "$iconsBasePath\ultraiso.ico" }; # Archiving
    "Blender (x64) - بلينددر" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\blender-4.4.0-windows-x64.msi"; IconPath = "$iconsBasePath\blender.png" }; # Design/Graphics
    "GIMP - كيمب" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\gimp-3.0.2-setup-1.exe"; IconPath = "$iconsBasePath\gimp.ico" }; # Design/Graphics
    "Inkscape (x64) - نسكيب" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\inkscape-1.4_2024-10-11_86a8ad7-x64.msi"; IconPath = "$iconsBasePath\inkscape.png" }; # Design/Graphics
    "Shotcut (x64) - شوركوت" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\shotcut-win64-250329.exe"; IconPath = "$iconsBasePath\shotcut.png" }; # Design/Graphics
    "Any Video Converter Free - محول ضيغ فيديوهات" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\avc-free.exe"; IconPath = "$iconsBasePath\anyvideoconverter.png" }; # Design/Graphics
    "Audacity - اوداسيتي" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\audacity-win-3.7.3-64bit.exe"; IconPath = "$iconsBasePath\audacity.png" }; # Design/Graphics
    "Office Arabic 2013 - أوفيس عربي" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\2013\Office ProPlus Arabic.bat"; IconPath = "$iconsBasePath\office.png" }; # Office/Productivity
    "Office English 2013 - اوفيس انكليزي" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\2013\Office ProPlus English.bat"; IconPath = "$iconsBasePath\office.png" }; # Office/Productivity
    "Office Arabic 2010 - اوفيس عربي"= [PSCustomObject]@{ InstallerPath = "$installersBasePath\2010\Office ProPlus Arabic.exe"; IconPath = "$iconsBasePath\office.png" }; # Office/Productivity
    "Office English 2010 - اوفيس انكليزي"= [PSCustomObject]@{ InstallerPath = "$installersBasePath\2010\Office ProPlus English.exe"; IconPath = "$iconsBasePath\office.png" }; # Office/Productivity
    "Notepad++ (x64) - نوت باد بلس" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\npp.8.7.9.Installer.x64.exe"; IconPath = "$iconsBasePath\notepadplusplus.ico" }; # Office/Productivity
    "Foxit PDF Reader - فوكسيت " = [PSCustomObject]@{ InstallerPath = "$installersBasePath\FoxitPDFReader20244_enu_Setup_Prom.exe"; IconPath = "$iconsBasePath\foxitreader.png" }; # Office/Productivity
    "Adobe Reader - ادوبي ريدر" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\Reader_en_install.exe"; IconPath = "$iconsBasePath\adobereader.png" }; # Office/Productivity
    "VLC Media Player (x64) - برنامج تشغيل وسائط" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\vlc-3.0.21-win64.exe"; IconPath = "$iconsBasePath\vlc.ico" }; # Media
    "K-Lite Codec Pack Full - تعريفات الأنكودرات" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\K-Lite_Codec_Pack_1885_Full.exe"; IconPath = "$iconsBasePath\klite.png" }; # Media
    "PotPlayer (x64) - برنامج تشغيل وسائط" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\PotPlayerSetup64.exe"; IconPath = "$iconsBasePath\potplayer.png" }; # Media
    "Steam - ستيم" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\SteamSetup.exe"; IconPath = "$iconsBasePath\steam.ico" }; # Gaming
    "GameLoop - محاكي أندرويد" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\GLP_installer_900223086_market.exe"; IconPath = "$iconsBasePath\gameloop.ico" }; # Gaming
    # --- Right Column Categories ---
    "Google Chrome (x64) - كروم" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\ChromeStandaloneSetup64.exe"; IconPath = "F:\الأدوات\source\icons\Chrome.png" }; # Browsers
    "Mozilla Firefox - فايرفوكس" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\Firefox Installer.exe"; IconPath = "$iconsBasePath\firefox.ico" }; # Browsers
    "Opera - اوبيرا" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\OperaSetup.exe"; IconPath = "$iconsBasePath\opera.ico" }; # Browsers
    "Ant Download Manager (x64) - داونلود مانجر نسخة مجانية" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\AntDM-x64.2.15.3-setup.exe"; IconPath = "$iconsBasePath\antdm.png" }; # Downloaders
    "Free Download Manager (x64) - فري داونلود مانجر" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\fdm_x64_setup.exe"; IconPath = "$iconsBasePath\freedownloadmanager.ico" }; # Downloaders
    "Internet Download Manager (IDM) - داونلود مانجر الأصلي" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\idman642build32.exe"; IconPath = "$iconsBasePath\idm.ico" }; # Downloaders
    "uTorrent - تورنت" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\utorrent_installer.exe"; IconPath = "$iconsBasePath\utorrent.ico" }; # Downloaders
    "AnyDesk - انيديسك" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\AnyDesk.exe"; IconPath = "$iconsBasePath\anydesk.ico" }; # Communication/Remote
    "Cloudflare WARP - كلاودفلير" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\Cloudflare_WARP_2025.2.600.0.msi"; IconPath = "$iconsBasePath\cloudflarewarp.png" }; # Communication/Remote
    "Discord - ديسكورد" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\DiscordSetup.exe"; IconPath = "$iconsBasePath\discord.ico" }; # Communication/Remote
    "Dropbox - دروبوكس" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\DropboxInstaller.exe"; IconPath = "$iconsBasePath\dropbox.ico" }; # Communication/Remote
    "Google Drive - كوكل درايف" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\GoogleDriveSetup.exe"; IconPath = "$iconsBasePath\googledrive.ico" }; # Communication/Remote
    "Messenger - ماسنجر" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\messenger-2250-1-0-0.appxbundle"; IconPath = "$iconsBasePath\messenger.png" }; # Communication/Remote
    "NitroShare (x64) - نايترو شير" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\nitroshare-0.3.4-windows-x86_64.exe"; IconPath = "$iconsBasePath\nitroshare.png" }; # Communication/Remote
    "Skype (Desktop) - سكايب" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\skype-8-138-0-214.exe"; IconPath = "$iconsBasePath\skype.ico" }; # Communication/Remote
    "Supremo - سوبريمو" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\Supremo.exe"; IconPath = "$iconsBasePath\supremo.png" }; # Communication/Remote
    "TeamViewer (x64) - تيم فيور" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\TeamViewer_Setup_x64.exe"; IconPath = "$iconsBasePath\teamviewer.ico" }; # Communication/Remote
    "Telegram Desktop (x64) - تيليكرام" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\tsetup-x64.5.13.1.exe"; IconPath = "$iconsBasePath\telegram.ico" }; # Communication/Remote
    "Viber - فايبر" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\ViberSetup.exe"; IconPath = "$iconsBasePath\viber.ico" }; # Communication/Remote
    "Zoom - زووم" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\ZoomInstallerFull.exe"; IconPath = "$iconsBasePath\zoom.ico" }; # Communication/Remote
    "Java Runtime Environment 8 (x64) - جافا" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\jre-8u441-windows-x64.exe"; IconPath = "$iconsBasePath\java.png" }; # System/Runtimes
    "VC++ Redist 1 (x64) - تعريفات C++" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\vcredist_x64.exe"; IconPath = "$iconsBasePath\vcredist.png" }; # System/Runtimes
    "VC++ Redist 2 (x64)  تعريفات C++" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\vcredist_x64 (1).exe"; IconPath = "$iconsBasePath\vcredist.png" }; # System/Runtimes
    "VC++ Redist 3 (x64) - تعريفات C++" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\vcredist_x64 (2).exe"; IconPath = "$iconsBasePath\vcredist.png" }; # System/Runtimes
    "VC++ Redist 4 (x64) - تعريفات C++" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\VC_redist.x64 (2).exe"; IconPath = "$iconsBasePath\vcredist.png" }; # System/Runtimes
    "VC++ Redist 5 (x64) - تعريفات C++" = [PSCustomObject]@{ InstallerPath = "$installersBasePath\vcredist_x64 (3).exe"; IconPath = "$iconsBasePath\vcredist.png" }; # System/Runtimes
}

# Define Categories and which column they belong to
$CategoriesLayout = @{ "Archiving Tools - أدوات الأرشفة" = 0; "Design and Graphics Tools - ادوات التصميم و الجرافيكس" = 0; "Office & Productivity - الأوفيس" = 0; "Media Players & Codecs - الأنكودرات و الوسائط" = 0; "Gaming - جيمنج" = 0; "Internet Tools - Browsers - المتصفحات" = 1; "Internet Tools - Download Managers - برامج التحميل" = 1; "Internet Tools - Communication & Remote - ادوات التحكم" = 1; "System & Runtimes - تعريفات النظام" = 1; "Security Related - ادوات الحماية" = 1 }

# --- GUI Setup ---
$methodSetStyle = [System.Windows.Forms.Control].GetMethod('SetStyle', [System.Reflection.BindingFlags]'NonPublic,Instance'); if ($null -eq $methodSetStyle) { Write-Error "Could not get SetStyle method via reflection."; exit 1 }
$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 1000
$script:estimatedEndTime = $null; $script:currentAppNameForTimer = ""; $script:currentAppNumForTimer = 0; $script:totalAppsForTimer = 0
$Script:iconSize = New-Object System.Drawing.Size(20, 20); $Script:iconMargin = 4

# Main Form
$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = "Install Center"; $mainForm.Icon = "${currentDrive}\الأدوات\source\Install-Center.ico"
# $mainForm.Size = New-Object System.Drawing.Size(850, 750); # حجم النافذة العادي - معطل
$mainForm.StartPosition = 'CenterScreen';
# $mainForm.MinimumSize = New-Object System.Drawing.Size(650, 600) # الحد الأدنى للحجم - معطل لأنه سيتم تكبيرها
# --- بداية التعديل: فتح النافذة مكبرة وتعطيل التصغير/التكبير ---
$mainForm.WindowState = [System.Windows.Forms.FormWindowState]::Maximized # فتح النافذة بشكل موسع
$mainForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle # جعل الإطار ثابتاً (لا يمكن تغيير الحجم بالسحب)
$mainForm.MaximizeBox = $false # تعطيل زر التكبير (لأنه موسع بالفعل)
$mainForm.MinimizeBox = $false # تعطيل زر التصغير (إذا أردت السماح بالتصغير، اجعلها $true أو احذف السطر)
# --- نهاية التعديل ---
try { $propInfoFormDoubleBuffered = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance'); $propInfoFormDoubleBuffered.SetValue($mainForm, $true, $null); Write-Host "Enabled double buffering on main form via reflection." -ForegroundColor Green } catch { Write-Warning "Could not enable double buffering on main form via reflection: $($_.Exception.Message)" }
if ($backgroundImagePath -ne $null -and (Test-Path $backgroundImagePath -PathType Leaf)) { try { $mainForm.BackgroundImage = [System.Drawing.Image]::FromFile($backgroundImagePath); $mainForm.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Stretch; Write-Host "Successfully loaded background image: $backgroundImagePath" -ForegroundColor Green } catch { Write-Warning "Failed to load background image '$backgroundImagePath': $($_.Exception.Message). Using fallback background color."; $mainForm.BackColor = $bgColor } } else { Write-Warning "Background image path not set or file not found: '$backgroundImagePath'. Using fallback background color."; $mainForm.BackColor = $bgColor }
$doubleBufferProperty = $mainForm.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags] "Instance, NonPublic"); if ($doubleBufferProperty) { $doubleBufferProperty.SetValue($mainForm, $true, $null) }

# --- بداية التعديل الجديد: منع استعادة النافذة عند سحب شريط العنوان ---
# Add a handler for the Resize event to force the window back to Maximized
# if the user tries to restore it down (e.g., by dragging the title bar).
$mainForm.Add_Resize({
    param($sender, $e)
    # $sender refers to the form ($mainForm)
    if ($sender.WindowState -ne [System.Windows.Forms.FormWindowState]::Maximized) {
        # If the window state changed from Maximized, force it back immediately.
        # This prevents the user from restoring the window by dragging the title bar.
        $sender.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    }
})
# --- نهاية التعديل الجديد ---

# $mainForm.add_ResizeBegin({ $mainForm.SuspendLayout() }); # لم يعد ضرورياً لأن تغيير الحجم معطل
# $mainForm.add_ResizeEnd({ $mainForm.ResumeLayout($true) }) # لم يعد ضرورياً لأن تغيير الحجم معطل

# --- Recursive double buffering function ---
function Enable-DoubleBufferingRecursively($control) { try { $prop = $control.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags] "Instance, NonPublic"); if ($prop) { $prop.SetValue($control, $true, $null) }; foreach ($child in $control.Controls) { Enable-DoubleBufferingRecursively $child } } catch { } }
Enable-DoubleBufferingRecursively $mainForm

# --- Bottom Panel, Progress Panel, Status Label, Progress Bar, Output Text Box ---
$buttonPanel = New-Object System.Windows.Forms.Panel; $buttonPanel.Height = 180; $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom; $buttonPanel.BackColor = $panelColor; $mainForm.Controls.Add($buttonPanel)
$progressPanel = New-Object System.Windows.Forms.Panel; $progressPanel.Location = New-Object System.Drawing.Point(10, 45); $progressPanelWidth = $buttonPanel.ClientSize.Width - 20; $progressPanelHeight = 50; $progressPanel.Size = New-Object System.Drawing.Size($progressPanelWidth, $progressPanelHeight); $progressPanel.Anchor = ('Top', 'Left', 'Right'); $progressPanel.Visible = $false; $progressPanel.BackColor = [System.Drawing.Color]::Transparent; $buttonPanel.Controls.Add($progressPanel)
$statusLabel = New-Object System.Windows.Forms.Label; $statusLabel.ForeColor = $fgColor; $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9); $statusLabel.Location = New-Object System.Drawing.Point(0, 5); $statusLabel.AutoSize = $false; $statusLabel.Size = New-Object System.Drawing.Size($progressPanel.ClientSize.Width, 20); $statusLabel.Anchor = ('Top', 'Left', 'Right'); $statusLabel.Text = "Status: Idle"; $statusLabel.BackColor = [System.Drawing.Color]::Transparent; $progressPanel.Controls.Add($statusLabel)
$progressBar = New-Object System.Windows.Forms.ProgressBar; $progressBar.Location = New-Object System.Drawing.Point(0, 25); $progressBar.Size = New-Object System.Drawing.Size($progressPanel.ClientSize.Width, 15); $progressBar.Anchor = ('Top', 'Left', 'Right'); $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous; $progressBar.BackColor = $progressBgColor; $progressBar.ForeColor = $progressFgColor; $progressPanel.Controls.Add($progressBar)
$outputTextBox = New-Object System.Windows.Forms.RichTextBox; $outputTextBox.Multiline = $true; $outputTextBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical; $outputTextBox.ReadOnly = $true; $outputTextBox.Font = New-Object System.Drawing.Font("Consolas", 9); $outputTextBox.BackColor = $textBoxBgColor; $outputTextBox.ForeColor = $textBoxFgColor; [int]$outputTextBoxY = $progressPanel.Location.Y + $progressPanel.Height + 5; $outputTextBox.Location = New-Object System.Drawing.Point(10, $outputTextBoxY); $outputTextBox.Height = $buttonPanel.ClientSize.Height - $outputTextBox.Location.Y - 10; $outputTextBox.Width = $buttonPanel.ClientSize.Width - 20; $outputTextBox.Anchor = ('Top', 'Bottom', 'Left', 'Right'); $buttonPanel.Controls.Add($outputTextBox)


# --- Helper Function to Style Buttons ---
Function Style-TransparentButton($button) {
    $button.BackColor = [System.Drawing.Color]::Transparent
    $button.ForeColor = $script:buttonFgColor
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.Padding = New-Object System.Windows.Forms.Padding(5, 2, 5, 2)
    $button.FlatAppearance.MouseOverBackColor = $script:buttonHoverBgOverlay
    $button.FlatAppearance.MouseDownBackColor = $script:buttonDownBgOverlay
    $button.Tag = $button.ForeColor # Store original color
    # Fix hover color persistence
    $button.add_MouseEnter({ $this.ForeColor = $script:buttonFgColor }) # Ensure hover color is standard
    $button.add_MouseLeave({ if($this.Tag -is [System.Drawing.Color]){ $this.ForeColor = $this.Tag } else { $this.ForeColor = $script:buttonFgColor } })
}

# --- Script-level variables ---
$AllCheckBoxes = [System.Collections.Generic.List[System.Windows.Forms.CheckBox]]::new()
$Script:currentY_Left = 5; $Script:currentY_Right = 5

# Buttons and ComboBox
$buttonFont = New-Object System.Drawing.Font("Roboto", 14, [System.Drawing.FontStyle]::Regular) # Define font once

$selectAllButton = New-Object System.Windows.Forms.Button; $selectAllButton.Text = 'Select All'; $selectAllButton.Size = New-Object System.Drawing.Size(100, 30); $selectAllButton.Location = New-Object System.Drawing.Point(10, 10); $selectAllButton.Anchor = ('Top', 'Left'); Style-TransparentButton $selectAllButton; $selectAllButton.Font = $buttonFont; $buttonPanel.Controls.Add($selectAllButton)
$deselectAllButton = New-Object System.Windows.Forms.Button; $deselectAllButton.Text = 'Deselect All'; $deselectAllButton.Size = New-Object System.Drawing.Size(100, 30); $deselectAllButton.Location = New-Object System.Drawing.Point(120, 10); $deselectAllButton.Anchor = ('Top', 'Left'); Style-TransparentButton $deselectAllButton; $deselectAllButton.Font = $buttonFont; $buttonPanel.Controls.Add($deselectAllButton)

# --- START: Add ComboBox ---
$presetsComboBox = New-Object System.Windows.Forms.ComboBox
$presetsComboBox.Name = 'presetsComboBox'
$presetsComboBox.Size = New-Object System.Drawing.Size(160, 30) # Adjust size as needed
$presetsComboBox.Location = New-Object System.Drawing.Point(230, 10) # Position after Deselect All
$presetsComboBox.Anchor = ('Top', 'Left')
$presetsComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList # Prevent typing
$presetsComboBox.Font = $buttonFont # Use same font
$presetsComboBox.BackColor = $textBoxBgColor # Use textbox background
$presetsComboBox.ForeColor = $textBoxFgColor # Use textbox foreground
$presetsComboBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat # Flat style to match buttons

# Add items to ComboBox
$presetsComboBox.Items.Add("Select Preset...") # Placeholder text
$presetsComboBox.Items.Add("المتصفحات") # Browsers
$presetsComboBox.Items.Add("الأساسية") # Essential
$presetsComboBox.SelectedIndex = 0 # Default to placeholder

# Add event handler for selection change
$presetsComboBox.Add_SelectedIndexChanged({
    param($sender, $e)
    $selectedPreset = $sender.SelectedItem.ToString()
    if ($selectedPreset -eq "Select Preset...") { return } # Do nothing for placeholder

    # Define app lists for presets
    $browserApps = @(
        "Google Chrome (x64) - كروم",
        "Mozilla Firefox - فايرفوكس",
        "Opera - اوبيرا"
    )
    $essentialApps = @(
        "7-Zip (x64) - برنامج فك الضغط",
        "VLC Media Player (x64) - برنامج تشغيل وسائط",
        "Foxit PDF Reader - فوكسيت ",
        "Google Chrome (x64) - كروم",
        "K-Lite Codec Pack Full - تعريفات الأنكودرات",
        "VC++ Redist 1 (x64) - تعريفات C++" # Example essential runtime
        # Add more essential apps by their exact name from $AppInstallers here if needed
    )

    $appsToSelect = @()
    switch ($selectedPreset) {
        "المتصفحات" { $appsToSelect = $browserApps }
        "الأساسية"  { $appsToSelect = $essentialApps }
    }

    # Loop through all checkboxes and check the ones in the selected list
    $Script:AllCheckBoxes | ForEach-Object {
        if ($appsToSelect -contains $_.Text) {
            if (-not $_.Checked) {
                $_.Checked = $true
                # No need to Invalidate here, CheckedChanged event already does that
            }
        }
        # Optional: Deselect others? Current logic only adds checks.
        # else {
        #     if ($_.Checked) { $_.Checked = $false }
        # }
    }
    # Reset ComboBox to placeholder after selection (optional)
    # $sender.SelectedIndex = 0
})

$buttonPanel.Controls.Add($presetsComboBox)
# --- END: Add ComboBox ---


$installButton = New-Object System.Windows.Forms.Button; $installButton.Text = 'Start Installation'; $installButton.Size = New-Object System.Drawing.Size(130, 30); $installButton.Anchor = ('Top', 'Right'); [int]$installButtonX = $buttonPanel.ClientSize.Width - $installButton.Width - 10; $installButton.Location = New-Object System.Drawing.Point($installButtonX, 10); Style-TransparentButton $installButton; $installButton.Font = $buttonFont; $buttonPanel.Controls.Add($installButton)


# --- Main Content Area & Scroll Panels (شفاف) ---
$mainTableLayoutPanel = New-Object System.Windows.Forms.TableLayoutPanel; $mainTableLayoutPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $mainTableLayoutPanel.BackColor = [System.Drawing.Color]::Transparent; $mainTableLayoutPanel.ColumnCount = 2; $mainTableLayoutPanel.RowCount = 1
$mainTableLayoutPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))); $mainTableLayoutPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$mainTableLayoutPanel.Padding = New-Object System.Windows.Forms.Padding(5); $mainTableLayoutPanel.AutoScroll = $false
$mainForm.Controls.Add($mainTableLayoutPanel); $mainForm.Controls.SetChildIndex($mainTableLayoutPanel, 0)
$leftPanel = New-Object System.Windows.Forms.Panel; $leftPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $leftPanel.BackColor = [System.Drawing.Color]::Transparent; $mainTableLayoutPanel.Controls.Add($leftPanel, 0, 0)
$rightPanel = New-Object System.Windows.Forms.Panel; $rightPanel.Dock = [System.Windows.Forms.DockStyle]::Fill; $rightPanel.BackColor = [System.Drawing.Color]::Transparent; $mainTableLayoutPanel.Controls.Add($rightPanel, 1, 0)
try { $propInfoDoubleBuffered = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance'); $propInfoDoubleBuffered.SetValue($leftPanel, $true, $null); $propInfoDoubleBuffered.SetValue($rightPanel, $true, $null); Write-Host "Enabled double buffering on scroll panels." -ForegroundColor Green } catch { Write-Warning "Could not set double buffering via reflection: $($_.Exception.Message)" }
try { $methodSetStyle.Invoke($leftPanel, @([System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer, $true)); $methodSetStyle.Invoke($rightPanel, @([System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer, $true)); Write-Host "Enabled OptimizedDoubleBuffer on scroll panels." -ForegroundColor Green } catch { Write-Warning "Could not enable OptimizedDoubleBuffer: $($_.Exception.Message)" }


# --- OWNER DRAW PAINT FUNCTION FOR CHECKBOXES (إزالة رسم الخلفية بالكامل) ---
Function CheckBox_Paint($sender, [System.Windows.Forms.PaintEventArgs]$e) {
    $checkBox = $sender -as [System.Windows.Forms.CheckBox]; if ($null -eq $checkBox) { return }
    $g = $e.Graphics; $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias; $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    # --- !! محذوف: قسم رسم الخلفية بالكامل !! ---
    # --- Define Sizes and Margins ---
    $iconImage = $null; $iconSize = $Script:iconSize; $iconMargin = $Script:iconMargin; $textMargin = $Script:textMargin
    if ($checkBox.Tag -is [PSCustomObject] -and $checkBox.Tag.PSObject.Properties.Name -contains 'IconImage') { $iconImage = $checkBox.Tag.IconImage }
    if ($iconImage -ne $null -and (-not $iconImage -is [System.Drawing.Image])) { $iconImage = $null } # Safety check
    # --- 1. Draw Checkbox FIRST ---
    $checkSize = 13; $checkX = 2; $checkY = ($checkBox.ClientSize.Height - $checkSize) / 2; $checkRect = [System.Drawing.Rectangle]::new($checkX, [int]$checkY, $checkSize, $checkSize)
    $boxState = [System.Windows.Forms.VisualStyles.CheckBoxState]::UncheckedNormal
    if ($checkBox.Checked) { $boxState = if ($checkBox.Enabled) { [System.Windows.Forms.VisualStyles.CheckBoxState]::CheckedNormal } else { [System.Windows.Forms.VisualStyles.CheckBoxState]::CheckedDisabled } } else { $boxState = if ($checkBox.Enabled) { [System.Windows.Forms.VisualStyles.CheckBoxState]::UncheckedNormal } else { [System.Windows.Forms.VisualStyles.CheckBoxState]::UncheckedDisabled } }
    $borderPen = $null
    try { $borderPen = New-Object System.Drawing.Pen($script:fgColor); if ($checkBox.Checked) { $checkedBrush = $null; try { $checkedBrush = New-Object System.Drawing.SolidBrush($script:progressFgColor); $g.FillRectangle($checkedBrush, $checkRect) } finally { if ($null -ne $checkedBrush) { $checkedBrush.Dispose() } }; $g.DrawRectangle($borderPen, $checkRect.X, $checkRect.Y, $checkRect.Width -1, $checkRect.Height -1); [System.Windows.Forms.ControlPaint]::DrawCheckBox($g, $checkRect, [System.Windows.Forms.ButtonState]::Checked) } else { $uncheckedBrush = $null; try { $uncheckedBrush = New-Object System.Drawing.SolidBrush($script:checkBoxUncheckedBackColor); $g.FillRectangle($uncheckedBrush, $checkRect) } finally { if ($null -ne $uncheckedBrush) { $uncheckedBrush.Dispose() } }; $g.DrawRectangle($borderPen, $checkRect.X, $checkRect.Y, $checkRect.Width -1, $checkRect.Height -1) } } finally { if ($null -ne $borderPen) { $borderPen.Dispose() } }
    # --- 2. Draw Icon SECOND (if it exists) ---
    $iconRect = [System.Drawing.Rectangle]::Empty; $currentItemRightEdge = $checkRect.Right
    if ($iconImage -ne $null) { $iconX = $checkRect.Right + $iconMargin; $iconY = ($checkBox.ClientSize.Height - $iconSize.Height) / 2; $iconRect = [System.Drawing.Rectangle]::new($iconX, [int]$iconY, $iconSize.Width, $iconSize.Height); try { $g.DrawImage($iconImage, $iconRect) } catch { Write-Error ("PAINT Event for '{0}': FAILED to draw icon! Error: {1}" -f $checkBox.Text, $_.Exception.ToString()) }; $currentItemRightEdge = $iconRect.Right } else { $currentItemRightEdge = $checkRect.Right } # Ensure edge is updated even without icon
    # --- 3. Draw Text THIRD ---
    $textX = $currentItemRightEdge + $textMargin; $textRect = [System.Drawing.Rectangle]::new($textX, 0, $checkBox.ClientSize.Width - $textX, $checkBox.ClientSize.Height)
    $textFlags = [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPadding;
    [System.Windows.Forms.TextRenderer]::DrawText($g, $checkBox.Text, $checkBox.Font, $textRect, $checkBox.ForeColor, ([System.Windows.Forms.TextFormatFlags]::Transparent -bor $textFlags));
    # --- 4. Draw Focus Rectangle ---
    if ($checkBox.Focused -and $checkBox.ShowFocusCues) { [System.Windows.Forms.ControlPaint]::DrawFocusRectangle($g, $checkBox.ClientRectangle) }
}


# --- Function to Create Checkboxes and GroupBoxes ---
Function Create-CategoryGroup($CategoryName, $ColumnIndex) {
    $parentPanel = if ($ColumnIndex -eq 0) { $leftPanel } else { $rightPanel }
    $currentY = if ($ColumnIndex -eq 0) { $Script:currentY_Left } else { $Script:currentY_Right }
    $groupBox = New-Object System.Windows.Forms.GroupBox; $groupBox.Text = $CategoryName; $groupBox.AutoSize = $false; $groupBox.Padding = New-Object System.Windows.Forms.Padding(8, 25, 8, 8); $groupBox.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold); $groupBox.ForeColor = $script:groupBoxTitleColor; $groupBox.BackColor = [System.Drawing.Color]::Transparent; $groupBox.Anchor = ('Top', 'Left', 'Right')
    $checkBoxY = $groupBox.Padding.Top; $checkBoxX = $groupBox.Padding.Left; $lastCheckBoxBottom = $checkBoxY
    $filterPattern = ''; $englishParts = $CategoryName -split ' - ' | Where-Object { $_ -notmatch '[\p{IsArabic}]' }; $categoryKeyPart = $englishParts -join ' - '; switch ($categoryKeyPart) { "Archiving Tools" { $filterPattern = '^(7-Zip|WinRAR|UltraISO).*' } "Design and Graphics Tools" { $filterPattern = '^(Blender|GIMP|Inkscape|Shotcut|Any Video Converter|Audacity).*' } "Office & Productivity" { $filterPattern = '^(Office|LibreOffice|WPS Office|FreeOffice|Notepad\+\+|Foxit PDF Reader|Adobe Reader).*' } "Media Players & Codecs" { $filterPattern = '^(VLC|K-Lite|PotPlayer).*' } "Gaming" { $filterPattern = '^(Steam|GameLoop).*' } "Internet Tools - Browsers" { $filterPattern = '^(Google Chrome|Mozilla Firefox|Opera).*' } "Internet Tools - Download Managers" { $filterPattern = '^(Ant Download|Free Download|Internet Download Manager|uTorrent).*' } "Internet Tools - Communication & Remote" { $filterPattern = '^(AnyDesk|Cloudflare WARP|Discord|Dropbox|Google Drive|Messenger|NitroShare|Skype|Supremo|TeamViewer|Telegram|Viber|WhatsApp|Zoom).*' } "System & Runtimes" { $filterPattern = '^(Java|VC\+\+ Redist).*' } "Security Related" { $filterPattern = '^(Microsoft Defender).*' } default { Write-Warning "Unhandled category key part '$categoryKeyPart' derived from category name '$CategoryName' in Create-CategoryGroup switch." } }
    $appNamesInCategory = @(); if ($filterPattern) { try { $appNamesInCategory = $AppInstallers.Keys | Where-Object { $_ -match $filterPattern } } catch { Write-Error "Regex error for category '$CategoryName' with pattern '$filterPattern': $($_.Exception.Message)" } }
    $sortedAppNames = $appNamesInCategory | Sort-Object; if ($sortedAppNames.Count -eq 0) { return $null }

    foreach ($appName in $sortedAppNames) {
        $appData = $AppInstallers[$appName]; if ($null -eq $appData -or -not ($appData -is [PSCustomObject])) { Write-Warning "Data structure error for '$appName'. Expected PSCustomObject."; continue }
        $installerPath = $appData.InstallerPath; $iconPath = $appData.IconPath
        $checkBox = New-Object System.Windows.Forms.CheckBox; $checkBox.Text = $appName; $checkBox.Location = New-Object System.Drawing.Point($checkBoxX, $checkBoxY); $checkBox.AutoSize = $true; $checkBox.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold); $checkBox.ForeColor = $fgColor; $checkBox.BackColor = [System.Drawing.Color]::Transparent
        $loadedIconImage = $null; $fileExists = $false; if (-not [string]::IsNullOrEmpty($iconPath)) { $fileExists = Test-Path -LiteralPath $iconPath -PathType Leaf }
        if ($fileExists) {
            $iconLoadError = $null
            try { $extension = [System.IO.Path]::GetExtension($iconPath).ToLower(); if ($extension -eq '.ico') { $iconObject = $null; try { $iconObject = New-Object System.Drawing.Icon($iconPath, $Script:iconSize.Width, $Script:iconSize.Height); $tempBitmap = $iconObject.ToBitmap(); if ($tempBitmap -ne $null -and $tempBitmap.Width -gt 0 -and $tempBitmap.Height -gt 0) { $loadedIconImage = $tempBitmap } else { $iconLoadError = "Failed to convert ICO to valid Bitmap for '$appName'."; $loadedIconImage = $null } } catch { Write-Error ("Failed to load/convert ICO '$iconPath' for '$appName': $($_.Exception.ToString())"); $iconLoadError = "ERROR loading/converting ICO."; $loadedIconImage = $null } finally { if ($iconObject -ne $null) { $iconObject.Dispose() } } } else { $originalImage = $null; $resizedImage = $null; $graphics = $null; try { $originalImage = [System.Drawing.Image]::FromFile($iconPath); $resizedImage = New-Object System.Drawing.Bitmap($Script:iconSize.Width, $Script:iconSize.Height); $graphics = [System.Drawing.Graphics]::FromImage($resizedImage); $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $graphics.DrawImage($originalImage, 0, 0, $Script:iconSize.Width, $Script:iconSize.Height); $loadedIconImage = $resizedImage; $resizedImage = $null } catch { Write-Error ("Failed to load/resize Image '$iconPath' for '$appName': $($_.Exception.ToString())"); $iconLoadError = "ERROR loading/resizing Image."; $loadedIconImage = $null } finally { if ($graphics -ne $null) { $graphics.Dispose() }; if ($originalImage -ne $null) { $originalImage.Dispose() }; if ($resizedImage -ne $null) { $resizedImage.Dispose()} } } } catch { Write-Error ("Generic error processing icon '$iconPath' for '$appName': $($_.Exception.ToString())"); $iconLoadError = "Generic ERROR processing icon."; $loadedIconImage = $null }
            if ($null -ne $iconLoadError) { Write-Warning "$iconLoadError Check console for details." }
        } else { Write-Warning "Icon file not found for '$appName': '$iconPath'"; $loadedIconImage = $null } # Added warning for missing icon file
        $checkBox.Tag = [PSCustomObject]@{ InstallerPath = $installerPath; IconImage = $loadedIconImage }
        try { $methodSetStyle.Invoke($checkBox, @([System.Windows.Forms.ControlStyles]::UserPaint, $true)); $methodSetStyle.Invoke($checkBox, @([System.Windows.Forms.ControlStyles]::ResizeRedraw, $true)); $methodSetStyle.Invoke($checkBox, @([System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer, $true)); $methodSetStyle.Invoke($checkBox, @([System.Windows.Forms.ControlStyles]::SupportsTransparentBackColor, $true)) } catch { Write-Warning "Could not set ControlStyles for CheckBox '$appName': $($_.Exception.Message)" } # AllPaintingInWmPaint removed
        $checkBox.add_Paint({ CheckBox_Paint $_ $EventArgs }); $checkBox.add_CheckedChanged({ $this.Invalidate() })
        $textMetrics = [System.Windows.Forms.TextRenderer]::MeasureText($checkBox.Text, $checkBox.Font); $iconSpace = if ($loadedIconImage) { $Script:iconSize.Width } else { 0 }; $marginAfterCheckbox = 5; # Fixed margin after checkbox itself
        $marginAfterIcon = if ($loadedIconImage) { $Script:iconMargin } else { 0 };
        $marginBeforeText = $textMargin;
        $requiredWidth = $checkSize + $marginAfterCheckbox + $iconSpace + $marginAfterIcon + $marginBeforeText + $textMetrics.Width + 10; # Adjusted calculation
        $requiredHeight = [Math]::Max($checkBox.Font.Height, $Script:iconSize.Height) + 6
        $checkBox.AutoSize = $false; $checkBox.Size = New-Object System.Drawing.Size($requiredWidth, $requiredHeight)
        $groupBox.Controls.Add($checkBox); $Script:AllCheckBoxes.Add($checkBox)
        $checkBoxY += $checkBox.Height + 5; $lastCheckBoxBottom = $checkBox.Bottom + 5
    } # End foreach
    [int]$calculatedHeight = $lastCheckBoxBottom + $groupBox.Padding.Bottom; $groupBox.Height = $calculatedHeight; $groupBox.Location = New-Object System.Drawing.Point(5, $currentY); $groupBox.MinimumSize = New-Object System.Drawing.Size(250, $calculatedHeight)
    $parentPanel.Controls.Add($groupBox); $newY = $currentY + $groupBox.Height + 10; if ($ColumnIndex -eq 0) { $Script:currentY_Left = $newY } else { $Script:currentY_Right = $newY }
    return $groupBox
}


# --- دالة تحديث التخطيط ---
Function Update-Layout {
    # هذه الدالة ستقوم بضبط العناصر داخل النافذة الموسعة الآن
    try {
        # Adjust Install button position
        if ($buttonPanel -and $installButton -and $buttonPanel.ClientSize.Width -gt ($installButton.Width + 20)) {
            $installButton.Location = [System.Drawing.Point]::new($buttonPanel.ClientSize.Width - $installButton.Width - 10, 10)
        }

        # Adjust Progress Panel elements
        if ($buttonPanel -and $progressPanel) {
            $pw = $buttonPanel.ClientSize.Width - 20; if ($pw -lt 10) { $pw = 10 }
            $progressPanel.Width = $pw
            if ($statusLabel) { $statusLabel.Width = $progressPanel.ClientSize.Width }
            if ($progressBar) { $progressBar.Width = $progressPanel.ClientSize.Width }
        }

        # Adjust Output Text Box
        if ($buttonPanel -and $progressPanel -and $outputTextBox) {
            $otY = $progressPanel.Location.Y + $progressPanel.Height + 5
            $otW = $buttonPanel.ClientSize.Width - 20; if ($otW -lt 10) { $otW = 10 }
            $otH = $buttonPanel.ClientSize.Height - $otY - 10; if ($otH -lt 10) { $otH = 10 }
            $outputTextBox.Location = [System.Drawing.Point]::new(10, $otY)
            $outputTextBox.Size = [System.Drawing.Size]::new($otW, $otH)
        }

        # Adjust GroupBox widths within panels
        $minGbWidth = 250 # الحد الأدنى لعرض الـ GroupBox
        if ($leftPanel -and $leftPanel.IsHandleCreated) {
            $panelWidth = $leftPanel.ClientSize.Width
            $gbWidth = $panelWidth - 10 # اترك هامش 5 من كل جانب
            if ($gbWidth -lt $minGbWidth) { $gbWidth = $minGbWidth}
            if ($leftPanel.Controls.Count -gt 0) {
                $leftPanel.Controls | Where-Object {$_ -is [System.Windows.Forms.GroupBox]} | ForEach-Object { $_.Width = $gbWidth }
            }
        }
        if ($rightPanel -and $rightPanel.IsHandleCreated) {
            $panelWidth = $rightPanel.ClientSize.Width
            $gbWidth = $panelWidth - 10 # اترك هامش 5 من كل جانب
            if ($gbWidth -lt $minGbWidth) { $gbWidth = $minGbWidth}
            if ($rightPanel.Controls.Count -gt 0) {
                $rightPanel.Controls | Where-Object {$_ -is [System.Windows.Forms.GroupBox]} | ForEach-Object { $_.Width = $gbWidth }
            }
        }
    } catch {
        Write-Warning "Update-Layout error: $($_.Exception.Message)"
    }
}


# --- Populate the columns ---
try { $leftPanel.Controls.Clear(); $rightPanel.Controls.Clear(); $Script:AllCheckBoxes.Clear(); $Script:currentY_Left = 5; $Script:currentY_Right = 5; foreach ($categoryEntry in $CategoriesLayout.GetEnumerator() | Sort-Object Name) { $categoryName = $categoryEntry.Name; $columnIndex = $categoryEntry.Value; Create-CategoryGroup -CategoryName $categoryName -ColumnIndex $columnIndex | Out-Null } } catch { Write-Error "An error occurred during GUI setup: $($_.Exception.Message)" }


# --- Installation Functions (Invoke-SilentInstall, Try-StartProcessJob, etc.) ---
# ... (No changes needed in these functions for the ComboBox) ...
function Invoke-SilentInstall { param( [Parameter(Mandatory=$true)][string]$AppName, [Parameter(Mandatory=$true)][string]$InstallerPath, [Parameter(Mandatory=$true)][System.Windows.Forms.RichTextBox]$OutputTextBox, [Parameter()][int]$TimeoutSeconds = 180 ); $outputTextBox.SelectionStart = $outputTextBox.TextLength; $outputTextBox.SelectionLength = 0; $outputTextBox.SelectionColor = $script:textBoxFgColor; $success = $false; if (-not ($AppName -like "*WhatsApp*") -and -not (Test-Path -Path $InstallerPath -PathType Leaf)) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ ERROR: Installer not found for '$AppName': $InstallerPath `r`n"); $outputTextBox.ScrollToCaret(); return $false }; $OutputTextBox.AppendText("⏳ Attempting to install '$AppName'...`r`n"); $OutputTextBox.Refresh(); $OutputTextBox.ScrollToCaret(); $ext = ".unknown"; if ($AppName -like "*WhatsApp*") { $ext = ".winget-placeholder" } elseif ($InstallerPath) { try { $ext = [System.IO.Path]::GetExtension($InstallerPath).ToLower() } catch { Write-Warning "Could not get extension for '$InstallerPath'" } }; $arguments = ""; $process = $null; $exitCode = -1; try { Write-Host "Starting installation for: ${AppName} ($InstallerPath) with interpreted extension '$ext'"; if ($ext -eq ".winget-placeholder" -and $AppName -like "*WhatsApp*") { Write-Host "Using winget to install WhatsApp..."; $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.AppendText("ℹ️ Using winget for '$AppName'. Requires internet connection and winget tool.`r`n"); $wingetArgs = 'install --id 9NKSQGP7F2NH -s msstore --exact --accept-package-agreements --accept-source-agreements --disable-interactivity'; Write-Host "Executing: winget $wingetArgs"; $proc = $null; try { $proc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop; $exitCode = $proc.ExitCode; Write-Host "Winget process finished for '$AppName'. ExitCode: $exitCode"; if ($exitCode -eq 0) { $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.AppendText("✔️ Winget successfully installed/updated '$AppName' (ExitCode: $exitCode).`r`n"); $success = $true } else { if ($exitCode -eq 0x8A15000F) { $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.AppendText("✔️ Winget reports '$AppName' is likely already installed or an install is in progress (ExitCode: $exitCode).`r`n"); $success = $true } else { $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $OutputTextBox.AppendText("⚠️ WARN: Winget finished for '$AppName' with ExitCode: $exitCode. Check winget logs if issues persist.`r`n"); $success = $false } } } catch { $ErrorMessage = $_.Exception.Message -replace '[\r\n]',' '; Write-Error "Error running winget for '$AppName': $ErrorMessage"; $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; if ($ErrorMessage -like "*cannot find the file*winget*") { $OutputTextBox.AppendText("❌ ERROR: Cannot find 'winget.exe'. Please ensure Windows Package Manager is installed and in your PATH.`r`n") } else { $OutputTextBox.AppendText("❌ ERROR running winget for '$AppName': $ErrorMessage `r`n") }; $success = $false } } else { switch ($ext) { '.msi' { $logFileName = "C:\Windows\Temp\$($AppName -replace '[^a-zA-Z0-9]','_')_Install.log"; $arguments = "/i `"$InstallerPath`" /qn /norestart /L*V `"$logFileName`""; Write-Host "Using msiexec with args: $arguments"; $processInfo = New-Object System.Diagnostics.ProcessStartInfo("msiexec.exe", $arguments); $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden; $processInfo.UseShellExecute = $false; $process = [System.Diagnostics.Process]::Start($processInfo); $process.WaitForExit(); $exitCode = $process.ExitCode; Write-Host "MSI process finished. ExitCode: $exitCode"; if ($exitCode -eq 0 -or $exitCode -eq 3010) { $success = $true; $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.AppendText("✔️ MSI '$AppName' completed (ExitCode: $exitCode)$(if($exitCode -eq 3010){' - Reboot may be needed'})`r`n") } else { $success = $false; $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $OutputTextBox.AppendText("⚠️ WARN: MSI '$AppName' finished (ExitCode: $exitCode). Check log: $logFileName `r`n") }; $process = $null } '.exe' { $commonSilentSwitches = @( "/S", "/s", "/q", "/qn", "/quiet", "/silent", "/verysilent", "/suppressmsgboxes" ); $arguments = ""; if ($AppName -like "*7-Zip*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*WinRAR*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*UltraISO*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*GIMP*") { $arguments = "/VERYSILENT /NORESTART /SP- /LANG=en" } elseif ($AppName -like "*Audacity*") { $arguments = "/VERYSILENT /NORESTART /SP- /LANG=en" } elseif ($AppName -like "*GameLoop*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*Notepad++*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*VLC*") { $arguments = "/L=1033 /S /LANG=en" } elseif ($AppName -like "*PotPlayer*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*K-Lite*") { $arguments = "/verysilent /norestart /LANG=en" } elseif ($AppName -like "*Steam*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*Chrome*") { $arguments = "/silent /install /LANG=en" } elseif ($AppName -like "*Firefox*") { $arguments = "-ms" } elseif ($AppName -like "*Opera*") { $arguments = "--silent --launchopera=0 --setdefaultbrowser=0 --allusers=1" } elseif ($AppName -like "*IDM*") { $arguments = "/skipdlgs" } elseif ($AppName -like "*Ant Download*") { $arguments = "/VERYSILENT /NORESTART /LANG=en" } elseif ($AppName -like "*Free Download*") { $arguments = "/S /L=1033 /LANG=en" } elseif ($AppName -like "*uTorrent*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*AnyDesk*") { $arguments = "--install `"C:\Program Files (x86)\AnyDesk`" --silent --update-disabled --remove-startup --no-request-elevation" } elseif ($AppName -like "*Discord*") { $arguments = "--silent" } elseif ($AppName -like "*Dropbox*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*Google Drive*") { $arguments = "--silent --skip_launch_new --gsuite_shortcuts=false" } elseif ($AppName -like "*Skype*") { $arguments = "/SILENT /LANG=en" } elseif ($AppName -like "*Supremo*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*TeamViewer*") { $arguments = "/S /LANG=en" } elseif ($AppName -like "*Telegram*") { $arguments = "/VERYSILENT /NORESTART /LANG=en" } elseif ($AppName -like "*Viber*") { $arguments = "/S /L=1033 /LANG=en" } elseif ($AppName -like "*Zoom*") { $arguments = "/silent /norestart /nobrandingZoom /runatwinlogon=0" } elseif ($AppName -like "*Java*Runtime*") { $arguments = "/s /LANG=en" } elseif ($AppName -like "*VC++ Redist*") { $arguments = "/install /quiet /norestart" } elseif ($AppName -like "*Foxit*Reader*") { $arguments = '/quiet LANG="ENU /LANG=en"' } elseif ($AppName -like "*Adobe*Reader*") { $arguments = "/sAll /msi /norestart /quiet EULA_ACCEPT=YES /LANG=en" } elseif ($AppName -like "*Defender*Update*"){ $arguments = "/q /LANG=en" } else { $arguments = "" }; $exeSuccess = $false; if ($arguments -ne "") { Write-Host "Using specific args for '$AppName': $arguments"; $exeSuccess = Try-StartProcessJob -InstallerPath $InstallerPath -Arguments $arguments -AppName $AppName -TimeoutSeconds $TimeoutSeconds -OutputTextBox $OutputTextBox }; if (-not $exeSuccess) { Write-Host "No specific args worked or none found for '$AppName'. Trying common options..."; $OutputTextBox.AppendText("    Trying common options...`r`n"); $OutputTextBox.Refresh(); $OutputTextBox.ScrollToCaret(); foreach ($switch in $commonSilentSwitches) { Write-Host "Attempting '$AppName' with base switch: $switch"; $OutputTextBox.AppendText("      Trying base switch: $switch ...`r`n"); $OutputTextBox.Refresh(); $OutputTextBox.ScrollToCaret(); if (Try-StartProcessJob -InstallerPath $InstallerPath -Arguments $switch -AppName $AppName -TimeoutSeconds $TimeoutSeconds -OutputTextBox $OutputTextBox) { $exeSuccess = $true; Write-Host "Success with base switch: $switch"; break } else { Write-Host "Base switch '$switch' failed or timed out."; Start-Sleep -Milliseconds 200 } }; if (-not $exeSuccess) { Write-Host "Base switches failed for '$AppName'. Trying common switches with English language parameter..."; $OutputTextBox.AppendText("    Trying switches with language parameter...`r`n"); $OutputTextBox.Refresh(); $OutputTextBox.ScrollToCaret(); $combinations = @{ "/S /L=1033" = "NSIS Silent + English Lang ID"; "/VERYSILENT /LANG=en" = "Inno Setup Very Silent + English Lang Code"; "/SILENT /LANG=en" = "Inno Setup Silent + English Lang Code"; '/quiet LANG="ENU"' = "Alternative Lang Syntax (e.g., Foxit)"; }; foreach ($comboEntry in $combinations.GetEnumerator()) { $comboArgs = $comboEntry.Name; $comboDesc = $comboEntry.Value; Write-Host "Attempting '$AppName' with combination ($comboDesc): $comboArgs"; $OutputTextBox.AppendText("      Trying combination: $comboArgs ...`r`n"); $OutputTextBox.Refresh(); $OutputTextBox.ScrollToCaret(); if (Try-StartProcessJob -InstallerPath $InstallerPath -Arguments $comboArgs -AppName $AppName -TimeoutSeconds $TimeoutSeconds -OutputTextBox $OutputTextBox) { $exeSuccess = $true; Write-Host "Success with combination: $comboArgs"; break } else { Write-Host "Combination '$comboArgs' failed or timed out."; Start-Sleep -Milliseconds 200 } } } }; if (-not $exeSuccess) { Write-Warning "EXE Installation for '$AppName' failed or timed out after trying specific args, common switches, and combinations."; $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $OutputTextBox.AppendText("⚠️ WARN: EXE '$AppName' installation did not complete successfully or timed out after trying options.`r`n") }; $success = $exeSuccess } { $_ -in '.appxbundle', '.msixbundle' } { $packageType = $ext.TrimStart('.'); Write-Host "Attempting to register Appx package (non-WhatsApp): $InstallerPath ($packageType)"; try { Add-AppxPackage -Path $InstallerPath -ErrorAction Stop; $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.AppendText("✔️ Successfully initiated registration for '$AppName' ($packageType). Check system notifications for final status.`r`n"); $success = $true } catch { $exception = $_.Exception; $ErrorMessage = $exception.Message -replace '[\r\n]',' '; Write-Error "Error registering $packageType for '$AppName': $ErrorMessage"; $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $hResult = $exception.HResult; if ($exception.InnerException -ne $null -and $hResult -ne $exception.InnerException.HResult) { $innerHResult = $exception.InnerException.HResult; if ($innerHResult -ne 0x80073CF0) { $hResult = $innerHResult }; Write-Host "DEBUG: Appx Error - Outer HResult: $($exception.HResult), Inner HResult: $innerHResult. Using HResult: $hResult for check." } else { Write-Host "DEBUG: Appx Error - HResult: $hResult." }; if ($hResult -eq 0x80073D06 -or $hResult -eq 0x800700B7) { $OutputTextBox.AppendText("ℹ️ INFO: Package for '$AppName' ($packageType) seems already registered/present or blocked by existing files/version. ($ErrorMessage).`r`n"); $success = $true; $outputTextBox.SelectionColor = $script:textBoxFgColor } elseif ($hResult -eq 0x80073CF3) { $dependencyMessage = "Missing required dependency."; if ($ErrorMessage -match 'Provide the framework "([^"]+)"' -or $ErrorMessage -match 'dependency ([^\s]+) specified') { $dependencyName = $matches[1]; $dependencyName = $dependencyName -replace '_[\d\.]+_neutral__\w+$','' -replace '_[\d\.]+_x64__\w+$','' -replace '_[\d\.]+_x86__\w+$',''; $dependencyMessage = "Missing required dependency: '$dependencyName'." } elseif ($ErrorMessage -match 'depends on a framework that could not be found') { $dependencyMessage = "Missing required framework dependency." }; $OutputTextBox.AppendText("❌ ERROR installing '$AppName' ($packageType): $dependencyMessage Please install missing components (e.g., from Microsoft Store or Windows Update) and try again. Error Code: $(('{0:X8}' -f $hResult))`r`n"); $success = $false } else { $OutputTextBox.AppendText("❌ ERROR registering '$AppName' ($packageType) (Code: $(('{0:X8}' -f $hResult))): $ErrorMessage `r`n"); $success = $false } } } { $_ -eq '.bat' -and ($AppName -like "*Office 2013*" -or $AppName -like "*Office 2010*") } { Write-Host "Attempting to run batch file: $InstallerPath"; try { $proc = Start-Process -FilePath $InstallerPath -Wait -WindowStyle Hidden -PassThru -ErrorAction Stop; $exitCode = $proc.ExitCode; Write-Host "Batch file '$AppName' finished with ExitCode: $exitCode"; if ($exitCode -eq 0) { $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.AppendText("✔️ Batch file '$AppName' completed successfully (ExitCode: $exitCode).`r`n"); $success = $true } else { $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $OutputTextBox.AppendText("⚠️ WARN: Batch file '$AppName' finished with ExitCode: $exitCode.`r`n"); $success = $false } } catch { $ErrorMessage = $_.Exception.Message -replace '[\r\n]',' '; Write-Error "Error running batch file for '$AppName': $ErrorMessage"; $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ ERROR running batch file '$AppName': $ErrorMessage `r`n"); $success = $false } } default { $outputTextBox.SelectionColor = [System.Drawing.Color]::Yellow; $OutputTextBox.AppendText("⚠️ SKIPPED: Unsupported file type or unhandled application '$AppName': '$ext' `r`n"); $success = $false } } } } catch { $ErrorMessage = $_.Exception.Message -replace '[\r\n]',' '; $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ FATAL ERROR installing '$AppName': $ErrorMessage `r`n"); Write-Error "Fatal Error installing ${AppName}: $ErrorMessage"; $success = $false }; $outputTextBox.SelectionStart = $outputTextBox.TextLength; $outputTextBox.SelectionLength = 0; $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.ScrollToCaret(); return $success }
Function Try-StartProcessJob { param( [Parameter(Mandatory)]$InstallerPath, [Parameter(Mandatory)]$Arguments, [Parameter(Mandatory)]$AppName, [Parameter(Mandatory)]$TimeoutSeconds, [Parameter(Mandatory)][Alias('OutTB')]$OutputTextBox ); $jobSuccess = $false; $job = $null; try { $sb = { param($p, $a); $pr = $null; try { $pr = Start-Process -FilePath $p -ArgumentList $a -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop; return $pr.ExitCode } catch { if ($pr -ne $null) { if (-not $pr.HasExited) { return -999 } else { return $pr.ExitCode } } else { return -998 } } }; $job = Start-Job -ScriptBlock $sb -ArgumentList $InstallerPath, $Arguments; $waitTimeout = if ($TimeoutSeconds -gt 0 -and $TimeoutSeconds -le 600) { $TimeoutSeconds } else { 180 }; $jr = Wait-Job -Job $job -Timeout $waitTimeout; if ($jr.State -eq 'Completed') { $jo = Receive-Job $job -Keep; $ec = -1; $eco = $jo | Select-Object -Last 1; if ($eco -is [int]) { $ec = $eco } elseif ($eco -is [string] -and $eco -match '^\s*(\-?\d+)\s*$') { try { $ec = [int]$matches[1] } catch {}} elseif ($jo -is [array] -and $jo.Count -gt 0) { $lastItem = $jo[-1]; if ($lastItem -is [int]) { $ec = $lastItem }} elseif ($jo -match 'ExitCode (\-?\d+)') { try { $ec = [int]$matches[1] } catch {}} elseif ($jo -match 'Job Error:') { $ec = -997 } else {}; if ($ec -eq -998) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ EXE '$AppName' failed to start (Error launching process). Args:'$Arguments'.`r`n"); $jobSuccess = $false } elseif ($ec -eq -999) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ EXE '$AppName' terminated abnormally or errored during wait. Args:'$Arguments'.`r`n"); $jobSuccess = $false } elseif ($ec -eq 0 -or ($AppName -like "*VC++ Redist*" -and $ec -eq 3010)) { $OutputTextBox.AppendText("✔️ EXE '$AppName' OK (Args:'$Arguments', ExitCode:$ec).`r`n"); $jobSuccess = $true } elseif ($ec -lt 0) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ EXE '$AppName' job error (Negative ExitCode:$ec). Args:'$Arguments'. Raw Output:`n$($jo -join "`n")`r`n"); $jobSuccess = $false } else { $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $OutputTextBox.AppendText("⚠️ EXE '$AppName' finished with Warning/Error (ExitCode:$ec, Args:'$Arguments'). Check installer logs if available.`r`n"); $jobSuccess = $false } } elseif ($jr.State -match 'Running|Suspended') { $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $OutputTextBox.AppendText("⏰ EXE '$AppName' timed out after $waitTimeout seconds. Stopping job.`r`n"); $jobSuccess = $false; try { Stop-Job $job -PassThru -ErrorAction Stop | Out-Null } catch { Write-Warning "DEBUG: Error stopping job '$($job.Name)': $($_.Exception.Message)"} } else { $reason = "Unknown"; if ($null -ne $jr.Reason -and $null -ne $jr.Reason.Message) { $reason = $jr.Reason.Message }; $errs = $job.ChildJobs[0].Error | ForEach-Object { $_.ToString() }; $errD = if($errs){ "`nJob Errors:$($errs -join '; ')" } else { "" }; $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ EXE Job '$AppName' failed. State:$($jr.State). Reason:$reason.$errD `r`n"); $jobSuccess = $false; Receive-Job $job -Keep | Out-Null } } catch { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("❌ Job setup error for '$AppName': $($_.Exception.Message)`r`n"); $jobSuccess = $false } finally { if ($job) { Remove-Job $job -Force -ErrorAction SilentlyContinue }; $outputTextBox.SelectionColor = $script:textBoxFgColor; $OutputTextBox.ScrollToCaret() }; return $jobSuccess }
Function Format-TimeSpan([System.TimeSpan]$TimeSpan) { return $TimeSpan.ToString("hh\:mm\:ss") }

$timer.add_Tick({ try { if ($script:estimatedEndTime) { $rem = $script:estimatedEndTime - (Get-Date); if ($rem.TotalSeconds -gt 0) { $statusLabel.Text = "Processing $($script:currentAppNumForTimer)/$($script:totalAppsForTimer): $($script:currentAppNameForTimer) | Est. Rem: $(Format-TimeSpan $rem)" } else { $statusLabel.Text = "Processing $($script:currentAppNumForTimer)/$($script:totalAppsForTimer): $($script:currentAppNameForTimer) | Est. Rem: 00:00:00"; $timer.Stop(); $script:estimatedEndTime = $null } } else { $timer.Stop() } } catch { Write-Warning "Timer tick error: $($_.Exception.Message)"; $timer.Stop(); $script:estimatedEndTime = $null } })
$selectAllButton.Add_Click({ $Script:AllCheckBoxes |% { if (-not $_.Checked) { $_.Checked = $true } }; $presetsComboBox.SelectedIndex = 0 }) # Reset preset on select all
$deselectAllButton.Add_Click({ $Script:AllCheckBoxes |% { if ($_.Checked) { $_.Checked = $false } }; $presetsComboBox.SelectedIndex = 0 }) # Reset preset on deselect all
$installButton.Add_Click({
    param($sender, $e)
    $installButton.Enabled = $false; $selectAllButton.Enabled = $false; $deselectAllButton.Enabled = $false; $presetsComboBox.Enabled = $false # Disable ComboBox during install
    $Script:AllCheckBoxes |% { $_.Enabled = $false; $_.Invalidate() }
    $timer.Stop(); $script:estimatedEndTime = $null; $outputTextBox.Clear(); $outputTextBox.SelectionColor = $script:textBoxFgColor; $outputTextBox.AppendText("Starting installation process...`r`n"); [System.Windows.Forms.Application]::DoEvents()
    $selectedApps = $Script:AllCheckBoxes |? { $_.Checked }
    if ($selectedApps.Count -eq 0) {
        $outputTextBox.AppendText("🤷 No applications selected.`r`n")
        $installButton.Enabled = $true; $selectAllButton.Enabled = $true; $deselectAllButton.Enabled = $true; $presetsComboBox.Enabled = $true # Re-enable ComboBox
        $Script:AllCheckBoxes |% { $_.Enabled = $true; $_.Invalidate() }
        return
    }
    $totalAppsToInstall = $selectedApps.Count; $appsProcessed = 0; $appsSucceeded = 0; $progressBar.Maximum = $totalAppsToInstall; $progressBar.Value = 0; $progressPanel.Visible = $true; $statusLabel.Text = "Starting..."; $startTime = Get-Date
    foreach ($checkbox in $selectedApps) {
        $appName = $checkbox.Text; $installerPath = $null
        if ($checkbox.Tag -is [PSCustomObject] -and $checkbox.Tag.PSObject.Properties.Name -contains 'InstallerPath') { $installerPath = $checkbox.Tag.InstallerPath } else { Write-Warning "Could not find InstallerPath in Tag for '$appName'. Trying Tag directly."; $installerPath = $checkbox.Tag }
        if ([string]::IsNullOrEmpty($installerPath)) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $outputTextBox.AppendText("❌ ERROR: Could not retrieve installer path for '$appName'. Skipping.`r`n"); $appsProcessed++; $progressBar.Value = $appsProcessed; continue }
        $appsProcessed++; $script:currentAppNameForTimer = $appName; $script:currentAppNumForTimer = $appsProcessed; $script:totalAppsForTimer = $totalAppsToInstall; $progressBar.Value = $appsProcessed
        $elapsedTime = (Get-Date) - $startTime; $elapsedFormatted = Format-TimeSpan $elapsedTime; $estimatedRemainingFormatted = "--:--:--"; $initialEstimatedSeconds = 0
        if ($appsProcessed -gt 1 -and $elapsedTime.TotalSeconds -gt 0.5) { $avgTimePerApp = $elapsedTime.TotalSeconds / ($appsProcessed - 1); $remainingApps = $totalAppsToInstall - $appsProcessed; if ($remainingApps -ge 0) { $initialEstimatedSeconds = [Math]::Round($avgTimePerApp * $remainingApps); if ($initialEstimatedSeconds -ge 1) { $estimatedRemainingFormatted = Format-TimeSpan ([TimeSpan]::FromSeconds($initialEstimatedSeconds)) } else { $estimatedRemainingFormatted = "< 1 min"; $initialEstimatedSeconds = 0 } } } elseif ($appsProcessed -eq $totalAppsToInstall) { $estimatedRemainingFormatted = "Finishing..." }
        $timer.Stop(); $script:estimatedEndTime = $null
        if ($appsProcessed -eq 1) { $statusLabel.Text = "Processing $appsProcessed/${totalAppsToInstall}: $appName | Elapsed: $elapsedFormatted" } elseif ($initialEstimatedSeconds -ge 1) { $script:estimatedEndTime = (Get-Date).AddSeconds($initialEstimatedSeconds); $statusLabel.Text = "Processing $appsProcessed/${totalAppsToInstall}: $appName | Est. Rem: $estimatedRemainingFormatted"; $timer.Start() } else { $statusLabel.Text = "Processing $appsProcessed/${totalAppsToInstall}: $appName | Est. Rem: $estimatedRemainingFormatted" }
        $statusLabel.Refresh(); $progressBar.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        $outputTextBox.SelectionColor = [System.Drawing.Color]::FromArgb(200, 200, 200); $outputTextBox.AppendText("`r`n--- [$appsProcessed/$totalAppsToInstall] Processing: '$appName' ---`r`n"); $outputTextBox.SelectionColor = $script:textBoxFgColor
        $installSuccess = $false
        try { $installSuccess = Invoke-SilentInstall -AppName $appName -InstallerPath $installerPath -OutputTextBox $outputTextBox } catch { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $outputTextBox.AppendText("❌ CRITICAL ERROR during Invoke-SilentInstall for '$appName': $($_.Exception.Message)`r`n"); $outputTextBox.SelectionColor = $script:textBoxFgColor; $installSuccess = $false } finally { $timer.Stop(); $script:estimatedEndTime = $null }
        if ($installSuccess) { $appsSucceeded++ }
        [System.Windows.Forms.Application]::DoEvents()
    }
    $timer.Stop(); $endTime = Get-Date; $totalElapsedTime = $endTime - $startTime; $finalElapsedTimeFormatted = Format-TimeSpan $totalElapsedTime
    $statusLabel.Text = "Completed $appsProcessed/$totalAppsToInstall | Total Time: $finalElapsedTimeFormatted | Success: $appsSucceeded/$totalAppsToInstall"
    $progressBar.Value = $progressBar.Maximum
    $outputTextBox.SelectionColor = [System.Drawing.Color]::FromArgb(200, 200, 200); $outputTextBox.AppendText("`r`n--- Installation Summary ---`r`n"); $outputTextBox.SelectionColor = $script:textBoxFgColor; $outputTextBox.AppendText("Attempted: $totalAppsToInstall.`r`n")
    if ($appsSucceeded -eq $totalAppsToInstall) { $outputTextBox.SelectionColor = [System.Drawing.Color]::LightGreen; $outputTextBox.AppendText("Success: $appsSucceeded.`r`n") } elseif ($appsSucceeded -gt 0) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Orange; $outputTextBox.AppendText("Success: $appsSucceeded (Partial).`r`n") } else { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $OutputTextBox.AppendText("Success: $appsSucceeded (Failed).`r`n") }
    $outputTextBox.SelectionColor = $script:textBoxFgColor; $outputTextBox.AppendText("Total time: $finalElapsedTimeFormatted.`r`n"); $outputTextBox.ScrollToCaret()
    $installButton.Enabled = $true; $selectAllButton.Enabled = $true; $deselectAllButton.Enabled = $true; $presetsComboBox.Enabled = $true # Re-enable ComboBox
    $Script:AllCheckBoxes |% { $_.Enabled = $true; if ($_.Checked) { $_.Checked = $false } else { $_.Invalidate() } }
    $presetsComboBox.SelectedIndex = 0 # Reset preset selection after completion
})


# --- Scroll Event Handlers (No Sleep) ---
$leftPanel.add_Scroll({ if ($leftPanel.IsHandleCreated) { $leftPanel.SuspendLayout(); $leftPanel.ResumeLayout($true); $leftPanel.Refresh() } })
$rightPanel.add_Scroll({ if ($rightPanel.IsHandleCreated) { $rightPanel.SuspendLayout(); $rightPanel.ResumeLayout($true); $rightPanel.Refresh() } })


# --- Form Shown Event Handler ---
$mainForm.Add_Shown({
    param($sender, $e)
    Write-Host "Form_Shown event triggered." -ForegroundColor Cyan
    # $mainForm.SuspendLayout() # No longer needed here as form is fixed
    # $mainForm.ResumeLayout($false) # No longer needed here
    Write-Host "Calling Update-Layout from Shown event." -ForegroundColor Cyan
    Update-Layout # Call Update-Layout to arrange elements within the maximized window
    Write-Host "Enabling Double Buffering recursively for panels' controls." -ForegroundColor Cyan
    try { foreach($ctrl in $leftPanel.Controls) { Enable-DoubleBufferingRecursively $ctrl } } catch { Write-Warning "Error applying double buffering to left panel controls."}
    try { foreach($ctrl in $rightPanel.Controls) { Enable-DoubleBufferingRecursively $ctrl } } catch { Write-Warning "Error applying double buffering to right panel controls."}
    Write-Host "Enabling AutoScroll and setting MinSize." -ForegroundColor Cyan
    try {
        $leftPanel.AutoScrollMinSize = [System.Drawing.Size]::new(0, $Script:currentY_Left + 5)
        $rightPanel.AutoScrollMinSize = [System.Drawing.Size]::new(0, $Script:currentY_Right + 5)
        $leftPanel.AutoScroll = $true
        $rightPanel.AutoScroll = $true
    } catch { Write-Warning "Error setting AutoScroll properties." }
    Write-Host "Calling Update-Layout again after enabling AutoScroll." -ForegroundColor Cyan
    Update-Layout # Call Update-Layout again after enabling AutoScroll to ensure scrollbars appear if needed
    # $mainForm.ResumeLayout($true) # No longer needed here
    $mainForm.Refresh() # Refresh the form to display everything correctly
})

# --- Show Form ---
try {
    Write-Host "Showing main form (Maximized and Fixed)..."
    $mainForm.ShowDialog() | Out-Null
    Write-Host "Main form closed."
} catch {
    Write-Error "Form execution error: $($_.Exception.Message)"
    if ($outputTextBox -and -not $outputTextBox.IsDisposed) { $outputTextBox.SelectionColor = [System.Drawing.Color]::Red; $outputTextBox.AppendText("`r`n❌ FORM ERROR: $($_.Exception.Message)`r`n") }
} finally {
    Write-Host "Performing cleanup..."
    # --- Cleanup ---
    if ($timer) { try { $timer.Stop(); $timer.Dispose() } catch { Write-Warning "Error disposing timer: $($_.Exception.Message)"} }
    Write-Host "Disposing checkbox icon images..."
    if ($AllCheckBoxes -ne $null -and $AllCheckBoxes.Count -gt 0) {
        foreach ($cb in $AllCheckBoxes) {
            if ($cb -ne $null -and $cb.Tag -is [PSCustomObject] -and $cb.Tag.PSObject.Properties.Name -contains 'IconImage') {
                 $img = $cb.Tag.IconImage
                 if ($img -ne $null -and $img -is [System.Drawing.Image]) {
                     try { $img.Dispose() }
                     catch { Write-Warning "Error disposing image for $($cb.Text): $($_.Exception.Message)" }
                 }
            }
        }
    } else { Write-Host "No checkboxes found in list for image disposal."}
    if ($mainForm -and -not $mainForm.IsDisposed) { try { if ($mainForm.BackgroundImage){ $mainForm.BackgroundImage.Dispose() }; $mainForm.Dispose() } catch { Write-Warning "Error disposing main form: $($_.Exception.Message)"} }
    try { Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue } catch { Write-Warning "Error removing jobs: $($_.Exception.Message)"}
    Write-Host "Cleanup complete."
}