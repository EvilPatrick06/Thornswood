<#
  A stand-in Data\Platform\UI for harnesses that run the real Publish-Update
  or Package-Thornswood. Save-ShipUiHashedAssets refuses a game folder whose
  build.js is missing or names nothing (#1318). The excerpt is the webpack
  file-loader form the real front uses, with two fonts THIRD-PARTY.md records
  as files build.js names.
#>
function Install-UiFrontFixture([string]$GameDir) {
    $ui = Join-Path $GameDir 'Data\Platform\UI'
    New-Item -ItemType Directory -Force -Path $ui | Out-Null
    $js = @'
!function(e){var t={};function n(r){if(t[r])return t[r].exports;var o=t[r]={i:r,l:!1,exports:{}};return e[r].call(o.exports,o,o.exports,n),o.l=!0,o.exports}n.p="";n(0)}([
function(e,t,n){e.exports=n.p+"6f802bf60c545304b09e.ttf";},
function(e,t,n){e.exports=n.p+"00e4a2200c3e5ae71d67.ttf";}
]);
'@
    [IO.File]::WriteAllText((Join-Path $ui 'build.js'), $js)
    [IO.File]::WriteAllText((Join-Path $ui 'index.html'), '<html></html>')
    [IO.File]::WriteAllText((Join-Path $ui '6f802bf60c545304b09e.ttf'), 'font-a')
    [IO.File]::WriteAllText((Join-Path $ui '00e4a2200c3e5ae71d67.ttf'), 'font-b')
}
