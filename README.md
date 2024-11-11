# New-TaskTab

Creates a new task-oriented tab in PowerShell ISE that monitors a target system's online/offline status and displays when a tab is busy or idle, making it easier to work multiple issues simultaneously.

Creates the variables `$cn` (FQDN) and `$TaskName` within each tab for easy access in functions like `Invoke-Command`, and injects additional administration functions defined in *New-TaskTab.func.ps1* (example file included)

Tabs are displayed with 3 lines:
- Task Name and Online Status icon
- Computer Name and Busy Status icon
- Resovled IP address and IP status issues

Syntax: `.\New-TaskTab.ps1 [[-TaskName] <String>] [[-ComputerName] <String>]`

Example: `PS> .\New-TaskTab.ps1 'Example Task' 'SHADOWWINVM10.local'`

![Example Task Tab](/example.png)

