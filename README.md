# confq

Imagine if dasel was a desired state configuration manager, turning any serialization format into a declarative configuration language. You get `confq`.

It is designed to offer a lot of similar features available in NixOS's Nix language with a command-line that is functionally similar to OpenWRT's `uci`.

In order to achieve feature parity with the Nix language, `confq` uses Dasel V3 query language with the addition of recursive queries.
- String values in data documents (JSON, YAML, XML, TOML, HCL, etc) can either be a string or a dasel expression.
  - To denote a dasel expression, begin the string with `=`. To escape, start the string with `\=` where `\` is a literal `\` character (i.e. JSON/YAML `\\=`).

In order to achieve feature parity with OpenWRT's `uci`, directory parsing and lazy-loading has been added to Dasel.

Currently, the only known missing feature is IPC support, which is planned for a future release. Depending on further research, we may model `confq`'s IPC after `uci`'s `rpcd` interface using `grpc`.

## Development

This repository uses the Project Laguardia SDK for development. It is included in the `sdk` directory. After cloning, ensure you run the `init.ps1` script to set up the repository correctly.
- it is primarily used for codesearching and repository management. At this time, it does not include any build tools or scripts.

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