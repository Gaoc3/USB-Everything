# Import the necessary .NET assemblies for WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Define the XAML for the WPF window
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="USB Lock" Height="300" Width="500" WindowStartupLocation="CenterScreen" Background="#2C2F33" ResizeMode="CanMinimize">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/> <ColumnDefinition Width="*"/>    <ColumnDefinition Width="Auto"/> </Grid.ColumnDefinitions>

        <TextBlock Text="USB Lock Tool" Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="3"
                   FontSize="24" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center" Margin="10"/>

        <TextBlock Text="Select USB Drive:" Grid.Row="1" Grid.Column="0" Margin="10,0,5,0" VerticalAlignment="Center" Foreground="#CCCCCC"/>

        <Border Grid.Row="1" Grid.Column="1" CornerRadius="15" Background="#000000" BorderBrush="#555555" BorderThickness="1" Height="30" VerticalAlignment="Center" Margin="0,0,5,0">
            <ComboBox Name="DriveListComboBox" Background="Transparent" Foreground="#000000" BorderThickness="0"/>
        </Border>

        <Button Name="RefreshButton" Content="🔄" Grid.Row="1" Grid.Column="2"
                Width="30" Height="30" VerticalAlignment="Center" Margin="0,0,10,0" ToolTip="Refresh Drive List" Background="#555555" Foreground="White" BorderThickness="0">
             <Button.Style>
                <Style TargetType="Button">
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}" CornerRadius="15">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                    <Style.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Background" Value="#0078D7"/>
                            <Setter Property="Cursor" Value="Hand"/>
                        </Trigger>
                    </Style.Triggers>
                </Style>
            </Button.Style>
        </Button>

        <Button Name="LockButton" Content="Lock USB" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="3"
                Margin="10" Width="150" Height="40" HorizontalAlignment="Center" Background="#0078D7" Foreground="White" FontWeight="Bold" FontSize="14">
            <Button.Style>
                <Style TargetType="Button">
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}" CornerRadius="20" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                    <Setter Property="Background" Value="#0078D7"/>
                    <Setter Property="Foreground" Value="White"/>
                    <Style.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Background" Value="#FF4500"/>
                            <Setter Property="Foreground" Value="#FFFFFF"/>
                            <Setter Property="Cursor" Value="Hand"/>
                        </Trigger>
                    </Style.Triggers>
                </Style>
            </Button.Style>
        </Button>

        <StackPanel Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="3" HorizontalAlignment="Center" Margin="10">
            <TextBlock Text="© Sajad Tech" FontSize="12" Foreground="#AAAAAA" HorizontalAlignment="Center" FontStyle="Italic"/>
            <TextBlock Text="Crafted with precision and care" FontSize="10" Foreground="#888888" HorizontalAlignment="Center"/>
        </StackPanel>
    </Grid>
</Window>
"@

# Parse the XAML and create the WPF window
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get the controls from the XAML
$driveListComboBox = $window.FindName("DriveListComboBox")
$lockButton = $window.FindName("LockButton")
$refreshButton = $window.FindName("RefreshButton")

# --- START: Function to Generate Hash ---
# (اسم الدالة هنا يبقى كما هو في هذا السكربت المحدد)
function Generate-Hash {
    param (
        [string]$InputString
    )
    # Added check for null/empty input
    if ([string]::IsNullOrWhiteSpace($InputString)) { return $null }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hashBytes = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes) -replace '-'
}
# --- END: Function to Generate Hash ---

