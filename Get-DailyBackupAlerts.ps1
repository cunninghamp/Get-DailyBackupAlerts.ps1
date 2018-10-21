<#
.SYNOPSIS
Get-DailyBackupAlerts.ps1 - Exchange 2010 Database Backup Alert Script

.DESCRIPTION
Checks the backup timestamps for the servers
and alerts if a database hasn't been backed up
recently

.INPUTS
No inputs required, however you should modify the Settings.xml file to
suit your environment.

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
Written by: Paul Cunningham

Find me on:

* My Blog:	https://paulcunningham.me
* Twitter:	https://twitter.com/paulcunningham
* LinkedIn:	https://au.linkedin.com/in/cunninghamp/
* Github:	https://github.com/cunninghamp

Additional Credits:
- Chris Brown (http://www.flamingkeys.com, http://twitter.com/chrisbrownie)
- @pascalrip on GitHub (https://github.com/pascalrip)

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
V1.07, 18/08/2016 - Added handling for differential backups
                    - Added color-coded backup status
                    - Hours since last backup now based on UTC
                    - General code cleanup
V1.08, 25/08/2016 - Fixed incorrect number formatting
                    - Fixed bug with databases that haven't been backed up being reported as "Incremental"
V1.09, 01/09/2016 - Fixed bug with Exchange 2010 servers throwing an error calculating hours since last backup
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

if ($Log) {
    $smtpsettings.Add("Attachments",$logfile)
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

#HTML replacements for color-coded alerts
#from @pascalrip on GitHub
$tdOK="<td>OK</td>"
$tdOKgreen="<td class=""pass"">OK</td>"
$tdALERT="<td>Alert</td>"
$tdALERTred="<td class=""fail"">Alert</td>"


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

#Load Exchange management tools if not already loaded
if (!(Test-Path function:Get-MailboxDatabase)) {
	
    Write-Verbose $initstring1
	if ($Log) {Write-Logfile $initstring1}
	
    try {
	. $env:ExchangeInstallPath\bin\RemoteExchange.ps1
	Connect-ExchangeServer -auto -AllowClobber
	}
	catch {
		#Snapin was not loaded
		Write-Verbose $initstring2
		if ($Log) {Write-Logfile $initstring2}
		throw $_.Exception.Message
	}
}


#...................................
# Script
#...................................

#Get all Mailbox and Public Folder databases in the organization
$tmpstring = "Retrieving database list"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}

#Get mailbox databases, accounting for pre-2010 and pre-2013 scenarios
$CommandGetMDB = @(Get-Command Get-MailboxDatabase)[0]
if ($CommandGetMDB.Parameters.ContainsKey("IncludePreExchange2010")) {
    $dbs = @(Get-MailboxDatabase -Status -IncludePreExchange2010 | Where {$_.Recovery -ne $true})
}
elseif ($CommandGetMDB.Parameters.ContainsKey("IncludePreExchange2013")) {
    $dbs = @(Get-MailboxDatabase -Status -IncludePreExchange2013 | Where {$_.Recovery -ne $true})
}
else {
    $dbs = @(Get-MailboxDatabase -Status | Where {$_.Recovery -ne $true})
}

#Set another variable with all mailbox database before removing excluded DBs from $dbs
$mbdbs = $dbs

if ($dbs) {
	$tmpstring = "$($dbs.count) mailbox databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

}
else {
	$tmpstring = "No mailbox databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
}

#Get public folder databases, accounting for pre-2010 scenario
$CommandGetPFDB = @(Get-Command Get-PublicFolderDatabase)[0]
if ($CommandGetPFDB.Parameters.ContainsKey("IncludePreExchange2010")) {
    $pfdbs = @(Get-PublicFolderDatabase -Status -IncludePreExchange2010)
}
else {
    $pfbs = @(Get-PublicFolderDatabase -Status)
}


$pfdbs = @(Get-PublicFolderDatabase -Status)
$tmpstring = "$($pfdbs.count) public folder databases found"
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}

if ($pfdbs) {
	$dbs += $pfdbs
	$tmpstring = "$($dbs.count) total databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
}
else {
	$tmpstring = "No mailbox databases found"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
}


#If a list of excluded databases exists, remove them from $dbs
if ($excludedbs) {
	$tmpstring = "Removing excluded databases from the checks"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}
	
    $tempdbs = $dbs
	$dbs = @()
	
    foreach ($tempdb in $tempdbs) {
		if (!($excludedbs -icontains $tempdb)) {
			$tmpstring = "$tempdb included"
            Write-Verbose $tmpstring
            if ($Log) {Write-Logfile $tmpstring}
			$dbs = $dbs += $tempdb
		}
		else {
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
foreach ($db in $dbs) {
	
    $tmpstring = "---- Checking $($db.name) ----"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

    if ($db.Mounted -eq $false) {
        #If databases are dismounted their status can't be retrieved
        #so they can't be reported on correctly.
        
        $tmpString = "$($db.name) is dismounted"
        Write-Verbose $tmpString
        if ($Log) {Write-Logfile $tmpstring}
    }
    elseif ($db.Mounted -eq $null) {
        #Indicates Information Store service was stopped on the server.
        #If IS service is stopped the database status can't be retrieved
        #so they can't be reported on correctly.

        $tmpString = "$($db.Name) could not be reached"
        Write-Verbose $tmpString
        if ($Log) {Write-Logfile $tmpstring}
    }
    elseif ( -not $db.LastFullBackup -and -not $db.LastIncrementalBackup -and -not $db.LastDifferentialBackup) {
		#No backup timestamps for any backup type is present. This means either the database has
		#never been backed up, or it was unreachable when this script ran.

		$LastBackups = @{
                            Incremental="n/a"
                            Differential="n/a"
                            Full="n/a"
                        }
	}
	else {
        #Backup timestamp was successfully retrieved, so now we need to work out which is
        #the most recent backup.

        #Check incremental backup timestamp and calculate hours since last Inc backup
        if (-not $db.LastIncrementalBackup) {

            $tmpString = "$($db.Name) has no incremental backup timestamp"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}

            $LastInc = "Never"
        }
        else {
            $tmpString = "$($db.Name) last incremental was $($db.LastIncrementalBackup) (UTC: $($db.LastIncrementalBackup.ToUniversalTime()))"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}

            [int]$LastInc = (($now.ToUniversalTime() - $db.LastIncrementalBackup.ToUniversalTime()).TotalHours)
        }

        #Check differential backup timestamp and calculate hours since last Diff backup
        if (-not $db.LastDifferentialBackup) {

            $tmpString = "$($db.Name) has no differential backup timestamp"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}

            $LastDiff = "Never"
        }
        else {
            $tmpString = "$($db.Name) last differential was $($db.LastDifferentialBackup) (UTC: $($db.LastDifferentialBackup.ToUniversalTime()))"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}

            [int]$LastDiff = (($now.ToUniversalTime() - $db.LastDifferentialBackup.ToUniversalTime()).TotalHours)
        }

        #Check full backup timestamp and calculate hours since last Full backup
        if (-not $db.LastFullBackup) {

            $tmpString = "$($db.Name) has no full backup timestamp"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}

            $LastFull = "Never"
        }
        else {
            $tmpString = "$($db.Name) last full was $($db.LastFullBackup) (UTC: $($db.LastFullBackup.ToUniversalTime()))"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}
 
            [int]$LastFull = (($now.ToUniversalTime() - $db.LastFullBackup.ToUniversalTime()).TotalHours)
        }

        #Values in this hashtable are calculated as hours since last backup
        $LastBackups = @{
                Incremental=$LastInc
                Differential=$LastDiff
                Full=$LastFull
                }
    }

    #From last backup information retrieve most recent backup
    $LatestBackup = ($LastBackups.GetEnumerator() | Sort-Object -Property Value)[0]
    if ($($LatestBackup.Value) -eq "n/a") {
            $tmpstring = "$($db.name) has never been backed up."
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}
    }
    else {
            $tmpstring = "Last backup of $($db.name) was $($LatestBackup.Key) $($LatestBackup.Value) hours ago"
            Write-Verbose $tmpString
            if ($Log) {Write-Logfile $tmpstring}
    }
 
 	#Determines the database type (Mailbox or Public Folder)
	if ($db.IsMailboxDatabase -eq $true) {$dbtype = "Mailbox"}
	if ($db.IsPublicFolderDatabase -eq $true) {$dbtype = "Public Folder"}

    #Report data is collected into a custom object
    $dbObj = New-Object PSObject
	if ( $dbtype -eq "Public Folder") {
		    #Exchange 2007/2010 Public Folder databases are only associated with a server
		    $dbObj | Add-Member NoteProperty -Name "Server/DAG" -Value $db.Server
		    [string]$mbcount = "n/a"
	    }
	else {
		    #Exchange Mailbox databases can be associated with a server or DAG
		    if ($db.MasterServerOrAvailabilityGroup)
		    {
			    $dbObj | Add-Member NoteProperty -Name "Server/DAG" -Value $db.MasterServerOrAvailabilityGroup
		    }
		    else
		    {
			    $dbObj | Add-Member NoteProperty -Name "Server/DAG" -Value $db.ServerName
		    }
		
		    #Mailbox count calculated for Mailbox Databases, including Archive mailboxes
		    [int]$mbcount = 0
		    [int]$mbcount = @($mailboxes | Where-Object {$_.Database -eq $($db.name)}).count
            [int]$archivecount = 0
            [int]$archivecount = @($mailboxes | Where-Object {$_.ArchiveDatabase -eq $($db.name)}).count
            [int]$mbcount = $mbcount + $archivecount
	    }
	
	$dbObj | Add-Member NoteProperty -Name "Database" -Value $db.name
	$dbObj | Add-Member NoteProperty -Name "Database Type" -Value $dbtype

	#Check last backup time against alert threshold and set report status accordingly
	if ($($LatestBackup.Value) -eq "n/a") {
		$dbObj | Add-Member NoteProperty -Name "Status" -Value "Alert"
		[bool]$alertflag = $true
		$tmpstring = "Alert flag is $alertflag"
        Write-Verbose $tmpstring
        if ($Log) {Write-Logfile $tmpstring}
    }
	elseif ($($LatestBackup.Value) -gt $threshold) {
		$dbObj | Add-Member NoteProperty -Name "Status" -Value "Alert"
		[bool]$alertflag = $true
		$tmpstring = "Alert flag is $alertflag"
        Write-Verbose $tmpstring
        if ($Log) {Write-Logfile $tmpstring}
    }
	else {
	    $dbObj | Add-Member NoteProperty -Name "Status" -Value "OK"
    }

    #Determine Yes/No status for backup in progress
    if ($($db.backupinprogress) -eq $true) {$inprogress = "Yes"}
    if ($($db.backupinprogress) -eq $false) {$inprogress = "No"}

	$dbObj | Add-Member NoteProperty -Name "Mailboxes" -Value $mbcount

    if ($($LatestBackup.Value) -eq "n/a") {
	    $dbObj | Add-Member NoteProperty -Name "Last Backup Type" -Value "n/a"
    }
    else {
        $dbObj | Add-Member NoteProperty -Name "Last Backup Type" -Value $($LatestBackup.Key)
    }

	$dbObj | Add-Member NoteProperty -Name "Hours Ago" -Value $($LatestBackup.Value)
	
    if ($($LatestBackup.Value -eq "n/a")) {
        $dbObj | Add-Member NoteProperty -Name "UTC Time Stamp" -Value "Never"
    }
    else {
        switch ($($LatestBackup.Key)) {
            "Full" { $dbObj | Add-Member NoteProperty -Name "UTC Time Stamp" -Value $db.LastFullBackup.ToUniversalTime() }
            "Incremental" { $dbObj | Add-Member NoteProperty -Name "UTC Time Stamp" -Value $db.LastIncrementalBackup.ToUniversalTime() }
            "Differential" { $dbObj | Add-Member NoteProperty -Name "UTC Time Stamp" -Value $db.LastDifferentialBackup.ToUniversalTime() }
        }
    }

    #Check whether a backup is currently running
	$dbObj | Add-Member NoteProperty -Name "Backup Currently Running" -Value $inprogress

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
if (($alertflag -and $alertdbs) -or ($alwayssend)) {
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
	if ($alertdbs) {
		$totalalerts = $alertdbs.count
		$alertintro = "<p>The following databases have not been backed up in the last $threshold hours.</p>"
		$alerthtml = $alertdbs | ConvertTo-Html -Fragment
        $alerthtml = $alerthtml -replace $tdALERT, $tdALERTred
	}
	else {
		$totalalerts = 0
	}

	#Summarise databases with OK status
	if ($okdbs)	{
		Switch ($totalalerts) {
			0 { $okintro = "<p>The following databases have been backed up in the last $threshold hours.</p>" }
			default { $okintro = "<p>The following databases have been backed up in the last $threshold hours.</p>" }
		}
		$okhtml = $okdbs | ConvertTo-Html -Fragment
        $okhtml = $okhtml -replace $tdOK, $tdOKgreen
	}
	else {
		$okintro = "<p>There are no databases that have been backed up in the last $threshold hours.</p>"
	}

	$tmpstring = "Report summary: Alerts $totalalerts, OK $($okdbs.count)"
    Write-Verbose $tmpstring
    if ($Log) {Write-Logfile $tmpstring}

	#Set some additional content for the email report
	$intro = "<p>This is the Exchange database backup status for <strong>$now</strong> (UTC: $($now.ToUniversalTime()))</p>"

	Switch ($totalalerts) {
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

    try {
        Send-MailMessage @smtpsettings -Subject $messageSubject -Body $htmlreport -BodyAsHtml -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction STOP
    }
    catch {
        $tmpstring = $_.Exception.Message
        Write-Warning $tmpstring
        if ($Log) {Write-Logfile $tmpstring}
    }
}

$tmpstring = "Finished."
Write-Verbose $tmpstring
if ($Log) {Write-Logfile $tmpstring}
