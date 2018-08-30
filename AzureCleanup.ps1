<#
.SYNOPSIS
    .
.DESCRIPTION
    .
.PARAMETER Mode
    Please select a scanning mode, which can be either Full, Storage or Network.
.PARAMETER ProductionRun
    Specifies is you want to run in production mode, which will actually delete the 
	resources found to be redundant. For some resources additional confirmation will be required
.EXAMPLE
    C:\PS>AzureCleanUp.ps1 -Mode Full -ProductionRun $false 
    <Description of example>
.NOTES
    Author: Roelf Zomerman
    Date:   July 4, 2016
#>
 [CmdletBinding(DefaultParameterSetName="Mode")]
Param(
	[Parameter(
		Mandatory=$true,
		ParameterSetName="Mode",
		ValueFromPipeline=$true, 
		ValueFromPipelineByPropertyName=$true,
		HelpMessage="Select the Mode"
		)]
	    [ValidateNotNullOrEmpty()]
        [string[]]
	[Alias('Please provide the Mode')]	
	$Mode, #Mode
	[Parameter(
		Mandatory=$false
		)]
	$ProductionRun,
		[Parameter(
		Mandatory=$false
		)]
	$Login,
			[Parameter(
		Mandatory=$false
		)]
	$Log
)
Function ActivateDebug(){
			Add-Content -Path $LogfileActivated -Value "***************************************************************************************************"
			Add-Content -Path $LogfileActivated -Value "Started processing at [$([DateTime]::Now)]."
			Add-Content -Path $LogfileActivated -Value "***************************************************************************************************"
			Add-Content -Path $LogfileActivated -Value ""
			Write-Host "Debug Enabled writing to logfile: " $LogfileActivated
	
}

Function WriteDebug{
	[CmdletBinding()]
  
  Param ([Parameter(Mandatory=$true)][string]$LineValue)
  
	Process{
			If ($Log) {
				Add-Content -Path $LogfileActivated -Value $LineValue
			}
	}
}

Function GetAllVMProperties(){
	#GetAllVM's
	$AllVMs=Get-AzureRmVM
	Write-Host (" found " + $AllVMs.Count + ": ") -ForegroundColor Gray -NoNewline
	WriteDebug (" found " + $AllVMs.Count + ": ")
	ForEach ($VM in $AllVMs){
		Write-Host ($VM.name + "," ) -ForegroundColor Gray -NoNewline
		WriteDebug ($VM.name + "," )

		$VMNames.Add($VM.name) > $null
		If ($vm.DiagnosticsProfile.BootDiagnostics.Enabled -eq $true){
			$VMDiagStorageURL.add($vm.DiagnosticsProfile.BootDiagnostics.StorageUri) >$null
			WriteDebug $VM.name
			WriteDebug (" BootDiagnostics " + $vm.DiagnosticsProfile.BootDiagnostics.StorageUri)
		}
		$OSDisk=$VM.StorageProfile.OsDisk
		WriteDebug (" OS Disk " + $OSDisk.vhd.uri)
		$DiskURIArray.Add($OSDisk.vhd.uri) > $null
	$DataDisks = New-Object System.Collections.ArrayList
	$DataDisks=$VM.StorageProfile.DataDisks
		Foreach ($dDisk in $DataDisks){
			#Write-Host $dDisk.vhd.uri -ForegroundColor Gray
			WriteDebug (" Data Disk " + $dDisk.vhd.uri)
			$DiskURIArray.Add($dDisk.vhd.uri) > $null
		}
	#NEED TO GET ALL NETWORK ADAPTERS
		$NICIDs=$VM.NetworkInterfaceIDs
		Foreach ($nicID in $NICIDs){
		$VMNICArray.Add($nicID) > $null
			#Write-Host $nicID -ForegroundColor Gray
			WriteDebug (" NIC " + $nicID)
		}
	}
}



