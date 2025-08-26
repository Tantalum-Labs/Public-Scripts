Install-Module -Name AzureAD -Force -Scope CurrentUser
Import-Module AzureAD
Connect-AzureAD

$allUsers = Get-AzureADUser -All $true
$totalUsers = $allUsers.Count

$activeUsers = $allUsers | Where-Object { $_.AccountEnabled -eq $true }
$totalActiveUsers = $activeUsers.Count

$inactiveUsers = $allUsers | Where-Object { $_.AccountEnabled -eq $false }
$totalInactiveUsers = $inactiveUsers.Count

$thirtyDaysAgo = (Get-Date).AddDays(-30)

$activeNoRecentLogins = $activeUsers | Where-Object {
    ($_.SignInActivity.LastInteractiveSignInDate -gt $thirtyDaysAgo) -or
    ($_.SignInActivity.LastNonInteractiveSignInDate -gt $thirtyDaysAgo)
}

$recentLogins = $activeNoRecentLogins | Select-Object `
    UserPrincipalName, `
    DisplayName, `
    UserType, `
    AccountEnabled, `
    @{Name='LastInteractiveLogin'; Expression={$_.SignInActivity.LastInteractiveSignInDate}}, `
    @{Name='LastNonInteractiveLogin'; Expression={$_.SignInActivity.LastNonInteractiveSignInDate}}

$activeRecentLogins = $activeUsers | Where-Object {
    ($_.SignInActivity.LastInteractiveSignInDate -lt $thirtyDaysAgo) -or
    ($_.SignInActivity.LastNonInteractiveSignInDate -lt $thirtyDaysAgo)
}

$recentLogins = $activeRecentLogins | Select-Object `
    UserPrincipalName, `
    DisplayName, `
    UserType, `
    AccountEnabled, `
    @{Name='LastInteractiveLogin'; Expression={$_.SignInActivity.LastInteractiveSignInDate}}, `
    @{Name='LastNonInteractiveLogin'; Expression={$_.SignInActivity.LastNonInteractiveSignInDate}}

Write-Output "Total Users: $totalUsers"
Write-Output "Total Active Users: $totalActiveUsers"
Write-Output "Total Inactive Users: $totalInactiveUsers"
Write-Output "Active Users with No Login Activity in the Last 30 Days:"
$noRecentLogins | Format-Table -AutoSize

Write-Output "Active Users with Login Activity in the Last 30 Days:"
$recentLogins | Format-Table -AutoSize
