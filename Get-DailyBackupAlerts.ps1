<#
.SYNOPSIS
Get-DailyBackupAlerts.ps1 - Exchange 2010 Database Backup Alert Script

.DESCRIPTION
Checks the backup timestamps for the servers
and alerts if a database hasn't been backed up
recently

.INPUTS
No inputs required, however you should modify the Settings.xml file to suit your environment.

.OUTPUTS
Sends an HTML email if databases are detected without
a backup for more than the specified number of hours.

.EXAMPLE
.\Get-DailyBackupAlerts.ps1
Tip: Run as a scheduled task to generate the alerts automatically

.EXAMPLE
.\Get-DailyBackupAlerts.ps1 -AlwaysSend -Log
Sends the report even if no alerts are found, and writes a log file.

.LINK
http://exchangeserverpro.com/set-automated-exchange-2010-database-backup-alert-email

.NOTES
Written By: Paul Cunningham
Website:	http://exchangeserverpro.com
Twitter:	http://twitter.com/exchservpro

Additional Credits: Chris Brown
Website:	http://www.flamingkeys.com
Twitter:	http://twitter.com/chrisbrownie

Change Log
V1.00, 10/11/2011 - Initial version
V1.01, 23/10/2012 - Bug fixes and minor improvements
V1.02, 30/10/2012 - Bug fix with alertflag
V1.03, 11/01/2013 - Many code improvements, more comments, archive mailboxes now counted, and added
					option to always send the report regardless of number of alerts.
V1.04, 15/01/2014 - Minor bug fixes and performance improvements
                    - databases with 1 mailbox now display as 1 instead of 0
                    - mailboxes for databases not on exclude list are no longer retrieved for mailbox counts
                    - backup currently in progress now displays as Yes/No instead of True/False
V1.05, 29/01/2014 - Changed SMTP method to PowerShell 2.0
                    - Fixed minor bug with loading of Exchange snap-in
V1.06, 22/05/2014 - Minor bug fixes
                    - Separated customizations into Settings.xml file
                    - Adding logging option
#>

#requires -version 2

[CmdletBinding()]
param (
	[Parameter( Mandatory=$false)]
	[switch]$Log,

	[Parameter( Mandatory=$false)]
	[switch]$AlwaysSend
	)


#...................................
# Variables
#...................................

$report = @()
$alertdbs = @()
$okdbs = @()
[bool]$alertflag = $false
$excludedbs = @()

#Current time is used in alert calculations
$now = [DateTime]::Now

$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logfile = "$myDir\Get-DailyBackupAlerts.log"

# Logfile Strings
$logstring0 = "====================================="
$logstring1 = " Exchange Database Backup Check"
$initstring0 = "Initializing..."
$initstring1 = "Loading the Exchange Server PowerShell snapin"
$initstring2 = "The Exchange Server PowerShell snapin did not load."
$initstring3 = "Setting scope to entire forest"

# Import Settings.xml config file
[xml]$ConfigFile = Get-Content "$MyDir\Settings.xml"

# Email settings from Settings.xml
$smtpsettings = @{
    To = $ConfigFile.Settings.EmailSettings.MailTo
    From = $ConfigFile.Settings.EmailSettings.MailFrom
    SmtpServer = $ConfigFile.Settings.EmailSettings.SMTPServer
    }


# Modify these alert thresholds in Settings.xml
# You can set a different alert threshold for Mondays
# to account for weekend backup schedules
$day = (Get-Date).DayOfWeek
if ($day -eq "Monday")
{
	[int]$threshold = $ConfigFile.Settings.OtherSettings.ThresholdMonday
}
else
{
	[int]$threshold = $ConfigFile.Settings.OtherSettings.ThresholdOther
}


# If you wish to exclude databases add them to the
# Settings.xml file

$exclusions = @($ConfigFile.Settings.Exclusions.DBName)

foreach ($dbname in $exclusions)
{
    $excludedbs += $dbname
}


#...................................
# Functions
#...................................

#This function is used to write the log file if -Log is used
Function Write-Logfile()
{
	param( $logentry )
	$timestamp = Get-Date -DisplayHint Time
	"$timestamp $logentry" | Out-File $logfile -Append
}


#...................................
# Initialization
#...................................

#Log file is overwritten each time the script is run to avoid
#very large log files from growing over time
if ($Log) {
	$timestamp = Get-Date -DisplayHint Time
	"$timestamp $logstring0" | Out-File $logfile
	Write-Logfile $logstring1
	Write-Logfile "  $now"
	Write-Logfile $logstring0
}

$tmpstring = "Threshold for this check is $threshold hours"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}