Function PrepareDeleteStorageAccountContents(){
	$StorageAccounts=Get-AzureRmStorageAccount
	Write-Host (" found " + $StorageAccounts.Count + " accounts") -ForegroundColor Gray 
	WriteDebug (" found " + $StorageAccounts.Count + " accounts")
	#Validate StorageAccount URL in VMDriveArray
	ForEach ($SA in $StorageAccounts){
				#Need to skip the built in security data logging part..  
				If($SA.ResourceGroupName -eq 'securitydata'){continue}
				Write-Host ("Storage Account " + $SA.StorageAccountName) -ForegroundColor Cyan
				WriteDebug 	(" Storage Account " + $SA.StorageAccountName)
				$DeleteStorageAccount=$True  #SET THE DELETE FLAG TO YES (WILL BE OVERRIDDEN IF BLOCKED)
		#RESET PER STORAGE ACCOUNT
				$FileDeleteCounter=0
				$DeleteContainers=$null
				$DeleteFiles=$null
				$DeleteContainerValidationCounter=0
				$DeleteFiles = New-Object System.Collections.ArrayList
				$DeleteContainers = New-Object System.Collections.ArrayList

				If ($DiskURIArray -match $SA.StorageAccountName -or  $VMDiagStorageURL -match $SA.StorageAccountName){
					#IF THE STORAGE ACCOUNTNAME IS BEING USED IN VM DISKS OR DIAGNOSTICS!
					$count=$SA.StorageAccountName.Length
					$msg=" is being used by VM's. Continuing with file scanning but storage account deletion is DISABLED"
						WriteDebug "Storage Account Blocked from deletion, existing VM's found"
						WriteDebug (" option1: " + $VMDiagStorageURL + " " + $SA.StorageAccountName)
						WriteDebug (" option2: " + $DiskURIArray + " " + $SA.StorageAccountName)
					Write-Host ("!" * ($count + $msg.Length)) -ForegroundColor Magenta
					Write-Host ($SA.StorageAccountName + $msg) -ForegroundColor Yellow
					Write-Host ("!" * ($count + $msg.Length)) -ForegroundColor Magenta
					$DeleteStorageAccount=$False  #MUST NOT DELETE STORAGE ACCOUNT
					Write-Host ""
				}
				Else {
					Write-Host ("Storage Account " + $SA.StorageAccountName + " not being used by VM's") -ForegroundColor Green
					WriteDebug ("Nothing found on " + $SA.StorageAccountName) 
					WriteDebug "DeleteStorageAccount Set to TRUE"
					$DeleteStorageAccount=$True
				}
				
			
				$Key=(Get-AzureRmStorageAccountKey -ResourceGroupName $SA.ResourceGroupName -Name $SA.StorageAccountName )
				$key1=$ket.key1
				WriteDebug (" Storage Account Key default: " + $key1)
				if ($Key1 -eq $null) {
						#Different version of Powershell CMD'lets
					$key1=$key.value[0]		
					WriteDebug (" Storage Account Key 2nd attempt: " + $key1)
				}

				$SACtx=New-AzureStorageContext -StorageAccountName $SA.StorageAccountName -StorageAccountKey $Key1
				Write-Host (" Storage Context is " + $SACtx.StorageAccountName) -ForegroundColor Gray
				WriteDebug ("Storage Context set to: " + $SACtx.StorageAccountName)

		#STANDARD STORAGE
		If ($SA.AccountType -match 'Standard' ){	
			WriteDebug (" Standard Storage Account found, checking tables and queues")		
					#THIS IS FOR TABLES AND QUEUES IF STORAGE IS STANDARD
					$Tables=Get-AzureStorageTable -Context $SACtx
					$queues=Get-AzureStorageQueue -Context $SACtx

					If (!($Tables)){
						Write-Host " Storage Tables not found" -ForegroundColor Green
						WriteDebug (" SA deletion is " + $DeleteStorageAccount)
					}
					ElseIf ($Tables){
						Write-Host " Storage Tables Found!" -ForegroundColor Yellow
						$DeleteStorageAccount=$False
						WriteDebug " Tables found, SA deletion set to FALSE"
					}
					If (!($queues)){
						Write-Host " Storage Queues not found" -ForegroundColor Green
						WriteDebug (" SA deletion is " + $DeleteStorageAccount)
					}
					Else {
						Write-Host " Storage Queues Found" -ForegroundColor Yellow
						$DeleteStorageAccount=$False
						WriteDebug " Queues found, SA deletion set to FALSE"
					}

					Write-Host ""
			} #STANDARD


			#THIS IS FOR BLOBS
#GOING DOWN TO CONTAINER LEVEL
					$Containers=Get-AzureStorageContainer -Context $SACtx
					WriteDebug " scannnig containers"
					foreach ($contain in $Containers) {
						#RESET THE COUNTERS PER CONTAINER
						$DeleteFilesCheck=$null
						$DeleteFiles=$null
						$DeleteFiles = New-Object System.Collections.ArrayList
						$DeleteFilesCheck = New-Object System.Collections.ArrayList
						
						$DeleteContainer=$False  #Security
						
						Write-Host (" Current container: "+ $contain.name) -ForegroundColor Green
						WriteDebug (" Current container: "+ $contain.name)
						
						#NEED TO FILTER OUT THE STILL BEING USED DIAGNOSTICS CONTAINERS
						$TempName=$contain.Name.split("-")[0]
						$TempName2=$contain.Name.split("-")[1]
						If ($TempName -eq 'bootdiagnostics' -and $VMNames -match $TempName2.ToUpper()){
						Write-Host "  container in use for VM diagnostics" -ForegroundColor Yellow
						WriteDebug "  container in use for VM diagnostics"
						WriteDebug "  BootDiagnostics found, SA deletion set to FALSE"
						$DeleteStorageAccount=$False
						continue
						}
						$filesInContainer=Get-AzureStorageBlob -Container $contain.Name -Context $SACtx
						$FileDeleteCounter=0

						If($filesInContainer -eq $null){
								$DeleteContainerValidationCounter++
								Write-Host " No files found" -ForegroundColor Yellow
								
									#DO YOU WISH TO DELETE THE Container?
			
								$title = ""
								$message = "  Container: '" + $contain.Name + "' does not contain any files, would you like to delete it?"
							
								$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
								"Marks container for deletion"

								$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
								"Skips deletion"

								$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

								$result = $host.ui.PromptForChoice($title, $message, $options, 1) 

								switch ($result)
								{
									0 {					
									Write-host ($contain.Name + " marked for deletion") -ForegroundColor Yellow
										$DeleteContainers.Add($contain.Name) >$null		
										WriteDebug "  no files in container, marked for deletion"
									} 

									1 {
									Write-host ($contain.Name +  " will remain") -ForegroundColor Green
									$DeleteStorageAccount=$False
									WriteDebug "  no files in container, SKIPPED for deletion"
									WriteDebug "  SA deletion set to FALSE"
									}
								}			
						continue
						}
						
#GOING DOWN TO FILE LEVEL
						Foreach ($file in $filesInContainer){
							$SafeGuard=$FileDeleteCounter
#NEED TO VALIDATE ON HTTP/HTTPS
							$BuiltVMFileName=("https://" + $SA.StorageAccountName + ".blob.core.windows.net/" + $contain.name + "/" + $file.name)
							$BuiltVMFileName2=("http://" + $SA.StorageAccountName + ".blob.core.windows.net/" + $contain.name + "/" + $file.name)
							WriteDebug " scannig VM files in container"
							WriteDebug ("$BuiltVMFileName")
							#VALIDATE IF NOT IN USE BY VM
							If ($DiskURIArray -contains $BuiltVMFileName -or $DiskURIArray -contains $BuiltVMFileName2) {
								Write-Host (" " + $file.name + " matches VM HDD file, and therefore must remain") -ForegroundColor Gray
								WriteDebug (" validated against DiskURIArray")
							continue



							}
							ElseIf ($VMNames -match $file.name.split(".")[0] -and $file.name.Endswith(".status") -eq $true){
								Write-host (" Existing VM status file for: " + $file.name.split(".")[0]) -ForegroundColor Gray
								WriteDebug " statusfile check" 
								WriteDebug (" option 1: " + $file.name.split(".")[0] + " in VMNames")
								WriteDebug " and ends with .status"
							continue

							}

							Else {
								WriteDebug ( "file was not found in arrays:" + $file.name)
							#DO YOU WISH TO DELETE THE FILE?
			
								$title = ""
								$message = "  Delete: " + $file.name 

								$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
								"Marks file for deletion"

								$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
								"Skips deletion"

								$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

								$result = $host.ui.PromptForChoice($title, $message, $options, 1) 

								switch ($result)
								{
									0 {					
									Write-host ($file.name + " marked for deletion") -ForegroundColor Yellow
										$DeleteFilesCheck.Add(" -blob " + $file.name + " -container " + $contain.Name) > $null
										WriteDebug (" file: " + $file.name + " added to deletion queue")					
										$FileDeleteCounter++
									} 

									1 {
									Write-host ($file.name +  " will remain") -ForegroundColor Green
									WriteDebug (" keeping file: " + $file.name)
									$DeleteStorageAccount=$False
									}
								}

							} #end else
						} # per file



						#Count the number of files marked for deletion versus the number of files in the container, then clear for container delete
						If ($FileDeleteCounter -eq $filesInContainer.count) 
						{
						WriteDebug (" FileDeleteCounter equals filesInContainer")
						WriteDebug (" 1: " + $FileDeleteCounter)
						WriteDebug (" 2: " + $filesInContainer.count)
						Write-Host " Container marked for deletion" -ForegroundColor Red
							$FileDeleteCounter=$SafeGuard #NO INDIVIDUAL FILE DELETES REQUIRED reset to container start
							$DeleteContainerValidationCounter++
							$DeleteContainers.Add($contain.Name) >$null	
							WriteDebug (" container: " + $contain.Name + " added to deletion queue")		
							$DeleteFilesCheck.Clear()			
							WriteDebug (" individual file deletion queue emptied")
						}
						ElseIf($FileDeleteCounter -lt $filesInContainer.count){
							#The number of the to be deleted files is less than the amount of files in the container, merge the Arrays into 1 big one
							Write-Host " container not empty, retaining..."  -ForegroundColor Green
							WriteDebug " container stays, individual file removal process..."
							$DeleteFiles=$DeleteFiles + $DeleteFilesCheck
						}
				
					
				}#ALL CONTAINERS DONE
				
				Write-Host ""
				Write-Host ("-" * 44 ) -ForegroundColor Green
				Write-Host ("Summary for " + $SA.StorageAccountName)
				Write-Host ("Delete StorageAccount ")  -NoNewline
				Write-host $DeleteStorageAccount -ForegroundColor Yellow
				Write-Host "Number of containers to be deleted: " -NoNewline
				Write-Host  $DeleteContainers.count -ForegroundColor Red
				Write-Host "Number of individual files to be deleted: " -NoNewline
				Write-Host  $DeleteFiles.count -ForegroundColor Red
				Write-Host ("-" * 44 ) -ForegroundColor Green
				
		
			If ($DeleteContainerValidationCounter -eq $Containers.Count -and $DeleteStorageAccount -eq $True)
			#STORAGE ACCOUNT DELETION
				{
					Write-Host ("DELETING STORAGE ACCOUNT " + $SA.StorageAccountName) -ForegroundColor Yellow
					WriteDebug (" Storage Account Deletion due to:")
					WriteDebug (" Container validation" + $DeleteContainerValidationCounter)
					WriteDebug (" containers to be deleted: " + $Containers.Count)
					WriteDebug (" DeleteStorageAccount is TRUE")
					DeleteStorageAccount $SA $SACtx

				}

			ElseIf ($DeleteContainerValidationCounter -eq $Containers.Count -and $DeleteContainers.count -ne 0 -and $DeleteStorageAccount -eq $False)
			#STORAGEACCOUNT DELETION IS BLOCKED BY QUEUES/TABLES, BUT PROCESSED CONTAINERS CAN BE REMOVED
				{
					Write-Host ("DELETING CONTAINERS ") -ForegroundColor Yellow
					WriteDebug (" Container Deletion due to:")
					WriteDebug (" Container validation" + $DeleteContainerValidationCounter)
					WriteDebug (" containers to be deleted: " + $Containers.Count)
					WriteDebug (" DeleteStorageAccount is FALSE")
 
					DeleteContainer $SA.StorageAccountName $DeleteContainers $SACtx
				}

			ElseIf ($DeleteContainerValidationCounter -ne $Containers.Count -and $DeleteContainers.count -ne 0)
			#INDIVIDUAL CONTAINERS CAN BE REMOVED
				{
					Write-Host ("DELETING CONTAINERS ") -ForegroundColor Yellow
					WriteDebug (" Container Deletion due to:")
					WriteDebug (" Container validation" + $DeleteContainerValidationCounter)
					WriteDebug (" containers to be deleted: " + $Containers.Count)
					WriteDebug (" number mismatch, therefore processing containers only")

					DeleteContainer $SA.StorageAccountName $DeleteContainers $SACtx
				}
		
			ElseIf ($DeleteContainer -eq $False -and $DeleteFiles.count -gt 0)
			#ONLY FILES CAN BE REMOVED
				{
					Write-Host ("DELETING Individual Files") -ForegroundColor Yellow
					WriteDebug (" File Deletion due to:")
					WriteDebug (" Delete Container is FALSE")
					
					DeleteFiles $SA.StorageAccountName $DeleteFiles $SACtx

				}
			Else 
				{
					Write-Host ("Nothing to be deleted") -ForegroundColor Green
					WriteDebug " Nothing to be processed, no deletes"
					Write-Host ""

				}
		
	}	#Next STORAGE ACCOUNT
	
}


