# This is per subscription, the customer has to set the az subscription before running this.
# az login
# az account set --subscription <subscription_id/subscription_name>
# This script uses parallel processing, modify the $parallelThrottleLimit parameter to either increase or decrease the number of parallel processes
# PS> .\MMAUnistallUtilityScript.ps1 GetInventory
# The above command will generate a csv file with the details of Vm's and Vmss that has MMA extension installed. 
# The customer can modify the the csv by adding/removing rows if needed
# Remove the MMA by running the script again as shown below:
# PS> .\MMAUnistallUtilityScript.ps1 UninstallMMAExtension

# This version of the script requires Powershell version >= 7 in order to improve performance via ForEach-Object -Parallel
# https://docs.microsoft.com/en-us/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.1
if ($PSVersionTable.PSVersion.Major -lt 7) 
{
 Write-Host "This script requires Powershell version 7 or newer to run. Please see https://docs.microsoft.com/en-us/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.1."
 exit 1
}

$parallelThrottleLimit = 16

function GetVmsWithMMAExtensionInstalled
{
 param(
     $fileName
 )
 
 $vmList = az vm list --query "[].{ResourceGroup:resourceGroup, VmName:name}" | ConvertFrom-Json
  
 if(!$vmList)
 {
     Write-Host "Cannot get the VM list"
     return
 }

 $vmsCount = $vmList.Length
 
 $vmParallelThrottleLimit = $parallelThrottleLimit
 if ($vmsCount -lt $vmParallelThrottleLimit) 
 {
     $vmParallelThrottleLimit = $vmsCount
 }

 if($vmsCount -eq 1)
 {
     $vmGroups += ,($vmList[0])
 }
 else
 {
     # split the vm's into batches to do parallel processing
     for ($i = 0; $i -lt $vmsCount; $i += $vmParallelThrottleLimit) 
     { 
         $vmGroups += , ($vmList[$i..($i + $vmParallelThrottleLimit - 1)]) 
     }
 }

 Write-Host "Detected $vmsCount Vm's running in this subscription."
 $hash = [hashtable]::Synchronized(@{})
 $hash.One = 1

 $vmGroups | Foreach-Object -ThrottleLimit $parallelThrottleLimit -Parallel {
     $len = $using:vmsCount
     $hash = $using:hash
     $_ | ForEach-Object {
         $percent = 100 * $hash.One++ / $len
         Write-Progress -Activity "Getting VM Inventory" -PercentComplete $percent
         $vmName = $_.VmName
         $resourceGroup = $_.ResourceGroup
         $extensionName = az vm extension list -g $resourceGroup --vm-name $vmName --query "[?name == 'MicrosoftMonitoringAgent' || name == 'OmsAgentForLinux'].name" | ConvertFrom-Json
         if ($extensionName) 
         {
             $csvObj = New-Object -TypeName PSObject -Property @{
                 'Name'           = $vmName
                 'Resource_Group' = $resourceGroup
                 'Resource_Type'  = "VM"
                 'Install_Type'   = "Extension"
                 'Extension_Name' = $extensionName
             }
             $csvObj | Export-Csv $using:fileName -Append -Force | Out-Null
         }
     }
 }
}

function GetVmssWithMMAExtensionInstalled
{
 param(
     $fileName
 )

 # get the vmss list which are successfully provisioned
 $vmssList = az vmss list --query "[?provisioningState=='Succeeded'].{ResourceGroup:resourceGroup, VmssName:name}" | ConvertFrom-Json   

 $vmssCount = $vmssList.Length
 Write-Host "Detected $vmssCount Vmss running in this subscription."
 $hash = [hashtable]::Synchronized(@{})
 $hash.One = 1

 $vmssList | Foreach-Object -ThrottleLimit $parallelThrottleLimit -Parallel {
     $len = $using:vmssCount
     $hash = $using:hash
     $percent = 100 * $hash.One++ / $len
     Write-Progress -Activity "Getting VMSS Inventory" -PercentComplete $percent
     $vmssName = $_.VmssName
     $resourceGroup = $_.ResourceGroup

     $extensionName = az vmss extension list -g $resourceGroup --vmss-name $vmssName --query "[?name == 'MicrosoftMonitoringAgent' || name == 'OmsAgentForLinux'].name" | ConvertFrom-Json
     if ($extensionName)
     {
         $csvObj = New-Object -TypeName PSObject -Property @{
             'Name'           = $vmssName
             'Resource_Group' = $resourceGroup
             'Resource_Type'  = "VMSS"
             'Install_Type'   = "Extension"
             'Extension_Name' = $extensionName
         }
         $csvObj | Export-Csv $using:fileName -Append -Force | Out-Null
     }    
 }
}

function GetInventory
{
 param(
     $fileName = "MMAInventory.csv"
 )

 # create a new file 
 New-Item -Name $fileName -ItemType File -Force

 Start-Transcript -Path $logFileName -Append
 GetVmsWithMMAExtensionInstalled $fileName
 GetVmssWithMMAExtensionInstalled $fileName
 Stop-Transcript
}

function UninstallMMAExtension
{
 param(
     $fileName = "MMAInventory.csv"
 )
 Start-Transcript -Path $logFileName -Append
 Import-Csv $fileName | ForEach-Object -ThrottleLimit $parallelThrottleLimit -Parallel {
     if ($_.Install_Type -eq "Extension") 
     {
         if ($_.Resource_Type -eq "VMSS") 
         {
             # if the extension is installed with a custom name, provide the name using the flag: --extension-instance-name <extension name>
             az vmss extension delete --name $_.Extension_Name --vmss-name $_.Name --resource-group $_.Resource_Group --output none --no-wait
         }
         else 
         {
             # if the extension is installed with a custom name, provide the name using the flag: --extension-instance-name <extension name>
             az vm extension delete --name $_.Extension_Name --vm-name $_.Name --resource-group $_.Resource_Group --output none --no-wait
         }
     }
 }
 Stop-Transcript
}

$logFileName = "MMAUninstallUtilityScriptLog.log"

switch ($args.Count)
{
 0 {
     Write-Host "The arguments provided are incorrect."
     Write-Host "To get the Inventory: Run the script as: PS> .\MMAUnistallUtilityScript.ps1 GetInventory"
     Write-Host "To uninstall MMA from Inventory: Run the script as: PS> .\MMAUnistallUtilityScript.ps1 UninstallMMAExtension"
 }
 1 {
     if (-Not (Test-Path $logFileName)) {
         New-Item -Path $logFileName -ItemType File
     }
     $funcname = $args[0]
     Invoke-Expression "& $funcname"
 }
 2 {
     if (-Not (Test-Path $logFileName)) {
         New-Item -Path $logFileName -ItemType File
     }
     $funcname = $args[0]
     $funcargs = $args[1]
     Invoke-Expression "& $funcname $funcargs"
 }
}
