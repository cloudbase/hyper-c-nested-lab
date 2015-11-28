$ErrorActionPreference = "Stop"
$VerbosePreference = "continue"

$vhdDir = "C:\VM\hyper-c-lab"
$ubuntuIso = "C:\ISO\ubuntu-14.04-server-amd64.iso"

$vmSwitchName = "external"
$vmDataSwitchName = "external"
$mgmtVlan = 41

$maasVMName = "hyper-c-maas"
$dc1VMName = "hyper-c-dc1"
$jujuStateMachineVMName = "hyper-c-juju"
$servicesVMName = "hyper-c-services"
$networkVMName = "hyper-c-net"
$s2dProxyVMName = "hyper-c-s2d-proxy"
$nanoVMNameBase = "hyper-c-nano-{0}"

mkdir $vhdDir -ea SilentlyContinue | Out-Null

function New-LabVM($vmName, $cpuCount, $memStartup, $memMax, $enableDynMem, $vhdSizeBytes, $vmSwitchName, $mgmtVlan, $pxe, $macAddressSpoofing, $nestedVirt)
{
	Write-Verbose "Creating VM: ${vmName}"

    $vhd = new-VHD (Join-Path $vhdDir "${vmName}.vhdx") -SizeBytes $vhdSizeBytes
    $vm = New-VM $vmName -MemoryStartupBytes $memStartup -SwitchName $vmSwitchName -VHDPath $vhd.Path -Generation 2
    $vm | Set-VMProcessor -Count $cpuCount -ExposeVirtualizationExtensions $nestedVirt
    $vm | Set-VMMemory -DynamicMemoryEnabled $enableDynMem
    if ($enableDynMem)
    {
        $vm | Set-VMMemory -MaximumBytes $memMax
    }
    $vm | Set-VMFirmware -EnableSecureBoot Off
    $vm | Set-VMNetworkAdapter -MacAddressSpoofing $macAddressSpoofing
    $vm | Set-VMNetworkAdapterVlan -Access -VlanId $mgmtVlan
    if ($pxe)
    {
        $vmVhdDrive = $vm | Get-VMHardDiskDrive
        $mgmtVNic = $vm | Get-VMNetworkAdapter
        $vm | Set-VMFirmware -EnableSecureBoot Off -BootOrder $mgmtVNic,$vmVhdDrive
    }
    return $vm
}


Write-Verbose "Creating MaaS VM: ${maasVMName}"
$vhd = new-VHD (Join-Path $vhdDir "${maasVMName}.vhdx") -SizeBytes 100GB
$vm = New-VM $maasVMName -MemoryStartupBytes 2GB -SwitchName $vmSwitchName -VHDPath $vhd.Path
$vm | Set-VMProcessor -Count 4
$vm | Set-VMMemory -DynamicMemoryEnabled $false
$vm | Add-VMNetworkAdapter -SwitchName $vmSwitchName -Passthru | Set-VMNetworkAdapterVlan -Access -VlanId $mgmtVlan
$vm | Get-VMDvdDrive | Set-VMDvdDrive -Path $ubuntuIso
$maas = $vm

$jujuSM = New-LabVM $jujuStateMachineVMName 4 2GB $null $false 20GB $vmSwitchName $mgmtVlan $true Off $false
$dc1 = New-LabVM $dc1VMName 2 1GB 2GB $true 20GB $vmSwitchName $mgmtVlan $true Off $false
$s2dProxy = New-LabVM $s2dProxyVMName 2 1GB 2GB $true 20GB $vmSwitchName $mgmtVlan $true Off $false

$services = New-LabVM $servicesVMName 4 5GB $null $false 100GB $vmSwitchName $mgmtVlan $true On $false
# Data
$services | Add-VMNetworkAdapter -SwitchName $vmDataSwitchName
# External
$services | Add-VMNetworkAdapter -SwitchName $vmSwitchName

$nanoVms = @()
for($i = 1; $i -le 4; $i++)
{
    $nanoVMName = "hyper-c-nano-{0}" -f $i
    $vm = New-LabVM $nanoVMName 4 2GB $null $false 10GB $vmSwitchName $mgmtVlan $true Off $true
    $vhdData = new-VHD (Join-Path $vhdDir "${nanoVMName}_data.vhdx") -SizeBytes 100GB
    $vm | Add-VMHardDiskDrive -Path $vhdData.Path
    # Data
    $vm | Add-VMNetworkAdapter -SwitchName $vmDataSwitchName -PassThru | Set-VMNetworkAdapter -MacAddressSpoofing On
    $nanoVms += $vm
}

# Data mac addresses for Hyper-V charm:
# foreach($vm in get-vm hyper-c-nano*) { ($vm | Get-VMNetworkAdapter)[1].MacAddress }