Function DeleteFiles($StorageAccountIN, [array]$FilesArrayIN, $ContextIN){
	Write-Host ($StorageAccountIN + " cannot be deleted")
	Write-Host "deleting the following files as marked"
	foreach ($file in $FilesArrayIN){
		Write-Host (" " + $file + " to be deleted") -ForegroundColor Red
		$DeletedFiles.add($file) >null
		If ($ProductionRun -eq $true){Remove-AzureStorageBlob $file -Context $ContextIN}
			Else {
				Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
				write-host " NO " -ForegroundColor Yellow -NoNewline
				Write-Host "delete confirmation" -ForegroundColor Green
			}	
		}
	Write-Host ""
	}

Function DeleteContainer($StorageAccountIN, [array]$ContainerIN, $ContextIN){
	Write-Host "deleting the following containers"
	
	foreach ($co in $ContainerIN){
		Write-Host (" Container named: " + $co + " to be deleted") -ForegroundColor Red
		$DeletedContainers.add($co) >null
		If ($ProductionRun -eq $true){Remove-AzureStorageContainer -Name $co -Context $ContextIN}
		Else {
			Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
			write-host " NO " -ForegroundColor Yellow -NoNewline
			Write-Host "delete confirmation" -ForegroundColor Green
		}
	}
	Write-Host ""
	
}
Function DeleteStorageAccount {
	[cmdletbinding(SupportsShouldProcess,ConfirmImpact='high')]
	param ($StorageAccountIN, $ContextIN)
	process {
		if ($PSCmdlet.ShouldProcess($StorageAccountIN.StorageAccountName)) {
			Write-Host "---------------" -ForegroundColor Yellow
			Write-Host ("deleting Storage Account: " + $StorageAccountIN.StorageAccountName) -ForegroundColor Red
			$DeletedStorageAccounts.add($StorageAccountIN.StorageAccountName) >null
			If ($ProductionRun -eq $true){
				Remove-AzureRMStorageAccount -Name $StorageAccountIN.StorageAccountName -ResourceGroup $StorageAccountIN.ResourceGroupName
			} #WHATIFDOESNOTEXIST
			Else {Write-Host " (Test Run) nothing deleted" -ForegroundColor Green}
		}
		Else {
		Write-host (" Deletion NOT confirmed, not deleting storage account: " + $StorageAccountIN.StorageAccountName) -ForegroundColor Green
		}
	}
	
} 
Function DeleteNIC($NICIN){
	Write-Host ("   will delete NIC: " + $NICIN.name) -ForegroundColor Red
	Write-Host ("   in resource group: " + $NICIN.ResourceGroupName) -ForegroundColor Red
	$DeletedNICs.add($NICIN.name) >null
	If ($ProductionRun -eq $true){Remove-AzureRmNetworkInterface -Name $NICIN.name -ResourceGroupName $NICIN.ResourceGroupName}
			Else {
			Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
			write-host " NO " -ForegroundColor Yellow -NoNewline
			Write-Host "delete confirmation" -ForegroundColor Green
		}
}
Function DeletePublicIPAddress($PublicIPIN){
	Write-Host ("   will delete Public IP: " + $PublicIPIN.name ) -ForegroundColor Red
	Write-Host ("   in resource group: " + $PublicIPIN.ResourceGroupName) -ForegroundColor Red
	$DeletedPublicIPAddresses.add($PublicIPIN.name) >null
	If ($ProductionRun -eq $true){Remove-AzureRmPublicIpAddress -Name $PublicIPIN.name -ResourceGroupName $PublicIPIN.ResourceGroupName}
			Else {
			Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
			write-host " NO " -ForegroundColor Yellow -NoNewline
			Write-Host "delete confirmation" -ForegroundColor Green
		}
}