#Add Exchange 2010 snapin if not already loaded in the PowerShell session
if (!(Get-PSSnapin | where {$_.Name -eq "Microsoft.Exchange.Management.PowerShell.E2010"}))
{
	Write-Verbose $initstring1
	if ($Log) {Write-Logfile $initstring1}
	try
	{
		Add-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction STOP
	}
	catch
	{
		#Snapin was not loaded
		Write-Verbose $initstring2
		if ($Log) {Write-Logfile $initstring2}
		Write-Warning $_.Exception.Message
		EXIT
	}
	. $env:ExchangeInstallPath\bin\RemoteExchange.ps1
	Connect-ExchangeServer -auto -AllowClobber
}



#...................................
# Script
#...................................

#Get all Mailbox and Public Folder databases
$tmpstring = "Retrieving database list"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}

$dbs = @(Get-MailboxDatabase -Status | Where {$_.Recovery -ne $true})
$mbdbs = $dbs
if ($dbs)
{
	$tmpstring = "$($dbs.count) mailbox databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

}
else
{
	$tmpstring = "No mailbox databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
}

$pfdbs = @(Get-PublicFolderDatabase -Status)
$tmpstring = "$($pfdbs.count) public folder databases found"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}


if ($pfdbs)
{
	$dbs += $pfdbs
	$tmpstring = "$($dbs.count) total databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
}
else
{
	$tmpstring = "No mailbox databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
}

#If a list of excluded databases exists, remove them from $dbs
if ($excludedbs)
{
	$tmpstring = "Removing excluded databases from the checks"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
	$tempdbs = $dbs
	$dbs = @()
	foreach ($tempdb in $tempdbs)
	{
		if (!($excludedbs -icontains $tempdb))
		{
			$tmpstring = "$tempdb included"
            Write-Verbose $tmpstring
            if ($Log) {Write-Logfile $tmpstring}
			$dbs = $dbs += $tempdb
		}
		else
		{
			$tmpstring = "$tempdb excluded"
            Write-Verbose $tmpstring
            if ($Log) {Write-Logfile $tmpstring}
		}
	}
}

#Get list of mailboxes only for databases that haven't been excluded
$tmpstring = "Retrieving list of mailboxes for use in mailbox count later"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}
$mailboxes = @($mbdbs | Get-Mailbox -IgnoreDefaultScope -ResultSize Unlimited)


#Check each database for most recent backup timestamp
foreach ($db in $dbs)
{
	$tmpstring = "---- Checking $($db.name) ----"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

	$lastbackup = @{}
	[int]$ago = $null

	if ( $db.LastFullBackup -eq $null -and $db.LastIncrementalBackup -eq $null)
	{
		#No backup timestamp was present. This means either the database has
		#never been backed up, or it was unreachable when this script ran
		$lastbackup.time = "Never/Unknown"
		$lastbackup.type = "Never/Unknown"
		[string]$ago = "Never/Unknown"
	}
	elseif ( $db.LastFullBackup -lt $db.LastIncrementalBackup )
	{
		#Most recent backup was Incremental
		$lastbackup.time = $db.LastIncrementalBackup
		$lastbackup.type = "Incremental"
		[int]$ago = ($now - $lastbackup.time).TotalHours
		[int]$ago = "{0:00}" -f $ago
	}
	elseif ( $db.LastIncrementalBackup -lt $db.LastFullBackup )
	{
		#Most recent backup was Full
		$lastbackup.time = $db.LastFullBackup
		$lastbackup.type = "Full"
		[int]$ago = ($now - $lastbackup.time).TotalHours
		[int]$ago = "{0:00}" -f $ago
	}

	$tmpstring = "Last backup of $($db.name) was $($lastbackup.type) on $($lastbackup.time), $ago hours ago"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

	#Determines the database type (Mailbox or Public Folder)
	if ($db.IsMailboxDatabase -eq $true) {$dbtype = "Mailbox"}
	if ($db.IsPublicFolderDatabase -eq $true) {$dbtype = "Public Folder"}

	#Report data is collected into a custom object
	$dbObj = New-Object PSObject
	if ( $dbtype -eq "Public Folder")
	{
		#Exchange 2007/2010 Public Folder databases are only associated with a server
		$dbObj | Add-Member NoteProperty -Name "Server/DAG" -Value $db.Server
		[string]$mbcount = "n/a"
	}
	else
	{
		#Exchange 2007/2010 Mailbox databases can be associated with a server or DAG
		if ($db.MasterServerOrAvailabilityGroup)
		{
			$dbObj | Add-Member NoteProperty -Name "Server/DAG" -Value $db.MasterServerOrAvailabilityGroup
		}
		else
		{
			$dbObj | Add-Member NoteProperty -Name "Server/DAG" -Value $db.ServerName
		}
		
		#Mailbox count calculated for Mailbox Databases, including Exchange 2010 Archive mailboxes
		[int]$mbcount = 0
		[int]$mbcount = @($mailboxes | Where-Object {$_.Database -eq $($db.name)}).count
        [int]$archivecount = 0
        [int]$archivecount = @($mailboxes | Where-Object {$_.ArchiveDatabase -eq $($db.name)}).count
        [int]$mbcount = $mbcount + $archivecount
	}
	
	$dbObj | Add-Member NoteProperty -Name "Database" -Value $db.name
	$dbObj | Add-Member NoteProperty -Name "Database Type" -Value $dbtype
	
	#Check last backup time against alert threshold and set report status accordingly
	if ( $ago -gt $threshold -or $ago -eq "Never")
	{
		$dbObj | Add-Member NoteProperty -Name "Status" -Value "Alert"
		[bool]$alertflag = $true
		$tmpstring = "Alert flag is $alertflag"
        Write-Verbose $tmpstring
        if ($Log) {Write-Logfile $tmpstring}
	}
	else
	{
		$dbObj | Add-Member NoteProperty -Name "Status" -Value "OK"
	}
	
    #Determine Yes/No status for backup in progress
    if ($($db.backupinprogress) -eq $true) {$inprogress = "Yes"}
    if ($($db.backupinprogress) -eq $false) {$inprogress = "No"}

	$dbObj | Add-Member NoteProperty -Name "Mailboxes" -Value $mbcount
	$dbObj | Add-Member NoteProperty -Name "Last Backup Type" -Value $lastbackup.type
	$dbObj | Add-Member NoteProperty -Name "Hrs Ago" -Value $ago
	$dbObj | Add-Member NoteProperty -Name "Time Stamp" -Value $lastbackup.time
	$dbObj | Add-Member NoteProperty -Name "Currently Running" -Value $inprogress

	#Add the custom object to the report
	$report = $report += $dbObj
}
#All databases have now been checked

