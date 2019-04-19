<#
.SYNOPSIS
               AD Replication Health Checker
                  

    Script to check Active Directory replication health and email results.


    *********************** WARNING ***********************
    *       Requires Active Directory PowerShell Module   *
    * Must be run as Domain User to query replication     *
    *******************************************************


.LINK
   https://github.com/nextinstall/activedirectory

.DESCRIPTION
    Script outputs status of Active Driectory replication for each parter and replication set.
   
.PARAMETER replicationOffset
    Time in Minutes that offest should be considered healthy/unhealhty.
    Make SURE this is greater than your longest inter-sitelink delay otherwise health will always be considered
    at issue

.PARAMETER SendEmail
    Skips installation of OMS Agent

.PARAMETER LocalReport
    Outputs .html and .csv reports on the local system.

.NOTES
    Version:            1.0
    Creation Date:      2019/03/11
    Modified Date:      2019/03/11
    Purpose:            Check Active Directory Replication Health
    Author:             Tom Gregory (tom [@] cubelink.org)
    
    Thanks to:          Paul Cunningham who long ago framed the HTML reporting logic in his excellent Exchange scripts: 
                        @ https://paulcunningham.me/

                        The Active Directory Engineering teams at Harvard University and MIT where I got paid to write the 
                        majority of this.


    Version 1.0 - Created script and released to public.
    
.EXAMPLE
    AD-HealthCheck.ps1 -replicationOffset 61 -SendEmail -LocalReport

.EXAMPLE
    Runs the script looking for replication health greater than 61 minutes, 
    sends and email via the $SMTP info embmeded in the script and saves 
    a local copy of the results.

#>
#-------------------------------------------------------[Initialisations]----------------------------------------------------------


[CmdletBinding()]
param(
    [Parameter( Mandatory=$false)]
	[int]$replicationOffset=31,	
    
    [Parameter( Mandatory=$false)]
	[switch]$SendEmail=$false,

	[Parameter( Mandatory=$false)]
	[switch]$LocalReport
	)

#...................................
# Variables
#...................................

#This is KEY - how far back from now is acceptable for healthy replication?
#$replicationOffset = 1

$now = Get-Date -Format F
$AllObjs =@()
$reportbody = $null
$timestamp = get-date -f yyyy-MM-dd_hh-mm-ss
$filename = "ADHealthCHeck - $timestamp"
$reportname = "AD Domain Replication Health Report - $now"
$systeminfo = hostname
$systeminfo += "`nConfigured IP(s): " + (Get-NetIPAddress | ?{ $_.AddressFamily -eq “IPv4” -and !($_.IPAddress -match “169”) -and !($_.IPaddress -match “127”) }).IPAddress

#...................................
# Modify these SMTP settings to
# suit your environment
#...................................
$smtpsettings = @{
	To =  "AD-Platform-Team@mail.domain.org"
	From = "ADHealthCheck@mail.domain.org"
	Subject = $reportname
	SmtpServer = "mailhub.domain.org"
	}


######################################################################################
# Script Logic                                                                       #
######################################################################################
$ADDomain = Get-ADDomain -ErrorAction SilentlyContinue

$servers = $ADDomain.ReplicaDirectoryServers | Sort-Object

#Specify a server for testing/targeting
#$servers = "dc.domain.edu"

$AllObjs =@()
    foreach ($server in $servers) 
    {
		$ComputerOBj=@()
            "Checking $server"
			"Please wait... "

           $CompObjHash = @{
                            "SERVER" = $server
                            "STATUS" = $null
                            "REPLICATION" = $null
                            }
           $ComputerOBj = New-Object PSObject -Property $CompObjHash
           $a=0
      
           if (Test-Connection -Cn $server -quiet){
				$ComputerOBj.status = "ONLINE"
                
                $ReplicationSets = (Get-ADReplicationPartnerMetadata -Target $server -Partition * | Select-Object Server,Partition,Partner,ConsecutiveReplicationFailures,lastreplicationsuccess | Sort-Object server -Descending)
                
                Foreach ($Partner in $ReplicationSets){
                   Foreach ($partion in $Partner.Partition){
                        $successtime = ($Partner).lastreplicationsuccess
                        if ($successtime -lt (get-date).AddMinutes(- $replicationOffset)){
                            "PROBLEM SKEW FOUND@ $successtime on $partner"
                            $ComputerOBj | Add-Member NoteProperty -Name "PARTNER" -Value ($Partner.Partner).TrimStart("CN=NTDS Settings,") -Force
                            $ComputerOBj | Add-Member NoteProperty -Name "PARTITION" -Value $partion -Force
                            $ComputerOBj.'REPLICATION' = "UNHEALTHY" 
                            break
                        }
                    $a++
                    }
                }if ($ComputerOBj.REPLICATION -ne "UNHEALTHY"){$ComputerOBj.'REPLICATION' = "HEALTHY"}                              
			}else {"$Computer appears to be offline!";$ComputerOBj.status = "OFFLINE"}
        
        $ComputerObj
        $AllObjs += $ComputerObj	
    } 
