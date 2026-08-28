# Jira Worklog Mover

A lightweight, interactive Bash script designed to move worklogs between Jira Cloud issues while preserving metadata such as time spent, start dates, and worklog descriptions.

## Description

This tool facilitates the transfer of worklogs from a source issue to a target issue using Bash interactivity & the Atlassian API. It is particularly useful for correcting misattributed time entries without manually recreating the log details. The script operates interactively, allowing you to browse existing worklogs, select specific IDs, and execute the move operation with validation. Once the worklog is replicated/regenerated to the destination Jira issue, the old worklog ID is removed. There is no clean way to move the worklog without generating a new ID but all the important info most people/companies need is retained. The ID itself is *usually* arbitrary and more for Jira's internal use. 

## Requirements

### Operating System Compatibility
- **Tested Environment:** Ubuntu and Debian Linux distributions.
- **Compatibility Note:** While the script relies on standard Bash commands, it has **only been tested on Ubuntu/Debian**. Behavior on other operating systems may vary. Users on unsupported OSes may need to adjust pathing or package management commands.

### Dependencies
The script requires the following tools to be installed on your system:

1.  **jq (JSON Processor)**
    -   **Why it is needed:** The Jira API returns data in JSON format. This script uses `jq` to parse that data, extract specific fields (like worklog IDs and timestamps), and construct the JSON payloads required to create new worklogs. Without `jq`, the script cannot interpret the API responses.
    -   **Installation (Ubuntu/Debian):** This is sometimes pre-installed on Linux distributions.
        ```bash
        sudo apt-get update
        sudo apt-get install jq
        ```
    -   **Verification:** Run `jq --version` to ensure it is installed correctly.

2.  **curl**
    -   Used for making HTTP requests to the Jira API. This is typically pre-installed on most Linux distributions.

3.  **Bash 4.0 or higher**
    -   Required for the associative arrays and string manipulation features used in the script. Should be OK on most modern Linux distributions.

## Installation & Setup

1.  **Generate an API Token:**
    Before running the script, you must generate a Jira API token. Your password will not work for this script.
    -   Go to [Atlassian Account Settings > Security](https://id.atlassian.com/manage-profile/security/api-tokens).
    -   Click **Create API token**.
    -   Label it (e.g., "Worklog Mover Script") and copy the token to a password manager.
    -   *Note: You will not be able to see this token again after closing the dialog.*

2.  **Install Dependencies and Download Script:**
    - Ensure `jq` is installed using the method appropriate for your OS (see Requirements above).
    - Download `jira-worklog-mover.sh` to your local machine.

4.  **In your terminal, navigate to the file's location to prepare the script**

5.  **Make the script executable:**
    ```bash
    chmod +x jira-worklog-mover.sh
    ```

6.  **Run the script:**
    ```bash
    ./jira-worklog-mover.sh
    ```

## Usage Instructions

1.  **Authentication:**
    Upon launch, you will be prompted for:
    -   **Jira Base URL:** Your organization's Jira domain (e.g., `https://your-company.atlassian.net`).
    -   **Email Address:** The email associated with your Jira account.
    -   **API Token:** Paste the token you generated in Step 1.

2.  **Select Source Issue:**
    Enter the Issue Key (e.g., `PROJ-123`) or a full URL containing the issue key. The script will validate the format and fetch available worklogs.

3.  **Move Worklogs:**
    -   Use the `m` command followed by one or more worklog IDs (comma-separated).
    -   Example: `m 1001, 1002`
    -   You will then be prompted for the **Target Issue Key** where the worklogs should be moved.

4.  **Navigation:**
    -   `r`: Refresh the worklog list for the current issue.
    -   `q` / `exit`: Return to the main menu or exit the script.

## Input Validation & Safety

The script includes several validation checks to prevent errors:
-   **Issue Key Parsing:** Automatically converts lowercase keys to uppercase and extracts keys from full URLs.
-   **ID Verification:** Validates selected worklog IDs against the fetched list before attempting any API calls.
-   **Network Checks:** Verifies connectivity and authentication status before proceeding.
-   **Error Handling:** Displays clear error messages if API calls fail (e.g., invalid credentials, missing worklogs).

## Disclaimer & Liability

**This software is provided "as is", without warranty of any kind, express or implied.**

By using this script, you acknowledge that:
-   The author is **not liable** for any damages, data loss, or operational issues resulting from the use of this software.
-   You are responsible for ensuring you have the necessary permissions to modify worklogs on your Jira instance.
-   Since the script interacts directly with your Jira API, incorrect usage could result in unintended data changes. Always test on non-production issues first.

## License

This project is licensed under the **MIT License**.

You are free to:
-   Share and copy the code.
-   Modify and adapt the code for your own needs.
-   Use the code commercially.

The only requirement is that you retain the original copyright and license text in any substantial portion of the code you distribute.

## Contributing

As this script was developed using collective human knowledge and AI assistance, it is intended for the greater good. I hope it saves you some stress. Contributions, bug fixes, and adaptations are welcome.
