# Get-DailyBackupAlerts.ps1
Generate an email report of Exchange database backup times. Download the latest version of the script from the [TechNet Script Gallery](https://gallery.technet.microsoft.com/office/Generate-a-report-and-fa3b0540) or the [releases](https://github.com/cunninghamp/Get-DailyBackupAlerts.ps1/releases) page.

## Description
Checks the backup timestamps for Exchange databases and alerts if a database hasn't been backed up recently.

## Inputs
No inputs required, however you should modify the Settings.xml file to suit your environment.

## Outputs
Sends an HTML email if databases are detected without a backup for more than the specified number of hours.

## Examples
```
.\Get-DailyBackupAlerts.ps1
```
Tip: Run as a scheduled task to generate the alerts automatically

```
.\Get-DailyBackupAlerts.ps1 -AlwaysSend -Log
```
Sends the report even if no alerts are found, and writes a log file.

## More information
http://exchangeserverpro.com/set-automated-exchange-2010-database-backup-alert-email

## Credits
Written by: Paul Cunningham

Find me on:

* My Blog:	https://paulcunningham.me
* Twitter:	https://twitter.com/paulcunningham
* LinkedIn:	https://au.linkedin.com/in/cunninghamp/
* Github:	https://github.com/cunninghamp

Check out my [books](https://paulcunningham.me/books/) and [courses](https://paulcunningham.me/training/) to learn more about Office 365 and Exchange Server.

Additional Credits:
* Chris Brown, http://www.flamingkeys.com and http://twitter.com/chrisbrownie