#Uncomment to display array of objects for testing:
#$AllObjs
######################################################################################
# End Script Logic                                                                   #
######################################################################################


######################################################################################
# Create HTML Report                                                                #
######################################################################################

$htmltablerow=$null
$replicationSummaryHTML=$null

$htmlhead="<html>
<style>
BODY{font-family: Arial; font-size: 8pt;}
H1{font-size: 16px;}
H2{font-size: 14px;}
H3{font-size: 12px;}
TABLE{border: 1px solid black; border-collapse: collapse; font-size: 8pt;}
TH{border: 1px solid black; background: #dddddd; padding: 5px; color: #000000;}
TD{border: 1px solid black; padding: 5px; }
td.pass{background: #7FFF00;}
td.warn{background: #FFE600;}
td.fail{background: #FF0000; color: #ffffff;}
td.info{background: #85D4FF;}
</style>
<body>
<h3 align=""center"">$reportname</h3>
<h2 align""left"">Replication Check for time offset greater than $replicationOffset minutes</h2>
<p>Generated: $now</p>"

$outro = "<BR><BR>This email generated from host: $systeminfo."

$htmltail = "</body></html>"	


#Begin Detail table HTML header
$htmltableheader = "<p>
                        <table>
						    <tr>
						        <th>SERVER</th>
						        <th>STATUS</th>
						        <th>REPLICATION</th>
                                <th>DETAILS</th>
						    </tr>"
#End Detail table HTML header

foreach ($line in $AllObjs){
    #Start row
    $htmltablerow ="<tr>"
    $htmltablerow = $htmltablerow + "<td>$($line.Server)</td>"
    
    #Warn if offline
    switch ($line.STATUS)
    {
        "ONLINE" {$htmltablerow= $htmltablerow + "<td class=""pass"">$($line.STATUS)</td>"}
        "OFFLINE" {$htmltablerow = $htmltablerow + "<td class=""warn"">$($line.STATUS)</td>"}
    }
        
    #FAIL if unhealthy
    switch ($line.REPLICATION)
    {
        "UNHEALTHY" {
                        $htmltablerow= $htmltablerow + "<td class=""fail"">$($line.REPLICATION)</td><td>PARTNER: $($line.PARTNER) - PARTITION: $($line.PARTITION)</td>"
                        # foreach ($thing in $line)
                        # {
                        #     $thing
                        # }
                    }
        "HEALTHY" {$htmltablerow = $htmltablerow + "<td class=""pass"">$($line.REPLICATION)</td>"}
    }
    
    #Finish row HTML
    $htmltablerow = $htmltablerow + "</tr>"
    
    #Add row to summary
    $replicationSummaryHTML += $htmltablerow
}

#End Table HTML
$replicationSummaryHTML += "</table>
							</p>"

# Pre-roll report table/fragment
$reportbody = $htmltableheader + $replicationsummaryHTML

#Less fancy version - has no conditional color formatting - HTML fragment for body
#$reportbody = ($AllObjs | select Server,Status,Replication | ConvertTo-Html -Fragment)

#Roll full report
$htmlreport = $htmlhead + "<br>"+"<br>" + $reportbody + "<br>"+"<br>"+ $outro + $htmltail


######################################################################################
# End HTML Summary                                                                   #
######################################################################################


#Output/send the HTML report
if ($SendEmail -or $LocalReport)
{
	if ($SendEmail){
        #Uncomment (or comment out the -attachments portion if your SPAM filter love/hates you or seriously delays attachment emails.)
        Send-MailMessage @smtpsettings -Body $htmlreport -BodyAsHtml -Encoding ([System.Text.Encoding]::UTF8)# -attachments "$filename.csv"
	}
    if ($LocalReport){
        $htmlreport | Out-File "$filename.htm"
        $AllObjs | Export-Csv -Path "$filename.csv" -notypeinformation 
    }
}