param(
    [string] $Origin,
    [string] $SDK = "https://github.com/project-laguardia/sdk", # Allows forked contributions
    [switch] $Branch,
    [switch] $Push
)

If( "$Origin".Trim() -ne "" ){
    git remote set-url origin $Origin
}
If( (git remote) -contains "sdk" ) {
    git remote set-url sdk $SDK
} Else {
    git remote add sdk $SDK
}

If( $Branch ) {
    git branch -M main
}
If ( $Push ) {
    git push -u origin main
}