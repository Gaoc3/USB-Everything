#Requires -RunAsAdministrator
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Stop'                   
$currentDrive = ($PWD.Path -split '\\')[0]
$env:Path += ";${currentDrive}\Programs Files\chocolatey\bin\Winget\AppInstaller_x64"

# استيراد المكتبات اللازمة لواجهة المستخدم
#Requires -RunAsAdministrator
# Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force # Consider if truly needed
$ErrorActionPreference = 'Stop'

# استيراد المكتبات اللازمة لواجهة المستخدم
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


[System.Windows.Forms.Application]::EnableVisualStyles()
$currentDrive = ($PWD.Path -split '\\')[0]
# ----------- شاشة التحميل -----------
$splashForm = New-Object System.Windows.Forms.Form
$splashForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$splashForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$splashForm.Size = New-Object System.Drawing.Size(1080, 1080) # تم تغيير الحجم هنا
$splashForm.Icon = "${currentDrive}\الأدوات\source\optimization.ico"
$splashForm.Text = 'Windows Optmizer'
# خلفية شاشة التحميل
$backgroundImagePath = "${currentDrive}\الأدوات\source\background.jfif" 
$splashForm.BackgroundImage = [System.Drawing.Image]::FromFile($backgroundImagePath)
$splashForm.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Zoom

# نص التحميل
$loadingLabel = New-Object System.Windows.Forms.Label
$loadingLabel.Text = "جاري التحميل..."
$loadingLabel.Font = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
$loadingLabel.ForeColor = [System.Drawing.Color]::White
$loadingLabel.BackColor = [System.Drawing.Color]::Transparent
$loadingLabel.AutoSize = $false
$loadingLabel.Size = New-Object System.Drawing.Size(300, 40)
$loadingLabel.Location = New-Object System.Drawing.Point(390, 1000) # تحديد موقع جديد للنص
$loadingLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$splashForm.Controls.Add($loadingLabel)
# ----------- تهيئة الخلفية -----------
$backgroundImage = [System.Drawing.Image]::FromFile($backgroundImagePath)

# تفعيل مقاومة تغييرات الـ DPI
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[DpiHelper]::SetProcessDPIAware()

# تأكد من الصلاحيات الإدارية
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --------------------------- الواجهة الرئيسية ---------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Optimizer"
$form.Size = New-Object System.Drawing.Size(1400, 900) # زيادة حجم النافذة
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.BackgroundImage = $backgroundImage
$form.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Zoom
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Icon = "${currentDrive}\الأدوات\source\optimization.ico"
$form.Add_FormClosing({
    param($sender, $e)
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        "هل أنت متأكد من رغبتك في الخروج؟",
        "تأكيد الخروج",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::No) {
        $e.Cancel = $true # منع الإغلاق
    }
})

# تحسين نص العنوان الخاص بالنافذة ليكون أكثر وضوحًا وجرأة
$form.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)

# --------------------------- نص العنوان ---------------------------
$addressLabel = New-Object System.Windows.Forms.Label
$addressLabel.Text = "بغداد شارع الصناعة - مقابل الجامعة التكنلوجية - مجمع النخلة"
$addressLabel.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
$addressLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 255, 255, 255)
$addressLabel.BackColor = [System.Drawing.Color]::Transparent
$addressLabel.AutoSize = $false

# تعديل حجم وموقع نص العنوان ليظهر بشكل كامل دون تداخل:
$addressLabel.Width = $form.Width - 60
$addressLabel.Height = 40

# تعيين الهوامش
$marginBottom = 70  # مقدار الارتفاع عن الحافة السفلى
$marginLeft = 60    # زيادة الهامش الأيسر قليلاً لتحريك النص إلى اليمين (بدلاً من 20)

# التأكد من أن ClientSize تُرجع قيمة صحيحة
$formHeight = [int]$form.ClientSize.Height
$labelHeight = [int]$addressLabel.Height

# ضبط موقع العنوان
$addressLabel.Location = New-Object System.Drawing.Point($marginLeft, ($formHeight - $labelHeight - $marginBottom))

# محاذاة النص داخل الـ Label إلى المنتصف
$addressLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$form.Controls.Add($addressLabel)

# --------------------------- منطقة النتائج (مصغرة) ---------------------------
$outputBox = New-Object System.Windows.Forms.RichTextBox
$outputBox.Location = New-Object System.Drawing.Point(300, 20)
$outputBox.Size = New-Object System.Drawing.Size(1050, 650) # تصغير الحجم
$outputBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$outputBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 230, 200)
$outputBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$outputBox.Font = New-Object System.Drawing.Font("Cascadia Code", 18)
$outputBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$outputBox.ReadOnly = $true
$form.Controls.Add($outputBox)

