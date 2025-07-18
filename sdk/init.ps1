param(
    [string] $Origin,
    [string] $SDK = (& {
        $default = "https://github.com/project-laguardia/sdk"
        $common = (git ls-remote $default sdkland) -split "`t" | Select-Object -First 1
        If( $common -eq "$(git rev-list --max-parents=0 HEAD)" ) {
            return $default
        }
    }), # Allows forked contributions
    [switch] $GitIgnore,
    [switch] $Branch,
    [switch] $Push
)

$gitRoot = git rev-parse --show-toplevel

If( "$Origin".Trim() -ne "" ){
    git remote set-url origin $Origin
}
If( (git remote) -contains "sdk" ) {
    git remote set-url sdk $SDK
} Else {
    git remote add sdk $SDK
}

cp "$gitRoot/sdk/.commitlintrc.yml" "$gitRoot/.commitlintrc.yml" -Force
If( $GitIgnore ) {
    cp "$gitRoot/sdk/.gitignore" "$gitRoot/.gitignore" -Force
}

If( $Branch ) {
    git branch -M main
}
If ( $Push ) {
    git push -u origin main
}