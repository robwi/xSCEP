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
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[System.String]
		$SourcePath = "$PSScriptRoot\..\..\",

		[System.String]
		$SourceFolder = "Source",

		[System.String]
		$Policy = "EP_DefaultPolicy.xml",

		[System.Boolean]
		$NoUpdate,

		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[System.Boolean]
		$SuppressReboot,

		[System.Boolean]
		$ForceReboot
	)

    Import-Module $PSScriptRoot\..\..\xPDT.psm1
        
    if($SourceCredential)
    {
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
    }
    $Path = Join-Path -Path (Join-Path -Path $SourcePath -ChildPath $SourceFolder) -ChildPath "SCEPInstallCAMP6.exe"
    $Path = ResolvePath $Path
    $Version = (Get-Item -Path $Path).VersionInfo.ProductVersion
    if($SourceCredential)
    {
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
    }

    $IdentifyingNumber = GetxPDTVariable -Component "SCEP" -Version $Version -Role "Agent" -Name "IdentifyingNumber"
    Write-Verbose "IdentifyingNumber is $IdentifyingNumber"
    
    if($IdentifyingNumber -and (Get-WmiObject -Class Win32_Product | Where-Object {$_.IdentifyingNumber -eq $IdentifyingNumber}))
    {
        $SignaturesLastUpdatedBA = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'SignaturesLastUpdated' -ErrorAction SilentlyContinue).SignaturesLastUpdated
        if($SignaturesLastUpdatedBA)
        {
            $SignaturesLastUpdatedFT = [System.BitConverter]::ToInt64($SignaturesLastUpdatedBA,0)
            $SignaturesLastUpdated = [DateTime]::FromFileTime($SignaturesLastUpdatedFT)
        }
        else
        {
            $SignaturesLastUpdated = ''
        }
        $returnValue = @{
            Ensure = "Present"
	        SourcePath = $SourcePath
	        SourceFolder = $SourceFolder
            EngineVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'EngineVersion' -ErrorAction SilentlyContinue).EngineVersion
            AVSignatureVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'AVSignatureVersion' -ErrorAction SilentlyContinue).AVSignatureVersion
            ASSignatureVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'ASSignatureVersion' -ErrorAction SilentlyContinue).ASSignatureVersion
            NISEngineVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'NISEngineVersion' -ErrorAction SilentlyContinue).NISEngineVersion
            NISSignatureVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Signature Updates' -Name 'NISSignatureVersion' -ErrorAction SilentlyContinue).NISSignatureVersion
            SignaturesLastUpdated = $SignaturesLastUpdated
	    }
    }
    else
    {
        $returnValue = @{
            Ensure = "Absent"
	        SourcePath = $SourcePath
	        SourceFolder = $SourceFolder
	    }
    }

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[System.String]
		$SourcePath = "$PSScriptRoot\..\..\",

		[System.String]
		$SourceFolder = "Source",

		[System.String]
		$Policy = "EP_DefaultPolicy.xml",

		[System.Boolean]
		$NoUpdate,

		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[System.Boolean]
		$SuppressReboot,

		[System.Boolean]
		$ForceReboot
	)

    Import-Module $PSScriptRoot\..\..\xPDT.psm1
        
    if($SourceCredential)
    {
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
        $TempFolder = [IO.Path]::GetTempPath()
        & robocopy.exe (Join-Path -Path $SourcePath -ChildPath $SourceFolder) (Join-Path -Path $TempFolder -ChildPath $SourceFolder) /e
        $SourcePath = $TempFolder
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
    }
    $Path = Join-Path -Path (Join-Path -Path $SourcePath -ChildPath $SourceFolder) -ChildPath "SCEPInstallCAMP6.exe"
    $Path = ResolvePath $Path
    $Version = (Get-Item -Path $Path).VersionInfo.ProductVersion

    $IdentifyingNumber = GetxPDTVariable -Component "SCEP" -Version $Version -Role "Agent" -Name "IdentifyingNumber"
    Write-Verbose "IdentifyingNumber is $IdentifyingNumber"

    switch($Ensure)
    {
        "Present"
        {
            $PolicyPath = Join-Path -Path (Join-Path -Path $SourcePath -ChildPath $SourceFolder) -ChildPath $Policy
            $PolicyPath = ResolvePath $PolicyPath
            $Arguments = "/s /q /policy $PolicyPath"
            if($NoUpdate)
            {
                $Arguments += " /NoSigsUpdateAtInitialExp"
            }
        }
        "Absent"
        {
            $Arguments = "/s /q /u"
        }
    }

    Write-Verbose "Path: $Path"
    Write-Verbose "Arguments: $Arguments"
    
    $Process = StartWin32Process -Path $Path -Arguments $Arguments
    Write-Verbose $Process
    WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments

    if($ForceReboot -or ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) -ne $null))
    {
	    if(!($SuppressReboot))
        {
            $global:DSCMachineStatus = 1
        }
        else
        {
            Write-Verbose "Suppressing reboot"
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
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[System.String]
		$SourcePath = "$PSScriptRoot\..\..\",

		[System.String]
		$SourceFolder = "Source",

		[System.String]
		$Policy = "EP_DefaultPolicy.xml",

		[System.Boolean]
		$NoUpdate,

		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[System.Boolean]
		$SuppressReboot,

		[System.Boolean]
		$ForceReboot
	)

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)

	$result
}


Export-ModuleMember -Function *-TargetResource