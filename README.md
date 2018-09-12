# Find-SfB-Orphaned-Objects
This script will search through SfB Active Objects, Active Directory Deleted Objects, and SfB Databases to reolve that pesky Ambigous Number
<BR />
There are a lot of scripts that will search through SfB for orphaned or Amgious number issue.  This however searches for everything with the culprit LineURI.</Br>
You need to be part of the CSAdministrators and Domain Admins Role to use this.<p>
  <B>Be Careful with this</B> since it can edit the Back End Databases directly and there is no going back, unless you re-create the accidentily deleted object.  And if you delete the object in one place, you need to delete it in all places.</p>
<p>
  Execution of Script</p>
  <p>
 & '.\Find Deleted Users.ps1' -lineuri "+14085551212"</p>
 
 <p>You can get the lineuri from snooper trace files and looking for SIP 485 Ambigious</p>
