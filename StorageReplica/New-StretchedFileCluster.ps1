<#
.SYNOPSIS
    Builds a virutal two node, streched, general purpose file server cluster with storage replica
.DESCRIPTION
    Script with all steps to build a streched cluster, based on two VMs, with a general purpose file server cluster role.
    The underneath storage is not shared storage but local storage. The volume insiede the VMs will then replicated with Storage Replica

    The sicript is intended to run on a third computer like a managemnt server where the Failover Cluster, Hyper-V and Storage Replica RSAT tools are installed.

.PARAMETER Server
    Computer names of the thwo cluster nodes

.PARAMETER Locations
    Name of the two sites. Will be used to name the sites in cluster fault domains configuration

.PARAMETER ClusterName
    Name of the failover cluster

.PARAMETER ClusterIP
    IP Address of the failover cluster

.PARAMETER CloudWitnessAccount
    Name of the Azure storage account which should be used as cloud witness (empty if cloud witness should not be configure)

.PARAMETER CloudWitnessAccessKey
    Primary access Key of the Azure storage account which should be used as cloud witness (empty if cloud witness should not be configure)

.PARAMETER WitnessShare
    Full UNC path to the sahre which sould be used as witness file share (only if cloud witness can/sould not be used)

.PARAMETER HyperVHosts
    Name of the Hyper-V hosts on which the two VMs are currently running (to attach the need VHDX to the VMs)

.PARAMETER DataVHDXBasePaths
    Paths to the location where the VHDX files for the Data disks should be created (SOFS Share,CSV Volume, or local volume of the Hyper-V host)

.PARAMETER LogVHDXBasePaths
    Paths to the location where the VHDX files for the Log disks should be created (SOFS Share,CSV Volume, or local volume of the Hyper-V host)

.PARAMETER LogDiskSize
    Size fo the Log disk VHDX files in bytes (PowerShell will convert <number>GB automatically in the corresponding bytes value)

.PARAMETER DataDiskSize
    Size fo the Data disk VHDX files in bytes (PowerShell will convert <number>GB automatically in the corresponding bytes value)

.PARAMETER LogDiskLetter
    Drive Letter of the Log disk volume

.PARAMETER DataDiskLetter
    Drive Letter of the Data disk volume

.PARAMETER FSClusterName
    Name of the File Server Cluster Role

.PARAMETER FSClusterIP
    IP Address of the File Server Cluster Role

.PARAMETER ShareNames
    An Arry with Hashtable(s) with file share which sould be created on the Data volume. (One Hashtable per File Share)
    The Hashtable must contains to keys "Sharename" and "ContinuouslyAvailable"
    Example: @{ShareName = "TestShare";ContinuouslyAvailable=$true}

.PARAMETER ReplicationMode
    The replication mode of Storage Replica. Must be "Synchronous" or "Asynchronous"

.NOTES
    Version: 1.0.0.0, 03/07/2017 (stable)

    Requires:
    PowerShell 5.0
    Hyper-V Cmdlets
    Failover Cluster Cmdlets
    Storage Cluster Cmdlets

.LINK
    @ Jonas Feller c/o J0F3, March 2017, www.jofe.ch

    Get latest version at: https://github.com/J0F3/PowerShell/StorageReplica
#>

