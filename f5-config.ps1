Add-PSSnapin iControlSnapIn
import-module $output_path\logger.psm1

$script = $MyInvocation.MyCommand.Name
$output_path = "c:\Users\xxx\Desktop\f5\"
$config_file = "$output_path\f5.config"
$logfile = "$output_path\$script.log"
$logflag = "silent"
$username = ""
$password = ""


# define this as an arraylist so that items can be removed from it (i.e. it's not fixed length)
[System.Collections.ArrayList]$device_list = Get-Content $config_file

#work through the list assessing the failover status of each device
# This creates an array of only the active devices.
# While I could create a $devicelogin for each device, it's easier just to use the current credentials and re-authenticate

$active_device = @()
foreach ($device in $device_list)
{
    # log in to the device
    $login = Initialize-F5.iControl -ErrorAction SilentlyContinue -Hostname $device -Username $username -Password $password
    if ( $login -ne "True" )
    {
        Write-host "An Error occurred while authenticating to $device"
        logger "$logfile" "$logflag" "ERROR" "$device Authentication Error"       
    }

    # Check to make sure we are on the active device.  
    $failover_state = Get-F5.DBVariable | Where {$_.Name -eq "Failover.State"} | Select Value

    if ($failover_state.Value -eq "active")
    {
        $active_device+=$device
        write-host -ForegroundColor DarkGreen $device "is currently active."
        logger "$logfile" "$logflag" "INFO" "$device is currently active."
    }
    else
    {
        write-host -ForegroundColor Red $device "is not currently active."
        logger "$logfile" "$logflag" "INFO" "$device is not currently active."
    }
} #end of foreach loop



$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"