Function DeleteNSG($NSGIN){
	Write-Host ("   will delete NSG: " + $NSGIN.name ) -ForegroundColor Red
	Write-Host ("   in resource group: " + $NSGIN.ResourceGroupName) -ForegroundColor Red
	$DeletedNSGs.add($NSGIN.name) >null
	If ($ProductionRun -eq $true){Remove-AzureRmNetworkSecurityGroup -Name $NSGIN.name -ResourceGroupName $NSGIN.ResourceGroupName}
			Else {
			Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
			write-host " NO " -ForegroundColor Yellow -NoNewline
			Write-Host "delete confirmation" -ForegroundColor Green
		}
}

Function DeleteSubnet($VnetIn,$SubnetIN){
	Write-Host ("   will delete Subnet: " + $SubnetIN ) -ForegroundColor Red
	Write-Host ("   in Vnet group: " + $VnetIn.name) -ForegroundColor Red
	$DeletedSubnets.add($SubnetIN) >null
	If ($ProductionRun -eq $true){Remove-AzureRmVirtualNetworkSubnetConfig -Name $SubnetIN -VirtualNetwork $VnetIn}
			Else {
			Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
			write-host " NO " -ForegroundColor Yellow -NoNewline
			Write-Host "delete confirmation" -ForegroundColor Green
		}

}