# --------------------------- شريط التقدم ---------------------------
$globalProgress = New-Object System.Windows.Forms.ProgressBar
$globalProgress.Location = New-Object System.Drawing.Point(300, 680)
$globalProgress.Size = New-Object System.Drawing.Size(1050, 25)
$globalProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$globalProgress.ForeColor = [System.Drawing.Color]::FromArgb(0, 184, 148)
$globalProgress.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$form.Controls.Add($globalProgress)

# --------------------------- الأزرار ---------------------------
$buttonStyle = @{
    Size = New-Object System.Drawing.Size(250, 60)
    Location = New-Object System.Drawing.Point(20, 30)
    Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    ForeColor = [System.Drawing.Color]::White
}

$buttons = @(
    "تثبيت تحديثات الويندوز", 
    "تحديث التطبيقات", 
    "تفعيل الويندوز", 
    "تثبيت الدرايفرات", 
    "إصلاح الأخطاء", 
    "تويكات الويندوز", 
    "نقطة استعادة"
)

foreach ($btnText in $buttons) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $btnText
    $button.Size = $buttonStyle.Size
    $button.Location = $buttonStyle.Location
    $button.Font = $buttonStyle.Font
    $button.FlatStyle = $buttonStyle.FlatStyle
    $button.BackColor = $buttonStyle.BackColor
    $button.ForeColor = $buttonStyle.ForeColor
    
    # تأثيرات التفاعل
    $button.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(0, 158, 255) })
    $button.Add_MouseLeave({ $this.BackColor = $buttonStyle.BackColor })
    $button.Add_MouseDown({ $this.BackColor = [System.Drawing.Color]::FromArgb(0, 90, 158) })
    $button.Add_MouseUp({ $this.BackColor = [System.Drawing.Color]::FromArgb(0, 158, 255) })
    
    # تحديد الإجراء
    switch ($btnText) {
        "تثبيت تحديثات الويندوز" { $button.Add_Click({WindowsUpdates}) }
        "تحديث التطبيقات" { $button.Add_Click({WindowsAppUpdate}) }
        "تفعيل الويندوز" { $button.Add_Click({WindowsActivate}) }
        "تثبيت الدرايفرات" { $button.Add_Click({InstallGraphicsDriver}) }
        "إصلاح الأخطاء" { $button.Add_Click({FixWindowsError}) }
        "تويكات الويندوز" { $button.Add_Click({WindowsTweaks}) }
        "نقطة استعادة" { $button.Add_Click({RestorePoint}) }
    }
    
    $form.Controls.Add($button)
    $buttonStyle.Location.Y += 70
}

# --------------------------- الدوال الوظيفية ---------------------------
function Write-OutputBox {
    param(
        [string]$message,
        [string]$color = "White",
        [bool]$newLine = $true
    )
    
    $outputBox.Invoke([Action]{
        $outputBox.SelectionStart = $outputBox.TextLength
        $outputBox.SelectionColor = $color
        $outputBox.AppendText((Get-Date -Format "HH:mm:ss") + " | " + $message)
        if ($newLine) { $outputBox.AppendText("`n") }
        $outputBox.ScrollToCaret()
    })
}

function WindowsUpdates {
    try {
        Write-OutputBox "جاري البحث عن تحديثات النظام..." -Color Cyan
        
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-OutputBox "تثبيت وحدة التحديثات..." -Color Yellow
            Install-Module PSWindowsUpdate -Force -Confirm:$false
        }

        Write-OutputBox "جاري تثبيت التحديثات..." -Color Yellow
        Add-WUServiceManager -MicrosoftUpdate -Confirm:$false
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -IgnoreUserInput | Out-File "C:\($env.computername-Get-Date -f yyyy-MM-dd)-MSUpdates.log" -Force
        Write-OutputBox "تم تثبيت التحديثات بنجاح ✓" -Color Green
    }
    catch {
        Write-OutputBox "خطأ: $_" -Color Red
    }
}

function WindowsAppUpdate {
    try {
        Write-OutputBox "جاري تحديث التطبيقات..." -Color Cyan
        Write-OutputBox $currentDrive -Color Cyan
        $env:Path += ";${currentDrive}\Programs Files\chocolatey\bin\Winget\AppInstaller_x64
        winget upgrade --all 
        Write-OutputBox "تم التحديث بنجاح ✓" -Color Green
    }
    catch {
        Write-OutputBox "خطأ: $_" -Color Red
    }
}

function WindowsActivate {
    try {
        Write-OutputBox "جاري تفعيل النظام..." -Color Cyan
        Invoke-RestMethod 'https://get.activated.win' | Invoke-Expression
        Write-OutputBox "تم التفعيل بنجاح ✓" -Color Green
    }
    catch {
        Write-OutputBox "خطأ: $_" -Color Red
    }
}

