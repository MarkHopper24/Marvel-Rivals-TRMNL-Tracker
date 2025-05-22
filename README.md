# Marvel-Rivals-TRMNL-Tracker
This repository contains the source code, templates, and setup instructions for sending Marvel Rivals account game data to your TRMNL device using PowerShell and GitHub Actions.
![Marvel Rivals](https://github.com/user-attachments/assets/3f8a79fe-ca81-4f40-a649-01489e0c204e)


## TRMNL Plugin Setup Instructions

### Prerequisites
- A TRMNL device (https://usetrmnl.com)
- TRMNL Private Plugin Id (https://help.usetrmnl.com/en/articles/9510536-private-plugins)
- API Key from MarvelRivalsAPI.com (https://marvelrivalsapi.com)
- A fork of this repository

### Create a TRMNL private plugin
1. Create a webhook TRMNL private plugin using the TRMNL documentation (https://help.usetrmnl.com/en/articles/9510536-private-plugins)
2. Note down the Plugin ID provided by TRMNL. This will be used as a repository secret later.
3. Copy and paste the content in .\TRML\Template.html as your markdown.

### Configuring Secrets and Variables for GitHub Actions
1. Go to your forked repository.
2. Navigate to Settings > Secrets and variables > Actions.
3. Add the following secrets:
    - **MARVELRIVALSAPIKEY**: Your Marvel Rivals API key.
    - **TRMNL_PLUGIN_ID1**: Your TRMNL Plugin ID.
    - **TRMNL_PLUGIN_ID2**: Your second TRMNL Plugin ID. (Optional)
4. Add the following variables:
    - **USERNAME1**: Your Marvel Rivals account username.
    - **USERNAME2**: Your second Marvel Rivals account username. (Optional)

### Enabling GitHub Actions Workflows
1. Go to your forked repository on GitHub.
2. Navigate to the Actions tab.
3. You will see a list of workflows defined in the repository. Click on the workflow you want to enable (e.g., MarvelRivalsTrackerUpdater.yml).
4. If the workflow is disabled, you will see a banner at the top of the page with an option to enable it. Click on "Enable workflow".
6. The workflow is now enabled and will run according to its defined schedule or when manually triggered. By default, it runs every 2 hours from 12AM-8AM UTC every day. Modify the cron schedule in the workflow file to your liking.

After enabling the plugin on your TRMNL, your GitHub Actions configuration should now run the script as scheduled, and you can run the script on-demand. Once the script is run, your TRMNL plugin should show your updated stats during it's next refresh. 


### Script Description
The purpose of the [scripts/MarvelRivalsTrmnl.ps1](scripts/MarvelRivalsTrmnl.ps1) script is to fetch and process Marvel Rivals game statistics for specific users and send this data to the TRMNL platform. Here's a breakdown of its functionality:

1. **Parameters**: The script accepts several parameters, including `TrmnlPluginId`, `APIKey`, and `username`.

2. **Headers**: It sets up authorization headers using the provided API key.

3. **Functions**:
   - `Update-Player-Stats`: Updates the player statistics by making an API call.
   - `Convert-EpochToDate`: Converts epoch time to a readable date format.
   - `Get-AccountData`: Retrieves and processes player account data and match history.
   - `Get-HeroName`: Maps hero ID to hero name.
   - `Get-MatchHistory`: Retrieves the player's recent match history.
   - `Get-MapName`: Maps map ID to map name.
   - `Get-MatchDetails`: Retrieves detailed information about a specific match.
   - `Invoke-TrmnlPostRequest`: Posts the processed data to the TRMNL platform.

4. **Execution**: The script gets account data with `Get-AccountData` and sends it to the TRMNL platform using `Invoke-TrmnlPostRequest`. This script can also be run manually by downloading it and running with the required parameters.

This script is used to automate the process of collecting and sending Marvel Rivals game statistics to the TRMNL platform for further analysis or display.

### Running the Script Manually
To run the script, use the following command:
```pwsh
.\MarvelRivalsTrmnl.ps1 -TrmnlPluginId "<YourPluginId>" -APIKey "<YourAPIKey>" -username "<YourUsername>"
```

### YAML Description
The purpose of the `.github/workflows/MarvelRivalsTrackerUpdater.yml` GitHub Actions workflow is to automate the process of running the `MarvelRivalsTrmnl.ps1` PowerShell script at scheduled intervals and on-demand. This script fetches and processes Marvel Rivals game statistics for specific users and sends this data to the TRMNL platform. Here's a breakdown of its functionality:

1. **Environment Variables**:
   - `api_key`: API key for accessing the Marvel Rivals API.
   - `trmnl_plugin_id1` and `trmnl_plugin_id2`: Plugin IDs for the TRMNL platform.
   - `username1` and `username2`: Usernames for the Marvel Rivals accounts.

2. **Triggers**:
   - `schedule`: Runs the workflow at specific times (10PM, 11:30PM, 2:30AM, 4AM, and 5:30AM UTC every day).
   - `workflow_dispatch`: Allows the workflow to be manually triggered.

3. **Jobs**:
   - `run-script`: The job that runs the PowerShell script.
     - `runs-on: windows-latest`: Specifies the runner environment.
     - `steps`:
       - `Checkout repository`: Checks out the repository to the runner.
       - `Run PowerShell script for user 1`: Executes the `MarvelRivalsTrmnl.ps1` script for the first username and plugin ID.
       - `Run PowerShell script for user 2`: Executes the `MarvelRivalsTrmnl.ps1` script for the second username and plugin ID (if provided).