Function DeleteVnet{
	[cmdletbinding(SupportsShouldProcess,ConfirmImpact='high')]
	param ($VnetIn, $ResourceGroupIN)
	process {
		if ($PSCmdlet.ShouldProcess($VnetIn)) {
			Write-Host "---------------" -ForegroundColor Yellow
			Write-Host ("deleting Virtual Network: " + $VnetIn) -ForegroundColor Red
			$DeletedVirtualNetworks.add($VnetIn) >null
			If ($ProductionRun -eq $true){
				write-host "Remove-AzureRmVirtualNetwork -Name $VnetIn -ResourceGroupName $ResourceGroupIN -Verbose"
				Remove-AzureRmVirtualNetwork -Name $VnetIn -ResourceGroupName $ResourceGroupIN -Verbose
			} #WHATIFDOESNOTEXIST
			Else {Write-Host " (Test Run) nothing deleted" -ForegroundColor Green}
		}
		Else {
		Write-host (" Deletion NOT confirmed, not deleting Virtual Network: " + $VnetIn) -ForegroundColor Green
		}
	}
} 



Function NetworkComponents{
	$PublicIPAddresses=Get-AzureRmPublicIpAddress

	#which are not used (not in $VMNICArray)
	#from those, which use external IP addresses
	#GetAll Network Security Groups fill in array - which ones have NetworkInterfaces & Subnets empty -> delete
	#Delete ExternalIPAddresses from unused NIC's
	#Delete Unused NIC's

	#GET ALL UNUSED PIP's
	Write-Host " Public IP Addresses" -ForegroundColor Cyan	
	WriteDebug "Public IP addresses"
		ForEach ($exIP in $PublicIPAddresses){
			if ($exIP.Ipconfiguration.id.count -eq 0){
				Write-Host (" " + $exIP.name + " is not in use") -ForegroundColor Yellow
				WriteDebug (" " + $exIP.name + " is not in use")
				DeletePublicIPAddress $exIP
			}
			Else {
				#FILTER GATEWAYS FROM THIS LIST SO WE CAN ALREADY ADD THEM TO AN ARRAY
				#get the $exIP.Ipconfiguration.id and split it on /.. [4] should be resource group, [7] is virtualNetworkGateways [8] is GW name!
					$IPConfigID = $exIP.Ipconfiguration.id
					WriteDebug " IP is in use"
					WriteDebug $IPConfigID
					$IPConfigIDsplit=$IPConfigID.Split("/")
				if (($exIP.Ipconfiguration.id).split("/")[7] -eq 'virtualNetworkGateways') {
					WriteDebug "validating GW IPs later-on"
					#WE FOUND A GATEWAY IP	
					$GatewayArray.add(($exIP.Ipconfiguration.id).split("/")[8] + "/" + $exIP.Ipconfiguration.id.split("/")[4])
					WriteDebug (" ADDED TO ARRAY: " + ($exIP.Ipconfiguration.id).split("/")[8] + "/" + $exIP.Ipconfiguration.id.split("/")[4])
					Write-Host (" found Public IP address for Azure Gateway in VNet " + ($exIP.Ipconfiguration.id).split("/")[8]) -ForegroundColor Gray
				}
			}
		}

	Write-Host ""
	Write-Host " Network Inferfaces" -ForegroundColor Cyan
	$ALLNics=Get-AzureRmNetworkInterface
	ForEach ($Nic in $ALLNics){
		If ($VMNICArray -notcontains $Nic.id) {
			WriteDebug $Nic.IpConfigurations.id
			#Write-Host $VMNICArray
					
			If ($NIC.IpConfigurations.PublicIPaddress.id){
				WriteDebug ("PIP: " + $NIC.IpConfigurations.PublicIPaddress.id)
				$PublicIP=Get-AzureRmPublicIpAddress -Name $NIC.IpConfigurations.PublicIPaddress.id.split("/")[$NIC.IpConfigurations.PublicIPaddress.id.split("/").count -1] -ResourceGroupName $NIC.IpConfigurations.PublicIPaddress.id.split("/")[4]
				WriteDebug ("DELETE ATTACHED PIP: " + $PublicIP.name)
				Write-Host (" " + $PublicIP.name + " used by orphaned NIC " + $Nic.Name) -ForegroundColor Yellow
				DeletePublicIPAddress $PublicIP
			}
			Write-Host ("  " + $Nic.Name + " may be deleted (not in use)") -ForegroundColor Yellow
			WriteDebug ("  " + $Nic.Name + " may be deleted (not in use)")
			DeleteNIC $Nic
			$NSGCheck.Add($NIC.id) >null
		}
		Else {
			Write-Host ("  " + $Nic.Name + " is in use") -ForegroundColor Gray
			WriteDebug ("  " + $Nic.Name + " is in use")
			#FOR ALL THE NIC'S THAT ARE IN USE, ADD THE SUBNET TO AN ARRAY (WILL BE ACTIVE SUBNETS ARRAY)
			$subnetIDArray.Add($Nic.IpConfigurations.subnet.id) >$null
		}
	}
	Write-Host ""
	Write-Host " Network Security Groups" -ForegroundColor Cyan
	WriteDebug " Network Security Groups"
		$AllNSGs=Get-AzureRmNetworkSecurityGroup
	ForEach ($NSG in $AllNSGs) {
		If ($NSG.NetworkInterfaces.count -eq 0 -and $NSG.Subnets.count -eq 0){
			Write-Host ("  NSG " + $NSG.Name + " may be deleted (not in use)") -ForegroundColor Yellow
			WriteDebug ("  NSG " + $NSG.Name + " may be deleted (not in use)")
			WriteDebug ("NSGInterfaceCount eq 0")
			WriteDebug ("NSGSubnetCount eq 0")
			DeleteNSG $NSG

		}
		ElseIf ($NSG.NetworkInterfaces.count -eq 1 -and $NSGCheck -contains $NSG.NetworkInterfaces.id){
			Write-Host ("  NSG " + $NSG.Name + " may be deleted (was in use)") -ForegroundColor Yellow
			WriteDebug ("  NSG " + $NSG.Name + " may be deleted (was in use)")
			WriteDebug ("NSGInterfaceCount eq 1")
			WriteDebug ("NSGCheck contains " + $NSG.NetworkInterfaces.id)
			DeleteNSG $NSG
		}
		Else {
			Write-Host ("  NSG " + $NSG.Name + " is in use") -ForegroundColor Gray
			WriteDebug (" " + $NSG.Name + " is in use")
		}
	}	
}

