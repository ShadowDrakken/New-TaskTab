param (
    [parameter(Mandatory=$true)]
    [string]$TaskName,

    [parameter(Mandatory=$true)]
    [Alias('cn','fqdn')]
    [string]$ComputerName
    )

# ThreadJob allows parallel access to variables as well as ByRef style access with $using:
if (-not (Get-Module -ListAvailable -Name 'ThreadJob')) {
    Install-Module -Name 'ThreadJob' -Force
}

$BaseName = (Get-Item $PSCommandPath).BaseName
$NewTab   = $psISE.PowerShellTabs.Add()

[array]$TabVariables = @(
    @{Name='TaskName';  Value=$TaskName}
    @{Name='cn';        Value=$ComputerName}
    )

# Heredoc + {} is a nifty trick to pass variables into a scriptblock that will be used with Invoke()
$TabInvoke = @"
    $($i=0; $TabVariables | % { "`$$($_.Name) = '$($_.Value)'; (Get-Variable '$($_.Name)').Description = 'New-TaskTab $i'`n";$i++ }; Remove-Variable 'i')

    $((Get-Content ".\$BaseName`.func.ps1" -Raw -ErrorAction SilentlyContinue) -replace '`$','``$')
"@ + {
    $Tab = $psISE.CurrentPowerShellTab

    # Registers handlers to remove background update threads when the tab is closed
    Register-EngineEvent PowerShell.Exiting -SupportEvent -Action {
        Get-Job -Name "$TaskName`:$cn" | Stop-Job

        While ((Get-Job -Name "$TaskName`:$cn").State -ne 'Stopped') {
            sleep -s 1
        }

        Get-Job -Name "$TaskName`:$cn" | Remove-Job
    }

    # Background update thread
    Start-ThreadJob -ThrottleLimit 100 -Name "$TaskName`:$cn" -ArgumentList $Host `
        -InitializationScript {
            # Replaces Write-Host because -StreamingHost is broken
            function WriteLine {
                param (
                    [parameter(Position=0)]
                    [string]$Text = $null,
                    [System.ConsoleColor]$ForegroundColor = $Console.UI.RawUI.ForegroundColor,
                    [System.ConsoleColor]$BackgroundColor = $Console.UI.RawUI.BackgroundColor
                    )

                $Console.UI.WriteLine($ForegroundColor, $BackgroundColor, $Text)
            }

            # Replaces Write-Host -NoNewLine because -StreamingHost is broken
            function Write {
                param (
                    [parameter(Position=0)]
                    [string]$Text = $null,
                    [System.ConsoleColor]$ForegroundColor = $Console.UI.RawUI.ForegroundColor,
                    [System.ConsoleColor]$BackgroundColor = $Console.UI.RawUI.BackgroundColor
                    )

                $Console.UI.Write($ForegroundColor, $BackgroundColor, $Text)
            }

            <# Currently not working
            # Sets the user's prompt back after custom writes
            function ResetPrompt {
                WriteLine
                Write $Tab.Prompt
            }
            #>

            # Checks if the system is online
            function IsOnline {
                try {
                    $ipv4 = (Resolve-DnsName $ComputerName -Type A | ? IPAddress -notmatch '^192[.]168[.]' )[0].IPAddress
                } catch {
                    $global:ip = 'IP Not Resolved'
                    return $false
                }

                try {
                    $reverse = (Resolve-DnsName $ipv4).NameHost

                    if ($reverse.split('.')[0] -eq $ComputerName.split('.')[0]) {
                        $global:ip = $ipv4
                    } else {
                        $global:ip = "$ipv4 (Resolves to '$($reverse.split('.')[0])')"
                    }
                } catch {
                    $global:ip = $ipv4
                }

                if ((Test-Connection $global:ip -Count 1 -ErrorAction SilentlyContinue) `
                    -or ($ComputerName -match "^$(Invoke-command $ComputerName {$env:COMPUTERNAME} -ErrorAction SilentlyContinue)[.]")) {
                    return $true
                }

                return $false
            }

            # Updates the Tab.DisplayName
            function UpdateDisplayName {
                # Update every 1 seconds
                if (((Get-Date -UFormat %s) - 1) -lt $global:smDisplayName) { return }

                if ($Tab.CanInvoke) {
                    $Busy = ''
                } else {
                    $Busy = '⏳'
                }

                [string]$UD = switch ($global:OnlineState) {
                    $true {'⚪'} #+ " $global:Timestamp"}
                    $false {'⚫'} #+ " $global:Timestamp"}
                    default {'🔴'}
                    }

                $Tab.DisplayName = "$TaskName $UD`n$ComputerName $Busy`n$global:ip"

                $global:smDisplayName = Get-Date -UFormat %s
            }

            function UpdateOnlineState {
                # Update every 60 seconds
                if (((Get-Date -UFormat %s) - 60) -lt $global:smOnline) { return }

                $global:LastState   = $global:OnlineState
                $global:OnlineState = IsOnline

                if (($Tab.CanInvoke) -and ($global:OnlineState -ne $global:LastState) -and ($global:LastState -ne $null)) {
                    $global:Timestamp = (Get-Date).ToString("dd-MMM hh:mm:ss tt")

                    <#
                    switch ($global:OnlineState) {
                        $true { WriteLine "[$global:Timestamp] $ComputerName has come online" -ForegroundColor Green }
                        $false { WriteLine "[$global:Timestamp] $ComputerName has gone offline" -ForegroundColor Red }
                    }
                    #>

                    #ResetPrompt
                }

                $global:smOnline = Get-Date -UFormat %s
            }
        } `
        -ScriptBlock {
            param (
                $Console
                )

            $TaskName     = $using:TaskName
            $ComputerName = $using:cn
            $Tab          = $using:Tab

            #Watch for systems to come online or go offline
            while ($true) {
                UpdateOnlineState
                UpdateDisplayName

                #WriteLine 'Ping? Pong!'
                #ResetPrompt

                sleep -m 200
            }
        }

    cls # Make it a pretty new screen after dumping all the stuff above
    if ($Error) {
        Write-Host $Error -ForegroundColor Red
    }
    sleep -milliseconds 100 # Color won't show up if we don't wait first

    [array]$MyVars = Get-Variable | ? Description -match '^New-TaskTab ' | sort Description
    $Length = ($MyVars.Name | Measure-Object -Property Length -Maximum).Maximum
    if ($MyVars) {
        Write-Host "Registered Variables:" -ForegroundColor Yellow
        $MyVars | % {
            Write-Host "- `$$($_.Name.PadRight($Length)) = $($_.Value -join ', ')" -ForegroundColor Cyan
        }
    }
    [array]$MyFuncs = Get-ChildItem function:\ | ? {$_.Name -notmatch '(:|\\|/|\.)$' -and $_.CommandType -eq 'Function'} | ? {(Get-Help $_.Name).Functionality -eq 'New-TaskTab.func'} | sort Name
    $Length = ($MyFuncs.Name | Measure-Object -Property Length -Maximum).Maximum
    if ($MyFuncs) {
        Write-Host "Registered Functions:" -ForegroundColor Yellow
        $MyFuncs | % {
            Write-Host "- $($_.Name.PadRight($Length)) -> $((Get-Help $_.Name).Synopsis)" -ForegroundColor Cyan
        }
    }
}

# Wait for the tab to be fully constructed before attempting to use it
while ((-not $NewTab.CanInvoke) -or ($NewTab.StatusText -ne '')) {
    sleep -Milliseconds 100
}

# Send the default variable and background job to the tab
$NewTab.Invoke($TabInvoke)
