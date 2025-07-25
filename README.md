# USB-Everything

A multi-tool utility suite packed into a single USB.  
Includes automation scripts, security tools, and system utilities — all in one place.

> ⚠️ **Note:**  
The [`arck.ps1`](./ZhanTool.ps1) script is required to launch the project.  
The `.exe` files are intentionally locked and cannot be executed directly.  
Locking is handled by a separate script: [`loock.ps1`](./lock.ps1), which only secures the `.exe` files.

## How to Run

1. Plug in the USB.
2. Open PowerShell.
3. Navigate to the USB directory.
4. Run:

```powershell
.\arck.ps1
