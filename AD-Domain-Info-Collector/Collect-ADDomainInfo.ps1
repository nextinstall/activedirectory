####################################################################################################################
# Collect-ADDomainInfo.ps1
#
# Version   1.0 - 2019-07-11
#           1.1 - 2019-07-23 - changed default DaysLastActive Parameter to 99999.
#           1.2 - 2019-07-24 - Added SPN collection and cleaned up .zip creation logic.
#
# Details: This script collects User, Computer, Group, Schema, and GPO information for an Acitve Directory Domain.
#          Script has been tested on PowerShell v5, however it should run on v3 or later.
#          Script should be run with account that has rights to read ALL GPOs, group, user, AD data.(DA).
#          
# Written by: Tom Gregory
# For:        Harvard University
####################################################################################################################


#-------------------------------------------------------[Initialisations]----------------------------------------------------------
[CmdletBinding()]
param (
    [Parameter(Position=1, HelpMessage = "Operating System to Search. Default is *")]
    [String]$OStoSearch="*",

    [Parameter(Position=2, HelpMessage = "Days last active for COMPUTER filter. Default is 999.")] 
    [Int]$DaysLastActive=99999,

    [Parameter(Position=2, HelpMessage = "Log directory. Default is C:\Logs")] 
    [String]$LogDir = "C:\CollectedADData"
   
)

#---------------------------------------------------------[Declarations]-----------------------------------------------------------
$VerbosePreference = 'Continue' 

#-----------------------------------------------------------[Variables]------------------------------------------------------------
#Build search time
$time = (Get-Date).Adddays(-($DaysLastActive)) 

# Logging
$Date = Get-Date -Format yyyy-MM-dd_HHmmss
$Log = "DataCollection_$Date.log"
$RootLogDir = $LogDir
$LogDir = $LogDir+"\$Date"

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function ZipFiles( $zipfilename, $sourcedir )
{
   Add-Type -Assembly System.IO.Compression.FileSystem
   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir,
        $zipfilename, $compressionLevel, $false)
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------
Write-Verbose "`n`n[***********************************]`n  Starting Collect-ADDomainInfo.ps1`n[***********************************]`
`n`nThis script will generate a number of files for use in analizing an Active Directory. `nLog directory: $LogDir`n`nGrab a coffee, this may take a moment." 

# Create log directory if needed
if (!(Test-Path $LogDir)) { 
    Write-Verbose "`n[+] Log directory not found... creating: $LogDir" 
    New-Item $LogDir -ItemType Directory -Force
}else {
    Write-Verbose "`n[*] Log directory found... user $LogDir"
}

# Domain
Write-Verbose "`n[*] Generating AD Domain Info"
$domain = Get-ADDomain
$DN = $domain.DistinguishedName
$pdc = $domain.PDCEmulator

Write-Verbose "`n[+] Exporting DomainInfo.log"
$Domain | Out-File -FilePath "$LogDir\$($Domain.NetBIOSName)-DomainInfo.log" -Append

