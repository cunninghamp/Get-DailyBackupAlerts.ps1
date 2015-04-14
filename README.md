# Get-DailyBackupAlerts.ps1
Generate an email report of Exchange database backup times

##Description
Checks the backup timestamps for Exchange databases and alerts if a database hasn't been backed up recently

##Inputs
No inputs required, however you should modify the Settings.xml file to suit your environment.

##Outputs
Sends an HTML email if databases are detected without a backup for more than the specified number of hours.

##Examples
```
.\Get-DailyBackupAlerts.ps1
```
Tip: Run as a scheduled task to generate the alerts automatically

```
.\Get-DailyBackupAlerts.ps1 -AlwaysSend -Log
```
Sends the report even if no alerts are found, and writes a log file.

##More information
http://exchangeserverpro.com/set-automated-exchange-2010-database-backup-alert-email

##Credits
Written by: Paul Cunningham

Find me on:

* My Blog:	http://paulcunningham.me
* Twitter:	https://twitter.com/paulcunningham
* LinkedIn:	http://au.linkedin.com/in/cunninghamp/
* Github:	https://github.com/cunninghamp

For more Exchange Server tips, tricks and news check out Exchange Server Pro.

* Website:	http://exchangeserverpro.com
* Twitter:	http://twitter.com/exchservpro

Additional Credits:
* Chris Brown, http://www.flamingkeys.com and http://twitter.com/chrisbrownie
