# confq

A state configuration manager based on OpenWRT's UCI and Dasel.

## Development

This repository uses the Project Laguardia SDK for development. It is included in the `sdk` directory. After cloning, ensure you run the `init.ps1` script to set up the repository correctly:

```powershell
git clone "https://github.com/project-laguardia/confq"
cd confq

# Sets remotes and initial branch
& .\sdk\init.ps1
<#
  # or
  & .\sdk\init.ps1 `
    -Origin "https://example.com/your-repo.git" `
    -Branch # renames current branch to 'main' `
    -Push # Pushes 'main' to origin
#>
```