$wiki_device_list=""
echo "<HTML>" > $output_path\index.html
foreach ($device in $active_device)
{
    $wiki_device_list += "  * [[:repmon:dropped:network:load_balancers:$device]]`n"
    Write-host -ForegroundColor Yellow Processing $device
    logger "$logfile" "$logflag" "INFO" "$device Processing Begin."
    $output_file="$script-$device-out.txt"
    

    $ErrorActionPreference= 'silentlycontinue'
    Try
    {
        $login = Initialize-F5.iControl -Hostname $device -Username $username -Password $password       
    }
    Catch [Exception]
    {
        Write-host "An Error occurred"
        exit 1;
    }

    if ($login -ne "True") 
    { 
        Write-host -foregroundcolor Red "[ERROR: 2] $device Login not correct."
        logger "$logfile" "$logflag" "ERROR" "$device Login not correct."
        exit 2;
    }

    $ErrorActionPreference= 'continue'


    # Check to make sure we are on the active device.
    # this should not be necessary as we have an array of only active devices
    $failover_state = Get-F5.DBVariable | Where {$_.Name -eq "Failover.State"} | Select Value

    if ($failover_state.Value -ne "active")
    {
        Write-Host -ForegroundColor  Red "[ERROR: 3] The device " $device " is currently in state" $failover_state.Value " - please change the device to be the active node and try again."
        exit 3;
    }


    $virtuals = Get-F5.LTMVirtualServer

    write-host $virtuals.count " virtual servers need to be processed."

    $ic = Get-F5.iControl
    #Set script to top level folder so that enumerated folders are from the root.
    $ic.SystemSession.set_active_folder("/")

    # Get the active number of partitions on the device.
    #Split these in to an array so that each is individually addressable
    #$partitions_array[1] is the second element

    $partitions = $ic.ManagementFolder.get_list()

    # Open a file and write a header in to the file.
    # header is important when we later use import-csv to import directly to an array.
    $file = New-Object System.IO.StreamWriter $output_path\$output_file
    $file.WriteLine("VIP,IP,PORT,POOL,LB_METHOD,POOL_MEMBER_ADDRESS,POOL_MEMBER_PORT")

    foreach ($element in $partitions)
    {
        write-host "Processing Partition: " $element 
        $ic.SystemSession.set_active_folder($element)
        $virtual_servers = Get-F5.LTMVirtualServer
        foreach ($item in $virtual_servers)
        {
            if ($virtual_servers.count -ne 0) 
            {
                $virt_address = $ic.LocalLBVirtualServer.get_destination($item.name)
                $pool = $ic.LocalLBVirtualServer.get_default_pool_name($item.name)
                if ( [string]::IsNullOrEmpty($pool)) 
                { 
                    $pool = "NULL" 
                    $lb_method = "NULL"
                }
                if ( $pool -ne "NULL" )
                {
                    $lb_method = $ic.LocalLBPool.get_lb_method($pool)
                    $pool_member_list = $ic.LocalLBPool.get_all_member_statistics($pool)
                    $pool_member = $pool_member_list.statistics.member   
                    #write-host $pool               
                    if ( $pool_member.count -gt 1 )
                    {
                        foreach ($p_member in $pool_member)
                        {
                            write-host $item.Name $virt_address[0].address $virt_address.port $pool $lb_method $p_member.address $p_member.port                            
                            $file.WriteLine($item.Name + "," + $virt_address[0].address + "," +  $virt_address.port + "," + $pool + "," + $lb_method + "," + $p_member.address + "," + $p_member.port)
                        }
                    }
                    else
                    {
                        #write-host "`t" $pool_member.address $pool_member.port
                        write-host $item.Name $virt_address[0].address $virt_address.port $pool $lb_method $pool_member.address $pool_member.port 
                        $file.WriteLine($item.Name + "," + $virt_address[0].address + "," + $virt_address.port + "," + $pool + "," + $lb_method + "," + $pool_member.address + "," + $pool_member.port) 
                    } #end if pool member is gt 1                    
                } #end if pool is null
                #$file.WriteLine($item.Name + "," + $virt_address[0].address + "," + $virt_address.port + "," + $pool + "," + $lb_method)                
            } #end of if statement
        } #end of foreach loop virtual_servers
        write-host
    }

    $file.Close();
    $current_run = import-csv $output_path\$output_file

    # create a custom object that can be added to an array with current and previous values.
    # much neater way of doing this because it means that I can use a custom object to contain only the values I need.
    Write-Host "Building object table."
    $array = @()
    foreach ($item in $current_run)
    {
        $object = New-Object -TypeName PSObject
        $object | Add-Member -Name 'VIP' -MemberType NoteProperty -Value $item.VIP
        $object | Add-Member -Name 'IP' -MemberType NoteProperty -Value $item.IP
        $object | Add-Member -Name 'PORT' -MemberType NoteProperty -Value ([int64]$item.PORT)
        $object | Add-Member -Name 'POOL' -MemberType NoteProperty -Value ($item.POOL)
        $object | Add-Member -Name 'LB_METHOD' -MemberType NoteProperty -Value ($item.LB_METHOD)
        $object | Add-Member -Name 'POOL_MEMBER_ADDRESS' -MemberType NoteProperty -Value ($item.POOL_MEMBER_ADDRESS)
        $object | Add-Member -Name 'POOL_MEMBER_PORT' -MemberType NoteProperty -Value ($item.POOL_MEMBER_PORT)
        $array += $object   
    }

    # loop through my new custom array and only get the ones that have increased.
    Write-Host "Writing HTML files."
    $array | ConvertTo-Html -Head $style > $output_path\$script-$device-config.html

    Write-host -ForegroundColor Yellow Completed Processing $device
    write-host "--------------------------------------------------------"
    echo "<a href=$script-$device-config.html target=""iframe"">$device</a><br>" >> $output_path\index.html
    logger "$logfile" "$logflag" "INFO" "$device Processing End."
} #end device foreach
echo "<iframe name=""iframe"" width=2000 height=4000 frameborder=0></iframe>" >> $output_path\index.html