$tmpstring = "$($report.count) total databases checked"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}

$alertdbs = @($report | Where-Object {$_.Status -eq "Alert"})
$okdbs = @($report | Where-Object {$_.Status -eq "OK"})

#Send the email if there is at least one alert, or if -AlwaysSend is set
if (($alertflag -and $alertdbs) -or ($alwayssend))
{
	$tmpstring = "Alert email will be sent"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
	
	#Common HTML head and styles
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
                <body>"

	#Summarise databases with Alert status
	if ($alertdbs)
	{
		$totalalerts = $alertdbs.count
		$alertintro = "<p>The following databases have not been backed up in the last $threshold hours.</p>"
		$alerthtml = $alertdbs | ConvertTo-Html -Fragment
	}
	else
	{
		$totalalerts = 0
	}

	#Summarise databases with OK status
	if ($okdbs)
	{
		Switch ($totalalerts) {
			0 { $okintro = "<p>The following databases have been backed up in the last $threshold hours.</p>" }
			default { $okintro = "<p>The following databases have been backed up in the last $threshold hours.</p>" }
		}
		$okhtml = $okdbs | ConvertTo-Html -Fragment
	}
	else
	{
		$okintro = "<p>There are no databases that have been backed up in the last $threshold hours.</p>"
	}

	$tmpstring = "Report summary: Alerts $totalalerts, OK $($okdbs.count)"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

	#Set some additional content for the email report
	$intro = "<p>This is the Exchange database backup status for the last $threshold hours.</p>"

	Switch ($totalalerts)
	{
		1 {
			$messageSubject = "Daily Check - Exchange Database Backups ($totalalerts alert)"
			$summary = "<p>There is <strong>$totalalerts</strong> database backup alert today.</p>"
		}
		default {
			$messageSubject = "Daily Check - Exchange Database Backups ($totalalerts alerts)"
			$summary = "<p>There are <strong>$totalalerts</strong> database backup alerts today.</p>"
		}
	}
	
	#$outro = "<p>You can place your own instructional text here or perhaps a link to your procedure for responding to backup alerts.</p>"
    $outro = ""

	$htmltail = "</body>
				</html>"

	#Get ready to send email message
	$htmlreport = $htmlhead + $intro + $summary + $alertintro + $alerthtml + $okintro + $okhtml + $outro + $htmltail

	#Send email message
	$tmpstring = "Sending email report"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

    try
    {
        Send-MailMessage @smtpsettings -Subject $messageSubject -Body $htmlreport -BodyAsHtml -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction STOP
    }
    catch
    {
        $tmpstring = $_.Exception.Message
        Write-Warning $tmpstring
        if ($Log) {Write-Logfile $tmpstring}
    }
}

$tmpstring = "Finished."
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}