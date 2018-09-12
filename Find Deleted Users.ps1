<#
.Synopsis
This will search the current objects in SfB, deleted AD Objects, and the Front End Database (rtclocal) for any phone number.
For the Skype objects it's pretty easy
For Deleted objects, a little more tricky because you have to resotre it and then disable it, you can then delete the object
For things in the rtclocal on the front end, it'spretty easy, however very risky, so I ask at each server to enter (or copy and paste) the sip address to delete.# Parameter help description

.Parameter lineuri
This is the e.164 of the number, for example +14085551212.  You can however just use any substring as well, for example 1212 since all the quaries use wild cards

.Example
FindDeletedObjects.ps1 -lineuri "+14085551212"


.Notes
Adam Berns
https://www.youseeadam.com
Sept 12 2018
I cannot copyright it, but hey, at lease let people know you go this from me, please....
#>


param (
    # e164
    [parameter (Position=0,Mandatory=$True,ValueFromPipeline=$true)]
    [validateNotNullOrEmpty()]
    [string]$lineuri
)
$Error.Clear()
$ErrorActionPreference = "stop"
$searchstring = "*"+$lineuri+"*"



function searchcs ($seachcommand,$objectType){
    $found = $null
    try {$found = Invoke-Expression $seachcommand}
    catch{}
    if ($found) {
        Write-host -ForegroundColor yellow "Found Object: "$found.SipAddress "("$found.LineURI")" $objectType
    }
}

function sqlquery ([string]$sfbhost,[string]$querystring) {
    [object] $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
    [object] $command = New-Object -TypeName System.Data.SqlClient.SqlCommand
    [object] $sqladapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
    [object] $results = New-Object -TypeName System.Data.Dataset
    
    [string] $connstring = "server="+$sfbhost+"\rtclocal;database=rtc;trusted_connection=true;"
    $command.CommandText = $querystring
    $connection.ConnectionString = $connstring
    $connection.Open()
    $command.Connection = $connection
    $sqladapter.SelectCommand = $command
    $recordcount = $sqladapter.Fill($results)
    $connection.Close()
    return $Results.Tables[0]
}

#First Search the basic stuff in SfB
searchcs "get-cscommonareaphone -filter {lineuri -like `"$searchstring`"}" "Common Area Phone"
searchcs "get-csmeetingroom -filter {lineuri -like `"$searchstring`"}" "Meeting Room"
searchcs "get-csmeetingroom -filter {LineServerURI -like `"$searchstring`"}" "Meeting Room"
searchcs "get-csexumcontact -filter {lineuri -like  `"$searchstring`"}" "EXUM Contact"
searchcs "get-csexumcontact -filter {displaynumber -like `"$searchstring`"}" "EXUM Contact"
searchcs "get-csuser -filter {lineuri -like `"$searchstring`"}" "User"
searchcs "get-csuser -filter {privateline -like `"$searchstring`"}" "User"
searchcs "get-csuser -filter {lineserverURI -like `"$searchstring`"}" "User"
searchcs "get-csanalogdevice -filter {lineuri -like `"$searchstring`"}" "Analog Device"
searchcs "Get-CsDialInConferencingAccessNumber -filter {lineuri -like `"$searchstring`"}" "Conference Number"
searchcs "Get-CsRgsWorkflow -ShowAll | where-object {$_.LineURI -imatch `"$searchstring`"}" "Response Group"
searchcs "Get-CsTrustedApplicationEndpoint -filter {lineuri -like `"$searchstring`"}" "Trusted Application"

#See if there is a deleted AD object with that number

#We search the global catalog in case there are sub domains.  I just pick a server in the forest, it can really be any GC searching port 3268
[string]$GC= (Get-ADForest).GlobalCatalogs[0] +":3268"
[array] $adobject = Get-ADObject -Filter {msRTCSIP-Line -like $searchstring} -IncludeDeletedObjects -Server $GC | where-object {$_.Deleted -eq $True}

#If more than 0 objects are returned, there is a deleted object that must be dealt with
if ($adobject.count -gt 0) {
    write-host  -ForegroundColor yellow "The following objects with the number $lineuri where found deleted"
    foreach ($object in $adobject) {
        write-host -ForegroundColor cyan $object.DistinguishedName ":" $object.ObjectClass
    }
    write-host "You will need to do the following:"
    write-host "1. undelete those objects (using Active Directory Administration Center is easy to do this with) and get the DN of the restored user"
    write-host "2. Retrieve the object type, for example get-csuser DN of restored object"
    write-host "3. Make sure the restore is replciated in AD then Disable the object in SfB"
    write-host "4. Make sure this is replacted in AD"
    write-host "5. You way want to run this again after restoring and disabling the SfB Object to make sure it is removed from the Database"
}

#Now search through the databases on the front end servers
#A lot of nesting but we want to go Front End Server by Front End Server just in case, this is brute force thing so I want to make sure it is safe

#Get a list of all the front end server
foreach ($fehost in (get-csservice -UserServer | foreach-object {get-cscomputer -Pool $_.PoolFQDN}).FQDN) {
    #Query the database for the phone number in question, we return it as an array so we can easily cycle through it
    $Query = "SELECT * From dbo.ResourcePhone where PhoneNum like '%"+$lineuri+"%'"
    [Array]$PhoneNum = sqlquery $fehost $Query

    #If we find more then 1 with that number we have a problem
    if ($PhoneNum.Count -gt 1) {
        #Go Through each PhoneNumber we found on each server
        foreach ($PhoneNumber in $PhoneNum) {
            #Find the Resource ID for that user
            $Query = "Select * from dbo.Resource where ResourceId = '" + $PhoneNumber.ResourceId+"'"
            $sip = sqlquery $fehost $Query

            #Get the SIP URI for that user with that phone number
            write-host -ForegroundColor Yellow "Found" $sip.UserAtHost "on" $fehost
            $badsip = read-host -Prompt "Press R to Remove any other key to continue"

            #If they want to delete that entry, Press R
            if ($badsip -eq "R") {
                $Query = "execute dbo.RtcDeleteResource '"+$sip.UserAtHost+"'"
                $removeghost =  sqlquery $fehost $Query
                $removeghost
            }
        }
    }
    
    
}
