This directory contains a set of common tools used by the Laguardia project to manage and interact with repositories:

- `init.ps1`: A PowerShell script to run after `git clone https://github.com/project-laguardia/sdk`.
  - Corrects the remotes and initial branch of the new repository.
  - If you plan to make changes to the SDK, ensure you run `init.ps1` with the `-SDK` parameter pointing to your fork of the SDK repository.
- `sdk.ps1`: A PowerShell script that ***MUST*** be run when making changes to this directory. If you do not run this script, your changes will not be accepted by Project Laguardia
  - This script is used to ensure that the SDK is correctly set up and that any changes made are compatible with the Laguardia project standards.
  - If you plan to make changes to the SDK, ensure you run `init.ps1` with the `-SDK` parameter pointing to your fork of the SDK repository.
- `search.ps1`: A PowerShell script that provides a search functionality for repositories.
  - It includes features to search for specific terms across repositories and manage remotes.
  - There are a lot of parameters available. Review this script to understand how to use it effectively.
- `unmerged.ps1`: A PowerShell script that helps identify unmerged commits in a repository using tags.
  - It is a useful alternative to `git cherry` that allows filtering by tag.