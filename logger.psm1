function logger ($logfile, $flag, $logmessagetype, $message)
{
    $logdate = Get-Date -Format "yyyy-MM-dd"
    $logtime = Get-Date -Format "HH:mm:ss"
    $logdatetime = $logdate + " " + $logtime

    $logmessage = "[$logdatetime] $logmessagetype : $message"
    
    if ( $flag.tolower() -ne "silent" )
    {
        Write-Host $logmessage
    }
    echo $logmessage >> $logfile
    
}