Function AnalyzeVNets {
	Write-Host " Virtual Networks" -ForegroundColor Cyan
	WriteDebug " Virtual Networks"
	$VNETs=Get-AzureRMVirtualNetwork
	Write-Host ("  Found: " + $VNETs.count + " Virtual Networks") -ForegroundColor Gray
	WritedEBUG ("  Found: " + $VNETs.count + " Virtual Networks")
	#GET ALL GATEWAYS PER RESOURCE GROUP
	Write-Host " Virtual Networks" -ForegroundColor Cyan
	$ResourceGroups=Get-AzureRMResourceGroup
	Foreach ($ResGroup in $ResourceGroups) {
		WriteDebug (" Resource Group: " + $ResGroup.ResourceGroupName)
		$NetGateways=Get-AzureRmVirtualNetworkGateway -ResourceGroupName $ResGroup.ResourceGroupName
		foreach ($NetGateway in $NetGateways){
			WriteDebug (" gateway:" + $NetGateway.name)
			$subnetID=($NetGateway.IpConfigurationsText | convertFrom-Json).subnet.id
			$subnetIDsplit=$subnetID.split("/")
			$comparesubnetIDtoIP=($NetGateway.name + "/" + $subnetIDsplit[4])
			If ($GatewayArray -contains  $comparesubnetIDtoIP) {
				Write-host (" Public IP address assigned to subnet (Azure Gateway) " + $NetGateway.name)  -ForegroundColor Gray
				$GatewaySubnetArray.add($subnetID) >null
				WriteDebug (" found: " + $comparesubnetIDtoIP + " in GatewayArray")
			}
		}
	}



	foreach ($vnet in $VNETs) {
		If ($vnet.subnets.id){
			$SubnetDeleteCounter=0
			foreach ($subnet in $vnet.subnets.id){
			If ($subnetIDArray -notcontains $subnet) {
				If ($GatewaySubnetArray -contains $subnet){
					Write-Host (" Subnet " + $subnet.split("/")[10] + " being used by Azure Gateway for network " + $subnet.split("/")[8]) -ForegroundColor Green
				}
				Else {
					Write-Host (" Subnet " + $subnet.split("/")[10] + " in " + $subnet.split("/")[8] + " is not being used") -ForegroundColor Yellow
					DeleteSubnet $vnet $subnet.split("/")[10]
					$SubnetDeleteCounter++
				}
				#MUST ADD GATEWAY SUBNETS PRIOR TO CALLING NOT BEING USED
				}
			}
		}
		Else {
		Write-Host (" Virtual Network " + $vnet.name + " does not contain any subnets")
		DeleteVnet $vnet.name $ResGroup.ResourceGroupName
		}
		If ($SubnetDeleteCounter -eq $vnet.subnets.id.count -and $SubnetDeleteCounter -ne 0) {
			Write-Host (" All subnets in Vnet " + $vnet.name + " deleted") -ForegroundColor Yellow
			DeleteVnet $vnet.name $ResGroup.ResourceGroupName	
		}
		
		Write-Host ""
	}
}


