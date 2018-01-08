###############################################################################
# Windows PE Automatisationsscript
# Version 1.0 / 19.12.2017
# Sebastian Reiche - Sebastian.Reiche@medion.com
###############################################################################
<#
.SYNOPSIS  
    Windows PE Automatiosationsscript   
      
.DESCRIPTION  
    Automatisierung von Testprozessen wie z.b. BurnIn Test
    Automatisches hinzufügen der möglichen Verbindungen und Auslesen der Systeminformationen
    Speichern/upload der gesammelten Daten auf dem FTP Server / USB
      
.NOTES  
    File Name  : WinPE_BurninTest.ps1  
    Author     : Sebastian Reiche - Sebastian.Reiche@medion.com 

.LINK  
    Erläuterungen zu BurnIn Testparametern:  
    Powershell Win32 Classes: https://msdn.microsoft.com/de-de/library/aa394084(v=vs.85).aspx
    Dokumentation und Files sollten unter folgenden Pfad zu finden sein:
    \\172.18.20.238\Software\Intern\WinPE_Test\PE_BurnIn  
 

.EXAMPLE  
    Ausführen des Scripts über "powershell.exe -ExecutionPolicy bypass WinPE_BurninTest.ps1"
    Das Script sollte bei WinPE start automatisch ausgeführt werden. 
    Für manuelle Tests ist ein separater aufruf wie oben beschrieben nötig. Eine Netzwerkverbindung sollte 
    automatisch hergestellt werden. Das Script bietet manuelle Testauswahlmöglichkeiten, oder startet nach 
    10 Minuten automatisch.  

.PARAMETER foo  
   The .Parameter area in the script is used to derive the contents of the PARAMETERS in Get-Help output which   
   documents the parameters in the param block. The section takes a value (in this case foo,  
   the name of the first actual parameter), and only appears if there is parameter of that name in the  
   params block. Having a section for a parameter that does not exist generate no extra output of this section  
   Appears in -det, -full (with more info than in -det) and -Parameter (need to specify the parameter name)  

#>

############################################################################################
###### Änderungshistorie
############################################################################################ 

# 14.11.17 - S.R.
# - Anpassung der Dokumentation; Cleanen der überflüssigen Variablen
#
# 11.12.17 - S.R. 
# - elseif auf switch-case umgeschrieben.
# - umgebungsvariable zum bit.exe aufruf. 
# - Fehlerkorrektur wlan Verbindungsaufbau
# - Filename string geändert
# - zugriff auf wifi config file geändert
#
# 12.12.17 - S.R.
# - Implementierung FTPWebRequest zum hochladen der Ergebnisse
# - Start-Process varianten statt *.bat aufruf für verschiedene Funktionstests
# - 10min Timer zum Autostart implementiert
#
# 13.12.17 - S.R.
# - Implementierung try/catch wlan switch für verfügbare verbindungen
#
# 14.12.17 - S.R.
# - Implementierung VLC Process
# - Benutzereingabe für Dateinamenwechsel angepasst 
# - Schönheitskorrekturen im Script
#
# 18.12.17 - S.R.
#
# - Anpassung Timer Event 
# - Implementierung neue ReadHost Funktion mit timeout
#
# 05.01.1.87 - SiT
# - Mousemove Test zum Keyboardtest hinzugefügt
#
#
#

############################################################################################
###### Parameter/Variablen
############################################################################################

Param 
( 
[String]$Computer = "LocalHost"  # entspricht $Computer = "." 
) # Param

# Global & Co
$Line = "`n" # Zeilenumbruch schreiben 
$stopwatch = New-Object System.Diagnostics.Stopwatch #Stopuhr Objekt erstellen
$Global:datum = Get-Date -format "d MMM yyyy" #Datumsobjekt
$Global:uhrzeit = Get-Date -Format "HH:mm" #Uhrzeit
$Global:Systemobj = Get-WmiObject -class win32_OperatingSystem -Computername $Computer       
$Global:BiosSn = Get-WmiObject -class Win32_Bios -Computername $Computer # SN aus BIOS für Filename $BiosSn.SerialNumber
$Global:Modelname = Get-WmiObject -class win32_ComputerSystem -ComputerName $Computer # Modelname: $Modelname.Model 
$Global:usedwlanstatus = "Kein WLAN verfügbar!" #dummytext
$Global:usedwlan = 0; #wlan connection ja= 1 / nein= 0
$Global:Fileuploadstatus = "unbekannt" #dummytext
$Global:Fileupload = 0; #file uploaded ja= 1 / nein= 0
$ErrorActionPreference = "SilentlyContinue" #Errormessages unterdrücken und weiter.. werden im catch gecached

#Keyboardtest
$Global:KeyboardtestPfad = "$PSScriptRoot\keyboardtestutility.exe"