Param
(
    [String[]]
    $Servers = @('SR-SRV01','SR-SRV02'),

    [String[]]
    $Locations = @('Bern', 'Zurich'),

    [String]
    $ClusterName = 'SR-CLU01',

    [String]
    $ClusterIP = '192.168.1.10',

    [String]
    $CloudWitnessAccount = 'cloudwitness',

    [String]
    $CloudWitnessAccessKey = 'fcNDPKdzxdTrbg3638ZvUDtrSfKTkAPLItQfsZ2suh10zLr8quWwDUXesIH8N6Wzyw==',

    [String]
    $WitnessShare = '',

    [String[]]
    $HyperVHosts = @('HV-SRV01','HV-SRV02'),

    [String[]]
    $DataVHDXBasePaths = @('\\SOFS-Bern\csv01\SR-SRV01\Virtual Hard Disks\','\\SOFS-Zurich\csv01\SR-SRV02\Virtual Hard Disks\'),

    [String[]]
    $LogVHDXBasePaths = @('\\SOFS-Bern\csv01\SR-SRV01\Virtual Hard Disks\','\\SOFS-Zurich\csv01\SR-SRV02\Virtual Hard Disks\'),

    [long]
    $LogDiskSize = 10GB,

    [long]
    $DataDiskSize = 127GB,

    [string]
    $LogDiskLetter = 'L',

    [string]
    $DataDiskLetter = 'D',

    [string]
    $FSClusterName = 'SR-FS01',

    [string]
    $FSClusterIP = '192.168.1.11',

    [hashtable[]]
    $ShareNames = @(@{ShareName = "TestShare";ContinuouslyAvailable=$true}),

    [string]
    [ValidateSet("Synchronous","Asynchronous")]
    $ReplicationMode = "Synchronous"
)

# install features
$Servers | ForEach-Object { Install-WindowsFeature -ComputerName $_ -Name Storage-Replica,Failover-Clustering,FS-FileServer -IncludeManagementTools -restart }

# build cluster
New-Cluster -Name $ClusterName -Server$Servers[0] $Servers -StaticAddress $ClusterIP

# configure cluster quorum
if($CloudWitnessAccount)
{
    Set-ClusterQuorum -Cluster $ClusterName -CloudWitness -AccountName $CloudWitnessAccount -AccessKey $CloudWitnessAccessKey
}
elseif ($WitnessShare)
{
    Set-ClusterQuorum -Cluster $ClusterName -FileShareWitness $WitnessShare
}

# configure fault domains (sites) in cluster
New-ClusterFaultDomain -CimSession $ClusterName -Name $Locations[0] -Type Site -Description "Primary" -Location $Locations[0]
New-ClusterFaultDomain -CimSession $ClusterName -Name $Locations[1] -Type Site -Description "Secondary" -Location $Locations[1]
Set-ClusterFaultDomain -CimSession $ClusterName -Name $Servers[0] -Parent $Locations[0]
Set-ClusterFaultDomain -CimSession $ClusterName -Name $Servers[1] -Parent $Locations[1]
(Get-Cluster -Name $ClusterName).PreferredSite=$Locations[0]

# Create new VHDX files
# Log disks
New-VHD -CimSession $HyperVHosts[0] -Path $($VHDXBasePaths[0] + 'Log.vhdx') -SizeBytes $LogDiskSize -Fixed
New-VHD -CimSession $HyperVHosts[1] -Path $($VHDXBasePaths[1] + 'Log.vhdx') -SizeBytes $LogDiskSize -Fixed

# Data diks
New-VHD -CimSession $HyperVHosts[0] -Path $($VHDXBasePaths[0] + 'Data.vhdx') -SizeBytes $DataDiskSize -Dynamic
New-VHD -CimSession $HyperVHosts[1] -Path $($VHDXBasePaths[1] + 'Data.vhdx') -SizeBytes $DataDiskSize -Dynamic


# Add new disks to cluster Server$Servers[0s
Add-VMHardDiskDrive -CimSession $HyperVHosts[0] -VMName $Servers[0] -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $($LogVHDXBasePaths[0] + 'Log.vhdx') -SupportPersistentReservationss

Add-VMHardDiskDrive -CimSession $HyperVHosts[0] -VMName $Servers[0] -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 2 -Path $($DataVHDXBasePaths[0] + 'Data.vhdx') -SupportPersistentReservations

Add-VMHardDiskDrive -CimSession $HyperVHosts[1] -VMName $Servers[1] -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $($LogVHDXBasePaths[1] + 'Log.vhdx') -SupportPersistentReservations

Add-VMHardDiskDrive -CimSession $HyperVHosts[1] -VMName $Servers[1] -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 2 -Path $($DataVHDXBasePaths[1] + 'Data.vhdx') -SupportPersistentReservations

# Format disks on first node
Invoke-Command -ComputerName $Servers[0] -ScriptBlock {
    Set-Disk -Number 1 -IsOffline $false
    set-disk -Number 2 -IsOffline $false
    Set-Disk -Number 1 -IsReadOnly $false
    set-disk -Number 2 -IsReadOnly $false

    Initialize-Disk -Number 1 -PartitionStyle GPT
    Initialize-Disk -Number 2 -PartitionStyle GPT

    Get-disk | Where-Object {$_.Size -eq 10gb -and $_.DiskNumber -ne $null} | New-Partition -UseMaximumSize -DriveLetter $USING:LogDiskLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Log"
    Get-disk | Where-Object {$_.Size -gt 10gb -and $_.DiskNumber -ne $null} | New-Partition -UseMaximumSize -DriveLetter $USING:DataDiskLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data"
}

# Add disks of first node to the cluster
Get-ClusterAvailableDisk -All -Cluster $ClusterName | Add-ClusterDisk

# Rename cluster resources of source node
Invoke-Command -ComputerName $Servers[0] -ScriptBlock {
    $ClusterDisks = Get-ClusterResource | Where-Object ResourceType -EQ 'Physical Disk'

    foreach ($ClusterDisk in $ClusterDisks)
    {
        $DiskResource = Get-WmiObject MSCluster_Resource -Namespace root/mscluster | Where-Object{ $_.Name -eq $ClusterDisk.Name }
        $Disk = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$DiskResource} Where ResultClass=MSCluster_Disk"
        $Partition = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$Disk} Where ResultClass=MSCluster_DiskPartition"

        $ClusterDisk.Name = "$($Partition.VolumeLabel)-Source"
    }
}

