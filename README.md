# USB-Everything

**USB-Everything** is a portable all-in-one toolkit stored on a USB drive, built to streamline Windows system setup, maintenance, and recovery. It features a collection of executable tools and automation scripts for:

- Repairing common Windows issues  
- Activating Windows systems  
- Installing GPU drivers  
- Applying missing Windows updates  
- And running various essential utilities  

All components are orchestrated through a centralized, script-driven interface using PowerShell for seamless execution and automation.

---

### 🔐 Security & Locking

Executable files are locked using a custom script (`lock.ps1`) to prevent unauthorized or accidental execution.  
They can only be accessed and launched through the main script interface.

---

### 🚀 Quick Launch

To launch the toolkit:

1. Plug in the USB drive.  
2. Open **PowerShell** as Administrator.  
3. Navigate to the USB directory.  
4. Run the main launcher:

```powershell
.\arck.ps1
