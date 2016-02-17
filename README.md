# f5-vip-pool-server-config

This powershellscript uses the F5 iControl powershell plugin to get a list of all VIPs in a list of devices, and present the following information in HTML tables:

VIP, VIP IP, VIP PORT, POOL, LOAD BALANCER METHOD, POOL MEMBER, POOL MEMBER PORT 

Features:

Checks to see if a device is active or standby and only queries the active device.
Check to all partitions (not just common).
Checks all VIPS per partition (even just forwarding VIPS).
Outputs as HTML.
Has a separate log file that logs begin and end of processing each device (useful for timings).