# FTP Data
$ftpIP = "62.180.131.133:21"
$ftpDNS = "medftp.medion.com"
$PingServer = "8.8.8.8" # Google DNS

# VLC Parameter

$Global:vlcPfad = ${env:ProgramFiles}+"\vlc\vlc.exe"
$vlcArguments = "-f -L --no-qt-privacy-ask --no-audio"
#$vlcMovie = "$PSScriptRoot\mov.mp4 $vlcArguments"
$Global:vlcMovie = "X:\Program Files\vlc\mov.mp4"
#$vlcMovie =  "$($PSScriptRoot)\mov.mp4 -f -L --no-qt-privacy-ask --no-audio"

# BurnIn Parameter

$Global:BurnPfad = ${env:ProgramFiles}+"\BurnInTest\bit.exe" #x64
$Global:BurnPfad32 = ${env:ProgramFiles}+"\BurnInTest\bit32.exe" #x86
$Global:BurnArguments = "/h /x /r /c preferedtestconfig.bitcfg" # BurnIn Testkonfiguration File - wird in BurnIn eingestellt und kann dann exportiert werden

# Arguments Documentation
#
#-C [configfilename]
#Loads the configuration file specified by [configfilename]
#
#-D [minutes]
#Sets the test duration to the value specified by minutes. Decimal values can be used.
#
#-H
#Set the screen resolution to 1024 x 768 with 32-bit color on startup. This is intended for use with BurnInTest when running on Microsoft WinPE.
#
#-M
#Automatically display the Machine ID Window when BurnInTest is started. This can be useful in a production line scenario to allow the tester to enter test specific information in a more automated fashion.
#
#-R
#Executes the tests immediately without needing to press the go button. It also skips the pre-test warning message.
#
#-U
#Force BurnInTest to set logging on at startup. Logging will be started with Activity trace 2 logging and a file name of Debug<_date/time>.trace.
#
#-W
#Minimize the amount of System Information collected and displayed by BurnInTest. This can be useful for test automation as is can take some time to collect this information and slow test startup. It could also be used to simply reduce the amount of system information in reports.
#
#-X
#Skip the DirectX version checks at startup time. This can be useful for users that do not want to install the latest version of DirectX and do not want to use the DirectX tests (eg. 3D tests).
#



############################################################################################
###### WLAN Connectivity
############################################################################################
Clear-Host
Write-Host "#########################################" -ForegroundColor White
Write-Host "#########Establish WLAN Connection#######" -ForegroundColor White
Write-Host "#########################################"$Line -ForegroundColor White

try 
 {
    netsh wlan add profile filename="$PSScriptRoot\WiFi1.xml"
    netsh wlan add profile filename="$PSScriptRoot\WiFi2.xml"
    netsh wlan add profile filename="$PSScriptRoot\WLAN_7590_r302.xml"
 }#try
catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName

}#catch



try 
{
    Write-Host "Try to connect to WLAN: Audit AC"
    # Verbinde mit Audit AC Wlan 
    netsh wlan connect name="Audit ac"

    Write-Host "Testing Internetconnection..."
    if (test-connection -computername $PingServer -quiet) 
    {
        Write-Host "Ping successful." -ForegroundColor Green
        $Global:usedwlanstatus = "Audit ac"
        $Global:usedwlan = 1;
    }else{
        Write-Host "Ping to $PingServer was not successful." -ForegroundColor Red
        Write-Host "Try to connect to WLAN: Audit_R302_2,4GHz"
        netsh wlan connect name="Audit_R302_2,4GHz"
            if (test-connection -computername $PingServer -quiet) 
            {
                Write-Host "Ping successful." -ForegroundColor Green
                $Global:usedwlanstatus = "Audit_R302_2,4GHz"
                $Global:usedwlan = 1;
            }else{
                   Write-Host "Error while connecting to WLAN and Ping" -ForegroundColor Red
                   Write-Host "Please try again or check the availability of your WLAN connections." -ForegroundColor Red
            }

    }#endifelse
}catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
}

# backup wlan
#netsh wlan connect name=7590-302

Start-Sleep -Seconds 1
############################################################################################
###### Filename Abfrage
############################################################################################
Clear-Host

Write-Host "#########################################" -ForegroundColor White
Write-Host "#########Collecting Computerinfo#########" -ForegroundColor White
Write-Host "#########################################"$Line -ForegroundColor White

Write-Host "Systemdaten werden abgerufen."$Line

Write-Host "Aktuelle Systeminformationen:"
Write-Host "BIOS SN: "$Global:BiosSn.SerialNumber -foregroundColor Green
Write-Host "Model: "$Global:Modelname.Model$Line -foregroundColor Green