function InstallGraphicsDriver {
    try {
        $currentDrive = ($PWD.Path -split '\\')[0]
        $nvidia = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" }
        $amd = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -like "*AMD*" }

        if ($nvidia) {
            Write-OutputBox "جاري تثبيت درايفرات NVIDIA..." -Color Yellow
            Start-Process -FilePath "$currentDrive\Drivers\Nvidia\NVIDIA_app_v11.0.2.341.exe" -Wait -Verb RunAs
        }
        if ($amd) {
            Write-OutputBox "جاري تثبيت درايفرات AMD..." -Color Yellow
            Start-Process -FilePath "$currentDrive\Drivers\AMD\adrenalin-edition-25.3.1.exe" -Wait -Verb RunAs
        }
        
        Write-OutputBox "تم التثبيت بنجاح ✓" -Color Green
    }
    catch {
        Write-OutputBox "خطأ: $_" -Color Red
    }
}

function FixWindowsError {
    try {
        $commands = @(
            @{Name='فحص النظام (DISM)'; Command='dism /Online /Cleanup-Image /RestoreHealth'},
            @{Name='فحص الملفات (SFC)'; Command='sfc /scannow'},
            @{Name='إصلاح الشبكة'; Command='netsh winsock reset && netsh int ip reset'}
        )

        # إعداد شريط التقدم
        $globalProgress.Maximum = $commands.Count * 100
        $globalProgress.Value = 0
        $currentProgress = 0
        $lastProgressLine = $null

        foreach ($cmd in $commands) {
            Write-OutputBox "جاري: $($cmd.Name)..." -Color Cyan

            $job = Start-Job -ScriptBlock {
                param($command)
                & cmd /c $command *>&1
                "EXIT_CODE:$LASTEXITCODE"
            } -ArgumentList $cmd.Command

            $resultExitCode = $null
            $outputLines = @()

            while ($job.State -eq 'Running') {
                # تحديث التقدم
                $currentProgress = [Math]::Min($currentProgress + 1, ($commands.IndexOf($cmd) + 1) * 100)
                $globalProgress.Value = $currentProgress
                Start-Sleep -Milliseconds 100
                [System.Windows.Forms.Application]::DoEvents()

                # استقبال ومعالجة المخرجات
                $output = Receive-Job -Job $job
                if ($output) {
                    foreach ($line in $output) {
                        $cleanLine = $line -replace '[\u200E\u200F]', '' # إزالة Unicode controls
                        $trimmedLine = $cleanLine.Trim()

                        # 1. تجاهل الأسطر الفارغة تمامًا
                        if ([string]::IsNullOrWhiteSpace($trimmedLine)) { continue }

                        # 2. تصحيح التعبير النمطي لأسطر الوقت الفارغة
                        if ($trimmedLine -match '^\d{2}:\d{2}:\d{2} \| $') { continue }

                        # 3. التعامل مع خطوط sfc ذات المحتوى
                        if ($trimmedLine -match '^\d{2}:\d{2}:\d{2} \| (.+)') {
                            $content = $matches[1]
                            if (-not [string]::IsNullOrWhiteSpace($content)) {
                                Write-OutputBox $content -Color Gray
                                $outputLines += $content
                            }
                            continue
                        }

                        # 4. التعامل مع خطوط التقدم
                        if ($trimmedLine -match '(\d+\.\d+%)') {
                            if ($trimmedLine -ne $lastProgressLine) {
                                Write-OutputBox $trimmedLine -Color DarkCyan
                                $lastProgressLine = $trimmedLine
                            }
                        }
                        elseif ($trimmedLine -match '^EXIT_CODE:(\d+)$') {
                            $resultExitCode = $matches[1]
                        }
                        else {
                            Write-OutputBox $trimmedLine -Color Gray
                            $outputLines += $trimmedLine
                        }
                    }
                }
            }

            # معالجة المخرجات المتبقية بعد الانتهاء
            $output = Receive-Job -Job $job
            if ($output) {
                foreach ($line in $output) {
                    $cleanLine = $line -replace '[\u200E\u200F]', ''
                    $trimmedLine = $cleanLine.Trim()

                    if ([string]::IsNullOrWhiteSpace($trimmedLine)) { continue }
                    if ($trimmedLine -match '^\d{2}:\d{2}:\d{2} \| $') { continue }

                    if ($trimmedLine -match '^\d{2}:\d{2}:\d{2} \| (.+)') {
                        $content = $matches[1]
                        if (-not [string]::IsNullOrWhiteSpace($content)) {
                            Write-OutputBox $content -Color Gray
                            $outputLines += $content
                        }
                        continue
                    }

                    if ($trimmedLine -match '(\d+\.\d+%)') {
                        if ($trimmedLine -ne $lastProgressLine) {
                            Write-OutputBox $trimmedLine -Color DarkCyan
                            $lastProgressLine = $trimmedLine
                        }
                    }
                    elseif ($trimmedLine -match '^EXIT_CODE:(\d+)$') {
                        $resultExitCode = $matches[1]
                    }
                    else {
                        Write-OutputBox $trimmedLine -Color Gray
                        $outputLines += $trimmedLine
                    }
                }
            }

            # تحديد حالة التنفيذ
            if (-not $resultExitCode) { $resultExitCode = 1 }
            
            if ($resultExitCode -eq 0) {
                Write-OutputBox "$($cmd.Name) - اكتمل ✓" -Color Green
            } else {
                $errorMessage = $outputLines -join "`n"
                Write-OutputBox "$($cmd.Name) - فشل ❌ (الكود: $resultExitCode)`n$errorMessage" -Color Red
            }

            $globalProgress.Value = ($commands.IndexOf($cmd) + 1) * 100
            Remove-Job -Job $job -Force
        }

        # معالجة CHKDSK مع إعادة التشغيل
        $chkdskChoice = [System.Windows.Forms.MessageBox]::Show(
            "هل تريد تشغيل فحص القرص وإعادة التشغيل الآن؟",
            "فحص القرص",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($chkdskChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                $process = Start-Process cmd -ArgumentList "/c echo y | chkdsk C: /f /r" -PassThru -Wait
                if ($process.ExitCode -eq 0) {
                    Write-OutputBox "تم الجدولة ✓`nسيتم إعادة التشغيل خلال 5 ثواني ..." -Color Green
                    shutdown /r /t 5
                } else {
                    throw "فشل في الجدولة"
                }
            }
            catch {
                $retry = [System.Windows.Forms.MessageBox]::Show(
                    "فشل! هل تريد التشغيل كمدير؟",
                    "خطأ في الصلاحيات",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )

                if ($retry -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Start-Process cmd -ArgumentList "/c echo y | chkdsk C: /f /r & shutdown /r /t 5" -Verb RunAs
                    Write-OutputBox "تم التشغيل كمدير ✓`nالإعادة بعد 5 ثوانٍ..." -Color Yellow
                }
            }
        }
    }
    catch {
        Write-OutputBox "خطأ جسيم: $($_.Exception.Message)" -Color Red
    }
    finally {
        $globalProgress.Value = 0
    }
}

