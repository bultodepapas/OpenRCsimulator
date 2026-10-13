param()

$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$pinnedCommit = "25f3c2da458e0a4f65bdb5903dc068b050930c06"
$downloads = @(
	@{
		RelativePath = "assets/landscape/lake/water-source/boujie_water.gdshader"
		Uri = "https://raw.githubusercontent.com/Chrisknyfe/boujie_water_shader/$pinnedCommit/addons/boujie_water_shader/shader/water.gdshader"
		Sha256 = "09a74e3b97738da896c9f39c73946e38f9487035c6559433316c2136ce84f607"
	},
	@{
		RelativePath = "assets/landscape/lake/water-source/LICENSE.md"
		Uri = "https://raw.githubusercontent.com/Chrisknyfe/boujie_water_shader/$pinnedCommit/LICENSE"
		Sha256 = "fbde0da26c3bec6344219a8da2936e5ecb7eee6254f6080d2fe47d6b315ae856"
	},
	@{
		RelativePath = "assets/landscape/lake/water-source/README.md"
		Uri = "https://raw.githubusercontent.com/Chrisknyfe/boujie_water_shader/$pinnedCommit/README.md"
		Sha256 = "5f80b7fec0f39cea3e8879ca1bb31f9faf72f108a54f242c3ff43836cb33f74f"
	},
	@{
		RelativePath = "assets/landscape/lake/water-source/audio/rubberduck-water-splash-slime-sfx.zip"
		Uri = "https://opengameart.org/sites/default/files/water-splash-slime-sfx.zip"
		Sha256 = "7cd39abb49d4362a37ba18dc0e454c7dc1d08029d4e5b683149046bc237b2eba"
	},
	@{
		RelativePath = "app/assets/audio/water/peludo-splash1.wav"
		Uri = "https://opengameart.org/sites/default/files/splash1_0.wav"
		Sha256 = "e45d466f7e63e5d566f8a822a7a1a3f7d5131319d17ca0436dcc615b251e9277"
	},
	@{
		RelativePath = "app/assets/audio/water/peludo-splash2.wav"
		Uri = "https://opengameart.org/sites/default/files/splash2_0.wav"
		Sha256 = "ad9472b711666de2d43c3b102d155a5d1118b1fcd0ecd29cb63177256ab63f31"
	},
	@{
		RelativePath = "app/assets/audio/water/randommind-vistula-short.mp3"
		Uri = "https://opengameart.org/sites/default/files/VistulaShort_0.mp3"
		Sha256 = "8c24607e41edd6f018ec3582a07e5a8dbc57347276339cb68440951a0fb4cfb1"
	}
)

foreach ($download in $downloads) {
	$destination = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $download.RelativePath))
	if (Test-Path -LiteralPath $destination -PathType Leaf) {
		$currentHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
		if ($currentHash -ne $download.Sha256) {
			throw "Refusing to overwrite ${destination}: expected SHA-256 $($download.Sha256), got $currentHash."
		}
		Write-Host "verified $($download.RelativePath)"
		continue
	}

	$destinationDirectory = Split-Path -Parent $destination
	New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
	$tempPath = [System.IO.Path]::GetTempFileName()
	try {
		Invoke-WebRequest -Uri $download.Uri -OutFile $tempPath -UseBasicParsing
		$downloadHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash.ToLowerInvariant()
		if ($downloadHash -ne $download.Sha256) {
			throw "Downloaded $($download.RelativePath) has unexpected SHA-256 $downloadHash."
		}
		Move-Item -LiteralPath $tempPath -Destination $destination
		Write-Host "downloaded and verified $($download.RelativePath)"
	} finally {
		if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
			Remove-Item -LiteralPath $tempPath
		}
	}
}
