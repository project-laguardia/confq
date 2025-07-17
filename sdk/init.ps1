param(
    [string] $Origin,
    [switch] $Branch,
    [switch] $Push
)

git remote set-url origin $Origin
git remote add sdk https://github.com/project-laguardia/sdk

If( $Branch ) {
    git branch -M main
}
If ( $Push ) {
    git push -u origin main
}