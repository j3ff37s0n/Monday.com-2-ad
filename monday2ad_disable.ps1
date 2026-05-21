#securely get your auth, check monday for how to use your auth

$key = Get-Content 'C:\Scripts\AD_Integrations\monday_com_aes.key'
$pHold = Get-Content 'C:\Scripts\AD_Integrations\monday_com_auth.enc' -Raw
$pTrans = $pHold | ConvertTo-SecureString -Key $key
$pNor = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pTrans)
$mondayAuth = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pNor)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pNor) #cleans mem

#funcion to create random pass
function random-Pass {
    $length = 16;

#Join arracy of ascii in alphabet - get 16 random number - for each random number set the ascii to a character (A,Z) (a,z) (0,9)
    $pass = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count $length | ForEach-Object { [char]$_ });
    return $pass;
};

#Function for AD Disable
function Disable-ADuserbyEmployeeID($employeeID) {
	#param (
	#	[Parameter(Mandatory = $true)]
	#	[string]$employeeID
	#)
	#$creds = Get-Crednetial
	$user = Get-ADUser -Filter "employeeID -eq '$employeeID'" -Properties Manager, PasswordLastSet, employeeID;
	
	write-host "User found is $($user.SamAccountName) with $($employeeID)"
	
	if ($user) {
	#Disable-ADAccount -Identity $user.SamAccountName
	Set-ADUser $user -Enabled $False -whatif
	$newPass = random-Pass;
            Set-ADAccountPassword -Identity $user.SamAccountName -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $newPass -Force) -whatif;
	}

}
#get board items
$boardItems = Invoke-RestMethod -Uri "https://api.monday.com/v2" -Method Post -Headers @{
    "Content-Type"  = "application/json"
    "Authorization" = $mondayAuth
    "API-Version"   = "2023-04"
} -Body (@{ query = 'query { boards (ids:<board_id>) { items_page { cursor items { id name } } } }' } | ConvertTo-Json -Depth 3)



#check the and store array with items
$boardItemsArr = $boardItems.data.boards[0].items_page.items

foreach($item in $boardItemsArr) {write-host "$($item.id): $($item.name)" }

#store cursor value and if not null get the next page till null
$cursor = $boardItems.data.boards[0].items_page.cursor

while($cursor) {
if($cursor -ne $null){
		#get board items
	$boardItems = Invoke-RestMethod -Uri "https://api.monday.com/v2" -Method Post -Headers @{
	    "Content-Type"  = "application/json"
	    "Authorization" = 	$mondayAuth
	    "API-Version"   = "2023-04"
	} -Body (@{ query = "query { boards (ids:<board_id>) { next_items_page (cursor: `"$cursor`") { cursor items { id name } } } }" } | ConvertTo-Json -Depth 3)
	
	$cursor = $boardItems.data.boards[0].next_items_page.cursor
	$boardItemsArr += $boardItems.data.boards[0].next_items_page.items
}
else {
	exit;
}
}


#query value of a column by item
foreach($id in $boardItemsArr.id) {

#get the value for 1 id 
$employeeObject = Invoke-RestMethod -Uri "https://api.monday.com/v2" -Method Post -Headers @{
    "Content-Type"  = "application/json"
    "Authorization" = $mondayAuth
    "API-Version"   = "2023-04"
} -Body (@{ query = "query { items (ids:[$($id)]) { name column_values (ids: [`"text_mks02734`", `"boolean_mksxne32`"]) { id text value } } }" } | ConvertTo-Json -Depth 3)

$pemployeeObject = $employeeObject.data.items[0].column_values

#check value for checkmark is true
if($pemployeeObject.value -like "*true*"){

write-host "checking below"
write-host $pemployeeObject.text $pemployeeObject.value

# Isolate the correct column value
$employeeID = ($pemployeeObject | Where-Object { $_.id -eq "text_mks7xf9z" }).text;

write-host "The ID being looked for is $($employeeID)"

Disable-ADuserbyEmployeeID $employeeID;

}

}
