# Set output directory
$OutDir = "D:\source\repos\Assemulator"

# Create directory if it doesn't exist
if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir }


function Try-Run($Command, $OutFile) {
	try {
		Invoke-Expression $Command | Out-File $OutFile
	} catch {
		"ERROR running: $Command`n$($_.Exception.Message)" | Out-File $OutFile
	}
}

# Collect container info with error handling
Try-Run 'docker inspect assemulator' "$OutDir\container_inspect.txt"
Try-Run 'docker exec assemulator printenv' "$OutDir\container_env.txt"
Try-Run 'docker exec assemulator ls -lR /usr/share/nginx/html' "$OutDir\container_files.txt"
Try-Run 'docker exec assemulator find /usr/share/nginx/html -name index.html -exec grep base {} \;' "$OutDir\container_basehref.txt"
Try-Run 'docker exec assemulator cat /usr/share/nginx/html/data/manifest.json' "$OutDir\container_manifest.txt"

# (Optional) Zip the results
Compress-Archive -Path "$OutDir\container_inspect.txt","$OutDir\container_env.txt","$OutDir\container_files.txt","$OutDir\container_basehref.txt","$OutDir\container_manifest.txt" -DestinationPath "$OutDir\container_info.zip"