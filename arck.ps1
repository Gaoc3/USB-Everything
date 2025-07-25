Add-Type -AssemblyName PresentationFramework
$currentDrive = ($PWD.Path -split '\\')[0]

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Stop' # Keep this to catch errors early

# Determine current drive (less reliable than $PSScriptRoot used later)
# $currentDrive = ($PWD.Path -split '\\')[0] # This line seems less relevant now as $scriptDrive is used later
# $env:Path += ";${currentDrive}\Programs Files\chocolatey\bin\Winget\AppInstaller_x64_stub" # Be cautious modifying system Path

#Requires -RunAsAdministrator
# Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force # Consider if truly needed, RunAsAdmin might suffice
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


# --- إظهار نافذة الخطأ أو السماح للسكربت بالاستمرار ---
if ($showErrorWindow) {
    # (WinForms Error Window code remains the same as provided)
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

# إذا وصل السكربت إلى هنا، فالتحقق نجح
# الكود الرئيسي للسكربت يأتي هنا
# ...

# الكود الرئيسي للسكربت يأتي هنا إذا نجح التحقق
# ...

# Create the XAML for the GUI with smooth rounded corners, close button, and media player
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="سجاد التقني" Height="450" Width="700" 
        Background="Transparent" WindowStartupLocation="CenterScreen" 
        WindowStyle="None" AllowsTransparency="True"
        Icon="${currentDrive}\الأدوات\source\iconlun.ico">
    <Border Background="#2C3E50" CornerRadius="20" Padding="0" BorderBrush="#1ABC9C" BorderThickness="2">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="60"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Top Bar with Close Button -->
            <Border Grid.Row="0" Background="#34495E" CornerRadius="20,20,0,0" ClipToBounds="True" Name="TopBar">
                <Grid>
                    <TextBlock Text="سجاد التقني 🚀" 
                               HorizontalAlignment="Center" VerticalAlignment="Center" 
                               FontSize="24" FontWeight="Bold" Foreground="#ECF0F1"/>

                    <Button Content="✖" Name="CloseButton"
                            Width="30" Height="30"
                            Background="Transparent" Foreground="White"
                            BorderBrush="Transparent" FontWeight="Bold"
                            FontSize="14" HorizontalAlignment="Right"
                            VerticalAlignment="Top" Margin="0,5,5,0"
                            Cursor="Hand">
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Background" Value="Transparent"/>
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Background="{TemplateBinding Background}" 
                                                    CornerRadius="5" Padding="5">
                                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter Property="Background" Value="#E74C3C"/>
                                                </Trigger>
                                                <Trigger Property="IsPressed" Value="True">
                                                    <Setter Property="Background" Value="#C0392B"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                </Grid>
            </Border>

            <!-- Buttons Section -->
            <StackPanel Grid.Row="1" VerticalAlignment="Center" HorizontalAlignment="Center" Orientation="Vertical">
                <Button Content="تحميل البرامج" Name="InstallCenterButton"
                        Width="280" Height="60"
                        Background="#3498DB" Foreground="White"
                        FontSize="18" FontWeight="Bold" 
                        BorderBrush="#2980B9" BorderThickness="2"
                        Cursor="Hand" Padding="10" Margin="0,10"
                        HorizontalAlignment="Center">
                    <Button.Effect>
                        <DropShadowEffect BlurRadius="10" Direction="270" ShadowDepth="4" Color="Black"/>
                    </Button.Effect>
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="15" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>

                <Button Content="تفعيل و تحديث الويندوز" Name="WindowsOptimizerButton"
                        Width="280" Height="60"
                        Background="#2ECC71" Foreground="White"
                        FontSize="18" FontWeight="Bold" 
                        BorderBrush="#27AE60" BorderThickness="2"
                        Cursor="Hand" Padding="10" Margin="0,10"
                        HorizontalAlignment="Center">
                    <Button.Effect>
                        <DropShadowEffect BlurRadius="10" Direction="270" ShadowDepth="4" Color="Black"/>
                    </Button.Effect>
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="15" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>

                <Button Content="التعاريف" Name="SDIButton"
                        Width="280" Height="60"
                        Background="#E74C3C" Foreground="White"
                        FontSize="18" FontWeight="Bold" 
                        BorderBrush="#C0392B" BorderThickness="2"
                        Cursor="Hand" Padding="10" Margin="0,10"
                        HorizontalAlignment="Center">
                    <Button.Effect>
                        <DropShadowEffect BlurRadius="10" Direction="270" ShadowDepth="4" Color="Black"/>
                    </Button.Effect>
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="15" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </StackPanel>

            <!-- Media Player Section (Added small media player in the bottom right corner) -->
            <MediaElement Name="MediaPlayer" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="200" Height="50" Margin="0,0,10,10" Opacity="0.7" LoadedBehavior="Manual" UnloadedBehavior="Manual"/>
        </Grid>
    </Border>
</Window>
"@

# Load the XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get UI elements
$InstallCenterButton = $window.FindName("InstallCenterButton")
$WindowsOptimizerButton = $window.FindName("WindowsOptimizerButton")
$SDIButton = $window.FindName("SDIButton")
$TopBar = $window.FindName("TopBar")
$CloseButton = $window.FindName("CloseButton")


# Ensure buttons have their default colors on startup
$InstallCenterButton.Background = [System.Windows.Media.Brushes]::Blue
$WindowsOptimizerButton.Background = [System.Windows.Media.Brushes]::Green
$SDIButton.Background = [System.Windows.Media.Brushes]::Red

# Button Actions
$InstallCenterButton.Add_Click({
    Start-Process "${currentDrive}\الأدوات\Install Center.exe"
})

$WindowsOptimizerButton.Add_Click({
    Start-Process "${currentDrive}\الأدوات\Windows optmizer.exe"
})

# Update SDI launch to include the correct working directory
$SDIButton.Add_Click({
    Start-Process "${currentDrive}\الأدوات\التعاريف\SDI_x64.exe" -WorkingDirectory "${currentDrive}\الأدوات\التعاريف"
})

# Fix hover effect to ensure buttons return to their original colors after mouse leave
$InstallCenterButton.Add_MouseEnter({
    $InstallCenterButton.Background = [System.Windows.Media.Brushes]::DodgerBlue
})
$InstallCenterButton.Add_MouseLeave({
    $InstallCenterButton.Background = [System.Windows.Media.Brushes]::Blue
})

$WindowsOptimizerButton.Add_MouseEnter({
    $WindowsOptimizerButton.Background = [System.Windows.Media.Brushes]::SeaGreen
})
$WindowsOptimizerButton.Add_MouseLeave({
    $WindowsOptimizerButton.Background = [System.Windows.Media.Brushes]::Green
})

$SDIButton.Add_MouseEnter({
    $SDIButton.Background = [System.Windows.Media.Brushes]::IndianRed
})
$SDIButton.Add_MouseLeave({
    $SDIButton.Background = [System.Windows.Media.Brushes]::Red
})

# Ensure the top bar is properly defined and draggable
$TopBar = $window.FindName("TopBar")
# Add drag functionality to the top bar
$TopBar.Add_MouseLeftButtonDown({
    $window.DragMove()
})

# Close window from button
$CloseButton.Add_Click({
    $window.Close()
})

# Show the window
$window.ShowDialog() | Out-Null
