Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework

function DefaultSavePath {
    # 使用者預設的 LocalLow 目錄路徑
    param (
        [string]$ChildPath
    )

    $Path = Join-Path "$($env:LOCALAPPDATA)Low" $ChildPath
    return $Path # 不做路徑檢查
}

function UpperPath {
    param (
        [string]$CurrentPath
    )

    $Path = Split-Path $CurrentPath
    return $Path
}

function CopyFile {
    param (
        [string]$Source,
        [string]$Target
    )

    if (-not(Test-Path $Target)) {
        New-Item $Target -ItemType Directory -Force
    }

    Copy-Item $Source $Target -Recurse -Container -Force
}

function Main {
    # 主要運行邏輯
    param (
        [string]$BackUpPath, # 調用的運行路徑 (備份存檔點)
        [string]$SavePath # 存檔的文件所在路徑 (輸出存檔點)
    )

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="遊戲存檔備份工具"
        WindowStartupLocation="CenterScreen"
        SizeToContent="WidthAndHeight"
        ResizeMode="CanResize"
        Background="#2B2B2B"
        Foreground="#A9B7C6"
        FontFamily="Microsoft JhengHei UI"
        MinWidth="550">
    <Window.Resources>
        <!-- Style for the main action buttons -->
        <Style TargetType="Button" x:Key="ActionButton">
            <Setter Property="Background" Value="#008080"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="10"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="MinWidth" Value="130"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#009696"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Style for the folder icon buttons -->
        <Style TargetType="Button" x:Key="FolderButton" BasedOn="{StaticResource ActionButton}">
             <Setter Property="Background" Value="#3C3F41"/>
             <Setter Property="Width" Value="40"/>
             <Setter Property="MinWidth" Value="40"/>
             <Setter Property="FontSize" Value="14"/>
             <Setter Property="Margin" Value="0"/>
             <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="0,5,5,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
             <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#4E5254"/>
                </Trigger>
            </Style.Triggers>
        </Style>

    </Window.Resources>

    <StackPanel Margin="20">
        
        <!-- Backup Path Input -->
        <TextBlock Text="備份路徑:" FontWeight="Bold" FontSize="16" Margin="0,0,0,5"/>
        <Border BorderBrush="#3C3F41" BorderThickness="1" CornerRadius="5" Background="#3C3F41">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox Grid.Column="0" Text="$BackUpPath" IsReadOnly="True" Background="Transparent" BorderThickness="0" Padding="8,6" VerticalContentAlignment="Center" FontSize="16" FontWeight="Bold" Foreground="{Binding RelativeSource={RelativeSource AncestorType=Window}, Path=Foreground}"/>
                <Button Grid.Column="1" Name="OpenBackUpPath" Content="📁" Style="{StaticResource FolderButton}"/>
            </Grid>
        </Border>

        <!-- Save Path Input -->
        <TextBlock Text="存檔路徑:" FontWeight="Bold" FontSize="16" Margin="0,15,0,5"/>
        <Border BorderBrush="#3C3F41" BorderThickness="1" CornerRadius="5" Background="#3C3F41">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox Grid.Column="0" Text="$SavePath" IsReadOnly="True" Background="Transparent" BorderThickness="0" Padding="8,6" VerticalContentAlignment="Center" FontSize="16" FontWeight="Bold" Foreground="{Binding RelativeSource={RelativeSource AncestorType=Window}, Path=Foreground}"/>
                <Button Grid.Column="1" Name="OpenSavePath" Content="📁" Style="{StaticResource FolderButton}"/>
            </Grid>
        </Border>

        <!-- Main Action Buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,25,0,0">
            <Button Name="BackupSave" Content="備份存檔" Style="{StaticResource ActionButton}"/>
            <Button Name="RestoreSave" Content="恢復存檔" Style="{StaticResource ActionButton}"/>
        </StackPanel>

    </StackPanel>
</Window>
"@

    $reader = New-Object System.IO.StringReader($xaml)
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)

    

    $BackUpParent = Split-Path $BackUpPath
    function BackUpErrorShow {
        [System.Windows.Forms.MessageBox]::Show("路徑錯誤", "找不到存檔相關路徑", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    $window.FindName("OpenBackUpPath").Add_Click({
            if (Test-Path $BackUpParent) { Start-Process $BackUpParent } else { BackUpErrorShow }
        })
    $window.FindName("BackupSave").Add_Click({
            if (Test-Path $SavePath) {
                # 刪除 Player.log, Player-prev.log
                Get-ChildItem -Path $SavePath -Include "Player.log", "Player-prev.log" -File -Recurse | ForEach-Object {
                    try { Remove-Item -Path $_.FullName -Force -ErrorAction Stop } catch {}
                }
            
                CopyFile $SavePath $BackUpParent
                $expectedBackupPath = Join-Path $BackUpParent (Split-Path $SavePath -Leaf)
                if (Test-Path $expectedBackupPath) {
                    [System.Windows.Forms.MessageBox]::Show("備份成功", "操作提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                }
                else {
                    BackUpErrorShow
                }
            }
            else {
                BackUpErrorShow
            }
        })

    $SaveParent = Split-Path $SavePath
    function SaveErrorShow {
        [System.Windows.Forms.MessageBox]::Show("路徑錯誤", "找不到備份相關路徑", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    $window.FindName("OpenSavePath").Add_Click({
            if (Test-Path $SaveParent) { Start-Process $SaveParent } else { SaveErrorShow }
        })
    $window.FindName("RestoreSave").Add_Click({
            if (Test-Path $BackUpPath) {
                CopyFile $BackUpPath $SaveParent
                if (Test-Path $SavePath) {
                    [System.Windows.Forms.MessageBox]::Show("恢復成功", "操作提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                }
                else {
                    SaveErrorShow
                }
            }
            else {
                SaveErrorShow
            }
        })

    try {
        $window.ShowDialog()
    }
    finally {
        $window.Close()
    }
}