If ($Log){
			$date=(Get-Date).ToString("d-M-y-h.m.s")
			$logname = ("AzureCleanLog-" + $date + ".log")
			New-Item -Path $pwd.path -Value $LogName -ItemType File
			$LogfileActivated=$pwd.path + "\" + $LogName
	ActivateDebug} #Activating DEBUG MODE

Try {
	Import-Module Azure.Storage
	}
	catch {
	Write-Host 'Modules NOT LOADED - EXITING'
	Exit
	}

#LOGIN TO TENANT
#clear
Write-Host ""
Write-Host ""
Write-Host ("-" * 90)
Write-Host ("             Welcome to the Azure unused resources cleanup script") -ForegroundColor Cyan
Write-Host ("-" * 90)
Write-host "This script comes without any warranty and CAN DELETE resources in your subscriptions" -ForegroundColor Yellow
Write-Host ("-" * 90)
Write-Host "This script will run against your Azure subscriptions can scan for the following resources"
Write-Host " -Storage Accounts"
Write-Host "   +Containers"
Write-Host "   +Files"
Write-Host " -Network"
Write-Host "   +Virtual Networks"
Write-Host "   +Subnets"
Write-Host "   +Public IP addresses"
Write-Host "   +Network Security Groups"
Write-host
Write-host "If resources are still in use, they will not be deleted, such as VM files, NIC's etc.."
Write-Host ""
Write-Host "Run the script with -Mode (Full/Storage/Network) for resource type based cleaning"
Write-Host "Run the script with -ProductionRun `$$True to actually delete the resources"
Write-Host ("-" * 90)


If (-not ($Login)) {Add-AzureRmAccount}


$selectedSubscriptions = New-Object System.Collections.ArrayList
$ProcessArray = New-Object System.Collections.ArrayList
$DiskURIArray = New-Object System.Collections.ArrayList
$VMNICArray = New-Object System.Collections.ArrayList
$VMNames = New-Object System.Collections.ArrayList
$VMDiagStorageURL= New-Object System.Collections.ArrayList
$NSGCheck = New-Object System.Collections.ArrayList
$ExternalIPArray = New-Object System.Collections.ArrayList
$filesInContainer = New-Object System.Collections.ArrayList
$subnetArray = New-Object System.Collections.ArrayList
$subnetIDArray = New-Object System.Collections.ArrayList
$GatewayArray = New-Object System.Collections.ArrayList
$GatewaySubnetArray = New-Object System.Collections.ArrayList
$DeletedFiles = New-Object System.Collections.ArrayList
$DeletedContainers = New-Object System.Collections.ArrayList
$DeletedStorageAccounts = New-Object System.Collections.ArrayList
$DeletedPublicIPAddresses = New-Object System.Collections.ArrayList
$DeletedNICs = New-Object System.Collections.ArrayList
$DeletedNSGs = New-Object System.Collections.ArrayList
$DeletedSubnets = New-Object System.Collections.ArrayList
$DeletedVirtualNetworks = New-Object System.Collections.ArrayList
$DeleteStorageAccount=$False

#GETTING A LIST OF SUBSCRIPTIONS
Write-Host "Getting the subscriptions, please wait..."

$Subscriptions=Get-AzureRMSubscription


