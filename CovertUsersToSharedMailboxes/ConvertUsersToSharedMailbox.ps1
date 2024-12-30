# Import CSV
$csvPath = "C:\usersToConvert.csv"
$mailboxes = Import-Csv -Path $csvPath

# Setup & Import needed module
Install-Module -Name ExchangeOnlineManagement -Force
Import-Module Exchange

# Authenticate (user the MS/AAD Federatiob login)
$UserCredential = Get-Credential
Connect-ExchangeOnline -Credential $UserCredential

# Do it
foreach ($mailbox in $mailboxes) {
    $primarySmtpAddress = $mailbox.PrimarySmtpAddress
    try {
        Set-Mailbox -Identity $primarySmtpAddress -Type Shared
        Write-Host "Converted user mailbox '$primarySmtpAddress' to a shared mailbox."
    } catch {
        Write-Host "Failed to convert user mailbox '$primarySmtpAddress' to a shared mailbox. $_" -ForegroundColor Red
    }
}
