# ConvertUsersToSharedMailbox.ps1

A PowerShell script to batch-convert **user mailboxes** to **shared mailboxes** in **Exchange Online** using data from a CSV file. This script authenticates to your Microsoft 365 tenant (via Exchange Online) and performs the mailbox conversion for each user listed in your CSV.

---

## Table of Contents

1. [Prerequisites](#prerequisites)  
2. [CSV File Preparation](#csv-file-preparation)  
3. [How It Works](#how-it-works)  
4. [Usage](#usage)  
5. [Common Issues & Troubleshooting](#common-issues--troubleshooting)  
6. [License](#license)  

---

## Prerequisites

Before running this script, ensure you have the following:

1. **Administrative Privileges**:  
   You must be a Microsoft 365 global admin or have the Exchange administrator role in your tenant.

2. **PowerShell 5.1 or Newer**:  
   - Typically, Windows 10/11 includes PowerShell 5.1 by default.  
   - For other operating systems or versions of PowerShell, please confirm compatibility.

3. **ExchangeOnlineManagement Module**:  
   - This script automatically installs (if not already installed) the ExchangeOnlineManagement module from the PowerShell Gallery.  
   - You need an internet connection to download and install the module.  

4. **CSV File**:  
   - A CSV file containing the primary SMTP addresses of user mailboxes that you want to convert.  
   - The file path used in the script is `C:\usersToConvert.csv`, but you can customize it.

---

## CSV File Preparation

The CSV file must have at least one column named `PrimarySmtpAddress`. For example:

```csv
PrimarySmtpAddress
user1@yourDomain.com
user2@yourDomain.com
user3@yourDomain.com
```

Save this CSV file at `C:\usersToConvert.csv` or update the script to use a different path.

---

## How It Works

1. **Reads the CSV**: The script imports the CSV file located at `C:\usersToConvert.csv` (or whichever path you specify).
2. **Imports/Installs ExchangeOnlineManagement**: Ensures the required PowerShell module is present.
3. **Prompts for Credentials**:  
   - You will be prompted to enter your **Microsoft 365 Admin** credentials (username and password).  
   - These credentials are used to connect to Exchange Online.
4. **Connects to Exchange Online**: Authenticates with the provided credentials.
5. **Converts Each Mailbox**: Iterates through each `PrimarySmtpAddress` in the CSV and runs the `Set-Mailbox -Identity <address> -Type Shared` command.
6. **Logs Output**: Outputs success or failure messages to the console for each conversion attempt.

---

## Usage

1. **Download the Script**  
   - Save the [**ConvertUsersToSharedMailbox.ps1**](ConvertUsersToSharedMailbox.ps1) file to your local machine.

2. **Prepare Your CSV**  
   - Ensure your CSV file (e.g., `C:\usersToConvert.csv`) has the `PrimarySmtpAddress` column and valid data.

3. **Open PowerShell as Administrator**  
   - Right-click PowerShell and select **"Run as Administrator"**.

4. **Run the Script**  
   ```powershell
   .\ConvertUsersToSharedMailbox.ps1
   ```
   - The script will install/verify the `ExchangeOnlineManagement` module if needed.
   - You will be prompted for credentials to connect to Exchange Online. Enter your global admin or Exchange admin username and password.

5. **Monitor the Output**  
   - Success messages will appear in standard text:  
     `Converted the user '<user@domain.com>' to a shared mailbox.`
   - Error messages, if any, will appear in red text.

## Common Issues & Troubleshooting

1. **Module Installation Failure**  
   - If the module installation fails, ensure you have [PowerShellGet](https://www.powershellgallery.com/packages/PowerShellGet) updated and are running PowerShell as Administrator.

2. **Insufficient Privileges**  
   - You may receive errors if your account does not have the correct Exchange permissions. Make sure you are a **Global Admin** or **Exchange Admin**.

3. **Incorrect CSV Path**  
   - Update `$csvPath` in the script if you are not storing the CSV at `C:\usersToConvert.csv`.

4. **Credential Prompt**  
   - If the script keeps prompting for credentials, ensure you entered valid credentials and that multi-factor authentication (MFA) is handled or disabled for the account used. You may need to use [Modern Auth modules or app passwords](https://docs.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/authenticated-client-protocols?view=exchserver-2019) if MFA is enabled.

5. **Rate Limiting/Throttling**  
   - Converting a large number of mailboxes might trigger rate limits. If you encounter throttling, consider spacing out conversions or using an administrative account that has higher limits.

---

## License

This project is licensed under the [MIT License](LICENSE). Feel free to modify and use it as needed.