# Gather AD Computer Object Info
Write-Verbose "`n[*] Finding systems last active within $daysLastActive days`n[*] OS Filter: $OStoSearch"
# Light attrib collection
$domainComputers = Get-ADComputer -Filter {(LastLogonTimeStamp -gt $time) -and (ObjectClass -eq "computer") -and (OperatingSystem -like $OStoSearch)}`
 -Properties Name,Division,Department,Description,OperatingSystem,OperatingSystemVersion,PasswordLastSet,`
 SID,TrustedForDelegation,WhenCreated,WhenChanged,ManagedBy,`
LastLogonDate,IPv4Address,IPv6Address,DistinguishedName,Created -SearchBase $dn -SearchScope Subtree -Server $pdc

# Very heavy all attribute search, many extranious attribs - sub out lines 54-57 for 60 in that case.
#$domainComputers = Get-ADComputer -Filter {(LastLogonTimeStamp -gt $time) -and (ObjectClass -eq "computer") -and (OperatingSystem -like $OStoSearch)} -Properties * -SearchBase $dn -SearchScope Subtree -Server $pdc

Write-Verbose "`nFound: $($domainComputers.count) Objects `nLast Active Within Days: $daysLastActive & OS Type: $OStoSearch"
"`nFound: $($domainComputers.count) Objects `nLast Active Within Days: $daysLastActive & OS Type: $OStoSearch " | Out-File -FilePath "$LogDir\$($Domain.NetBIOSName)-DomainInfo.log" -Append
$domainComputers | group OperatingSystem |  select count, Name| sort Count -Descending | Out-File -FilePath "$LogDir\$($Domain.NetBIOSName)-DomainInfo.log" -Append

Write-Verbose "`n[+] Exporting AD Computer Object data to .CSV"
$domainComputers | Export-Csv -Path "$LogDir\$($Domain.NetBIOSName)-All_Computers-$date.csv" -NoTypeInformation
$domainComputers = $null
# If you need to output a quick converted LastLogon use the bellow
#$domainComputers | %{"`n---------------------------------";$_.name;LastLogon: " +[datetime]::FromFileTime($_.lastlogontimestamp);"OS Type: " + $_.operatingsystem;"OU: "+ $_.distinguishedName}

#Find all users
Write-Verbose "`n[*] Finding all domain users... please wait as this may take a while depending on userbase..."
#$allusers = Get-ADUser -Filter * -Properties * | select Name,givenName,sn,displayName,enabled,LastLogonDate,lastlogon,whencreated,distinguishedName,targetAddress,Company,Department,Division,PasswordLastSet
$allusers = Get-ADUser -Filter * -Properties Name,givenName,sn,displayName,enabled,LastLogonDate,lastlogon,lastLogonTimestamp,whencreated,distinguishedName,targetAddress,Company,Department,Division,PasswordLastSet -server $pdc
Write-Verbose "`n[+] Exporting AD User data to .CSV"
$allusers |select Name,givenName,sn,displayName,enabled,LastLogonDate,lastlogon,lastLogonTimestamp,whencreated,distinguishedName,targetAddress,Company,Department,Division,PasswordLastSet |Export-Csv "$LogDir\$($Domain.NetBIOSName)-All-Users.csv" –NoTypeInformation
 
#Find all users that have not logged in
Write-Verbose "`n[*] Generating unused (no login) AD User data."

$allusers | where {!($_.lastlogontimestamp)} | select Name,givenName,sn,displayName,enabled,lastlogon,whencreated,distinguishedName,targetAddress,Company,Department,Division |Export-Csv "$LogDir\$($Domain.NetBIOSName)-UsersNeverLoggedIn.csv"  –NoTypeInformation
$allusers = $null

#Find groups
Write-Verbose "`n[*] Generating AD Group data... please wait."
$allGroups = Get-ADGroup  -filter *  -Properties * -Server $PDC
Write-Verbose "`n[+] Exporting AD Group data to .CSV"
$allGroups |select Name,objectsid,whenCreated,distinguishedName,GroupCategory,GroupScope,mail |Export-Csv "$LogDir\$($Domain.NetBIOSName)-AllDomainGroups.csv" –NoTypeInformation
 
#Find empty groups
Write-Verbose "`n[+] Exporting empty AD Group data... please wait."
foreach ($group in $allGroups){
    if ($group.members -ne "*"){
        $group | select Name,objectsid,whenCreated,distinguishedName,GroupCategory,GroupScope,mail | Export-Csv "$LogDir\$($Domain.NetBIOSName)-EmptyGroups.csv" –NoTypeInformation -Append
     }
} 
$allGroups = $null

#Find empty OUs
Write-Verbose "`n[*] Generating OU data..." 
$OUS = Get-ADOrganizationalUnit -Filter * -Server $PDC
Write-Verbose "`n[+] Exporting empty OU data..." 
$OUs | ForEach-Object { if (-not (Get-ADObject -SearchBase $_ -SearchScope OneLevel -Filter * )) {$_}} |Export-Csv $LogDir\$($Domain.NetBIOSName)-EmptyOus.csv -NoTypeInformation
$OUs = $null