function WindowsTweaks {
    try {
        $originalSize = $form.Size
        $originalLocation = $form.Location
        $originalFont = $form.Font

        Write-OutputBox "جاري تحسين إعدادات النظام..." -Color Cyan
        
        Start-Process -FilePath "powershell" `
            -ArgumentList "-Command & { iwr https://christitus.com/win | iex }" `
            -Wait -WindowStyle Hidden | Out-Null

        $form.Size = $originalSize
        $form.Location = $originalLocation
        $form.Font = $originalFont
        $form.PerformLayout()
        $form.Refresh()

        Write-OutputBox "تم التحسين بنجاح ✓" -Color Green
    }
    catch {
        Write-OutputBox "خطأ: $_" -Color Red
    }
}

function RestorePoint {
    try {
        Write-OutputBox "جاري إنشاء نقطة استعادة..." -Color Cyan
        Checkpoint-Computer -Description "ZhanTool-RestorePoint" -RestorePointType "MODIFY_SETTINGS"
        Write-OutputBox "تم الإنشاء بنجاح ✓" -Color Green
    }
    catch {
        Write-OutputBox "خطأ: $_" -Color Red
    }
}

# ----------- دالة التبديل بين النوافذ -----------
# ----- عرض شاشة التحميل -----
# عدم استخدام المزامنة هنا، فقط عرض الشاشة
$splashForm.Show()
[System.Windows.Forms.Application]::DoEvents() # ضمان تحديث الواجهة

# ----- الانتظار 3 ثوان بطريقة لا تؤثر على الواجهة -----
$startTime = Get-Date
do {
    [System.Windows.Forms.Application]::DoEvents() # السماح بتحديث واجهة المستخدم
    Start-Sleep -Milliseconds 50 # انتظار قصير للحفاظ على استجابة النظام
} until ((Get-Date).Subtract($startTime).TotalSeconds -ge 3)

# ----- إغلاق شاشة التحميل -----
$splashForm.Close()
$splashForm.Dispose() # تحرير الموارد

# ----- عرض النافذة الرئيسية -----
# هنا يجب التأكد أن النافذة الرئيسية معرفة مسبقًا
# يمكنك استخدام ShowDialog() لعرض النافذة الرئيسية
$form.ShowDialog()