Foreach ($subscription in $Subscriptions) {
	#ask if it should be included
	$title = $subscription.subscriptionname
	$message = "Do you want this subscription to be added to the selection?"

	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
    "Adds the subscription to the script."

	$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
    "Skips the subscription from scanning."

	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

	$result = $host.ui.PromptForChoice($title, $message, $options, 0) 

	switch ($result)
    {
        0 {
			$selectedSubscriptions.Add($subscription) > $null
			Write-host ($subscription.subscriptionname + " has been added")
			} 
		1 {Write-host ($subscription.subscriptionname + " will be skipped")
			}
    }

}
Write-Host ""



Write-Host "------------------------------------------------------"
Write-Host "Subscriptions selected:" -ForegroundColor Yellow
Foreach ($entry in $selectedSubscriptions){Write-Host " " + $entry.SubscriptionName -ForegroundColor Yellow}
If ($ProductionRun -eq $true){
	Write-Host ""
	Write-Host ""
	
	Write-Host "*************************" -ForegroundColor Yellow
	Write-Host "     !! WARNING !!" -ForegroundColor Red
	Write-Host "!!DATA MAY BE DELETED!!" -ForegroundColor Yellow
	Write-Host "     !! WARNING !!" -ForegroundColor Red
	Write-Host "*************************" -ForegroundColor Yellow
	Write-Host ""
	Write-Host ""
	#Write-Host "Press any key to exit or press p to continue"
	$x = Read-Host 'Press any key to exit or press P to continue'
	If ($x.toUpper() -ne "P") {
		Write-Host "SAFE QUIT" -ForegroundColor Green
		exit
	}
	clear
}

foreach ($entry in $selectedSubscriptions){
	Write-Host ("scanning: " + $entry.subscriptionname)
	
	$select=Select-AzureRmSubscription -SubscriptionId $entry.subscriptionID
	Write-Host "selected subscription"
	#GET ALL VM PROPERTIES
	Write-Host " collecting VM properties...."
	$VMProperties=GetAllVMProperties

	Switch ($Mode.ToLower()){
		full{
		Write-Host ""
		Write-Host "------------------------------------------------------"
		Write-Host " collecting Storage Accounts ...."
		$StorageAccountStatus=PrepareDeleteStorageAccountContents
	
		Write-Host ""
		Write-Host "------------------------------------------------------"
		Write-Host " collecting Network components ...."
		$NICStatus=NetworkComponents
	
		Write-Host ""
		Write-Host "------------------------------------------------------"
		Write-Host " collecting Network components ...."
		$AnalyzeVnetsforme=AnalyzeVNets	
		Write-Host "------------------------------------------------------"
		$select=""	
		}

		storage{
		Write-Host ""
		Write-Host "------------------------------------------------------"
		Write-Host " collecting Storage Accounts ...."
		$StorageAccountStatus=PrepareDeleteStorageAccountContents
		}

		network{
		Write-Host ""
		Write-Host "------------------------------------------------------"
		Write-Host " collecting Network components ...."
		$NICStatus=NetworkComponents
	
		Write-Host ""
		Write-Host "------------------------------------------------------"
		Write-Host " collecting Network components ...."
		$AnalyzeVnetsforme=AnalyzeVNets	
		Write-Host "------------------------------------------------------"
		$select=""	
		}
	
	}

	If ($ProductionRun -eq $False -or $ProductionRun -eq $null){
	Write-Host "Summay"
	Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
	Write-host "The following items may be deleted manually (ran test run)" -ForegroundColor Yellow
	Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
	Write-Host "Files to be Deleted:"
		Foreach ($file in $DeletedFiles) {Write-Host (" " + $file) -ForegroundColor Cyan}
	Write-Host "Containers to be Deleted:"
		Foreach ($container in $DeletedContainers) {Write-Host (" " + $container) -ForegroundColor Cyan}
	Write-Host "Storage Accounts to be Deleted:"
		Foreach ($SA in $DeletedStorageAccounts) {Write-Host (" " + $SA) -ForegroundColor Cyan}
	Write-Host "Public IP Addresses to be Deleted:"
		Foreach ($PIP in $DeletedPublicIPAddresses) {Write-Host (" " + $PIP) -ForegroundColor Cyan}
	Write-Host "NIC's to be Deleted:"
		Foreach ($NIC in $DeletedNICs) {Write-Host (" " + $NIC) -ForegroundColor Cyan}
	Write-Host "NSG's to be Deleted:"
		Foreach ($NS in $DeletedNSGs) {Write-Host (" " + $NS) -ForegroundColor Cyan}
	Write-Host "Subnets to be Deleted:"
		Foreach ($sub in $DeletedSubnets) {Write-Host (" " + $sub) -ForegroundColor Cyan}
	Write-Host "Virtual Networks to be Deleted:"
		Foreach ($vinet in $DeletedVirtualNetworks) {Write-Host (" " + $vinet) -ForegroundColor Cyan}
	Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
	Write-host "Items above will be deleted in production run (-production `$$true)" -ForegroundColor Yellow
	Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
	}
}
Write-Host ""


