$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xSCEPHelper.psm1 -Verbose:$false -ErrorAction Stop

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Default","UNC","MMPC")]
		[System.String]
		$Source = "Default",

        [System.String]
        $Path,

		[ValidateSet("SignaturesLastUpdated","LastFallbackTime")]
		[System.String]
		$TestType = "LastFallbackTime",

        [System.Byte]
        $Interval = 7
	)

    foreach($RegEntry in ('SignaturesLastUpdated','LastFallbackTime'))
    {
        $BA = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name $RegEntry -ErrorAction SilentlyContinue)."$RegEntry"
        if($BA)
        {
            $FT = [System.BitConverter]::ToInt64($BA,0)
            Set-Variable -Name $RegEntry -Value ([DateTime]::FromFileTime($FT))
        }
        else
        {
            Set-Variable -Name $RegEntry -Value ''
        }
    }

    $returnValue = @{
        EngineVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'EngineVersion' -ErrorAction SilentlyContinue).EngineVersion
        AVSignatureVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'AVSignatureVersion' -ErrorAction SilentlyContinue).AVSignatureVersion
        ASSignatureVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'ASSignatureVersion' -ErrorAction SilentlyContinue).ASSignatureVersion
        NISEngineVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'NISEngineVersion' -ErrorAction SilentlyContinue).NISEngineVersion
        NISSignatureVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'NISSignatureVersion' -ErrorAction SilentlyContinue).NISSignatureVersion
        SignaturesLastUpdated = $SignaturesLastUpdated
        LastFallbackTime = $LastFallbackTime
    }

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Default","UNC","MMPC")]
		[System.String]
		$Source = "Default",

        [System.String]
        $Path,

		[ValidateSet("SignaturesLastUpdated","LastFallbackTime")]
		[System.String]
		$TestType = "LastFallbackTime",

        [System.Byte]
        $Interval = 7
	)

    $InstallFolder = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware' -Name 'InstallLocation' -ErrorAction SilentlyContinue).InstallLocation
    if($InstallFolder)
    {
        $MpCmdRun = Join-Path -Path $InstallFolder -ChildPath 'MpCmdRun.exe'
        if(Test-Path -Path $MpCmdRun)
        {
            
            switch($Source)
            {
                "Default"
                {
                    Write-Verbose "Running $MpCmdRun -SignatureUpdate"
                    & $MpCmdRun -SignatureUpdate
                }
                "UNC"
                {
                    Write-Verbose "Running $MpCmdRun -SignatureUpdate -UNC -Path $Path"
                    & $MpCmdRun -SignatureUpdate -UNC -Path $Path
                }
                "MMPC"
                {
                    Write-Verbose "Running $MpCmdRun -SignatureUpdate -MMPC"
                    & $MpCmdRun -SignatureUpdate -MMPC
                }
            }
        }
    }

    if(!(Test-TargetResource @PSBoundParameters))
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
    }
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Default","UNC","MMPC")]
		[System.String]
		$Source = "Default",

        [System.String]
        $Path,

		[ValidateSet("SignaturesLastUpdated","LastFallbackTime")]
		[System.String]
		$TestType = "LastFallbackTime",

        [System.Byte]
        $Interval = 7
	)

    $Update = Get-TargetResource @PSBoundParameters

    if($Update."$TestType")
    {
        $Age = ([DateTime]::Now - [DateTime]($Update."$TestType")).Days
        Write-Verbose "Signature age is $Age days"
        if($Age -le $Interval)
        {
            $result = $true
        }
        else
        {
            $result = $false
        }
    }
    else
    {
        $result = $false
    }
    
	$result
}


Export-ModuleMember -Function *-TargetResource