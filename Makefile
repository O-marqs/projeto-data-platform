.PHONY: up test-fnd01 down clean-fnd01

up:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fnd01.ps1 up

test-fnd01:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fnd01.ps1 test

down:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fnd01.ps1 down

clean-fnd01:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fnd01.ps1 clean
