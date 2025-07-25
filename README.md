# USB-Everything

USB-Everything is a portable all-in-one toolkit stored on a USB drive, designed to simplify system setup, maintenance, and recovery. It includes various .exe programs and automation scripts for:

- Fixing common Windows errors  
- Activating Windows systems  
- Downloading and installing GPU drivers  
- Installing missing updates  
- And more essential system utilities  

All tools are centrally managed and launched through a custom PowerShell interface.

🔐 Executable files are locked using a dedicated script (loock.ps1) to prevent unauthorized usage.  
🚀 To launch the full toolkit, run the main PowerShell script arck.ps1 via the terminal.

This project combines scripting, backend logic, and system-level automation to create a compact and efficient support solution for any Windows machine.

> ⚠️ **Note:**  
The [arck.ps1](./arck.ps1) script is required to launch the project.  
The .exe files are intentionally locked and cannot be executed directly.  
Locking is handled by a separate script: [lock.ps1](./lock.ps1), which only secures the .exe files.

## How to Run

1. Plug in the USB.
2. Open PowerShell.
3. Navigate to the USB directory.
4. Run:

powershell
.\arck.ps1