# Create File Server Cluster Role
Add-ClusterFileServerRole -Cluster $ClusterName -Name $FSClusterName -StaticAddress $FSClusterIP -Storage "Data-Source"

# Create File Shares
foreach($Share in $ShareNames) {
    $SharePath = Join-Path -path "${DataDiskLetter}:" -ChildPath $($Share.ShareName)
    Invoke-Command -ComputerName $Servers[0] -ScriptBlock {mkdir $USING:SharePath}
    New-SmbShare -CimSession $Servers[0] -Name $Share.ShareName -Path $SharePath -ContinuouslyAvailable $Share.ContinuouslyAvailable
}

# Configure Storage Replica to destination node/site

# Format disks on second node
Invoke-Command -ComputerName $Servers[1] -ScriptBlock {
    Set-Disk -Number 1 -IsOffline $false
    set-disk -Number 2 -IsOffline $false
    Set-Disk -Number 1 -IsReadOnly $false
    set-disk -Number 2 -IsReadOnly $false

    Initialize-Disk -Number 1 -PartitionStyle GPT
    Initialize-Disk -Number 2 -PartitionStyle GPT

    Get-disk | Where-Object {$_.Size -eq 10gb -and $_.DiskNumber -ne $null} | New-Partition -UseMaximumSize -DriveLetter $USING:LogDiskLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Log"
    Get-disk | Where-Object {$_.Size -gt 10gb -and $_.DiskNumber -ne $null} | New-Partition -UseMaximumSize -DriveLetter $USING:DataDiskLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data"
}

# Add disks of second node to the cluster
Get-ClusterAvailableDisk -All -Cluster $ClusterName | Add-ClusterDisk

# Move available storage to second node
Move-ClusterGroup -Name "Available Storage" -Node $Servers[1]

# Rename cluster resources of destination node
Invoke-Command -ComputerName $Servers[1] -ScriptBlock {
    $ClusterDisks = Get-ClusterResource | Where-Object {$_.ResourceType -EQ 'Physical Disk' -and $_.Name -notlike "*-Source"}

    foreach ($ClusterDisk in $ClusterDisks)
    {
        $DiskResource = Get-WmiObject MSCluster_Resource -Namespace root/mscluster | Where-Object{ $_.Name -eq $ClusterDisk.Name }
        $Disk = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$DiskResource} Where ResultClass=MSCluster_Disk"
        $Partition = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$Disk} Where ResultClass=MSCluster_DiskPartition"

        $ClusterDisk.Name = "$($Partition.VolumeLabel)-Destination"
    }
}

# Configure Storage Replica
New-SRPartnership -SourceComputerName $Servers[0] -SourceRGName "RG-Data-$($Servers[0])" -SourceRGDescription "Replication Group for D: from $($Servers[0]) to $($Servers[1])" -SourceVolumeName $DataDiskLetter -SourceLogVolumeName $LogDiskLetter -DestinationComputerName $Servers[1] -DestinationRGName "RG-Data-$($Servers[1])" -DestinationRGDescription "Replication Group for D: from $($Servers[0]) to $($Servers[1])" -DestinationVolumeName $DataDiskLetter -DestinationLogVolumeName $LogDiskLetter -ReplicationMode $ReplicationMode

#Check status of inital sync
do{
    $r=(Get-SRGroup -ComputerName $Servers[1] -Name "RG-Data-$($Servers[1])").replicas
    [System.Console]::Write("Number of remaining bytes {0}`n", $r.NumOfBytesRemaining)
    Start-Sleep 10
}until($r.ReplicationStatus -eq 'ContinuouslyReplicating')
Write-Output "Replica Status: "$r.replicationstatus