Write-Verbose "`n[+] Exporting Schema via ldifde" 
ldifde -f "$LogDir\$($Domain.NetBIOSName)_Schema.ldif" -d "CN=Schema,CN=Configuration,$dn"


Write-Verbose "`n[*] Gathering SPN data... Please wait..."
# Create GPO Backup directory if needed
$search = New-Object DirectoryServices.DirectorySearcher([ADSI]"")
$search.filter = "(servicePrincipalName=*)"
$results = $search.Findall()
$AllObjs=@()
foreach($result in $results)

{
        $userEntry = $result.GetDirectoryEntry()

        $ComputerOBj=@()
        $SPNObjHash = @{
                        "OBJECT" = $userEntry.name
                        "DN" = $userEntry.distinguishedName
                        "CAT" = $userEntry.objectCategory
                        "SPNS" = $userEntry.servicePrincipalName
                        }
        $SPNOBj = New-Object PSObject -Property $SPNObjHash
               
       $AllObjs += $SPNOBj
}
Write-Verbose "`n[+] Exporting discovered SPNs to logs..."
foreach ($obj in $allobjs) {
    if ($obj.cat.Value -like "CN=Person*"){
        "`n" |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-PERSON.log -Append
        $obj.OBJECT.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Person.log -Append
        $obj.cat.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Person.log -Append
        $obj.DN.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Person.log -Append
        $obj.SPNS.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Person.log -Append
    }elseif($obj.cat.Value -like "CN=Computer*"){
        "`n" |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Computer.log -Append
        $obj.OBJECT.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Computer.log -Append
        $obj.cat.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Computer.log -Append
        $obj.DN.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Computer.log -Append
        $obj.SPNS.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-Computer.log -Append
    }else{
        "`n" |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-ODD.log -Append
        $obj.OBJECT.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-ODD.log -Append
        $obj.cat.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-ODD.log -Append
        $obj.DN.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-ODD.log -Append
        $obj.SPNS.Value |Out-File $LogDir\$($Domain.NetBIOSName)-SPNs-ODD.log -Append
    
    }

}


Write-Verbose "`n[*] Preparing GPO backup to $LogDir\GPO_$Date"
# Create GPO Backup directory if needed
$GPOBackupPath = "$LogDir\GPOBackup_$Date"
if (!(Test-Path $GPOBackupPath )) { 
    Write-Verbose "`n[+] Log directory not found... creating: $GPOBackupPath " 
    New-Item $GPOBackupPath  -ItemType Directory -Force
}else {
    Write-Verbose "`n[*] Log directory found... user $GPOBackupPath "
}
Write-Verbose "`n[+] Backing up GPOs to directory: $GPOBackupPath`n     Please wait...`n"
Backup-Gpo -All -Path $GPOBackupPath | Out-Null

Write-Verbose "`n[+] Building .ZIP of all collected data." 
If (Test-Path "$RootLogDir\$($Domain.NetBIOSName)-DomainData-$Date.zip" -ErrorAction SilentlyContinue){Remove-Item "$RootLogDir\$($Domain.NetBIOSName)-DomainData.zip" -Force}

ZipFiles -zipfilename "$RootLogDir\$($Domain.NetBIOSName)-DomainData-$Date.zip" -sourcedir $LogDir

Write-Verbose "`n[**********************************************]`n Please submit collected .ZIP file for analysis`n[**********************************************]`n" 
Get-Item "$RootLogDir\$($Domain.NetBIOSName)-DomainData-$Date.zip"

Write-Verbose "`n[*]Log Folder(s) are preserved for informational purposes: $LogDir`n"
Write-Verbose "`n`n[***************************]`n Collection Script Completed`n[***************************]`n" 