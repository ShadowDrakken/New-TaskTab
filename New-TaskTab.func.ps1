function Clear-CcmCache {
    <#
    .SYNOPSIS
        Clears CcmClient cache by invoking CcmClient cleanup

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Clears CcmClient cache by invoking CcmClient cleanup
    #>

    Invoke-Command $cn {
        $resman    = New-Object -ComObject "UIResource.UIResourceMgr"
        $cacheInfo = $resman.GetCacheInfo()
        $cacheinfo.GetCacheElements() | foreach {$cacheInfo.DeleteCacheElement($_.CacheElementID)}

        del "$env:SystemRoot\ccmcache\*" -Force -Recurse

        $resman    = New-Object -ComObject "UIResource.UIResourceMgr"
        $cacheInfo = $resman.GetCacheInfo()
        $cacheinfo.GetCacheElements() | foreach {$cacheInfo.DeleteCacheElement($_.CacheElementID)}

        dir "$env:SystemRoot\ccmcache\"
    }
}

function Invoke-CcmClientAction {
    <#
    .SYNOPSIS
        Runs CcmClient management actions (policy download, application scan, etc)

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Runs CcmClient management actions (policy download, application scan, etc)
    #>
    Invoke-Command $cn {
        enum CCMActions {
            MachinePolicyRetrievalAndEval    = '21'
            MachinePolicyEval                = '22'
            DiscoveryDataCollection          = '3'
            SoftwareInventoryCycle           = '2'
            HardwareInventoryCycle           = '1'
            SoftwareUpdateScan               = '113'
            SoftwareUpdateDeploymentEval     = '114'
            SoftwareMeteringUsageReport      = '31'
            ApplicationDeploymentCycle       = '121'
            UserPolicyRetrieval              = '26'
            UserPolicyEval                   = '27'
            WindowsInstallerSourceListUpdate = '32'
            FileCollection                   = '10'
        }

        function Invoke-CCMClientAction {
            param (
                [parameter(Mandatory=$true)]
                [CCMActions[]]$CCMAction
                )

            foreach ($action in $CCMAction) {
                Invoke-WmiMethod -Namespace root\ccm -Class sms_client -Name TriggerSchedule "{00000000-0000-0000-0000-$($action.value__.ToString().PadLeft(12,'0'))}"
            }
        }

        Invoke-CCMClientAction MachinePolicyRetrievalAndEval,HardwareInventoryCycle,SoftwareInventoryCycle,SoftwareUpdateScan,SoftwareUpdateDeploymentEval,ApplicationDeploymentCycle
    }
}

function Get-BitsStatus {
    <#
    .SYNOPSIS
        Get status of BITS downloads

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Get status of BITS downloads
    #>

    Invoke-Command $cn { bitsadmin /list /allusers }
}

function Get-CcmCache {
    <#
    .SYNOPSIS
        Shows CcmCache location

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Shows CcmCache location
    #>

    Invoke-Command $cn { "$env:SystemRoot\ccmcache\" }
}

function Get-CcmCacheContent {
    <#
    .SYNOPSIS
        Shows top level content of CcmCache

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Shows top level content of CcmCache
    #>

    Invoke-Command $cn { dir "$env:SystemRoot\ccmcache\" -Depth 1 }
}

function Get-MeteredStatus {
    <#
    .SYNOPSIS
        Shows all WLAN metered connection status

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Shows all WLAN metered connection status
    #>

    Invoke-Command $cn {
        [array]$WlanProfiles = netsh wlan show profiles |
            ? {$_ -match '^\s+All User Profile\s+: '} |
            % {($_ -split ':',2)[1].trim()}

            [array]$Connections = @()
            $WlanProfiles | % {
                $Cost = netsh wlan show profile name="$_" |
                        ? {$_ -match '^\s+(Cost)\s+: '} |
                        % {($_ -split ':',2)[1].trim()}
                $Connections += [PSCustomObject]@{Name=$_; Cost=$Cost}
            }

            $Connections
        } | select Name,Cost
}

function Set-MeteredStatus {
    <#
    .SYNOPSIS
        Sets the WLAN metered connection type

    .FUNCTIONALITY
        New-TaskTab.func

    .DESCRIPTION
        Sets the WLAN metered connection type
    #>

    param (
        [parameter(Mandatory=$true)]
        [string[]]$Name,
        [parameter(Mandatory=$true,ParameterSetName='Metered')]
        [switch]$Metered,
        [parameter(Mandatory=$true,ParameterSetName='Unmetered')]
        [switch]$Unmetered
        )

    if ($Metered) { $Cost = 'Fixed' }
    elseif ($Unmetered) { $Cost = 'Unrestricted' }
    else { return }

    Invoke-Command $cn {
        param ([string[]]$profile, [string]$cost)

        $profile | % {
            $Status = netsh wlan show profile name="$profile"

            if ($Status -match "Profile `"$profile`" is not found on the system.") {
                $Status
            } else {
                netsh wlan set profileparameter name="$profile" cost=$cost
            }
        }
    } -Args $Name,$Cost

    Get-MeteredStatus
}
