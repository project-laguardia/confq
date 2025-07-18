param(
    [switch] $Publish
)

$module = Get-Module -Name "Laguardia.SDK.Stash"

$module = If( $module ) {
    $module
} Else {
    New-Module -Name "Laguardia.SDK.Stash" -ScriptBlock {
        $private = @{
            stash = $null
            branch = $null
        }

        Export-ModuleMember
    } | % {
        Import-Module $_
        $_
    }
}

If( $Publish ) {
    # Check for unstaged changes, and throw an error if any are found
    $unstaged = git diff --name-only
    If( $unstaged ) {
        Write-Error "Unstaged changes found. Please commit or stash them before publishing."
        return
    }

    git checkout sdk-changes
    git push sdk sdk-changes:main
    Write-Host "SDK changes published to the 'sdk' remote."

    $sha = & $module { $private.stash }
    $branch = & $module { $private.branch }

    git checkout $branch

    git merge sdk-changes --no-ff -m "Merge SDK changes from sdk-changes branch"

    git branch -D sdk-changes

    If( $sha ) {
        <# git branch temp-$sha $sha
        git diff temp-$sha -- . ':!sdk/' | git apply
        git branch -D temp-$sha #>
        git stash apply $sha
    }
    return
}

If( git stash list ){
    Write-Error "Changes found in stash. Apply them or clear them with 'git stash clear'."
    return
}

$stash = git stash create
If( $stash ) {

    $sb = [scriptblock]::Create((@(
        '$private.stash ='
        "'$($stash)'"
    ) -join ' '))
    & $module $sb

    $sb = [scriptblock]::Create((@(
        '$private.branch ='
        "'$(git rev-parse --abbrev-ref HEAD)'"
    ) -join ' '))
    & $module $sb

    git stash store $stash
    git reset --hard
    git checkout -b sdk-changes sdk/main
    git reset --hard
    git checkout $stash -- sdk/
    git add sdk/
    Write-Host "Changes stashed and SDK branch staged."
}