# --- START: Updated Function to populate/refresh the ComboBox ---
function Update-DriveList {
    $driveListComboBox.Items.Clear()
    $usbDrives = Get-WmiObject Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" }

    foreach ($drive in $usbDrives) {
        $partitions = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($drive.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
        foreach ($partition in $partitions) {
            $logicalDisks = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition"
            foreach ($logicalDisk in $logicalDisks) {
                $serial = $drive.SerialNumber.Trim()
                $logicalDiskId = $logicalDisk.DeviceID # Get the drive letter (e.g., "E:")
                if (-not [string]::IsNullOrWhiteSpace($serial) -and -not [string]::IsNullOrWhiteSpace($logicalDiskId)) {
                    $driveListComboBox.Items.Add([PSCustomObject]@{
                        Display     = "$logicalDiskId - $($drive.Model)"
                        Serial      = $serial
                        DriveLetter = $logicalDiskId
                    })
                }
            }
        }
    }

    $driveListComboBox.DisplayMemberPath = "Display"
    $driveListComboBox.SelectedValuePath = "Serial"

     if ($driveListComboBox.Items.Count -gt 0 -and $driveListComboBox.SelectedIndex -eq -1) {
        $driveListComboBox.SelectedIndex = 0
    }
}
# --- END: Updated Function to populate/refresh the ComboBox ---

# Populate the ComboBox initially when the window loads
Update-DriveList

# Add Click Event for Refresh Button
$refreshButton.Add_Click({
    Update-DriveList
})

# --- START: Updated Lock Button Click Event ---
$lockButton.Add_Click({
    $selectedItem = $driveListComboBox.SelectedItem

    if ($null -ne $selectedItem -and $selectedItem.PSObject.Properties['Serial'] -and $selectedItem.PSObject.Properties['DriveLetter']) {
        $currentSerialNumber = $selectedItem.Serial
        $selectedDriveLetter = $selectedItem.DriveLetter

        if ([string]::IsNullOrWhiteSpace($currentSerialNumber)) {
             Show-Notification "لا يمكن قراءة الرقم التسلسلي للفلاشة المختارة" "Error"
             return
        }
        if ([string]::IsNullOrWhiteSpace($selectedDriveLetter)) {
             Show-Notification "لا يمكن تحديد حرف القرص للفلاشة المختارة" "Error"
             return
        }

        # --- START: Use names consistent with the previous script ---
        $dataPath = Join-Path -Path $selectedDriveLetter -ChildPath "indexes\pakage"   # Changed directory name
        $dataFileName = "aGlkZGVuX2ZpbGUudHh0.bin" # Changed filename and extension
        # --- END: Use names consistent with the previous script ---

        if (-not (Test-Path $selectedDriveLetter)) {
             Show-Notification "لا يمكن الوصول إلى القرص المختار: $selectedDriveLetter" "Error"
             return
        }

        # Ensure the directory exists on the selected drive
        if (-not (Test-Path $dataPath)) { # Use updated variable $dataPath
            try {
                 New-Item -ItemType Directory -Path $dataPath -Force -ErrorAction Stop | Out-Null # Use updated variable $dataPath
            } catch {
                 Show-Notification "فشل إنشاء مجلد البيانات على '$selectedDriveLetter`: $($_.Exception.Message)" "Error" # Updated message
                 return
            }
        }

        # Define the full file path on the selected drive
        $dataFilePath = Join-Path -Path $dataPath -ChildPath $dataFileName # Use updated variables

        # Generate hash for the selected drive's serial number
        $currentHash = Generate-Hash -InputString $currentSerialNumber

        # Check if the file exists *on the selected drive* and if the hash matches
        if (Test-Path $dataFilePath) { # Use updated variable $dataFilePath
            try {
                $storedHash = Get-Content -Path $dataFilePath -ErrorAction Stop # Use updated variable $dataFilePath
                # Added Trim() for safety when comparing hash read from file
                if ($storedHash.Trim() -eq $currentHash) {
                    Show-Notification "الفلاشة هذه مقفلة بالفعل" "Error"
                    return
                }
            } catch {
                 Show-Notification "فشل قراءة ملف البيانات من '$selectedDriveLetter`: $($_.Exception.Message)" "Error" # Updated message
                 return
            }
        }

        # Lock the selected drive: Create/Update the file *on the selected drive*
        try {
            if (-not (Test-Path $dataFilePath)) { # Use updated variable $dataFilePath
                 New-Item -ItemType File -Path $dataFilePath -Force -ErrorAction Stop | Out-Null # Use updated variable $dataFilePath
            }
            # Set content (hash) into the file
            Set-Content -Path $dataFilePath -Value $currentHash -ErrorAction Stop -NoNewline # Use updated variable $dataFilePath, -NoNewline is often good for hash files
            # NOTE: Hidden attribute is not set for .bin file, but could be added if desired:
            # (Get-Item $dataFilePath -ErrorAction Stop).Attributes = 'Hidden'

            Show-Notification "تم قفل الفلاشة $selectedDriveLetter" "Success"
        } catch {
             Show-Notification "فشل قفل الفلاش '$selectedDriveLetter`: $($_.Exception.Message)" "Error"
        }

    } else {
        Show-Notification "الرجاء تحديد فلاشة صالحة أولاً" "Error"
    }
})
# --- END: Updated Lock Button Click Event ---

# Show-Notification Function (remains the same)
function Show-Notification {
    param (
        [string]$Message,
        [string]$Type
    )
    $notificationXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Notification" Height="150" Width="300" WindowStartupLocation="CenterScreen" Background="Black" WindowStyle="None" ResizeMode="NoResize" Topmost="True">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="$Message" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="16" FontWeight="Bold" Foreground="White" Grid.Row="0" TextWrapping="Wrap"/>
        <Button Name="CloseButton" Content="إغلاق" Width="80" Height="30" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,10,0,10" Grid.Row="1"
                Background="#FF4500" Foreground="White" FontWeight="Bold" Cursor="Hand">
            <Button.Style>
                <Style TargetType="Button">
                    <Setter Property="Background" Value="#FF4500"/>
                    <Setter Property="Foreground" Value="White"/>
                     <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="{x:Type Button}">
                                <Border Background="{TemplateBinding Background}" CornerRadius="5">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                    <Style.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Background" Value="#C0392B"/>
                        </Trigger>
                    </Style.Triggers>
                </Style>
            </Button.Style>
        </Button>
    </Grid>
</Window>
"@
    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$notificationXaml)
        $notificationWindow = [Windows.Markup.XamlReader]::Load($reader)
        if ($null -eq $notificationWindow) { Write-Error "Failed to initialize notification window."; return }
        $closeButton = $notificationWindow.FindName("CloseButton")
        if ($null -eq $closeButton) { Write-Error "Failed to find CloseButton."; return }
        $closeButton.Add_Click({ $notificationWindow.Close() })
        $notificationWindow.ShowDialog() | Out-Null
    } catch {
        Write-Error "Error displaying notification: $_"
        Write-Host "NOTIFICATION [$Type]: $Message" -ForegroundColor Yellow # Fallback console notification
    }
}

# Show the WPF window
$window.ShowDialog() | Out-Null