Write-Host "Attention: These Information will be used for unique identification of the results for this Notebook."$Line -ForegroundColor Red

$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes"
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "No"
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
$choice=$host.ui.PromptForChoice("Datei umbenennen?", "Model und BIOS SN ändern?", $options, 1)


#if($BiosSn.SerialNumber -eq "INVALID" -or $Modelname.Model -eq "INVALID")
if($choice -eq 0)
{
    $NewModelname = Read-Host -Prompt "Bitte Modelname eingeben "
    $NewBiosSN = Read-Host -Prompt "Bitte Bios Serialnumber eingeben "
    
    #umschreiben des filenames
    [String]$filelabelname = $NewModelname+" "+$NewBiosSN+".txt" # Filenamebenennung nach Computermodelname
            
}else
{
    # Variablenvergabe um den Filestream übersichtlich zu halten
    $filelabelCollection = Get-WmiObject -class win32_ComputerSystem -ComputerName $Computer #Collectionarray zum aufruf von verschiedenen parametern
    [String]$filelabelname = $filelabelCollection.Model+" "+$Global:BiosSn.SerialNumber+".txt" # Filenamebenennung nach Computermodelname 

}#endifelse


        
$path = [System.IO.Path]::Combine($PSScriptRoot+"\"+$filelabelname) # Speicherort für das File mit allen Infos
$mode = [System.IO.FileMode]::Append # Hänge text an ..
$access = [System.IO.FileAccess]::Write # Access aufs File
$sharing = [IO.FileShare]::Read 

# Erstelle die FileStream and StreamWriter Objekte
$fs = New-Object IO.FileStream($path, $mode, $access, $sharing) 
$sw = New-Object System.IO.StreamWriter($fs)

Write-Host "Speichere Daten in $PSScriptRoot"
Write-Host "Dateiname: $filelabelname"

############################################################################################
###### Systeminformationen abfragen
############################################################################################
		
Function Get-ComputerInfo 
{ 
            Write-Host "Collecting Systeminformation..."
 
            # collect computer data: 
            $colItemsPC = Get-WmiObject -class win32_ComputerSystem -Computername $Computer
            $colItemsDisk = Get-WmiObject -class win32_DiskDrive -Computername $Computer
            $colItemsGPU = Get-WmiObject -class cim_PCVideoController -Computername $Computer
            $colItemsCPU = Get-WmiObject -class win32_Processor -Computername $Computer
            $colItemsOS = Get-WmiObject -class win32_OperatingSystem -Computername $Computer
            $colItemsBIOS = Get-WmiObject -class win32_Bios -Computername $Computer  
            
            $sw.WriteLine("COMPUTER:")
            foreach($objItem in $colItemsPC) 
            { 
            $sw.WriteLine("Manufacturer         : " + $objItem.Manufacturer )
            $sw.WriteLine("Model                : " + $objItem.Model )
            $sw.WriteLine("Name                 : " + $objItem.Name )
            $sw.WriteLine("Domain               : " + $objItem.Domain ) 
            $sw.WriteLine("Number of processors : " + $objItem.NumberOfProcessors )
            $sw.WriteLine("Physical memory      : " + [Math]::Round($objItem.TotalPhysicalMemory/1GB, 2) + " GB" )
            $sw.WriteLine("System type          : " + $objItem.SystemType )
            $Line 
            } #ForEach 

            $Line + $sw.WriteLine("DISK:" )
            # collect disk data: 
            ForEach($objItem in $colItemsDisk) 
            { 
            $sw.WriteLine("Manufacturer         : " + $objItem.Manufacturer )
            $sw.WriteLine("Model                : " + $objItem.Model )
            $sw.WriteLine("Disk name            : " + $objItem.Name )
            $sw.WriteLine("Mediatype            : " + $objItem.MediaType )
            $sw.WriteLine("Partitions           : " + $objItem.Partitions )
            $sw.WriteLine("Size                 : " + [Math]::Round($objItem.Size/1GB,2) + " GB" )
            $Line 
            } #ForEach 

            $Line + $sw.WriteLine("GRAPHICS:" )
            # collect grafics data: 
            ForEach($objItem in $colItemsGPU) 
            { 
            $sw.WriteLine("Name                 : " + $objItem.Name )
            $sw.WriteLine("Resolution horizontal: " + $objItem.CurrentHorizontalResolution + " pixels" )
            $sw.WriteLine("Resolution vertical  : " + $objItem.CurrentVerticalResolution + " pixels" )
            $sw.WriteLine("Refresh rate         : " + $objItem.CurrentRefreshRate + " Hz" )
            $Line 
            } #ForEach 

            $line + $sw.WriteLine("PROCESSOR:" )
            # collect processor data 
            ForEach($objItem in $colItemsCPU) 
            { 
            $sw.WriteLine("Manufacturer         : " + $objItem.Manufacturer )
            $sw.WriteLine("Name                 : " + $objItem.Name.Trim() )
            $sw.WriteLine("Version              : " + $objItem.Version )
            $sw.WriteLine("Clock speed          : " + $objItem.CurrentClockSpeed + " Hz" )
            $sw.WriteLine("Voltage              : " + $objItem.CurrentVoltage + " V" )
            $sw.WriteLine("Data width           : " + $objItem.Datawidth + " bit" )
            $sw.WriteLine("Number of cores      : " + $objItem.NumberOfCores )
            $sw.WriteLine("Logical Processors   : " + $objItem.NumberOfLogicalProcessors )
            $Line 
            } #ForEach 

            $Line + $sw.WriteLine("OPERATING SYSTEM:" )
            # collect OS data 
            ForEach($objItem in $colItemsOS) 
            { 
            $sw.WriteLine("Manufacturer         : " + $objItem.Manufacturer )
            $sw.WriteLine("Name                 : " + $objItem.Name )
            $sw.WriteLine("Version              : " + $objItem.Version )
            $sw.WriteLine("Build number         : " + $objItem.BuildNumber )
            $sw.WriteLine("Build type           : " + $objItem.BuildType )
            $sw.WriteLine("Code set             : " + $objItem.CodeSet )
            $sw.WriteLine("System directory     : " + $objItem.SystemDirectory )
            $sw.WriteLine("Total virtual memory : " + [Math]::Round($objItem.TotalVirtualMemorySize/1MB,2) + " MB" )
            $sw.WriteLine("Serial number        : " + $objItem.SerialNumber )
            $sw.WriteLine("Architecture         : " + $objItem.OSArchitecture )
            $Line 
            } #ForEach 

            $Line + $sw.WriteLine("BIOS:" )
            # collect BIOS data 
            ForEach($objItem in $colItemsBIOS) 
            { 
            $sw.WriteLine("Manufacturer         : " + $objItem.Manufacturer )
            $sw.WriteLine("Name                 : " + $objItem.Name )
            $sw.WriteLine("Serial number        : " + $objItem.SerialNumber )
            $Line 

            } #ForEach 
} #Function 

# start ... 
Get-ComputerInfo 

#Dispose um den Speicher wieder freizugeben
$sw.Dispose()
$fs.Dispose()

Start-Sleep -Seconds 2
Clear-Host

############################################################################################
###### Fileupload
############################################################################################

Write-Host "#########################################" -ForegroundColor White
Write-Host "###########Upoading Computerinfo#########" -ForegroundColor White
Write-Host "#########################################"$Line -ForegroundColor White
if($Global:usedwlan -eq 0){Write-Host "WLAN connected to: $Global:usedwlanstatus" -ForegroundColor Red }else{Write-Host "WLAN connected to: $Global:usedwlanstatus" -ForegroundColor Green }
Write-Host "Try to connect to FTP Server: "$ftpDNS

if($Global:usedwlan -eq 1){
    if (test-connection -computername "medftp.medion.com" -quiet) 
        {
                Write-Host "Connection to $ftpDNS ok."
                Write-Host "Try to upload File..."
                try
                {
                # Config
                $Username = "mLion"
                $Password = "3k8Ip4EyUm8"

                $LocalFile = $PSScriptRoot+"\"+$filelabelname
                $RemoteFile = "ftp://medftp.medion.com/results/"+$filelabelname


                # Erstelle FTP Request Objekte - Übergabe Credentials 
                $FTPRequest = [System.Net.FtpWebRequest]::Create("$RemoteFile")
                $FTPRequest = [System.Net.FtpWebRequest]$FTPRequest
                $FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
                $FTPRequest.Credentials = new-object System.Net.NetworkCredential($Username, $Password)
                $FTPRequest.UseBinary = $true
                $FTPRequest.UsePassive = $true

                # Fileupload auslesen
                $FileContent = gc -en byte $LocalFile
                $FTPRequest.ContentLength = $FileContent.Length

                Write-Host "FTP Datei:" $RemoteFile
                Write-Host "Lokale Datei:" $LocalFile
                Write-Host "Datei:"$filelabelname
                Write-Host "Dateigröße:"$FileContent.Length + "KB"

                # Stream it ...
                $Upload = $FTPRequest.GetRequestStream()
                $Upload.Write($FileContent, 0, $FileContent.Length)

                Write-Host "Fileupload succeed." -ForegroundColor Green
                $Global:Fileuploadstatus = "File uploaded to $ftpDNS"
                $Global:Fileupload = 1;

                # Aufräumen
                $Upload.Close()
                $Upload.Dispose()



                }#try      
                catch [System.SystemException],[System.Net.WebException] 
                {
                    $ErrorMessage = $_.Exception.Message
                    $FailedItem = $_.Exception.ItemName
                    #$err=$_ # temp error variable
                    #Write-Host $error.exception.message

                }#catch 
            }
    else{
                
                Write-Host "Connection to $ftpDNS failed." -ForegroundColor Red
                Write-Host "Try to connect to FTP Server: "$ftpIP
                
                Write-Host "Try to upload File..."

                if (test-connection -computername $ftpIP -quiet) 
                {
                    try
                    {
                        # Config
                        $Username = "mLion"
                        $Password = "3k8Ip4EyUm8"

                        $LocalFile = $PSScriptRoot+"\"+$filelabelname
                        $RemoteFile = "ftp://62.180.131.133:21/results/"+$filelabelname


                        # Erstelle FTP Request Objekte - Übergabe Credentials 
                        $FTPRequest = [System.Net.FtpWebRequest]::Create("$RemoteFile")
                        $FTPRequest = [System.Net.FtpWebRequest]$FTPRequest
                        $FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
                        $FTPRequest.Credentials = new-object System.Net.NetworkCredential($Username, $Password)
                        $FTPRequest.UseBinary = $true
                        $FTPRequest.UsePassive = $true

                        # Fileupload auslesen
                        $FileContent = gc -en byte $LocalFile
                        $FTPRequest.ContentLength = $FileContent.Length

                        Write-Host "FTP Datei:" $RemoteFile
                        Write-Host "Lokale Datei:" $LocalFile
                        Write-Host "Datei:"$filelabelname
                        Write-Host "Dateigröße:"$FileContent.Length + "KB"

                        # Stream it ...
                        $Upload = $FTPRequest.GetRequestStream()
                        $Upload.Write($FileContent, 0, $FileContent.Length)

                        Write-Host "Fileupload succeed." -ForegroundColor Green
                        $Global:Fileuploadstatus = "File uploaded to $ftpIP"
                        $Global:Fileupload = 1;

                        # Aufräumen
                        $Upload.Close()
                        $Upload.Dispose()

                    }#try      
                    catch [System.SystemException],[System.Net.WebException] 
                    {
                        $ErrorMessage = $_.Exception.Message
                        $FailedItem = $_.Exception.ItemName
                        #$err=$_ # temp error variable
                        #Write-Host $error.exception.message

                    }#catch
                }else{
                    Write-Host "Fileupload failed. Couldnt establish an upload connection." -ForegroundColor Red
                    $Global:Fileuploadstatus = "File was not uploaded. Connection to $ftpIP or $ftpDNS seems to have problems."
                } 

            }#endifelse (test-connection check)
}else{
    $Global:Fileuploadstatus = "Upload failed. No WLAN connection available."
}#endifelse (usedwlan check)

Start-Sleep -Seconds 2 
############################################################################################
###### Timer - Nach 10 Min. wird automatisch BurnIn aufgerufen und ausgeführt.
############################################################################################

## Erstellen der Timer instance 
$Global:timer = New-Object Timers.Timer
$Global:timer.Interval = 60000     # fire every 10min
$Global:timer.AutoReset = $false  # Event nicht wiederholen
$Global:timer.Enabled = $false #aktiv ($true) oder nicht ($false)
#$countdown = 30 # 30s countdown

#$Global:timer.Start();

# Timer Event - Start von Burnin nach ablauf von 10min. (Interval=600000)
#Register-ObjectEvent -InputObject $Global:timer -EventName Elapsed –SourceIdentifier BurnInTimer -Action Timeraction

function global:Timeraction
{
 Start-Process $Global:BurnPfad -ArgumentList $Global:BurnArguments
 #$Global:timer.Stop()
 Unregister-Event BurnInTimer
};

############################################################################################
###### Testloop
############################################################################################
$LoopEnd = 0
do
{
Clear-Host

# Script Start

Write-Host "..__..__............_.._..................____...__..__." -ForegroundColor White
Write-Host ".|..\/..|..........|.|(_)................/.__.\.|..\/..|" -ForegroundColor White
Write-Host ".|.\../.|..___...__|.|._...___..._.__...|.|..|.||.\../.|" -ForegroundColor White
Write-Host ".|.|\/|.|./._.\./._`..||.|./._.\.|.'_.\..|.|..|.||.|\/|.|" -ForegroundColor White
Write-Host ".|.|..|.||..__/|.(_|.||.||.(_).||.|.|.|.|.|__|.||.|..|.|" -ForegroundColor White
Write-Host ".|_|..|_|.\___|.\__,_||_|.\___/.|_|.|_|..\___\_\|_|..|_|" -ForegroundColor White
Write-Host " "
Write-Host "           WinPE Automatic Testing Script"		 -ForegroundColor Gray   
Write-Host " "
Write-Host "          Datum: $Global:datum - $Global:uhrzeit Uhr"   -ForegroundColor Gray
Write-Host " "
Write-Host "Verbunden mit: " 
if($Global:usedwlan -eq 0){Write-Host "$Global:usedwlanstatus" -ForegroundColor Red }else{Write-Host "$Global:usedwlanstatus" -ForegroundColor Green }
Write-Host "Uploadstatus Computerinfo: " 
if($Global:Fileupload -eq 0){Write-Host $Global:Fileuploadstatus -ForegroundColor Red}else{Write-Host $Global:Fileuploadstatus -ForegroundColor Green}
Write-Host " "
Write-Host "BurnIn Testlauf wird nach 10 MIN. automatisch gestartet!" -ForegroundColor Gray
Write-Host " "


function Read-KeyOrTimeout {

    Param(
        [int]$seconds = 600, #Timer Value in Sekunden
        [string]$default = '6' #Default Wert bei keiner Eingabe
    )

    $Line = "`n" # Zeilenumbruch schreiben

    $startTime = Get-Date #Startzeit
    $timeOut = New-TimeSpan -Seconds $seconds #Endzeit

    Write-Host  "[1] Keyboard Test$Line[2] Kameratest starten$Line[3] LAN Test starten$Line[4] ODD Test starten$Line[5] Sound Test starten$Line$Line[6] BurnIn Testlauf starten$Line[7] exit$Line$Line[Auswahl]: "

    #Solange Zeitspanne nicht überschritten
    while (-not $host.ui.RawUI.KeyAvailable) {
        $currentTime = Get-Date
        if ($currentTime -gt $startTime + $timeOut)
        {
            Break; #Timeout
        }
    }

    if ($host.ui.RawUI.KeyAvailable)
    {
        [string]$response = ($host.ui.RawUI.ReadKey("IncludeKeyDown,NoEcho")).character #Eingabe abfangen
    }else{
        $response = $default #Wenn nichts gedrückt wurde, setze default 
    }
    Write-Output $($response.toUpper()) #Ausgabe 
}#end function keyortimeout

$strResponse = Read-KeyOrTimeOut 
switch($strResponse){
    1  {
            Clear-Host

            
            $LoopEnd = 1;
            $LoopKeytest = 0;
            $Line = "`n" # Zeilenumbruch schreiben 

            $Global:Mouseclicked = "false";
            $Global:Pressedkeys = ""
            
            #Touchpad movement

            Write-Host "##############################################" -ForegroundColor White
            Write-Host "###              Touchpad test              ##" -ForegroundColor White
            Write-Host "##############################################"$Line -ForegroundColor White
             Write-Host "Touchpad response?: " 
                  $p1 = [System.Windows.Forms.Cursor]::Position
                  Start-Sleep -Seconds 5  # or use a shorter intervall with the -milliseconds parameter
                  $p2 = [System.Windows.Forms.Cursor]::Position
                  if($p1.X -eq $p2.X -and $p1.Y -eq $p2.Y) {
                      Write-Host "Touchpad not responding"-ForegroundColor Red
                  } else {
                      Write-Host "Touchpad ok" -ForegroundColor Green
                  }

            do
            {

            #$key = if ($host.UI.RawUI.KeyAvailable) {
            #  $host.UI.RawUI.ReadKey('NoEcho, IncludeKeyDown')
            # }

            #[Windows.Forms.UserControl]::MouseButtons -match "Left"


            #Clear-Host
            Write-Host "##############################################" -ForegroundColor White
            Write-Host "###              Keyboard Test              ##" -ForegroundColor White
            Write-Host "##############################################"$Line -ForegroundColor White
            Write-Host " Bitte geben Sie eine beliebige Zahl/Buchstaben ein.$Line Achtung: Funtkionstasten und Sonderzeichen werden nicht gewertet."
            Write-Host " "
            #if([Windows.Forms.UserControl]::MouseButtons -match "Left"){
            #$Global:Mouseclicked = "true";}
           # if($Global:Mouseclieck -eq "false"){Write-Host "Not Implemented." -ForegroundColor Red }else{Write-Host "Mouseclick ok." -ForegroundColor Green }   
            Write-Host ""
            Write-Host "Abbruch: STRG + C"
            Write-Host ""
            Write-Host "Keys pressed: "$Global:Pressedkeys 


            function Read-Keytest {

                Param(
                    [int]$seconds = 1000, #Timer Value in Sekunden
                    [string]$default = 'default' #Default Wert bei keiner Eingabe
                )

                $startTime = Get-Date #Startzeit
                $timeOut = New-TimeSpan -Seconds $seconds #Endzeit

                #Solange Zeitspanne nicht überschritten
                while (-not $host.ui.RawUI.KeyAvailable) {
                    $currentTime = Get-Date
                    if ($currentTime -gt $startTime + $timeOut)
                    {
                        Break; #Timeout
                    }
                }

                if ($host.ui.RawUI.KeyAvailable)
                {
                    [string]$response = ($host.ui.RawUI.ReadKey("IncludeKeyDown,NoEcho")).character #Eingabe abfangen
                }else{
                    $response = $default #Wenn nichts gedrückt wurde, setze default 
                }
                Write-Output $($response.toUpper()) #Ausgabe 
            }#end function keyortimeout

            $strresponse = Read-Keytest 


             switch($strresponse){
                 1{       
                        Clear-Host
                        #$a = "a"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 1"
                        break
                }
                    2{       
                        Clear-Host
                        #$s = "s"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 2"
                        break
                }
                    3{       
                        Clear-Host
                        #$d = "d"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 3"
                        break
                }
                    4{       
                        Clear-Host
                        #$f = "f"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 4"
                        break
                }
                    5{       
                        Clear-Host
                        #$g = "g"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 5"
                        break
                }
                    6{       
                        Clear-Host
                        #$h = "h"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 6"
                        break
                }
                    7{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 7"
                        break
                }
                        8{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 8"
                        break
                }
                        9{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 9"
                        break
                }
                        0{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" 0"
                        break
                }
                            ß{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" ß"
                        break
                }
                a{       
                        Clear-Host
                        $a = "a"
                        $Global:Pressedkeys = $Global:Pressedkeys+" a"
                        break
                }
                    s{       
                        Clear-Host
                        $s = "s"
                        $Global:Pressedkeys = $Global:Pressedkeys+" s"
                        break
                }
                    d{       
                        Clear-Host
                        $d = "d"
                        $Global:Pressedkeys = $Global:Pressedkeys+" d"
                        break
                }
                    f{       
                        Clear-Host
                        $f = "f"
                        $Global:Pressedkeys = $Global:Pressedkeys+" f"
                        break
                }
                    g{       
                        Clear-Host
                        $g = "g"
                        $Global:Pressedkeys = $Global:Pressedkeys+" g"
                        break
                }
                    h{       
                        Clear-Host
                        $h = "h"
                        $Global:Pressedkeys = $Global:Pressedkeys+" h"
                        break
                }
                    j{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" j"
                        break
                }
                        k{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" k"
                        break
                }
                        l{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" l"
                        break
                }
                        ö{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" ö"
                        break
                }
                        ä{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" ä"
                        break
                }
                            "#"{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" #"
                        break
                }
                        q{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" q"
                        break
                }
                        w{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" w"
                        break
                }        e{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" e"
                        break
                }
                        r{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" r"
                        break
                }
                        t{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" t"
                        break
                }        z{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" z"
                        break
                }        u{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" u"
                        break
                }        i{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" i"
                        break
                }        o{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" o"
                        break
                }        p{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" p"
                        break
                }        ü{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" ü"
                        break
                }        +{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" +"
                        break
                }        "<"{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" <"
                        break
                }        y{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" y"
                        break
                }        x{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" x"
                        break
                }        c{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" c"
                        break
                }
                        v{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" v"
                        break
                }
                        b{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" b"
                        break
                }        n{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" n"
                        break
                }        m{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" m"
                        break
                }        ","{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" ,"
                        break
                }        "."{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" ."
                        break
                }        "-"{       
                        Clear-Host
                        #$j = " j"
                        $Global:Pressedkeys = $Global:Pressedkeys+" -"
                        break
                }

    	            default
                    {
                        Write-Host "Eingabe nicht verwertbar."

                    }
             }
             }while ($LoopKeytest -eq 0)
             #until ($key.VirtualKeyCode -eq 81 -and $key.ControlKeyState -cmatch '^(Right|Left)CtrlPressed$')
            break
    }
	2  {    
            Clear-Host
            Write-Host "###########################################" -ForegroundColor White
            Write-Host "### Starte BurnIn Testsuite - Kameratest ##" -ForegroundColor White
            Write-Host "###########################################"$Line -ForegroundColor White        

            Start-Sleep -Seconds 1
            Write-Host "Initialisiere BurnIn Testsuite..."
            
            #if ($Systemobj.OSArchitecture -eq "64-Bit")
            #{

                Start-Process $Global:BurnPfad -ArgumentList "/x /r /p /c $($PSScriptRoot)\cam_test.bitcfg"
            #}else{
            #    Start-Process $BurnPfad32 -ArgumentList "/x /r /p /c cam_test.bitcfg"
            #}#ifelse
            
            #$Global:timer.Stop()
            #Unregister-Event BurnInTimer
            $LoopEnd = 1
			break
        }
	3  {
            Clear-Host
            Write-Host "###########################################" -ForegroundColor White
            Write-Host "### Starte BurnIn Testsuite - LAN Test  ###" -ForegroundColor White
            Write-Host "###########################################"$Line -ForegroundColor White        

            Start-Sleep -Seconds 1
            Write-Host "Initialisiere BurnIn Testsuite..."
            
            #if ($Systemobj.OSArchitecture -eq "64-Bit")
            #{
                Start-Process $Global:BurnPfad -ArgumentList "/x /r /p /c $($PSScriptRoot)\Lan_test.bitcfg"
            #}else{
            #    Start-Process $BurnPfad32 -ArgumentList "/x /r /p /c Lan_test.bitcfg"
            #}#ifelse

            #$Global:timer.Stop()
            #Unregister-Event BurnInTimer
            $LoopEnd = 1
			break
        }
    4  {
            Clear-Host
            Write-Host "###########################################" -ForegroundColor White
            Write-Host "### Starte BurnIn Testsuite - ODD Test  ###" -ForegroundColor White
            Write-Host "###########################################"$Line -ForegroundColor White        

            Start-Sleep -Seconds 1
            Write-Host "Initialisiere BurnIn Testsuite..."
            
            #if ($Systemobj.OSArchitecture -eq "64-Bit")
            #{
                Start-Process $Global:BurnPfad -ArgumentList "/x /r /p /c $($PSScriptRoot)\odd_burn_test.bitcfg"
            #}else{
            #    Start-Process $BurnPfad32 -ArgumentList "/x /r /p /c odd_burn_test.bitcfg"
            #}#ifelse

            #$Global:timer.Stop()
            #Unregister-Event BurnInTimer
            $LoopEnd = 1
			break
        }
    5  {
            Clear-Host
            Write-Host "###########################################" -ForegroundColor White
            Write-Host "### Starte BurnIn Testsuite - Soundtest ###" -ForegroundColor White
            Write-Host "###########################################"$Line -ForegroundColor White        

            Start-Sleep -Seconds 1
            Write-Host "Initialisiere BurnIn Testsuite..."
            
            #if ($Systemobj.OSArchitecture -eq "64-Bit")
            #{
                Start-Process $Global:BurnPfad -ArgumentList "/x /r /c /p /d 3 $($PSScriptRoot)\sound_test.bitcfg"
            #}else{
            #    Start-Process $BurnPfad32 -ArgumentList "/x /r /c /p /d 3 sound_test.bitcfg"
            #}#ifelse

            #$Global:timer.Stop()
            #Unregister-Event BurnInTimer
            $LoopEnd = 1
			break
        }
    6  {
            Clear-Host
            Write-Host "###########################################" -ForegroundColor White
            Write-Host "##Starte BurnIn Testdurchlauf + VLC Video##" -ForegroundColor White
            Write-Host "###########################################"$Line -ForegroundColor White        

            Start-Sleep -Milliseconds 500
            Write-Host "Initialisiere VLC..."


            Start-Sleep -Seconds 1
            Write-Host "Initialisiere BurnIn Testsuite. This may take several Seconds.."

            Start-Sleep -Seconds 2
            
            #if(Test-Path $vlcPfad)
            #{
                Start-Process $Global:vlcPfad -ArgumentList $Global:vlcMovie
            #}else{

            #    $vlcPfad2 = ${env:ProgramFiles}+"\VLC\vlc.exe"
            #    Start-Process $vlcPfad2 -ArgumentList $vlcMovie
            #}
            

            $Burnincfg = ${env:ProgramFiles}+"\BurnInTest\preferedtestconfig.bitcfg"

            if(Test-Path $Burnincfg)
            {
                Start-Process $Global:BurnPfad -ArgumentList $Global:BurnArguments # Prozess Thread starten und Argumente übergeben
            }else{
             #Neue Argumentlist übergeben
             $NewBurnArguments = "/h /x /r /c preferedtestconfig.bitcfg"
             Start-Process $Global:BurnPfad -ArgumentList $Global:BurnArguments # Prozess Thread starten und Argumente übergeben
            }
            

            #$Global:timer.Stop()
            #Unregister-Event BurnInTimer
            $LoopEnd = 1
			break
        }
    7  {
            Write-Host "Beende Script..."

            #$Global:timer.Stop()
            #Unregister-Event BurnInTimer
            $LoopEnd = 1
			break
		
			#Stop-Computer
        }
	default
        {
            Write-Host $Line"Eingabe war keine gülte Auswahlmöglichkeit.$Line
            Script wird neugestartet!$Line" -foregroundColor Red
            #$Global:timer.Stop()
            $LoopEnd = 0
        }
}
}
while ($LoopEnd -eq 0)
